//
//  CodexLaneStore.swift
//  Talkie iOS
//
//  Owns persistent Codex lane mappings and the narrated voice loop.
//
//  Selecting a lane is immediate: it chooses the exact Codex task that receives
//  the next message. Availability is determined by the actual submit.
//

import Foundation
import UIKit

@MainActor
final class CodexLaneStore: ObservableObject {
    static let shared = CodexLaneStore()

    private enum Keys {
        static let legacyLanes = "codex.lanes.v1"
        static let legacyActiveLane = "codex.lanes.active.v1"
        static let migratedLegacyHost = "codex.lanes.v2.migrated-host"

        static func lanes(for hostID: String) -> String {
            "codex.lanes.v2.\(hostID)"
        }

        static func activeLane(for hostID: String) -> String {
            "codex.lanes.active.v2.\(hostID)"
        }

        static func selectedChannel(for hostID: String) -> String {
            "codex.channels.selected.v1.\(hostID)"
        }
    }

    /// Cadence of the catalog refresh while the mapper is on screen.
    private static let catalogRefreshInterval: TimeInterval = 15
    static let createdTaskVisibilityGracePeriod: TimeInterval = 120

    private static let historyLimit = 20
    private static let liveActivityLimit = 6

    // MARK: - Lane bindings

    @Published private(set) var lanes: [Int: CodexLane] = [:]
    @Published private(set) var activeLaneNumber: Int?
    @Published private(set) var selectedChannel: CodexTaskSummary?
    @Published private(set) var newTaskProject: CodexProjectSummary?

    // MARK: - Voice loop

    @Published private(set) var phase: CodexLanePhase = .idle
    @Published private(set) var captureLevel: Float = 0
    @Published private(set) var narrationState: CodexNarrationState = .idle
    @Published private(set) var failure: CodexLaneFailure?
    @Published private(set) var lastTurn: CodexTurnRecord?
    @Published private(set) var history: [CodexTurnRecord] = []
    @Published private(set) var liveActivitiesByLane: [Int: [CodexLaneActivity]] = [:]
    /// Live activity for exact tasks that are not mounted to a numbered lane.
    /// Pending new-task activity uses a submission-scoped key until the Mac
    /// returns the real task identity, then moves to that task's key.
    @Published private(set) var liveActivitiesByDirectKey: [String: [CodexLaneActivity]] = [:]
    @Published private(set) var inFlightRequestCounts: [Int: Int] = [:]
    @Published private(set) var queuedMessageCounts: [Int: Int] = [:]

    // MARK: - Mapper catalog

    @Published private(set) var catalog: [CodexTaskSummary] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isLoadingNextCatalogPage = false
    @Published private(set) var isCreatingTask = false
    @Published private(set) var canCreateChannel = false
    @Published private(set) var catalogFailure: CodexLaneFailure?
    @Published private(set) var creationFailure: CodexLaneFailure?
    @Published var searchQuery: String = ""

    private let defaults: UserDefaults
    private let bridge: BridgeManager
    private let pendingTurnStore: CodexPendingTurn.Store
    private lazy var dictation: InlineDictationController = makeDictationController()
    private var catalogRefreshTask: Task<Void, Never>?
    private var catalogViewers = 0
    private var speakingTask: Task<Void, Never>?
    private var isPushToTalkHeld = false
    private var notificationNarratedJobIDs: Set<String> = []
    private var queuedActivityIDs: Set<UUID> = []
    private var loadedHostID: String?
    private var nextCatalogCursor: String?
    private var unpinnedInFlightRequestCount = 0
    private var recentlyCreatedTaskExpirations: [String: Date] = [:]
    private var newTaskSubmissionID: UUID?
    private var pendingTurns: [CodexPendingTurn]
    private var pendingTurnTasks: [UUID: Task<Void, Never>] = [:]

    init(
        defaults: UserDefaults = .standard,
        bridge: BridgeManager? = nil,
        hostIDOverride: String? = nil,
        pendingTurnStore: CodexPendingTurn.Store? = nil
    ) {
        self.defaults = defaults
        let resolvedBridge = bridge ?? .shared
        self.bridge = resolvedBridge
        self.pendingTurnStore = pendingTurnStore ?? CodexPendingTurn.Store(
            url: Self.pendingTurnStoreURL
        )
        self.loadedHostID = hostIDOverride ?? resolvedBridge.activePairedMacID
        self.canCreateChannel = resolvedBridge.activePairedMacID?.isEmpty == false
        do {
            self.pendingTurns = try self.pendingTurnStore.load()
        } catch {
            self.pendingTurns = []
            AppLogger.ai.warning(
                "iPhone Codex receipt inbox is unreadable: \(error.localizedDescription)"
            )
        }
        loadPersistedLanes()
        if !self.pendingTurns.isEmpty {
            AppLogger.ai.info(
                "iPhone Codex receipt inbox restored count=\(self.pendingTurns.count)"
            )
        }
    }

    // MARK: - Derived state

    var sortedLanes: [CodexLane] {
        lanes.values.sorted { $0.number < $1.number }
    }

    var activeLane: CodexLane? {
        activeLaneNumber.flatMap { lanes[$0] }
    }

    /// The exact dispatch destination. A channel can be selected without being
    /// pinned to one of the six lanes.
    var selectedTask: CodexTaskSummary? {
        selectedChannel ?? activeLane?.task
    }

    /// A recent task opened for a quick interaction without changing the six
    /// persistent lane assignments. Temporary destinations intentionally
    /// expire when explicitly closed or when the app is relaunched.
    var isTemporaryTaskSelected: Bool {
        selectedChannel != nil && activeLaneNumber == nil && newTaskProject == nil
    }

    /// A real task or an explicit NEW action can receive the next transcript.
    /// NEW remains project-scoped until the host atomically creates the Codex
    /// thread and accepts its first turn.
    var hasDispatchDestination: Bool {
        selectedTask != nil || newTaskProject != nil
    }

    var isTurnInFlight: Bool {
        unpinnedInFlightRequestCount > 0 || inFlightRequestCounts.values.contains { $0 > 0 }
    }

    var activeLaneIsInFlight: Bool {
        activeLaneNumber.map(isTurnInFlight(on:)) ?? false
    }

    var activeLaneMessageMode: CodexMessageMode {
        activeLane?.preferredMessageMode ?? .steer
    }

    var selectedDestinationIsInFlight: Bool {
        if let activeLaneNumber { return isTurnInFlight(on: activeLaneNumber) }
        return unpinnedInFlightRequestCount > 0
    }

    var selectedMessageMode: CodexMessageMode {
        activeLane?.preferredMessageMode ?? .steer
    }

    var canLoadMoreCatalog: Bool { nextCatalogCursor != nil }

    var projects: [CodexProjectSummary] {
        Self.deriveProjects(
            hostID: loadedHostID,
            lanes: sortedLanes,
            catalog: catalog
        )
    }

    func lane(_ number: Int) -> CodexLane? { lanes[number] }

    func activity(for number: Int) -> CodexLaneActivity? {
        liveActivitiesByLane[number]?.last
    }

    func activities(for number: Int) -> [CodexLaneActivity] {
        liveActivitiesByLane[number] ?? []
    }

    var selectedDirectActivities: [CodexLaneActivity] {
        guard activeLaneNumber == nil,
              let key = selectedDirectActivityKey else { return [] }
        return liveActivitiesByDirectKey[key] ?? []
    }

    var selectedActivity: CodexLaneActivity? {
        if let activeLaneNumber {
            return activity(for: activeLaneNumber)
        }
        return selectedDirectActivities.last
    }

    private var selectedDirectActivityKey: String? {
        if let selectedChannel {
            return Self.directActivityKey(taskID: selectedChannel.id)
        }
        if let newTaskSubmissionID {
            return Self.pendingDirectActivityKey(submissionID: newTaskSubmissionID)
        }
        return nil
    }

    private static func directActivityKey(taskID: String) -> String {
        "task:\(taskID)"
    }

    private static func pendingDirectActivityKey(submissionID: UUID) -> String {
        "new:\(submissionID.uuidString.lowercased())"
    }

    func isTurnInFlight(on number: Int) -> Bool {
        inFlightRequestCounts[number, default: 0] > 0
    }

    func queuedMessageCount(for number: Int) -> Int {
        queuedMessageCounts[number, default: 0]
    }

    func latestTurn(for number: Int) -> CodexTurnRecord? {
        history.first { $0.laneNumber == number }
    }

    func latestTurn(forTaskID taskID: String) -> CodexTurnRecord? {
        history.first { $0.taskID == taskID }
    }

    var filteredCatalog: [CodexTaskSummary] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalog }
        return catalog.filter { $0.matchesSearch(query) }
    }

    /// Lane numbers with no task bound yet, in order — what the mapper offers
    /// as the default destination.
    var unassignedLaneNumbers: [Int] {
        CodexLane.range.filter { lanes[$0] == nil }
    }

    /// Reloads the lane bank after the active Mac changes. Lane numbers are
    /// intentionally local to a host: lane 2 on one Mac must never route to a
    /// task that happened to occupy lane 2 on another Mac.
    func reloadForActiveHost() {
        let nextHostID = bridge.activePairedMacID
        guard nextHostID != loadedHostID else { return }

        for task in pendingTurnTasks.values {
            task.cancel()
        }
        pendingTurnTasks = [:]
        loadedHostID = nextHostID
        canCreateChannel = nextHostID?.isEmpty == false
        lanes = [:]
        activeLaneNumber = nil
        selectedChannel = nil
        newTaskProject = nil
        newTaskSubmissionID = nil
        catalog = []
        nextCatalogCursor = nil
        catalogFailure = nil
        creationFailure = nil
        searchQuery = ""
        liveActivitiesByLane = [:]
        liveActivitiesByDirectKey = [:]
        inFlightRequestCounts = [:]
        queuedMessageCounts = [:]
        queuedActivityIDs = []
        unpinnedInFlightRequestCount = 0
        recentlyCreatedTaskExpirations = [:]
        lastTurn = nil
        history = []
        failure = nil
        phase = .idle
        narrationState = .idle
        loadPersistedLanes()
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
        Task { @MainActor [weak self] in
            await self?.resumePendingTurns()
        }
    }

    // MARK: - Catalog

    /// Call when the mapper appears. Refreshes immediately and keeps refreshing
    /// while at least one caller is still viewing.
    func beginCatalogUpdates() {
        catalogViewers += 1
        guard catalogRefreshTask == nil else { return }

        catalogRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshCatalog()
                try? await Task.sleep(for: .seconds(Self.catalogRefreshInterval))
            }
        }
    }

    func endCatalogUpdates() {
        catalogViewers = max(0, catalogViewers - 1)
        guard catalogViewers == 0 else { return }
        catalogRefreshTask?.cancel()
        catalogRefreshTask = nil
    }

    func refreshCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        do {
            let page = try await bridge.codexRecentTasks(limit: 25)
            let liveTaskIDs = Set(page.tasks.map(\.id))
            liveTaskIDs.forEach { recentlyCreatedTaskExpirations[$0] = nil }
            recentlyCreatedTaskExpirations = recentlyCreatedTaskExpirations.filter {
                $0.value > .now
            }
            let locallyCreatedTasks = catalog.filter {
                recentlyCreatedTaskExpirations[$0.id] != nil
            }
            catalog = Self.mergingCatalog(locallyCreatedTasks, with: page.tasks)
            refreshTaskReferences(with: catalog)
            nextCatalogCursor = page.nextCursor
            catalogFailure = nil
            WatchSessionManager.shared.publishCurrentCodexSnapshot()
        } catch {
            // Keep whatever we last showed — a stale list the user can read
            // beats an empty one — but say the refresh failed.
            catalogFailure = Self.describe(error)
            AppLogger.ai.warning("Codex catalog refresh failed: \(error.localizedDescription)")
        }
    }

    /// Loads the page after the current catalogue and appends without allowing
    /// the same exact task to appear twice.
    func loadNextCatalogPage() async {
        guard !isLoadingCatalog,
              !isLoadingNextCatalogPage,
              let cursor = nextCatalogCursor else { return }

        isLoadingNextCatalogPage = true
        defer { isLoadingNextCatalogPage = false }

        do {
            let page = try await bridge.codexRecentTasks(limit: 25, cursor: cursor)
            catalog = Self.mergingCatalog(catalog, with: page.tasks)
            refreshTaskReferences(with: catalog)
            nextCatalogCursor = page.nextCursor
            catalogFailure = nil
            WatchSessionManager.shared.publishCurrentCodexSnapshot()
        } catch {
            catalogFailure = Self.describe(error)
            AppLogger.ai.warning("Codex catalog page failed: \(error.localizedDescription)")
        }
    }

    /// Called by a row's appearance. Only the true final loaded row advances
    /// the cursor, preventing filtered results from draining every page.
    func loadNextCatalogPageIfNeeded(after task: CodexTaskSummary) async {
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              catalog.last?.id == task.id else { return }
        await loadNextCatalogPage()
    }

    /// Enters the deck's explicit NEW mode without creating an empty Codex
    /// thread. The first transcript carries this action to the host, where
    /// thread creation and turn submission happen in one app-server lifetime.
    @discardableResult
    func enterNewTaskMode(
        in project: CodexProjectSummary,
        submissionID: UUID
    ) -> Bool {
        creationFailure = nil
        guard project.hostID == loadedHostID else {
            creationFailure = CodexLaneFailure(
                message: "That project belongs to another Mac.",
                hint: "Reconnect to the Mac that owns it and try again."
            )
            return false
        }

        selectedChannel = nil
        activeLaneNumber = nil
        newTaskProject = project
        newTaskSubmissionID = submissionID
        persistSelectedChannel()
        persistActiveLane()
        failure = nil
        phase = .idle
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
        return true
    }

    func clearCreationFailure() {
        creationFailure = nil
    }

    static func mergingCatalog(
        _ existing: [CodexTaskSummary],
        with incoming: [CodexTaskSummary]
    ) -> [CodexTaskSummary] {
        var merged: [CodexTaskSummary] = []
        var indexByTaskID: [String: Int] = [:]

        for task in existing + incoming {
            if let index = indexByTaskID[task.id] {
                // Keep the established row position, but let a refreshed
                // server snapshot replace the creation-time "New task"
                // placeholder once Codex has derived its real title.
                if task.updatedAt >= merged[index].updatedAt {
                    merged[index] = task
                }
            } else {
                indexByTaskID[task.id] = merged.count
                merged.append(task)
            }
        }

        return merged
    }

    /// Replaces creation-time placeholders held by the selection and lane bank
    /// once Codex publishes the task's real title and metadata in the catalog.
    /// Task identity and the user's lane settings remain unchanged.
    func refreshTaskReferences(with refreshedCatalog: [CodexTaskSummary]) {
        let refreshedByID = Dictionary(uniqueKeysWithValues: refreshedCatalog.map { ($0.id, $0) })

        if let selectedChannel,
           let refreshed = refreshedByID[selectedChannel.id],
           refreshed.updatedAt >= selectedChannel.updatedAt,
           refreshed != selectedChannel {
            self.selectedChannel = refreshed
            persistSelectedChannel()
        }

        var refreshedLanes = lanes
        var lanesChanged = false
        for (number, lane) in lanes {
            guard let refreshed = refreshedByID[lane.task.id],
                  refreshed.updatedAt >= lane.task.updatedAt,
                  refreshed != lane.task else { continue }
            var updatedLane = lane
            updatedLane.task = refreshed
            refreshedLanes[number] = updatedLane
            lanesChanged = true
        }
        if lanesChanged {
            lanes = refreshedLanes
            persistLanes()
        }
    }

    static func deriveProjects(
        hostID: String?,
        lanes: [CodexLane],
        catalog: [CodexTaskSummary]
    ) -> [CodexProjectSummary] {
        guard let hostID else { return [] }

        let assignedPaths = Set(lanes.map(\.task.canonicalWorkingDirectory))
        let orderedTasks = lanes.map(\.task) + catalog
        var seen = Set<String>()

        return orderedTasks.compactMap { task in
            let cwd = task.canonicalWorkingDirectory
            guard seen.insert(cwd).inserted else { return nil }
            return CodexProjectSummary(
                hostID: hostID,
                cwd: cwd,
                name: task.projectName,
                updatedAt: task.updatedAt,
                isAssignedToLane: assignedPaths.contains(cwd)
            )
        }
    }

    // MARK: - Assignment

    /// Binds a task to a lane without changing the active lane.
    func assign(_ task: CodexTaskSummary, to number: Int) {
        guard CodexLane.range.contains(number) else { return }

        let previousAssignments = lanes.values.filter { $0.task.id == task.id }
        let wasActiveAssignment = previousAssignments.contains { $0.number == activeLaneNumber }
        for lane in previousAssignments where lane.number != number {
            lanes[lane.number] = nil
        }

        let existingLane = lanes[number]
        lanes[number] = CodexLane(
            number: number,
            task: task,
            messageMode: existingLane?.preferredMessageMode ?? .steer,
            voiceOverride: existingLane?.voiceOverride
        )

        if wasActiveAssignment {
            activeLaneNumber = number
            persistActiveLane()
        }

        persistLanes()
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
    }

    func clearLane(_ number: Int) {
        guard lanes[number] != nil else { return }
        let clearedTaskID = lanes[number]?.task.id
        lanes[number] = nil

        if activeLaneNumber == number {
            activeLaneNumber = nil
            persistActiveLane()
            if selectedChannel?.id != clearedTaskID {
                selectedChannel = catalog.first { $0.id == clearedTaskID }
            }
            persistSelectedChannel()
        }
        persistLanes()
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
    }

    func setVoiceOverride(_ override: CodexLaneVoiceOverride?, for number: Int) {
        guard var lane = lanes[number] else { return }
        lane.voiceOverride = override
        lanes[number] = lane
        persistLanes()
    }

    /// Sets the delivery preference on the lane itself so it stays predictable
    /// while the user moves between tasks and across app launches.
    func setMessageMode(_ mode: CodexMessageMode, for number: Int) {
        guard mode == .queue || mode == .steer, var lane = lanes[number] else { return }
        let previousMode = lane.preferredMessageMode
        lane.messageMode = mode
        lanes[number] = lane
        persistLanes()
        AppLogger.ai.info(
            "Codex delivery mode changed lane=\(number) task=\(lane.task.id) "
                + "from=\(previousMode.rawValue) to=\(mode.rawValue)"
        )
    }

    // MARK: - Activation

    /// Selects an exact task without assigning or replacing any numbered lane.
    func selectChannel(_ task: CodexTaskSummary) {
        newTaskProject = nil
        newTaskSubmissionID = nil
        selectedChannel = task
        activeLaneNumber = lanes.values.first(where: { $0.task.id == task.id })?.number
        persistSelectedChannel()
        persistActiveLane()
        failure = nil
        phase = .idle
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
    }

    /// Returns the instrument to an intentionally unarmed state without
    /// changing any lane mappings. A future lane tap or mapper selection can
    /// choose the next exact destination again.
    func clearSelection() {
        guard !phase.isCapturing else { return }
        newTaskProject = nil
        newTaskSubmissionID = nil
        selectedChannel = nil
        activeLaneNumber = nil
        persistSelectedChannel()
        persistActiveLane()
        failure = nil
        phase = .idle
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
    }

    /// Selects the exact task that receives the next message.
    @discardableResult
    func activate(_ number: Int) async -> Bool {
        guard lanes[number] != nil else {
            failure = CodexLaneFailure(
                message: "Lane \(number) has no task yet.",
                hint: "Map a Codex task to this lane first."
            )
            return false
        }

        newTaskProject = nil
        newTaskSubmissionID = nil
        activeLaneNumber = number
        selectedChannel = lanes[number]?.task
        persistActiveLane()
        persistSelectedChannel()
        failure = nil
        phase = .idle
        WatchSessionManager.shared.publishCurrentCodexSnapshot()
        return true
    }

    // MARK: - Voice loop

    /// Single entry point for the deck's capture control.
    ///
    /// While narration is playing this interrupts and listens — that is the
    /// interaction the whole loop is built around, so it is not a special case
    /// bolted on the side.
    func handleCaptureControl() {
        switch phase {
        case .listening:
            dictation.stop(insertTranscript: true)
        case .submitting where isTurnInFlight:
            startCapture()
        case .transcribing, .submitting, .preparingSpeech:
            return
        case .speaking:
            interruptNarration()
            startCapture()
        case .idle, .failed:
            startCapture()
        }
    }

    /// Begins the deck's physical push-to-talk gesture. This is separate from
    /// the legacy tap-to-toggle control so the high-fidelity deck can make the
    /// literal promise printed on its face: recording lasts only while held.
    func beginPushToTalk() {
        guard !isPushToTalkHeld else { return }

        switch phase {
        case .submitting where isTurnInFlight:
            isPushToTalkHeld = true
            startCapture()
        case .transcribing, .submitting, .preparingSpeech:
            return
        case .listening:
            isPushToTalkHeld = true
        case .speaking:
            isPushToTalkHeld = true
            interruptNarration()
            startCapture()
        case .idle, .failed:
            isPushToTalkHeld = true
            startCapture()
        }
    }

    /// Ends push-to-talk and submits whatever was captured. Calling stop is
    /// also correct during permission preflight: InlineDictationController
    /// cancels the pending start token so a released control can never begin
    /// recording later on its own.
    func endPushToTalk() {
        guard isPushToTalkHeld else { return }
        isPushToTalkHeld = false
        dictation.stop(insertTranscript: true)
    }

    func cancelCapture() {
        guard isPushToTalkHeld || phase.isCapturing else { return }
        isPushToTalkHeld = false
        captureLevel = 0
        dictation.cancel()
        phase = isTurnInFlight ? .submitting : .idle
        AppLogger.ai.info("Codex capture cancelled")
    }

    /// Stops narration immediately. Safe to call when nothing is playing.
    func interruptNarration() {
        speakingTask?.cancel()
        speakingTask = nil
        WalkieFX.shared.stopVoicePlayback()
        narrationState = .idle
        if phase == .speaking {
            phase = isTurnInFlight ? .submitting : .idle
        }
    }

    /// Reads the last successful response again using the currently selected
    /// output route. The response remains available as text whether speech
    /// succeeds, fails, or is deliberately silent.
    func narrateLastResponse() {
        guard let record = lastTurn else {
            failure = CodexLaneFailure(
                message: "There is no response to narrate yet.",
                hint: "Send an instruction to Codex first."
            )
            return
        }

        replayNarration(record)
    }

    /// Replays the latest response belonging to one lane. This keeps deck
    /// controls attached to the task currently in view instead of whichever
    /// lane happened to finish most recently.
    func narrateLatestResponse(for laneNumber: Int) {
        guard let record = latestTurn(for: laneNumber) else {
            failure = CodexLaneFailure(
                message: "There is no response to narrate for this lane yet.",
                hint: "Send an instruction to this Codex task first."
            )
            return
        }

        replayNarration(record)
    }

    func narrateLatestResponse(forTaskID taskID: String) {
        guard let record = latestTurn(forTaskID: taskID) else {
            failure = CodexLaneFailure(
                message: "There is no response to narrate for this channel yet.",
                hint: "Send an instruction to this Codex task first."
            )
            return
        }

        replayNarration(record)
    }

    private func replayNarration(_ record: CodexTurnRecord) {
        var record = record

        interruptNarration()
        record.speechFailure = nil
        record.narrationSuppressed = false

        Task { [weak self] in
            guard let self else { return }
            let updated = await self.narrate(record)
            if self.lastTurn?.id == updated.id {
                self.lastTurn = updated
            }
            if let index = self.history.firstIndex(where: { $0.id == updated.id }) {
                self.history[index] = updated
            }
        }
    }

    private func startCapture() {
        guard hasDispatchDestination else {
            failure = CodexLaneFailure(
                message: "No Codex channel is selected.",
                hint: "Choose NEW or select an exact task."
            )
            return
        }

        failure = nil
        narrationState = .idle
        Task { await dictation.start() }
    }

    private func makeDictationController() -> InlineDictationController {
        let controller = InlineDictationController()

        controller.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .recording:
                self.phase = .listening
            case .transcribing:
                self.captureLevel = 0
                // Only reflect this while we own the flow; the controller also
                // reports `.transcribing` during its permission preflight.
                if self.phase == .listening || self.phase == .idle {
                    self.phase = .transcribing
                }
            case .idle:
                self.captureLevel = 0
                // The submit path takes over from here; only reset when the
                // capture ended without producing anything.
                if self.phase == .transcribing || self.phase == .listening {
                    self.phase = self.isTurnInFlight ? .submitting : .idle
                }
            }
        }

        controller.onTranscript = { [weak self] transcript in
            guard let self else { return }
            Task { await self.submit(instruction: transcript) }
        }

        controller.onError = { [weak self] message in
            guard let self else { return }
            self.captureLevel = 0
            self.failure = CodexLaneFailure(message: message, hint: nil)
            self.phase = .failed(message)
        }

        controller.onAudioLevel = { [weak self] level in
            self?.captureLevel = level
        }

        return controller
    }

    // MARK: - Submission

    private func submit(instruction: String) async {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = isTurnInFlight ? .submitting : .idle
            return
        }

        if let project = newTaskProject,
           let submissionID = newTaskSubmissionID {
            AppLogger.ai.info(
                "Codex dispatch resolved action=new project=\(project.cwd) lane=none"
            )
            await deliverToNewTask(
                instruction: text,
                project: project,
                submissionID: submissionID
            )
            return
        }

        guard let task = selectedTask else {
            let described = CodexLaneFailure(
                message: "No Codex channel is selected.",
                hint: "Choose NEW or select an exact task."
            )
            failure = described
            phase = .failed(described.message)
            return
        }

        if let number = activeLaneNumber,
           let lane = lanes[number],
           lane.task.id == task.id {
            // Delivery is a lane setting, not a transient inference from this
            // phone's request count. The host makes either preference safe when
            // idle: steer falls back to a new turn and queue starts immediately.
            AppLogger.ai.info(
                "Codex dispatch resolved task=\(task.id) lane=\(number) "
                    + "mode=\(lane.preferredMessageMode.rawValue)"
            )
            await deliver(
                instruction: text,
                to: lane,
                laneNumber: number,
                mode: lane.preferredMessageMode
            )
        } else {
            AppLogger.ai.info(
                "Codex dispatch resolved task=\(task.id) lane=none mode=steer"
            )
            await deliverToUnpinnedChannel(instruction: text, task: task)
        }
    }

    /// Creates a fresh task for a Watch-originated instruction, using the
    /// selected task only as a project anchor.
    ///
    /// This method never consults `activeLaneNumber` and never submits into the
    /// anchor task. A stale host or missing anchor fails before task creation,
    /// preventing an accidental fallback to whichever lane is active on iPhone.
    func dispatchFromWatch(
        instruction: String,
        taskID: String,
        projectDirectory: String?,
        expectedHostID: String?,
        submissionID: UUID = UUID()
    ) async throws -> CodexTurnJob {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CodexDispatchError.emptyInstruction }
        guard let hostID = loadedHostID else { throw CodexDispatchError.noActiveHost }
        if let expectedHostID, expectedHostID != hostID {
            throw CodexDispatchError.hostMismatch
        }
        let projectAnchor = availableTask(id: taskID)
        let workingDirectory = try Self.resolveWatchProjectDirectory(
            requestedDirectory: projectDirectory,
            projectAnchor: projectAnchor
        )

        // The Watch request ID is the durable key for the combined operation.
        // The Mac creates the task and starts its first turn in one app-server
        // lifetime, avoiding an unmaterialized thread with no rollout.
        let receipt = try await bridge.codexStartFreshTurn(
            submissionId: submissionID,
            cwd: workingDirectory,
            text: text
        )
        guard let task = receipt.task else {
            throw CodexDispatchError.unavailableTask
        }
        retainRecentlyCreatedTask(task)
        catalog = Self.mergingCatalog([task], with: catalog)
        WatchSessionManager.shared.publishCurrentCodexSnapshot()

        AppLogger.ai.info(
            "Watch dispatch created task=\(task.id) project=\(task.canonicalWorkingDirectory) "
                + "anchor=\(taskID)"
        )

        return receipt
    }

    /// Continues one exact task selected on Watch without changing the iPhone
    /// deck selection. Steer is the voice-friendly default: it adjusts an
    /// active turn and starts a normal turn when the task is idle.
    func dispatchFromWatchToTask(
        instruction: String,
        taskID: String,
        taskTitle: String?,
        projectDirectory: String?,
        expectedHostID: String?,
        submissionID: UUID = UUID()
    ) async throws -> CodexTurnJob {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CodexDispatchError.emptyInstruction }
        guard let hostID = loadedHostID else { throw CodexDispatchError.noActiveHost }
        if let expectedHostID, expectedHostID != hostID {
            throw CodexDispatchError.hostMismatch
        }

        let localTask = availableTask(id: taskID)
        _ = try Self.resolveWatchProjectDirectory(
            requestedDirectory: projectDirectory,
            projectAnchor: localTask
        )
        let resolvedTitle = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dispatchTitle: String
        if let resolvedTitle, !resolvedTitle.isEmpty {
            dispatchTitle = resolvedTitle
        } else {
            dispatchTitle = localTask?.title ?? "Codex task"
        }
        let receipt = try await bridge.codexStartTurn(
            submissionId: submissionID,
            taskId: taskID,
            taskTitle: dispatchTitle,
            text: text,
            mode: .steer
        )
        AppLogger.ai.info(
            "Watch dispatch continued task=\(taskID) mode=steer "
                + "phoneSelection=\(selectedTask?.id ?? "none")"
        )
        return receipt
    }

    private func retainRecentlyCreatedTask(_ task: CodexTaskSummary) {
        recentlyCreatedTaskExpirations[task.id] = .now.addingTimeInterval(
            Self.createdTaskVisibilityGracePeriod
        )
    }

    /// Resolves the project independently of UI/catalog hydration. The Watch
    /// receives this canonical directory from the phone's durable snapshot and
    /// returns it with the recording. When the anchor is locally available, it
    /// must still agree so stale snapshots cannot silently cross projects.
    static func resolveWatchProjectDirectory(
        requestedDirectory: String?,
        projectAnchor: CodexTaskSummary?
    ) throws -> String {
        if let requestedDirectory {
            let trimmed = requestedDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("/") else { throw CodexDispatchError.invalidProject }
            let canonical = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            if let projectAnchor,
               projectAnchor.canonicalWorkingDirectory != canonical {
                throw CodexDispatchError.projectMismatch
            }
            return canonical
        }

        guard let projectAnchor else { throw CodexDispatchError.unavailableTask }
        return projectAnchor.canonicalWorkingDirectory
    }

    private func availableTask(id taskID: String) -> CodexTaskSummary? {
        if selectedChannel?.id == taskID { return selectedChannel }
        if let task = catalog.first(where: { $0.id == taskID }) { return task }
        return lanes.values.first(where: { $0.task.id == taskID })?.task
    }

    /// Restarts every Mac-owned receipt saved by an earlier iPhone process.
    /// Starting is intentionally non-blocking: several independent Codex jobs
    /// must be able to finish without one long turn hiding later replies.
    func resumePendingTurns() async {
        let resumable = pendingTurns.filter { record in
            record.hostID == nil || record.hostID == bridge.activePairedMacID
        }
        guard !resumable.isEmpty else { return }

        AppLogger.ai.info(
            "iPhone Codex receipt resume count=\(resumable.count) "
                + "host=\(bridge.activePairedMacID ?? "none")"
        )
        for record in resumable {
            _ = startPendingTurnTask(id: record.id)
        }
    }

    private func startPendingTurnTask(id: UUID) -> Task<Void, Never> {
        if let existing = pendingTurnTasks[id] { return existing }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processPendingTurn(id: id)
            self.pendingTurnTasks[id] = nil
        }
        pendingTurnTasks[id] = task
        return task
    }

    private func processPendingTurn(id: UUID) async {
        guard let record = pendingTurn(id: id) else { return }
        guard record.hostID == nil || record.hostID == bridge.activePairedMacID else {
            AppLogger.ai.info(
                "iPhone Codex receipt deferred id=\(id) job=\(record.job.id) reason=host-mismatch"
            )
            return
        }

        if let laneNumber = record.laneNumber,
           lanes[laneNumber]?.task.id == record.task.id {
            if !isCurrentActivity(id, on: laneNumber) {
                appendActivity(
                    CodexLaneActivity(
                        id: id,
                        instruction: record.instruction,
                        state: .working(record.job.mode)
                    ),
                    on: laneNumber
                )
            }
            beginSubmission(on: laneNumber)
            updateActivity(id, on: laneNumber, from: record.job)
            await finishLaneTurn(
                record.job,
                instruction: record.instruction,
                task: record.task,
                activityID: id,
                laneNumber: laneNumber
            )
            return
        }

        let activityKey = Self.directActivityKey(taskID: record.task.id)
        if liveActivitiesByDirectKey[activityKey]?.contains(where: { $0.id == id }) != true {
            appendDirectActivity(
                CodexLaneActivity(
                    id: id,
                    instruction: record.instruction,
                    state: .working(record.job.mode)
                ),
                for: activityKey
            )
        }
        unpinnedInFlightRequestCount += 1
        updateDirectActivity(id, for: activityKey, from: record.job)
        await finishUnpinnedTurn(
            record.job,
            instruction: record.instruction,
            task: record.task,
            activityID: id,
            activityKey: activityKey
        )
    }

    private func savePendingTurn(
        id: UUID,
        instruction: String,
        task: CodexTaskSummary,
        laneNumber: Int?,
        job: CodexTurnJob
    ) {
        let now = Date()
        let record = CodexPendingTurn(
            id: id,
            hostID: loadedHostID ?? bridge.activePairedMacID,
            task: task,
            instruction: instruction,
            laneNumber: laneNumber,
            createdAt: now,
            updatedAt: now,
            job: job
        )
        pendingTurns.removeAll { $0.id == id }
        pendingTurns.append(record)
        persistPendingTurns()
        AppLogger.ai.info(
            "iPhone Codex receipt persisted id=\(id) job=\(job.id) task=\(task.id)"
        )
    }

    private func updatePendingTurn(id: UUID, job: CodexTurnJob) {
        guard let index = pendingTurns.firstIndex(where: { $0.id == id }),
              pendingTurns[index].job != job else { return }
        pendingTurns[index].job = job
        pendingTurns[index].updatedAt = .now
        persistPendingTurns()
    }

    private func pendingTurn(id: UUID) -> CodexPendingTurn? {
        pendingTurns.first { $0.id == id }
    }

    private func removePendingTurn(id: UUID) {
        pendingTurns.removeAll { $0.id == id }
        persistPendingTurns()
        AppLogger.ai.info("iPhone Codex receipt consumed id=\(id)")
    }

    private func persistPendingTurns() {
        do {
            try pendingTurnStore.save(pendingTurns)
        } catch {
            AppLogger.ai.error(
                "iPhone Codex receipt inbox could not be saved: \(error.localizedDescription)"
            )
        }
    }

    private func deliverToUnpinnedChannel(
        instruction: String,
        task: CodexTaskSummary
    ) async {
        let submissionID = UUID()
        let activityKey = Self.directActivityKey(taskID: task.id)
        unpinnedInFlightRequestCount += 1
        phase = .submitting
        failure = nil
        appendDirectActivity(
            CodexLaneActivity(
                id: submissionID,
                instruction: instruction,
                state: .working(.steer)
            ),
            for: activityKey
        )

        let receipt: CodexTurnJob
        do {
            receipt = try await startTurnWithRetry(
                submissionID: submissionID,
                onRetry: { [weak self] retryCount in
                    self?.mutateDirectActivity(submissionID, for: activityKey) {
                        $0.retryCount = retryCount
                    }
                },
                operation: {
                    try await bridge.codexStartTurn(
                        submissionId: submissionID,
                        taskId: task.id,
                        taskTitle: task.title,
                        text: instruction,
                        mode: .steer
                    )
                }
            )
        } catch {
            unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
            let described = Self.describe(error)
            failure = described
            failDirectActivity(submissionID, for: activityKey, message: described.combined)
            phase = .failed(described.message)
            AppLogger.ai.warning("Codex submit failed channel=\(task.id): \(described.combined)")
            return
        }

        updateDirectActivity(submissionID, for: activityKey, from: receipt)
        savePendingTurn(
            id: submissionID,
            instruction: instruction,
            task: task,
            laneNumber: nil,
            job: receipt
        )
        unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
        await startPendingTurnTask(id: submissionID).value
    }

    private func deliverToNewTask(
        instruction: String,
        project: CodexProjectSummary,
        submissionID: UUID
    ) async {
        let activityKey = Self.pendingDirectActivityKey(submissionID: submissionID)
        unpinnedInFlightRequestCount += 1
        phase = .submitting
        failure = nil
        appendDirectActivity(
            CodexLaneActivity(
                id: submissionID,
                instruction: instruction,
                state: .working(.steer)
            ),
            for: activityKey
        )

        let receipt: CodexTurnJob
        do {
            receipt = try await startTurnWithRetry(
                submissionID: submissionID,
                onRetry: { [weak self] retryCount in
                    self?.mutateDirectActivity(submissionID, for: activityKey) {
                        $0.retryCount = retryCount
                    }
                },
                operation: {
                    try await bridge.codexStartFreshTurn(
                        submissionId: submissionID,
                        cwd: project.cwd,
                        text: instruction
                    )
                }
            )
        } catch {
            unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
            let described = Self.describe(error)
            failure = described
            failDirectActivity(submissionID, for: activityKey, message: described.combined)
            phase = .failed(described.message)
            AppLogger.ai.warning(
                "Codex new-task submit failed project=\(project.cwd): \(described.combined)"
            )
            return
        }

        guard let task = receipt.task else {
            unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
            let message = "Codex accepted the new turn without returning its task."
            failure = CodexLaneFailure(
                message: message,
                hint: "Update Talkie on the Mac and try NEW again."
            )
            failDirectActivity(submissionID, for: activityKey, message: message)
            phase = .failed(message)
            return
        }

        let taskActivityKey = Self.directActivityKey(taskID: task.id)
        moveDirectActivities(from: activityKey, to: taskActivityKey)
        updateDirectActivity(submissionID, for: taskActivityKey, from: receipt)
        retainRecentlyCreatedTask(task)
        catalog = Self.mergingCatalog([task], with: catalog)
        selectChannel(task)
        phase = .submitting
        AppLogger.ai.info(
            "Codex new-task dispatch accepted task=\(task.id) project=\(project.cwd)"
        )

        savePendingTurn(
            id: submissionID,
            instruction: instruction,
            task: task,
            laneNumber: nil,
            job: receipt
        )
        unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
        await startPendingTurnTask(id: submissionID).value
    }

    private func finishUnpinnedTurn(
        _ receipt: CodexTurnJob,
        instruction: String,
        task: CodexTaskSummary,
        activityID: UUID,
        activityKey: String
    ) async {

        guard let job = await waitForUnpinnedTurnJob(
            receipt,
            activityID: activityID,
            activityKey: activityKey
        ) else {
            unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
            failDirectActivity(
                activityID,
                for: activityKey,
                message: "Timed out waiting for the Mac-owned turn."
            )
            phase = .failed("Timed out waiting for the Mac-owned turn.")
            return
        }
        unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
        updatePendingTurn(id: activityID, job: job)

        if job.status == "failed" || job.status == "blocked" || job.status == "unknown" {
            guard UIApplication.shared.applicationState == .active else {
                AppLogger.ai.info(
                    "iPhone Codex terminal receipt retained id=\(activityID) job=\(job.id) "
                        + "status=\(job.status) reason=app-inactive"
                )
                phase = isTurnInFlight ? .submitting : .idle
                return
            }
            let message = job.error
                ?? (job.status == "blocked" ? "Codex needs attention on the Mac." : "The Codex turn failed on the Mac.")
            failure = CodexLaneFailure(message: message, hint: job.hint)
            failDirectActivity(activityID, for: activityKey, message: message)
            phase = .failed(message)
            removePendingTurn(id: activityID)
            return
        }

        guard let deliveryValue = job.delivery,
              let delivery = CodexTurnDelivery(rawValue: deliveryValue) else {
            let message = "Codex reported an incomplete delivery receipt."
            failure = CodexLaneFailure(
                message: message,
                hint: "Update Talkie so it understands this version of Codex Desktop."
            )
            failDirectActivity(activityID, for: activityKey, message: message)
            phase = .failed(message)
            removePendingTurn(id: activityID)
            return
        }

        guard let response = job.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else {
            if delivery == .steeredActiveTurn {
                acceptDirectActivity(activityID, for: activityKey, delivery: delivery)
                phase = isTurnInFlight ? .submitting : .idle
                removePendingTurn(id: activityID)
            } else {
                let message = "Codex completed without a readable response."
                failure = CodexLaneFailure(message: message, hint: "Open the task on your Mac to inspect the turn.")
                failDirectActivity(activityID, for: activityKey, message: message)
                phase = .failed(message)
                removePendingTurn(id: activityID)
            }
            return
        }

        receiveDirectActivity(
            activityID,
            for: activityKey,
            response: response,
            delivery: delivery
        )
        var record = CodexTurnRecord(
            laneNumber: nil,
            taskID: task.id,
            taskTitle: task.title,
            instruction: instruction,
            response: response,
            delivery: delivery
        )
        // If the terminal receipt can run, narration gets its own background
        // execution window below. Tying speech to foreground state meant a
        // reply received just after the screen locked was silently withheld.
        if !notificationNarratedJobIDs.contains(job.id) {
            record = await narrate(record)
        } else {
            record.narrationSuppressed = true
            let route = AIResponseSpeechRoute(
                rawValue: TalkieAppSettings.shared.aiVoiceOutputRoute
            ) ?? .phone
            narrationState = .suppressed(laneNumber: nil, route: route)
            phase = isTurnInFlight ? .submitting : .idle
        }
        remember(record)
        removePendingTurn(id: activityID)
    }

    private func waitForUnpinnedTurnJob(
        _ receipt: CodexTurnJob,
        activityID: UUID,
        activityKey: String
    ) async -> CodexTurnJob? {
        var job = receipt
        var loggedStatus: String?
        let deadline = Date().addingTimeInterval(62 * 60)
        while Date() < deadline, !Task.isCancelled {
            updateDirectActivity(activityID, for: activityKey, from: job)
            updatePendingTurn(id: activityID, job: job)
            if job.status != loggedStatus {
                loggedStatus = job.status
                AppLogger.ai.info(
                    "Codex direct activity status id=\(activityID) "
                        + "job=\(job.id) status=\(job.status) updates=\(job.updates?.count ?? 0)"
                )
            }
            if job.status == "completed" || job.status == "failed"
                || job.status == "blocked" || job.status == "unknown" {
                return job
            }

            try? await Task.sleep(for: .milliseconds(700))
            do {
                job = try await bridge.codexTurnStatus(jobId: job.id)
            } catch {
                guard Self.shouldRetryTurnStatus(after: error) else {
                    let described = Self.describe(error)
                    AppLogger.ai.warning(
                        "Codex direct receipt became terminal id=\(activityID) "
                            + "job=\(job.id): \(described.combined)"
                    )
                    return CodexTurnJob(
                        id: job.id,
                        submissionId: job.submissionId,
                        taskId: job.taskId,
                        taskTitle: job.taskTitle,
                        status: "failed",
                        mode: job.mode,
                        createdAt: job.createdAt,
                        updatedAt: job.updatedAt,
                        turnId: job.turnId,
                        delivery: job.delivery,
                        response: job.response,
                        updates: job.updates,
                        error: described.combined,
                        code: "turn-receipt-unavailable",
                        hint: described.hint,
                        retryable: false,
                        task: job.task,
                        approval: nil
                    )
                }
                mutateDirectActivity(activityID, for: activityKey) {
                    $0.retryCount += 1
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        return nil
    }

    private func deliver(
        instruction: String,
        to lane: CodexLane,
        laneNumber: Int,
        mode: CodexMessageMode
    ) async {
        let activityID = UUID()
        beginSubmission(on: laneNumber)
        appendActivity(CodexLaneActivity(
            id: activityID,
            instruction: instruction,
            state: .working(mode)
        ), on: laneNumber)
        AppLogger.ai.info(
            "Codex activity created lane=\(laneNumber) id=\(activityID) "
                + "mode=\(mode.rawValue) chars=\(instruction.count)"
        )
        phase = .submitting
        failure = nil

        let receipt: CodexTurnJob
        do {
            receipt = try await startTurnWithRetry(
                submissionID: activityID,
                onRetry: { [weak self] retryCount in
                    self?.mutateActivity(activityID, on: laneNumber) {
                        $0.retryCount = retryCount
                    }
                },
                operation: {
                    try await bridge.codexStartTurn(
                        submissionId: activityID,
                        taskId: lane.task.id,
                        taskTitle: lane.task.title,
                        text: instruction,
                        mode: mode
                    )
                }
            )
        } catch {
            finishSubmission(activityID, on: laneNumber)
            guard isCurrentActivity(activityID, on: laneNumber) else { return }
            let described = Self.describe(error)
            failure = described
            failActivity(activityID, on: laneNumber, message: described.combined)
            phase = .failed(described.message)
            AppLogger.ai.warning("Codex submit failed on lane \(laneNumber): \(described.combined)")
            return
        }

        updateActivity(activityID, on: laneNumber, from: receipt)
        AppLogger.ai.info(
            "Codex activity accepted lane=\(laneNumber) id=\(activityID) job=\(receipt.id) "
                + "status=\(receipt.status) mode=\(receipt.mode.rawValue) "
                + "delivery=\(receipt.delivery ?? "pending")"
        )

        savePendingTurn(
            id: activityID,
            instruction: instruction,
            task: lane.task,
            laneNumber: laneNumber,
            job: receipt
        )
        finishSubmission(activityID, on: laneNumber)
        await startPendingTurnTask(id: activityID).value
    }

    private func finishLaneTurn(
        _ receipt: CodexTurnJob,
        instruction: String,
        task: CodexTaskSummary,
        activityID: UUID,
        laneNumber: Int
    ) async {

        let job = await waitForTurnJob(receipt, activityID: activityID, laneNumber: laneNumber)
        guard let job else {
            finishSubmission(activityID, on: laneNumber)
            guard isCurrentActivity(activityID, on: laneNumber) else { return }
            phase = .failed("Timed out waiting for the Mac-owned turn.")
            return
        }

        finishSubmission(activityID, on: laneNumber)
        updatePendingTurn(id: activityID, job: job)
        if job.status == "failed" || job.status == "blocked" || job.status == "unknown" {
            guard UIApplication.shared.applicationState == .active else {
                AppLogger.ai.info(
                    "iPhone Codex terminal receipt retained id=\(activityID) job=\(job.id) "
                        + "status=\(job.status) reason=app-inactive"
                )
                phase = isTurnInFlight ? .submitting : .idle
                return
            }
            let message = job.error
                ?? (job.status == "blocked" ? "Codex needs attention on the Mac." : "The Codex turn failed on the Mac.")
            failure = CodexLaneFailure(message: message, hint: job.hint)
            failActivity(activityID, on: laneNumber, message: message)
            phase = .failed(message)
            removePendingTurn(id: activityID)
            if job.code == "stale-thread" {
                clearLane(laneNumber)
            }
            return
        }

        guard let deliveryValue = job.delivery,
              let delivery = CodexTurnDelivery(rawValue: deliveryValue) else {
            let message = "Codex reported an incomplete delivery receipt."
            failure = CodexLaneFailure(
                message: message,
                hint: "Update Talkie so it understands this version of Codex Desktop."
            )
            failActivity(activityID, on: laneNumber, message: message)
            phase = .failed(message)
            removePendingTurn(id: activityID)
            return
        }

        AppLogger.ai.info(
            "Codex response received lane=\(laneNumber) delivery=\(deliveryValue) "
                + "hasResponse=\(job.response?.isEmpty == false)"
        )

        // A steer is an immediate receipt. The request which started the active
        // turn remains responsible for its one final response and narration.
        guard let responseText = job.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !responseText.isEmpty else {
            guard delivery == .steeredActiveTurn else {
                let message = "Codex completed without a readable response."
                failure = CodexLaneFailure(
                    message: message,
                    hint: "Open the task on your Mac to inspect the turn."
                )
                failActivity(activityID, on: laneNumber, message: message)
                phase = .failed(message)
                removePendingTurn(id: activityID)
                return
            }
            acceptActivity(activityID, on: laneNumber, delivery: delivery)
            if isCurrentActivity(activityID, on: laneNumber) {
                phase = isTurnInFlight ? .submitting : .idle
            }
            removePendingTurn(id: activityID)
            return
        }

        receiveActivity(
            activityID,
            on: laneNumber,
            response: responseText,
            delivery: delivery
        )

        var record = CodexTurnRecord(
            laneNumber: laneNumber,
            taskID: task.id,
            taskTitle: task.title,
            instruction: instruction,
            response: responseText,
            delivery: delivery
        )

        // The turn already succeeded. Everything below is presentation, and it
        // records the response before narration is attempted so the text stays
        // readable no matter what speech does.
        // A locked screen must not turn a successful receipt into a silent
        // one. `narrate` owns the short background window needed to synthesize
        // and schedule playback.
        if !notificationNarratedJobIDs.contains(job.id) {
            record = await narrate(record)
        } else {
            record.narrationSuppressed = true
            let route = AIResponseSpeechRoute(
                rawValue: TalkieAppSettings.shared.aiVoiceOutputRoute
            ) ?? .phone
            narrationState = .suppressed(laneNumber: laneNumber, route: route)
            phase = isTurnInFlight ? .submitting : .idle
        }
        remember(record)
        removePendingTurn(id: activityID)
    }

    private func waitForTurnJob(
        _ receipt: CodexTurnJob,
        activityID: UUID,
        laneNumber: Int
    ) async -> CodexTurnJob? {
        var job = receipt
        var loggedStatus: String?
        let deadline = Date().addingTimeInterval(62 * 60)
        while Date() < deadline, !Task.isCancelled {
            updateActivity(activityID, on: laneNumber, from: job)
            updatePendingTurn(id: activityID, job: job)
            if job.status != loggedStatus {
                loggedStatus = job.status
                AppLogger.ai.info(
                    "Codex activity status lane=\(laneNumber) id=\(activityID) "
                        + "job=\(job.id) status=\(job.status) updates=\(job.updates?.count ?? 0)"
                )
            }
            if job.status == "completed" || job.status == "failed"
                || job.status == "blocked" || job.status == "unknown" {
                return job
            }

            try? await Task.sleep(for: .milliseconds(700))
            do {
                job = try await bridge.codexTurnStatus(jobId: job.id)
            } catch {
                guard Self.shouldRetryTurnStatus(after: error) else {
                    let described = Self.describe(error)
                    AppLogger.ai.warning(
                        "Codex receipt became terminal lane=\(laneNumber) id=\(activityID) "
                            + "job=\(job.id): \(described.combined)"
                    )
                    return CodexTurnJob(
                        id: job.id,
                        submissionId: job.submissionId,
                        taskId: job.taskId,
                        taskTitle: job.taskTitle,
                        status: "failed",
                        mode: job.mode,
                        createdAt: job.createdAt,
                        updatedAt: job.updatedAt,
                        turnId: job.turnId,
                        delivery: job.delivery,
                        response: job.response,
                        updates: job.updates,
                        error: described.combined,
                        code: "turn-receipt-unavailable",
                        hint: described.hint,
                        retryable: false,
                        task: job.task,
                        approval: nil
                    )
                }
                // Leaving the foreground may suspend network work. Keep the
                // Mac-owned receipt alive for genuinely transient failures.
                mutateActivity(activityID, on: laneNumber) {
                    $0.retryCount += 1
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        failActivity(activityID, on: laneNumber, message: "Timed out waiting for the Mac-owned turn.")
        return nil
    }

    static func shouldRetryTurnStatus(after error: Error) -> Bool {
        if error is URLError { return true }

        guard let bridgeError = error as? BridgeError else { return false }
        switch bridgeError {
        case .connectionFailed:
            return true
        case .httpError(let status, _):
            return status == 408 || status == 425 || status == 429 || (500..<600).contains(status)
        case .notConfigured,
             .invalidResponse,
             .pairingRejected,
             .messageFailed,
             .encryptionDowngrade:
            return false
        }
    }

    /// Retries transport-level uncertainty with the same submission identity.
    /// The Mac de-duplicates that identity, so a lost HTTP response can never
    /// turn one spoken instruction into duplicate Codex turns.
    private func startTurnWithRetry(
        submissionID: UUID,
        onRetry: (Int) -> Void,
        operation: () async throws -> CodexTurnJob
    ) async throws -> CodexTurnJob {
        let maximumAttempts = 4
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < maximumAttempts,
                      Self.shouldRetryTurnStatus(after: error) else {
                    throw error
                }

                onRetry(attempt)
                AppLogger.ai.warning(
                    "Codex dispatch transport retry submission=\(submissionID) "
                        + "attempt=\(attempt + 1)/\(maximumAttempts)"
                )
                let delay = min(4_000, 500 * (1 << (attempt - 1)))
                try? await Task.sleep(for: .milliseconds(delay))
                attempt += 1
            }
        }
    }

    private func updateActivity(
        _ id: UUID,
        on laneNumber: Int,
        from job: CodexTurnJob
    ) {
        updateQueuedDisposition(id, on: laneNumber, from: job)
        mutateActivity(id, on: laneNumber) { activity in
            activity.jobID = job.id
            activity.retryCount = 0
            activity.updates = job.updates ?? []
            if let deliveryValue = job.delivery,
               let delivery = CodexTurnDelivery(rawValue: deliveryValue),
               job.status != "failed",
               job.status != "blocked",
               job.status != "unknown" {
                activity.state = .accepted(delivery)
            }
        }
    }

    private func isCurrentActivity(_ id: UUID, on laneNumber: Int) -> Bool {
        liveActivitiesByLane[laneNumber]?.contains { $0.id == id } == true
    }

    func narrateNotificationResponse(
        _ response: String,
        preview: String,
        jobID: String
    ) async {
        notificationNarratedJobIDs.insert(jobID)
        _ = await AIResponseSpeechRouter.shared.speak(response, preview: preview)
    }

    private func beginSubmission(on laneNumber: Int) {
        inFlightRequestCounts[laneNumber, default: 0] += 1
    }

    private func finishSubmission(_ activityID: UUID, on laneNumber: Int) {
        let remaining = max(0, inFlightRequestCounts[laneNumber, default: 0] - 1)
        if remaining == 0 {
            inFlightRequestCounts[laneNumber] = nil
        } else {
            inFlightRequestCounts[laneNumber] = remaining
        }
        if queuedActivityIDs.remove(activityID) != nil {
            let queued = max(0, queuedMessageCounts[laneNumber, default: 0] - 1)
            if queued == 0 {
                queuedMessageCounts[laneNumber] = nil
            } else {
                queuedMessageCounts[laneNumber] = queued
            }
        }
    }

    private func updateQueuedDisposition(
        _ activityID: UUID,
        on laneNumber: Int,
        from job: CodexTurnJob
    ) {
        guard job.delivery == CodexTurnDelivery.queuedTurn.rawValue,
              queuedActivityIDs.insert(activityID).inserted else { return }
        queuedMessageCounts[laneNumber, default: 0] += 1
    }

    private func acceptActivity(
        _ id: UUID,
        on laneNumber: Int,
        delivery: CodexTurnDelivery
    ) {
        mutateActivity(id, on: laneNumber) { activity in
            activity.state = .accepted(delivery)
        }
    }

    private func receiveActivity(
        _ id: UUID,
        on laneNumber: Int,
        response: String,
        delivery: CodexTurnDelivery
    ) {
        mutateActivity(id, on: laneNumber) { activity in
            activity.response = response
            activity.state = .receiving(delivery)
        }
    }

    private func failActivity(_ id: UUID, on laneNumber: Int, message: String) {
        mutateActivity(id, on: laneNumber) { activity in
            activity.state = .failed(message)
        }
    }

    private func appendActivity(_ activity: CodexLaneActivity, on laneNumber: Int) {
        var activities = liveActivitiesByLane[laneNumber] ?? []
        activities.append(activity)
        if activities.count > Self.liveActivityLimit {
            activities.removeFirst(activities.count - Self.liveActivityLimit)
        }
        liveActivitiesByLane[laneNumber] = activities
    }

    private func mutateActivity(
        _ id: UUID,
        on laneNumber: Int,
        mutation: (inout CodexLaneActivity) -> Void
    ) {
        guard var activities = liveActivitiesByLane[laneNumber],
              let index = activities.firstIndex(where: { $0.id == id }) else { return }
        mutation(&activities[index])
        liveActivitiesByLane[laneNumber] = activities
    }

    private func appendDirectActivity(
        _ activity: CodexLaneActivity,
        for key: String
    ) {
        var activities = liveActivitiesByDirectKey[key] ?? []
        activities.append(activity)
        if activities.count > Self.liveActivityLimit {
            activities.removeFirst(activities.count - Self.liveActivityLimit)
        }
        liveActivitiesByDirectKey[key] = activities
    }

    private func mutateDirectActivity(
        _ id: UUID,
        for key: String,
        mutation: (inout CodexLaneActivity) -> Void
    ) {
        guard var activities = liveActivitiesByDirectKey[key],
              let index = activities.firstIndex(where: { $0.id == id }) else { return }
        mutation(&activities[index])
        liveActivitiesByDirectKey[key] = activities
    }

    private func moveDirectActivities(from sourceKey: String, to destinationKey: String) {
        guard sourceKey != destinationKey,
              let pending = liveActivitiesByDirectKey.removeValue(forKey: sourceKey) else { return }
        let existing = liveActivitiesByDirectKey[destinationKey] ?? []
        liveActivitiesByDirectKey[destinationKey] = Array(
            (existing + pending)
                .sorted { $0.sentAt < $1.sentAt }
                .suffix(Self.liveActivityLimit)
        )
    }

    private func updateDirectActivity(
        _ id: UUID,
        for key: String,
        from job: CodexTurnJob
    ) {
        mutateDirectActivity(id, for: key) { activity in
            activity.jobID = job.id
            activity.retryCount = 0
            activity.updates = job.updates ?? []
            if let deliveryValue = job.delivery,
               let delivery = CodexTurnDelivery(rawValue: deliveryValue),
               job.status != "failed",
               job.status != "blocked",
               job.status != "unknown" {
                activity.state = .accepted(delivery)
            }
        }
    }

    private func acceptDirectActivity(
        _ id: UUID,
        for key: String,
        delivery: CodexTurnDelivery
    ) {
        mutateDirectActivity(id, for: key) {
            $0.state = .accepted(delivery)
        }
    }

    private func receiveDirectActivity(
        _ id: UUID,
        for key: String,
        response: String,
        delivery: CodexTurnDelivery
    ) {
        mutateDirectActivity(id, for: key) {
            $0.response = response
            $0.state = .receiving(delivery)
        }
    }

    private func failDirectActivity(_ id: UUID, for key: String, message: String) {
        mutateDirectActivity(id, for: key) {
            $0.state = .failed(message)
        }
    }

    // MARK: - Narration

    /// Speaks the response through the app's existing output route and returns
    /// the record annotated with what actually happened. Never throws: a
    /// narration problem is an annotation on a successful turn.
    private func narrate(_ record: CodexTurnRecord) async -> CodexTurnRecord {
        var record = record

        // The response often lands seconds after dictation has ended and the
        // user has locked the phone. Keep the process alive long enough to
        // synthesize and schedule spoken-audio playback; the app's audio
        // background mode owns playback after this method returns.
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "Codex response narration"
        ) {
            AppLogger.ai.warning("Codex narration background window expired")
        }
        defer {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }

        let route = AIResponseSpeechRoute(
            rawValue: TalkieAppSettings.shared.aiVoiceOutputRoute
        ) ?? .phone

        AppLogger.ai.info(
            "Codex narration decision route=\(route.rawValue) "
                + "provider=\(TalkieAppSettings.shared.ttsProvider) "
                + "mode=\(TalkieAppSettings.shared.ttsMode) chars=\(record.response.count)"
        )

        guard route != .silent else {
            AppLogger.ai.info("Codex narration suppressed route=silent")
            record.narrationSuppressed = true
            narrationState = .suppressed(laneNumber: record.laneNumber, route: route)
            phase = isTurnInFlight ? .submitting : .idle
            return record
        }

        // A previous playback timer must not clear the status for this newer
        // synthesis while it is still waiting on the remote provider.
        speakingTask?.cancel()
        speakingTask = nil
        narrationState = .preparing(laneNumber: record.laneNumber, route: route)
        phase = .preparingSpeech
        let result = await AIResponseSpeechRouter.shared.speak(
            record.response,
            preview: record.taskTitle
        )

        AppLogger.ai.info(
            "Codex narration result route=\(result.route.rawValue) "
                + "didSpeak=\(result.didSpeak) failure=\(result.failure ?? "none") "
                + "duration=\(result.speechDuration)"
        )

        if let speechFailure = result.failure {
            record.speechFailure = speechFailure
            narrationState = .failed(
                laneNumber: record.laneNumber,
                route: result.route,
                message: speechFailure
            )
            phase = isTurnInFlight ? .submitting : .idle
            AppLogger.ai.warning("Codex narration failed: \(speechFailure)")
            return record
        }

        guard result.didSpeak else {
            record.narrationSuppressed = true
            narrationState = .suppressed(laneNumber: record.laneNumber, route: result.route)
            phase = isTurnInFlight ? .submitting : .idle
            return record
        }

        // Hold `.speaking` for as long as audio is actually playing, so the deck
        // reports the phase the user is in rather than snapping back to idle
        // while the response is still being read.
        narrationState = .speaking(laneNumber: record.laneNumber, route: result.route)
        phase = .speaking
        speakingTask?.cancel()
        speakingTask = Task { [weak self] in
            while WalkieFX.shared.isVoicePlaybackActive, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.phase == .speaking {
                self.phase = self.isTurnInFlight ? .submitting : .idle
            }
            if case .speaking(let laneNumber, _) = self.narrationState,
               laneNumber == record.laneNumber {
                self.narrationState = .idle
            }
            self.speakingTask = nil
        }

        return record
    }

    private func remember(_ record: CodexTurnRecord) {
        lastTurn = record
        history.insert(record, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    // MARK: - Internals

    private static func describe(_ error: Error) -> CodexLaneFailure {
        // The Mac's error bodies already carry both the symptom and the
        // recovery hint, and the bridge client joins them, so the useful
        // message is the localized description of the thrown BridgeError.
        if case BridgeError.httpError(_, let detail) = error,
           let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            return CodexLaneFailure(message: detail, hint: nil)
        }

        if case BridgeError.notConfigured = error {
            return CodexLaneFailure(
                message: "This iPhone isn't paired with a Mac.",
                hint: "Pair from Talkie on your Mac, then try again."
            )
        }

        if case BridgeError.connectionFailed = error {
            return CodexLaneFailure(
                message: "Couldn't reach your Mac.",
                hint: "Make sure Talkie is running on the Mac and both devices are on the same network."
            )
        }

        return CodexLaneFailure(message: error.localizedDescription, hint: nil)
    }

    // MARK: - Persistence

    private static var pendingTurnStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Codex", directoryHint: .isDirectory)
            .appending(path: "pending-phone-turns.json")
    }

    private func loadPersistedLanes() {
        guard let loadedHostID else { return }

        let lanesKey = Keys.lanes(for: loadedHostID)
        let activeLaneKey = Keys.activeLane(for: loadedHostID)
        let selectedChannelKey = Keys.selectedChannel(for: loadedHostID)

        migrateLegacyLanesIfNeeded(to: loadedHostID)

        if let data = defaults.data(forKey: lanesKey),
           let stored = try? JSONDecoder().decode([CodexLane].self, from: data) {
            lanes = Dictionary(
                uniqueKeysWithValues: stored
                    .filter { CodexLane.range.contains($0.number) }
                    .map { ($0.number, $0) }
            )
        }

        // Restore only a pinned destination. A recent task opened outside the
        // lane bank is deliberately temporary and must not re-arm itself on a
        // later launch.
        let storedActive = defaults.integer(forKey: activeLaneKey)
        if lanes[storedActive] != nil {
            activeLaneNumber = storedActive
        }

        if let data = defaults.data(forKey: selectedChannelKey),
           let storedChannel = try? JSONDecoder().decode(CodexTaskSummary.self, from: data),
           let storedLane = lanes.values.first(where: { $0.task.id == storedChannel.id }) {
            selectedChannel = storedLane.task
            activeLaneNumber = storedLane.number
        } else {
            selectedChannel = activeLane?.task
            defaults.removeObject(forKey: selectedChannelKey)
        }
    }

    private func persistLanes() {
        guard let loadedHostID else { return }
        let ordered = sortedLanes
        guard let data = try? JSONEncoder().encode(ordered) else { return }
        defaults.set(data, forKey: Keys.lanes(for: loadedHostID))
    }

    private func persistActiveLane() {
        guard let loadedHostID else { return }
        let key = Keys.activeLane(for: loadedHostID)
        if let activeLaneNumber {
            defaults.set(activeLaneNumber, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func persistSelectedChannel() {
        guard let loadedHostID else { return }
        let key = Keys.selectedChannel(for: loadedHostID)
        if let activeLaneNumber,
           let selectedChannel,
           lanes[activeLaneNumber]?.task.id == selectedChannel.id,
           let data = try? JSONEncoder().encode(selectedChannel) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Assign the former global lane bank to the first paired host which opens
    /// it. This preserves existing mappings once without leaking them to every
    /// Mac the user subsequently selects.
    private func migrateLegacyLanesIfNeeded(to hostID: String) {
        guard defaults.string(forKey: Keys.migratedLegacyHost) == nil else { return }
        defer { defaults.set(hostID, forKey: Keys.migratedLegacyHost) }

        guard defaults.data(forKey: Keys.lanes(for: hostID)) == nil,
              let legacyData = defaults.data(forKey: Keys.legacyLanes) else {
            return
        }

        defaults.set(legacyData, forKey: Keys.lanes(for: hostID))
        if defaults.object(forKey: Keys.legacyActiveLane) != nil {
            defaults.set(
                defaults.integer(forKey: Keys.legacyActiveLane),
                forKey: Keys.activeLane(for: hostID)
            )
        }
    }
}
