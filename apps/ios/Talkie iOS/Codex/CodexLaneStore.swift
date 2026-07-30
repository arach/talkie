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

    // MARK: - Voice loop

    @Published private(set) var phase: CodexLanePhase = .idle
    @Published private(set) var narrationState: CodexNarrationState = .idle
    @Published private(set) var failure: CodexLaneFailure?
    @Published private(set) var lastTurn: CodexTurnRecord?
    @Published private(set) var history: [CodexTurnRecord] = []
    @Published private(set) var liveActivitiesByLane: [Int: [CodexLaneActivity]] = [:]
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

    init(
        defaults: UserDefaults = .standard,
        bridge: BridgeManager? = nil,
        hostIDOverride: String? = nil
    ) {
        self.defaults = defaults
        let resolvedBridge = bridge ?? .shared
        self.bridge = resolvedBridge
        self.loadedHostID = hostIDOverride ?? resolvedBridge.activePairedMacID
        self.canCreateChannel = resolvedBridge.activePairedMacID?.isEmpty == false
        loadPersistedLanes()
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

        loadedHostID = nextHostID
        canCreateChannel = nextHostID?.isEmpty == false
        lanes = [:]
        activeLaneNumber = nil
        selectedChannel = nil
        catalog = []
        nextCatalogCursor = nil
        catalogFailure = nil
        creationFailure = nil
        searchQuery = ""
        liveActivitiesByLane = [:]
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

    /// Creates and selects a channel without assigning it to a lane. The bridge request intentionally
    /// carries no model field, so Codex uses the Mac's configured default.
    @discardableResult
    func createTask(
        in project: CodexProjectSummary,
        creationID: UUID
    ) async -> CodexTaskSummary? {
        guard !isCreatingTask else { return nil }
        creationFailure = nil
        guard project.hostID == loadedHostID else {
            creationFailure = CodexLaneFailure(
                message: "That project belongs to another Mac.",
                hint: "Reconnect to the Mac that owns it and try again."
            )
            return nil
        }

        isCreatingTask = true
        defer { isCreatingTask = false }

        do {
            let task = try await bridge.codexCreateTask(
                creationId: creationID,
                cwd: project.cwd
            )
            retainRecentlyCreatedTask(task)
            catalog = Self.mergingCatalog([task], with: catalog)
            selectChannel(task)
            creationFailure = nil
            return task
        } catch {
            creationFailure = Self.describe(error)
            AppLogger.ai.warning("Codex task creation failed: \(error.localizedDescription)")
            return nil
        }
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
        guard phase.isCapturing else { return }
        isPushToTalkHeld = false
        dictation.cancel()
        phase = isTurnInFlight ? .submitting : .idle
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
        guard selectedTask != nil else {
            failure = CodexLaneFailure(
                message: "No Codex channel is selected.",
                hint: "Open the channel catalogue and choose an exact task."
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
                // Only reflect this while we own the flow; the controller also
                // reports `.transcribing` during its permission preflight.
                if self.phase == .listening || self.phase == .idle {
                    self.phase = .transcribing
                }
            case .idle:
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
            self.failure = CodexLaneFailure(message: message, hint: nil)
            self.phase = .failed(message)
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

        guard let task = selectedTask else {
            let described = CodexLaneFailure(
                message: "No Codex channel is selected.",
                hint: "Open the channel catalogue and choose an exact task."
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

    private func deliverToUnpinnedChannel(
        instruction: String,
        task: CodexTaskSummary
    ) async {
        let submissionID = UUID()
        unpinnedInFlightRequestCount += 1
        phase = .submitting
        failure = nil

        let receipt: CodexTurnJob
        do {
            receipt = try await bridge.codexStartTurn(
                submissionId: submissionID,
                taskId: task.id,
                taskTitle: task.title,
                text: instruction,
                mode: .steer
            )
        } catch {
            unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
            let described = Self.describe(error)
            failure = described
            phase = .failed(described.message)
            AppLogger.ai.warning("Codex submit failed channel=\(task.id): \(described.combined)")
            return
        }

        guard let job = await waitForUnpinnedTurnJob(receipt) else {
            unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)
            phase = .failed("Timed out waiting for the Mac-owned turn.")
            return
        }
        unpinnedInFlightRequestCount = max(0, unpinnedInFlightRequestCount - 1)

        if job.status == "failed" || job.status == "blocked" || job.status == "unknown" {
            let message = job.error
                ?? (job.status == "blocked" ? "Codex needs attention on the Mac." : "The Codex turn failed on the Mac.")
            failure = CodexLaneFailure(message: message, hint: job.hint)
            phase = .failed(message)
            return
        }

        guard let deliveryValue = job.delivery,
              let delivery = CodexTurnDelivery(rawValue: deliveryValue) else {
            let message = "Codex reported an incomplete delivery receipt."
            failure = CodexLaneFailure(
                message: message,
                hint: "Update Talkie so it understands this version of Codex Desktop."
            )
            phase = .failed(message)
            return
        }

        guard let response = job.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else {
            if delivery == .steeredActiveTurn {
                phase = isTurnInFlight ? .submitting : .idle
            } else {
                let message = "Codex completed without a readable response."
                failure = CodexLaneFailure(message: message, hint: "Open the task on your Mac to inspect the turn.")
                phase = .failed(message)
            }
            return
        }

        var record = CodexTurnRecord(
            laneNumber: nil,
            taskID: task.id,
            taskTitle: task.title,
            instruction: instruction,
            response: response,
            delivery: delivery
        )
        if UIApplication.shared.applicationState == .active,
           !notificationNarratedJobIDs.contains(job.id) {
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
    }

    private func waitForUnpinnedTurnJob(_ receipt: CodexTurnJob) async -> CodexTurnJob? {
        var job = receipt
        let deadline = Date().addingTimeInterval(62 * 60)
        while Date() < deadline, !Task.isCancelled {
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
                    failure = described
                    return nil
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
            receipt = try await bridge.codexStartTurn(
                submissionId: activityID,
                taskId: lane.task.id,
                taskTitle: lane.task.title,
                text: instruction,
                mode: mode
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

        mutateActivity(activityID, on: laneNumber) { activity in
            activity.jobID = receipt.id
        }
        updateQueuedDisposition(activityID, on: laneNumber, from: receipt)
        AppLogger.ai.info(
            "Codex activity accepted lane=\(laneNumber) id=\(activityID) job=\(receipt.id) "
                + "status=\(receipt.status) mode=\(receipt.mode.rawValue) "
                + "delivery=\(receipt.delivery ?? "pending")"
        )

        let job = await waitForTurnJob(receipt, activityID: activityID, laneNumber: laneNumber)
        guard let job else {
            finishSubmission(activityID, on: laneNumber)
            guard isCurrentActivity(activityID, on: laneNumber) else { return }
            phase = .failed("Timed out waiting for the Mac-owned turn.")
            return
        }

        if job.status == "failed" || job.status == "blocked" || job.status == "unknown" {
            finishSubmission(activityID, on: laneNumber)
            guard isCurrentActivity(activityID, on: laneNumber) else { return }
            let message = job.error
                ?? (job.status == "blocked" ? "Codex needs attention on the Mac." : "The Codex turn failed on the Mac.")
            failure = CodexLaneFailure(message: message, hint: job.hint)
            failActivity(activityID, on: laneNumber, message: message)
            phase = .failed(message)
            if job.code == "stale-thread" {
                clearLane(laneNumber)
            }
            return
        }

        guard let deliveryValue = job.delivery,
              let delivery = CodexTurnDelivery(rawValue: deliveryValue) else {
            finishSubmission(activityID, on: laneNumber)
            guard isCurrentActivity(activityID, on: laneNumber) else { return }
            let message = "Codex reported an incomplete delivery receipt."
            failure = CodexLaneFailure(
                message: message,
                hint: "Update Talkie so it understands this version of Codex Desktop."
            )
            failActivity(activityID, on: laneNumber, message: message)
            phase = .failed(message)
            return
        }

        finishSubmission(activityID, on: laneNumber)

        AppLogger.ai.info(
            "Codex response received lane=\(laneNumber) delivery=\(deliveryValue) "
                + "hasResponse=\(job.response?.isEmpty == false)"
        )

        // A steer is an immediate receipt. The request which started the active
        // turn remains responsible for its one final response and narration.
        guard let responseText = job.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !responseText.isEmpty else {
            guard delivery == .steeredActiveTurn else {
                guard isCurrentActivity(activityID, on: laneNumber) else { return }
                let message = "Codex completed without a readable response."
                failure = CodexLaneFailure(
                    message: message,
                    hint: "Open the task on your Mac to inspect the turn."
                )
                failActivity(activityID, on: laneNumber, message: message)
                phase = .failed(message)
                return
            }
            acceptActivity(activityID, on: laneNumber, delivery: delivery)
            if isCurrentActivity(activityID, on: laneNumber) {
                phase = isTurnInFlight ? .submitting : .idle
            }
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
            taskID: lane.task.id,
            taskTitle: lane.task.title,
            instruction: instruction,
            response: responseText,
            delivery: delivery
        )

        // The turn already succeeded. Everything below is presentation, and it
        // records the response before narration is attempted so the text stays
        // readable no matter what speech does.
        if UIApplication.shared.applicationState == .active,
           !notificationNarratedJobIDs.contains(job.id) {
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
                        task: job.task
                    )
                }
                // Leaving the foreground may suspend network work. Keep the
                // Mac-owned receipt alive for genuinely transient failures.
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

    private func updateActivity(
        _ id: UUID,
        on laneNumber: Int,
        from job: CodexTurnJob
    ) {
        updateQueuedDisposition(id, on: laneNumber, from: job)
        mutateActivity(id, on: laneNumber) { activity in
            activity.jobID = job.id
            activity.updates = job.updates ?? []
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

    // MARK: - Narration

    /// Speaks the response through the app's existing output route and returns
    /// the record annotated with what actually happened. Never throws: a
    /// narration problem is an annotation on a successful turn.
    private func narrate(_ record: CodexTurnRecord) async -> CodexTurnRecord {
        var record = record

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

        // Restore the selected destination so the deck opens where the user
        // left it. The submit itself is the live availability check.
        let storedActive = defaults.integer(forKey: activeLaneKey)
        if lanes[storedActive] != nil {
            activeLaneNumber = storedActive
        }

        if let data = defaults.data(forKey: selectedChannelKey),
           let storedChannel = try? JSONDecoder().decode(CodexTaskSummary.self, from: data) {
            selectedChannel = storedChannel
            if lanes[activeLaneNumber ?? 0]?.task.id != storedChannel.id {
                activeLaneNumber = lanes.values.first(where: { $0.task.id == storedChannel.id })?.number
            }
        } else {
            selectedChannel = activeLane?.task
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
        if let selectedChannel,
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
