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

@MainActor
final class CodexLaneStore: ObservableObject {
    static let shared = CodexLaneStore()

    private enum Keys {
        static let lanes = "codex.lanes.v1"
        static let activeLane = "codex.lanes.active.v1"
    }

    /// Cadence of the catalog refresh while the mapper is on screen.
    private static let catalogRefreshInterval: TimeInterval = 15

    private static let historyLimit = 20

    // MARK: - Lane bindings

    @Published private(set) var lanes: [Int: CodexLane] = [:]
    @Published private(set) var activeLaneNumber: Int?

    // MARK: - Voice loop

    @Published private(set) var phase: CodexLanePhase = .idle
    @Published private(set) var failure: CodexLaneFailure?
    @Published private(set) var lastTurn: CodexTurnRecord?
    @Published private(set) var history: [CodexTurnRecord] = []
    @Published private(set) var isTurnInFlight = false
    @Published private(set) var queuedMessageCount = 0
    @Published private(set) var duringTurnMessageMode: CodexMessageMode = .queue

    // MARK: - Mapper catalog

    @Published private(set) var catalog: [CodexTaskSummary] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogFailure: CodexLaneFailure?
    @Published var searchQuery: String = ""

    private let defaults: UserDefaults
    private let bridge: BridgeManager
    private lazy var dictation: InlineDictationController = makeDictationController()
    private var catalogRefreshTask: Task<Void, Never>?
    private var catalogViewers = 0
    private var speakingTask: Task<Void, Never>?
    private var isPushToTalkHeld = false
    private var submissionRequestCount = 0

    init(
        defaults: UserDefaults = .standard,
        bridge: BridgeManager = .shared
    ) {
        self.defaults = defaults
        self.bridge = bridge
        loadPersistedLanes()
    }

    // MARK: - Derived state

    var sortedLanes: [CodexLane] {
        lanes.values.sorted { $0.number < $1.number }
    }

    var activeLane: CodexLane? {
        activeLaneNumber.flatMap { lanes[$0] }
    }

    func lane(_ number: Int) -> CodexLane? { lanes[number] }

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
            let tasks = try await bridge.codexRecentTasks(limit: 25)
            catalog = tasks
            catalogFailure = nil
        } catch {
            // Keep whatever we last showed — a stale list the user can read
            // beats an empty one — but say the refresh failed.
            catalogFailure = Self.describe(error)
            AppLogger.ai.warning("Codex catalog refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Assignment

    /// Binds a task to a lane without changing the active lane.
    func assign(_ task: CodexTaskSummary, to number: Int) {
        guard CodexLane.range.contains(number) else { return }

        let existingOverride = lanes[number]?.voiceOverride
        lanes[number] = CodexLane(number: number, task: task, voiceOverride: existingOverride)

        persistLanes()
    }

    func clearLane(_ number: Int) {
        guard lanes[number] != nil else { return }
        lanes[number] = nil

        if activeLaneNumber == number {
            activeLaneNumber = nil
            persistActiveLane()
        }
        persistLanes()
    }

    func setVoiceOverride(_ override: CodexLaneVoiceOverride?, for number: Int) {
        guard var lane = lanes[number] else { return }
        lane.voiceOverride = override
        lanes[number] = lane
        persistLanes()
    }

    // MARK: - Activation

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
        persistActiveLane()
        failure = nil
        phase = .idle
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
        if phase == .speaking {
            phase = isTurnInFlight ? .submitting : .idle
        }
    }

    /// Selects what the next utterance means while Codex is already working.
    /// Queue is the default; steer is always an explicit choice.
    func setDuringTurnMessageMode(_ mode: CodexMessageMode) {
        guard mode == .queue || mode == .steer else { return }
        duringTurnMessageMode = mode
    }

    /// Reads the last successful response again using the currently selected
    /// output route. The response remains available as text whether speech
    /// succeeds, fails, or is deliberately silent.
    func narrateLastResponse() {
        guard var record = lastTurn else {
            failure = CodexLaneFailure(
                message: "There is no response to narrate yet.",
                hint: "Send an instruction to Codex first."
            )
            return
        }

        interruptNarration()
        record.speechFailure = nil
        record.narrationSuppressed = false

        Task { [weak self] in
            guard let self else { return }
            let updated = await self.narrate(record)
            self.lastTurn = updated
            if let index = self.history.firstIndex(where: { $0.id == updated.id }) {
                self.history[index] = updated
            }
        }
    }

    private func startCapture() {
        guard let number = activeLaneNumber, lanes[number] != nil else {
            failure = CodexLaneFailure(
                message: "No lane is active.",
                hint: "Pick a lane in the lid first."
            )
            return
        }

        failure = nil
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

        guard let number = activeLaneNumber, let lane = lanes[number] else {
            let described = CodexLaneFailure(
                message: "No lane is active.",
                hint: "Pick a lane in the lid first."
            )
            failure = described
            phase = .failed(described.message)
            return
        }

        let mode = isTurnInFlight ? duringTurnMessageMode : .auto
        await deliver(
            instruction: text,
            to: lane,
            laneNumber: number,
            mode: mode
        )
    }

    private func deliver(
        instruction: String,
        to lane: CodexLane,
        laneNumber: Int,
        mode: CodexMessageMode
    ) async {
        submissionRequestCount += 1
        isTurnInFlight = true
        if mode == .queue {
            queuedMessageCount += 1
        }
        phase = .submitting
        failure = nil

        let response: CodexSubmitResponse
        do {
            response = try await bridge.codexSubmit(
                taskId: lane.task.id,
                text: instruction,
                mode: mode
            )
        } catch {
            finishSubmission(mode: mode)
            let described = Self.describe(error)
            failure = described
            phase = .failed(described.message)
            AppLogger.ai.warning("Codex submit failed on lane \(laneNumber): \(described.combined)")
            return
        }

        guard let delivery = CodexTurnDelivery(rawValue: response.delivery) else {
            finishSubmission(mode: mode)
            let message = "Codex reported an unrecognized delivery (\(response.delivery))."
            failure = CodexLaneFailure(
                message: message,
                hint: "Update Talkie so it understands this version of Codex Desktop."
            )
            phase = .failed(message)
            return
        }

        finishSubmission(mode: mode)

        AppLogger.ai.info(
            "Codex response received lane=\(laneNumber) delivery=\(response.delivery) "
                + "hasResponse=\(response.response?.isEmpty == false)"
        )

        // A steer is an immediate receipt. The request which started the active
        // turn remains responsible for its one final response and narration.
        guard let responseText = response.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !responseText.isEmpty else {
            guard delivery == .steeredActiveTurn else {
                let message = "Codex completed without a readable response."
                failure = CodexLaneFailure(
                    message: message,
                    hint: "Open the task on your Mac to inspect the turn."
                )
                phase = .failed(message)
                return
            }
            phase = isTurnInFlight ? .submitting : .idle
            return
        }

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
        record = await narrate(record)
        remember(record)
    }

    private func finishSubmission(mode: CodexMessageMode) {
        submissionRequestCount = max(0, submissionRequestCount - 1)
        isTurnInFlight = submissionRequestCount > 0
        if mode == .queue {
            queuedMessageCount = max(0, queuedMessageCount - 1)
        }
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
            phase = isTurnInFlight ? .submitting : .idle
            return record
        }

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
            phase = isTurnInFlight ? .submitting : .idle
            AppLogger.ai.warning("Codex narration failed: \(speechFailure)")
            return record
        }

        guard result.didSpeak else {
            record.narrationSuppressed = true
            phase = isTurnInFlight ? .submitting : .idle
            return record
        }

        // Hold `.speaking` for as long as audio is actually playing, so the deck
        // reports the phase the user is in rather than snapping back to idle
        // while the response is still being read.
        phase = .speaking
        let duration = result.speechDuration
        speakingTask?.cancel()
        speakingTask = Task { [weak self] in
            if duration > 0 {
                try? await Task.sleep(for: .seconds(duration))
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.phase == .speaking {
                self.phase = self.isTurnInFlight ? .submitting : .idle
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
        if let data = defaults.data(forKey: Keys.lanes),
           let stored = try? JSONDecoder().decode([CodexLane].self, from: data) {
            lanes = Dictionary(
                uniqueKeysWithValues: stored
                    .filter { CodexLane.range.contains($0.number) }
                    .map { ($0.number, $0) }
            )
        }

        // Restore the selected destination so the deck opens where the user
        // left it. The submit itself is the live availability check.
        let storedActive = defaults.integer(forKey: Keys.activeLane)
        if lanes[storedActive] != nil {
            activeLaneNumber = storedActive
        }
    }

    private func persistLanes() {
        let ordered = sortedLanes
        guard let data = try? JSONEncoder().encode(ordered) else { return }
        defaults.set(data, forKey: Keys.lanes)
    }

    private func persistActiveLane() {
        if let activeLaneNumber {
            defaults.set(activeLaneNumber, forKey: Keys.activeLane)
        } else {
            defaults.removeObject(forKey: Keys.activeLane)
        }
    }
}
