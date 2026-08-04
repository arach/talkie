//
//  WatchSessionManager.swift
//  TalkieWatch
//
//  Handles WatchConnectivity communication with iPhone
//

import Foundation
import AVFoundation
import WatchConnectivity
import WatchKit

// MARK: - Watch Memo Model

struct WatchMemo: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    var status: MemoStatus
    var transcriptionPreview: String?
    var presetId: String?
    var presetName: String?
    /// Where the ask actually got to. Sent explicitly by the phone rather than
    /// inferred from `transcriptionPreview`, which used to be the only way to
    /// tell transcribing apart from answering.
    var phase: WatchAskPhase?
    /// Who narrated the finished answer. Rendered as provenance on the Asks
    /// surface; absent for memos that never carried an answer.
    var delivery: WatchAnswerDelivery?
    /// When the ask reached a terminal phase, which is what "have I seen this
    /// yet" is measured against. `timestamp` cannot serve: it records when the
    /// memo was captured, which is always before the wearer could have looked.
    var settledAt: Date?
    /// The question, kept apart from `transcriptionPreview` because that field
    /// is a single slot the answer overwrites. Without this the Asks page is a
    /// list of answers to questions you can no longer see — and a failure, whose
    /// preview becomes the error, would keep no record of itself at all.
    var askQuestion: String?
    /// When the phone last said anything about this ask. Distinct from
    /// `timestamp` (when it was recorded) and `settledAt` (when it finished):
    /// this is what "has the phone gone quiet" is measured against, and it is
    /// the only defence against an in-flight ask spinning forever because the
    /// terminal update never arrived.
    var lastUpdatedAt: Date?

    enum MemoStatus: String, Codable {
        case sending
        case sent
        case received      // iPhone received it
        case thinking      // iPhone is transcribing or answering
        case transcribed   // Transcription complete
        case answered      // AI answer is ready
        case failed
    }

    init(duration: TimeInterval) {
        self.id = UUID()
        self.timestamp = Date()
        self.duration = duration
        self.status = .sending
        self.transcriptionPreview = nil
        self.presetId = nil
        self.presetName = nil
        self.phase = nil
        self.delivery = nil
        self.settledAt = nil
        self.askQuestion = nil
        self.lastUpdatedAt = nil
    }

    /// Ask AI captures are the only ones the Asks surface lists. The preset is
    /// the discriminator because `sendAudio` attaches one only on the AI route.
    var isAsk: Bool { presetId == WatchPreset.ai.id }

    /// True while the phone still owes an outcome. Drives both the in-flight
    /// panel on the Asks page and the live state of the capture-face strip.
    var isInFlight: Bool {
        switch status {
        case .sending, .sent, .received, .thinking:
            return true
        case .transcribed, .answered, .failed:
            return false
        }
    }

    /// How long the phone may go quiet on an in-flight ask before the wrist
    /// stops claiming it is still working. Answering can legitimately take a
    /// while, so this is generous — the point is to eventually say something
    /// rather than to time the model.
    static let silenceTolerance: TimeInterval = 90

    /// When the phone was last heard from about this memo, falling back to the
    /// capture time for one that has never been updated.
    var lastHeardAt: Date { lastUpdatedAt ?? timestamp }

    /// True when an ask is still nominally in flight but the phone has said
    /// nothing for `silenceTolerance`. The phone cannot report its own death,
    /// so a dropped session, a force-quit, or a crashed provider all arrive as
    /// silence — and silence rendered as a spinner is the same silent failure
    /// this surface exists to end.
    func isStalled(asOf now: Date) -> Bool {
        guard isInFlight else { return false }
        return now.timeIntervalSince(lastHeardAt) > Self.silenceTolerance
    }

    /// The phase to render. Falls back to a status-derived value so a memo that
    /// predates the `phase` field, or an update from an older phone build, still
    /// reads correctly rather than showing nothing.
    var resolvedPhase: WatchAskPhase {
        if let phase { return phase }
        switch status {
        case .sending: return .sending
        case .sent: return .sending
        case .received: return .received
        case .thinking: return .transcribing
        // Transcription finished means the model has the question. Reporting
        // "TRANSCRIBING" here made the wrist read as stuck on a completed step
        // whenever the answer was slow.
        case .transcribed: return .answering
        case .answered: return .answered
        case .failed: return .failed
        }
    }
}

/// Where an ask has got to, in the vocabulary shared by the capture-face strip,
/// the Asks page, and the phone's activity pill.
///
/// Declared once per target with the raw values as the contract — the Watch
/// folder cannot share a type with the phone target — matching the pattern
/// already used by `status` and `delivery`.
enum WatchAskPhase: String, Codable {
    case queued
    case sending
    case received
    case transcribing
    case answering
    case answered
    case failed

    /// Uppercase mono label. Short enough to sit in the 24pt capture strip
    /// without truncating on the smallest supported watch.
    var label: String {
        switch self {
        case .queued: return "QUEUED"
        case .sending: return "SENDING"
        case .received: return "RECEIVED"
        case .transcribing: return "TRANSCRIBING"
        case .answering: return "ANSWERING"
        case .answered: return "ANSWER READY"
        case .failed: return "ASK FAILED"
        }
    }

    var isTerminal: Bool {
        self == .answered || self == .failed
    }
}

/// Who narrates a finished answer, and therefore who owns the arrival cue on
/// the wrist. Sent by the phone on the terminal transition.
///
/// An absent or unrecognized value means the Watch owns the cue. A missed
/// answer is the failure worth avoiding, so the default fails toward signalling.
enum WatchAnswerDelivery: String, Codable {
    case watchAudio
    case phoneAudio
    case silent
}

/// Which memos have already been announced on the wrist, and which are still
/// owed an announcement by audio that has not arrived yet.
///
/// This has to be durable. `didReceiveApplicationContext` replays the phone's
/// last-known context on every activation, so a purely in-memory record would
/// re-announce the same answer every time the Watch app launches.
private struct WatchSignalLedger: Codable {
    /// An answer whose audio the phone promised but has not delivered yet. The
    /// wearer's preference is captured with the promise so the fallback honours
    /// what was true when the answer completed, not whatever is current when a
    /// suspended Watch finally wakes.
    struct PendingAnswer: Codable {
        let promisedAt: Date
        let readyHapticEnabled: Bool
    }

    var signaledMemoIDs: [UUID] = []
    var awaitingWatchAudio: [UUID: PendingAnswer] = [:]
}

private struct PendingAudioTransfer: Codable, Identifiable {
    let id: UUID
    let memoID: UUID
    let audioFilename: String
    let metadataData: Data
    let createdAt: Date
    var transferCompletedAt: Date?
}

// MARK: - Watch Session Manager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable = false
    @Published var lastSentStatus: SendStatus = .idle
    @Published var recentMemos: [WatchMemo] = []
    @Published private(set) var appearanceThemeName = WatchTheme.currentName.rawValue
    @Published private(set) var codexSnapshot: CodexWatchSnapshot?
    @Published private(set) var selectedCodexTaskID: String?
    @Published private(set) var codexDispatchReceipt: CodexWatchDispatchReceipt? {
        didSet { saveCodexDispatchReceipt() }
    }
    /// Narrated answers still on the wrist, keyed by memo. Published so the
    /// capture face can offer replay only where there is something to replay —
    /// an answer spoken on the phone leaves nothing here, and a play button that
    /// does nothing is worse than none.
    @Published private(set) var answerAudio: [UUID: URL] = [:]
    /// The answer currently speaking, if any. Drives the play/stop face of the
    /// capture key.
    @Published private(set) var playingAnswerID: UUID?

    /// Whether the app is frontmost, which on this device means the wrist is up
    /// and the screen is lit. watchOS exposes no wrist-raise API; the scene
    /// phase is the closest honest proxy, since lowering a wrist backgrounds
    /// the app within a couple of seconds.
    private var isForeground = false
    /// When the wrist last went down. `nil` until the app has been foregrounded
    /// at least once this launch.
    private var lastForegroundAt: Date?

    private let maxRecentMemos = 10
    private let selectedCodexTaskKey = "watch.codex.selected-task.v1"

    /// The ledger has to outlive the display window. A replayed application
    /// context can still carry a memo that has aged out of `recentMemos`, and
    /// that memo must not be announced a second time.
    ///
    /// It must also stay at or above the phone's `maxContextMemoUpdates` (10,
    /// see TLK-036), which is what makes a double announcement impossible: a
    /// memo can only fall out of this ledger after 40 newer answers, by which
    /// point it is long gone from the ten-slot context that would replay it.
    private var maxSignaledMemos: Int { maxRecentMemos * 4 }

    /// How long the Watch waits for audio the phone said it was sending before
    /// falling back to a plain arrival tap. Long enough to cover an ordinary
    /// file transfer, short enough that the wearer is not left wondering.
    private static let watchAudioGrace: TimeInterval = 12

    /// How long after the wrist goes down an arriving answer may still speak on
    /// its own. Inside this window the wearer is plainly still in the exchange
    /// they started — asked, dropped the wrist, waiting — and hearing the answer
    /// is the whole point. Past it they have moved on, and a voice out of a
    /// sleeping watch is a startle, not a service.
    private static let autoPlayWindow: TimeInterval = 90

    enum SendStatus: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    private var session: WCSession?
    private var pendingAudioTransfers: [PendingAudioTransfer] = []
    private var aiAudioPlayer: AVAudioPlayer?
    private var signalLedger = WatchSignalLedger()

    var codexChannels: [CodexWatchChannel] {
        codexSnapshot?.channels ?? []
    }

    var selectedCodexChannel: CodexWatchChannel? {
        guard let selectedCodexTaskID else { return nil }
        return codexChannels.first { $0.taskID == selectedCodexTaskID }
    }

    // MARK: - Asks

    /// Ask AI captures only, newest first. This is the whole Asks surface: the
    /// display window is deliberately `maxRecentMemos`, not a separate archive.
    /// The wrist wants a recent guide, not a transcript store — the phone keeps
    /// the durable history.
    var asks: [WatchMemo] {
        recentMemos.filter(\.isAsk)
    }

    /// The ask the phone still owes an outcome on. Only ever one is shown: the
    /// newest, because that is the one the wearer just spoke.
    var activeAsk: WatchMemo? {
        asks.first(where: \.isInFlight)
    }

    /// The newest settled ask the wearer has not opened the Asks page since.
    /// Drives the resting state of the capture-face strip, so an answer that
    /// arrived while the wrist was down is still visible when it comes back up.
    var unseenAsk: WatchMemo? {
        guard let latest = asks.first(where: { $0.resolvedPhase.isTerminal }) else { return nil }
        // A memo written by an older build has no `settledAt`; fall back to its
        // capture time rather than treating it as permanently unseen.
        guard (latest.settledAt ?? latest.timestamp) > lastAsksVisit else { return nil }
        return latest
    }

    /// Marked when the Asks page comes forward. Persisted so the unseen badge
    /// does not come back from the dead after a relaunch.
    private(set) var lastAsksVisit: Date = UserDefaults.standard
        .object(forKey: WatchSessionManager.lastAsksVisitKey) as? Date ?? .distantPast

    private static let lastAsksVisitKey = "watch.asks.last-visit.v1"

    func markAsksSeen() {
        let now = Date()
        lastAsksVisit = now
        UserDefaults.standard.set(now, forKey: Self.lastAsksVisitKey)
        objectWillChange.send()
        publishSharedState()
        WatchAnswerNotifier.shared.clearDelivered()
    }

    // MARK: - Dismissal

    /// Take a capture off the wrist before the phone has finished with it.
    ///
    /// What this can honestly undo depends on how far the capture got. Audio
    /// still sitting in the Watch's own queue is recalled outright — the phone
    /// never sees it, so there is nothing left behind anywhere. Once the phone
    /// has acknowledged the capture it owns it: the phone finishes what it
    /// started and the result lands in its history, and dismissing here only
    /// stops the wrist reporting on it.
    ///
    /// That narrower promise is the whole request. An ask the phone will never
    /// answer — a dropped session, a force-quit, a provider that died — holds
    /// the in-flight panel forever, and the wearer needs a way to say so.
    func dismissCapture(memoID: UUID) {
        guard let index = recentMemos.firstIndex(where: { $0.id == memoID }) else { return }
        let memo = recentMemos[index]

        // Silences the arrival tap for an answer that lands after the row is
        // gone. `signalReadyIfNeeded` fires on the phone's update alone, so
        // without this a dismissed ask still buzzes the wrist with nothing
        // behind it to look at.
        markSignaled(memoID: memoID)

        if memo.isInFlight { recallPendingAudio(memoID: memoID) }

        recentMemos.remove(at: index)
        if playingAnswerID == memoID { stopAnswerPlayback() }
        pruneAnswerAudio()
        saveRecentMemos()

        WatchConsole.info("⌚️ [Watch] Dismissed capture \(memoID) (status: \(memo.status))")
    }

    /// Cancel audio for this memo that has not left the Watch, and drop it from
    /// the durable queue so the next flush does not send it anyway.
    ///
    /// A transfer already handed to WatchConnectivity may or may not still be
    /// cancellable — that race belongs to the framework. What matters here is
    /// that nothing is retried on the wearer's behalf after they said no.
    private func recallPendingAudio(memoID: UUID) {
        let queueIDs = pendingAudioTransfers
            .filter { $0.memoID == memoID }
            .map(\.id)
        guard !queueIDs.isEmpty else { return }

        let outstandingKeys = Set(queueIDs.map(\.uuidString))
        for transfer in session?.outstandingFileTransfers ?? [] {
            guard let queueID = transfer.file.metadata?["queueID"] as? String,
                  outstandingKeys.contains(queueID) else { continue }
            transfer.cancel()
        }

        for queueID in queueIDs {
            completePendingAudioTransfer(queueID: queueID)
            WatchConsole.info("⌚️ [Watch] Recalled queued audio \(queueID) memo=\(memoID)")
        }
    }

    // MARK: - Shared State

    private let sharedState = WatchSharedStateStore()

    /// Republish what the complication draws.
    ///
    /// Called from every path that can move it rather than on a timer: the
    /// complication extension is a separate process with no view of this
    /// object, so an unpublished change is simply invisible on the face until
    /// something else happens to publish. The store itself drops writes that
    /// change nothing, so calling this liberally is cheap and calling it too
    /// rarely is the only real failure.
    private func publishSharedState() {
        // The newest ask, whatever became of it. An older in-flight one behind
        // a newer settled one is not worth a second slot on a watch face.
        let now = Date()
        let ask = asks.first
        let isStalled = ask?.isStalled(asOf: now) ?? false
        // Only worth publishing while there is still a crossing ahead of us.
        // Once it has settled or already gone quiet, the flip has happened and
        // a date in the past would just make the complication reschedule itself
        // for a moment that has been and gone.
        let staleAt: Date? = ask.flatMap { ask in
            guard ask.isInFlight, !isStalled else { return nil }
            return ask.lastHeardAt.addingTimeInterval(WatchMemo.silenceTolerance)
        }
        sharedState.publish(
            WatchSharedState(
                askID: ask?.id.uuidString,
                askPhase: ask?.resolvedPhase.rawValue,
                askIsStalled: isStalled,
                askStaleAt: staleAt,
                askIsUnseen: unseenAsk != nil,
                askChangedAt: ask.map { $0.settledAt ?? $0.lastHeardAt },
                askQuestion: ask?.askQuestion,
                lastCaptureAt: recentMemos.first?.timestamp,
                captureCount: recentMemos.count,
                isReachable: isReachable
            )
        )
    }

    private override init() {
        super.init()
        loadRecentMemos()
        loadSignalLedger()
        selectedCodexTaskID = UserDefaults.standard.string(forKey: selectedCodexTaskKey)
        loadCodexDispatchReceipt()
        loadPendingAudioTransfers()
        loadAnswerAudio()
        pruneAnswerAudio()
        reconcilePendingAudioWithMemoStatuses()
        reconcilePendingCodexAudioWithReceipt()

        // The complication survives app launches and reinstalls; the container
        // does not necessarily agree with what just came off disk. Reconcile
        // once before anything live arrives.
        publishSharedState()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }

        observeAudioInterruptions()
    }

    // MARK: - Persistence

    private var memosFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recent_memos.json")
    }

    private func loadRecentMemos() {
        guard let data = try? Data(contentsOf: memosFileURL),
              let memos = try? JSONDecoder().decode([WatchMemo].self, from: data) else {
            return
        }
        recentMemos = memos
    }

    private func saveRecentMemos() {
        guard let data = try? JSONEncoder().encode(recentMemos) else { return }
        try? data.write(to: memosFileURL)
        // Every change to the memo list passes through here, which makes this
        // the one place the face cannot fall behind the app.
        publishSharedState()
    }

    private var signalLedgerFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("signaled_memos.json")
    }

    private func loadSignalLedger() {
        guard let data = try? Data(contentsOf: signalLedgerFileURL),
              let ledger = try? JSONDecoder().decode(WatchSignalLedger.self, from: data) else {
            return
        }
        signalLedger = ledger
    }

    private func saveSignalLedger() {
        guard let data = try? JSONEncoder().encode(signalLedger) else { return }
        try? data.write(to: signalLedgerFileURL, options: .atomic)
    }

    private func hasSignaled(memoID: UUID) -> Bool {
        signalLedger.signaledMemoIDs.contains(memoID)
    }

    private func markSignaled(memoID: UUID) {
        signalLedger.awaitingWatchAudio[memoID] = nil
        guard !signalLedger.signaledMemoIDs.contains(memoID) else {
            saveSignalLedger()
            return
        }
        signalLedger.signaledMemoIDs.append(memoID)
        signalLedger.signaledMemoIDs = Array(signalLedger.signaledMemoIDs.suffix(maxSignaledMemos))
        saveSignalLedger()
    }

    private func handleAppearanceTheme(_ rawValue: String) {
        guard let theme = WatchThemeName(rawValue: rawValue) else {
            WatchConsole.info("⌚️ [Watch] Ignored unknown appearance theme: \(rawValue)")
            return
        }
        UserDefaults.standard.set(theme.rawValue, forKey: WatchTheme.selectedThemeKey)
        appearanceThemeName = WatchTheme.currentName.rawValue
    }

    func setLocalAppearanceTheme(_ theme: WatchThemeName?) {
        if let theme {
            UserDefaults.standard.set(theme.rawValue, forKey: WatchTheme.localOverrideKey)
            WatchConsole.info("⌚️ [Watch] Appearance override: \(theme.rawValue)")
        } else {
            UserDefaults.standard.removeObject(forKey: WatchTheme.localOverrideKey)
            WatchConsole.info("⌚️ [Watch] Appearance follows iPhone")
        }
        appearanceThemeName = WatchTheme.currentName.rawValue
        WKInterfaceDevice.current().play(.click)
    }

    private var codexReceiptFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("codex_dispatch_receipt.json")
    }

    private func loadCodexDispatchReceipt() {
        guard let data = try? Data(contentsOf: codexReceiptFileURL),
              let receipt = try? JSONDecoder().decode(CodexWatchDispatchReceipt.self, from: data) else {
            return
        }
        codexDispatchReceipt = receipt
    }

    private func saveCodexDispatchReceipt() {
        guard let codexDispatchReceipt,
              let data = try? JSONEncoder().encode(codexDispatchReceipt) else {
            try? FileManager.default.removeItem(at: codexReceiptFileURL)
            return
        }
        try? data.write(to: codexReceiptFileURL, options: .atomic)
    }

    private var pendingAudioDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "PendingAudio", directoryHint: .isDirectory)
    }

    private var pendingAudioTransfersFileURL: URL {
        pendingAudioDirectoryURL.appending(path: "transfers.json")
    }

    private func loadPendingAudioTransfers() {
        guard let data = try? Data(contentsOf: pendingAudioTransfersFileURL),
              let transfers = try? JSONDecoder().decode([PendingAudioTransfer].self, from: data) else {
            return
        }
        pendingAudioTransfers = transfers
        WatchConsole.info("⌚️ [Watch] Restored \(transfers.count) pending audio transfer(s)")
    }

    private func savePendingAudioTransfers() throws {
        try FileManager.default.createDirectory(
            at: pendingAudioDirectoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(pendingAudioTransfers)
        try data.write(to: pendingAudioTransfersFileURL, options: .atomic)
    }

    private func persistPendingAudioTransfer(
        fileURL: URL,
        memoID: UUID,
        metadata: [String: Any]
    ) throws -> PendingAudioTransfer {
        let queueID = UUID()
        let extensionName = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
        let audioFilename = queueID.uuidString + "." + extensionName
        let durableAudioURL = pendingAudioDirectoryURL.appending(path: audioFilename)

        try FileManager.default.createDirectory(
            at: pendingAudioDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fileURL, to: durableAudioURL)

        var durableMetadata = metadata
        durableMetadata["queueID"] = queueID.uuidString
        let metadataData = try PropertyListSerialization.data(
            fromPropertyList: durableMetadata,
            format: .binary,
            options: 0
        )
        let transfer = PendingAudioTransfer(
            id: queueID,
            memoID: memoID,
            audioFilename: audioFilename,
            metadataData: metadataData,
            createdAt: Date(),
            transferCompletedAt: nil
        )

        pendingAudioTransfers.append(transfer)
        do {
            try savePendingAudioTransfers()
        } catch {
            pendingAudioTransfers.removeAll { $0.id == queueID }
            try? FileManager.default.removeItem(at: durableAudioURL)
            throw error
        }
        return transfer
    }

    private func metadata(for transfer: PendingAudioTransfer) -> [String: Any]? {
        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: transfer.metadataData,
            options: [],
            format: nil
        ) else {
            return nil
        }
        return propertyList as? [String: Any]
    }

    private func flushPendingAudioTransfers() {
        guard let session, session.activationState == .activated else {
            WatchConsole.info("⌚️ [Watch] Audio queue waiting for session activation")
            return
        }

        let outstandingQueueIDs = Set(session.outstandingFileTransfers.compactMap { transfer in
            transfer.file.metadata?["queueID"] as? String
        })

        for transfer in pendingAudioTransfers where !outstandingQueueIDs.contains(transfer.id.uuidString) {
            let audioURL = pendingAudioDirectoryURL.appending(path: transfer.audioFilename)
            guard FileManager.default.fileExists(atPath: audioURL.path),
                  var metadata = metadata(for: transfer) else {
                WatchConsole.info("⌚️ [Watch] ❌ Pending audio is missing or unreadable: \(transfer.id)")
                continue
            }

            // Codex recordings remain durable until the phone sends its own
            // application-level `received` receipt. Suppress rapid duplicate
            // transfers while still retrying if that receipt never arrives.
            if metadata["intent"] as? String == "codex",
               let completedAt = transfer.transferCompletedAt,
               Date().timeIntervalSince(completedAt) < 300 {
                continue
            }

            metadata["background"] = !session.isReachable
            session.transferFile(audioURL, metadata: metadata)
            WatchConsole.info(
                "⌚️ [Watch] Enqueued durable audio \(transfer.id) (reachable: \(session.isReachable))"
            )
        }
    }

    private func completePendingAudioTransfer(queueID: UUID) {
        guard let transfer = pendingAudioTransfers.first(where: { $0.id == queueID }) else {
            return
        }

        pendingAudioTransfers.removeAll { $0.id == queueID }
        do {
            try savePendingAudioTransfers()
            let audioURL = pendingAudioDirectoryURL.appending(path: transfer.audioFilename)
            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            pendingAudioTransfers.append(transfer)
            WatchConsole.info("⌚️ [Watch] ❌ Could not commit audio queue completion: \(error.localizedDescription)")
        }
    }

    private func markTransferCompleted(queueID: UUID, at date: Date?) {
        guard let index = pendingAudioTransfers.firstIndex(where: { $0.id == queueID }) else {
            return
        }
        let previous = pendingAudioTransfers[index].transferCompletedAt
        pendingAudioTransfers[index].transferCompletedAt = date
        do {
            try savePendingAudioTransfers()
        } catch {
            pendingAudioTransfers[index].transferCompletedAt = previous
            WatchConsole.info(
                "⌚️ [Watch] ❌ Could not save transfer receipt wait: \(error.localizedDescription)"
            )
        }
    }

    /// A phone receipt is the durable application-level acknowledgement. It
    /// closes the Watch queue even when WatchConnectivity never delivers the
    /// lower-level file-transfer callback before the Watch app is suspended.
    private func acknowledgePendingCodexAudio(with receipt: CodexWatchDispatchReceipt) {
        guard receipt.state.progressRank >= CodexWatchDispatchReceipt.State.received.progressRank else {
            return
        }

        let queueIDs = pendingAudioTransfers.compactMap { transfer -> UUID? in
            guard let metadata = metadata(for: transfer),
                  metadata["intent"] as? String == "codex",
                  metadata["requestID"] as? String == receipt.requestID.uuidString,
                  metadata["hostID"] as? String == receipt.hostID,
                  metadata["taskID"] as? String == receipt.taskID else {
                return nil
            }
            return transfer.id
        }

        for queueID in queueIDs {
            completePendingAudioTransfer(queueID: queueID)
            WatchConsole.info("⌚️ [Watch] Retired acknowledged Codex audio \(queueID)")
        }
    }

    private func reconcilePendingCodexAudioWithReceipt() {
        guard let codexDispatchReceipt else { return }
        acknowledgePendingCodexAudio(with: codexDispatchReceipt)
    }

    /// Memo status updates are the phone's durable application-level receipt.
    /// WatchConnectivity may suspend the Watch before `didFinish` arrives, so
    /// the receipt—not that lower-level callback—owns queue retirement.
    private func acknowledgePendingAudio(memoID: UUID) {
        let queueIDs = pendingAudioTransfers
            .filter { $0.memoID == memoID }
            .map(\.id)

        for queueID in queueIDs {
            completePendingAudioTransfer(queueID: queueID)
            WatchConsole.info(
                "⌚️ [Watch] Retired acknowledged memo audio \(queueID) memo=\(memoID)"
            )
        }
    }

    private func reconcilePendingAudioWithMemoStatuses() {
        let acknowledgedMemoIDs = Set(recentMemos.compactMap { memo -> UUID? in
            switch memo.status {
            case .received, .thinking, .transcribed, .answered, .failed:
                memo.id
            case .sending, .sent:
                nil
            }
        })

        for memoID in acknowledgedMemoIDs {
            acknowledgePendingAudio(memoID: memoID)
        }
    }

    /// Send audio file to iPhone for transcription.
    ///
    /// `autoRoute` flags that the phone should classify intent from the
    /// transcript and choose memo vs Ask AI on its own. When `preset`
    /// is provided (e.g. the "ASK AI" pill), the explicit `intent` in
    /// metadata wins and the phone skips classification.
    func sendAudio(
        fileURL: URL,
        duration: TimeInterval = 0,
        preset: WatchPreset? = nil,
        autoRoute: Bool = false
    ) {
        WatchConsole.info("⌚️ [Watch] sendAudio called with: \(fileURL.lastPathComponent), preset: \(preset?.name ?? "none"), autoRoute: \(autoRoute)")
        WatchConsole.info("⌚️ [Watch] File exists: \(FileManager.default.fileExists(atPath: fileURL.path))")

        var routingMetadata: [String: Any] = [:]
        if let preset = preset {
            if let workflowId = preset.workflowId {
                routingMetadata["workflowId"] = workflowId
            }
            if let intent = preset.intent {
                routingMetadata["intent"] = intent
            }
        }

        // Flag for the phone-side intent classifier. Phone reads
        // transcript and picks memo vs Ask AI when this is true and no
        // explicit `intent` was sent.
        if autoRoute {
            routingMetadata["autoRoute"] = true
        }

        enqueueAudio(
            fileURL: fileURL,
            duration: duration,
            presetID: preset?.id,
            presetName: preset?.name,
            routingMetadata: routingMetadata
        )
    }

    /// Transfers a recording to either the selected conversation or an
    /// explicitly requested fresh task in the same project.
    func sendCodexAudio(
        fileURL: URL,
        duration: TimeInterval,
        requestID: UUID,
        hostID: String,
        taskID: String,
        taskTitle: String,
        workingDirectory: String,
        action: CodexWatchDispatchAction
    ) {
        let routingMetadata: [String: Any] = [
            "intent": "codex",
            "requestID": requestID.uuidString,
            "hostID": hostID,
            "taskID": taskID,
            "taskTitle": taskTitle,
            "cwd": workingDirectory,
            "codexAction": action.rawValue
        ]
        WatchConsole.info(
            "⌚️ [Watch] Codex dispatch action=\(action.rawValue) task=\(taskID)"
        )

        enqueueAudio(
            fileURL: fileURL,
            duration: duration,
            presetID: nil,
            presetName: "Codex · \(taskTitle)",
            routingMetadata: routingMetadata,
            codexRequestID: requestID,
            codexHostID: hostID,
            codexTaskID: taskID
        )
    }

    private func enqueueAudio(
        fileURL: URL,
        duration: TimeInterval,
        presetID: String?,
        presetName: String?,
        routingMetadata: [String: Any],
        codexRequestID: UUID? = nil,
        codexHostID: String? = nil,
        codexTaskID: String? = nil
    ) {
        var memo = WatchMemo(duration: duration)
        memo.presetId = presetID
        memo.presetName = presetName
        recentMemos.insert(memo, at: 0)

        if recentMemos.count > maxRecentMemos {
            recentMemos = Array(recentMemos.prefix(maxRecentMemos))
            pruneAnswerAudio()
        }
        saveRecentMemos()

        var metadata: [String: Any] = [
            "type": "audio",
            "timestamp": memo.timestamp.timeIntervalSince1970,
            "memoId": memo.id.uuidString,
            "duration": duration
        ]
        if let presetID { metadata["presetId"] = presetID }
        if let presetName { metadata["presetName"] = presetName }
        routingMetadata.forEach { metadata[$0.key] = $0.value }

        do {
            let transfer = try persistPendingAudioTransfer(
                fileURL: fileURL,
                memoID: memo.id,
                metadata: metadata
            )
            WatchConsole.info("⌚️ [Watch] Persisted audio before delivery: \(transfer.id)")
        } catch {
            WatchConsole.info("⌚️ [Watch] ❌ Could not persist audio: \(error.localizedDescription)")
            lastSentStatus = .failed("Could not save recording")
            updateMemoStatus(memo.id, status: .failed)
            if let codexRequestID, let codexHostID, let codexTaskID {
                codexDispatchReceipt = CodexWatchDispatchReceipt(
                    requestID: codexRequestID,
                    hostID: codexHostID,
                    taskID: codexTaskID,
                    state: .failed,
                    detail: "Could not save recording on Watch"
                )
            }
            return
        }

        let isActivated = session?.activationState == .activated
        let isReachable = isActivated && session?.isReachable == true

        if let codexRequestID, let codexHostID, let codexTaskID {
            codexDispatchReceipt = CodexWatchDispatchReceipt(
                requestID: codexRequestID,
                hostID: codexHostID,
                taskID: codexTaskID,
                state: isReachable ? .sending : .queued,
                detail: isReachable ? nil : "Waiting for iPhone delivery"
            )
        }

        lastSentStatus = .sending
        guard isActivated else {
            WatchConsole.info("⌚️ [Watch] Session not activated; durable audio remains queued")
            return
        }

        flushPendingAudioTransfers()
    }

    // MARK: - Memo Updates

    private func updateMemoStatus(
        _ memoId: UUID,
        status: WatchMemo.MemoStatus,
        preview: String? = nil,
        phase: WatchAskPhase? = nil,
        delivery: WatchAnswerDelivery? = nil
    ) {
        if let index = recentMemos.firstIndex(where: { $0.id == memoId }) {
            recentMemos[index].status = status
            // Any update at all is proof of life, whatever it carries.
            recentMemos[index].lastUpdatedAt = Date()
            if let preview = preview {
                // The `.answering` preview *is* the question — the phone sends
                // it precisely so the wrist can confirm what was heard. Catch it
                // on the way past into its own slot, because the next preview to
                // arrive is the answer (or the failure) and overwrites this one.
                // Derived here rather than added to the wire format: the payload
                // already carries it, and an older phone build stays compatible.
                if phase == .answering, recentMemos[index].askQuestion == nil {
                    recentMemos[index].askQuestion = preview
                }
                recentMemos[index].transcriptionPreview = preview
            }
            if let phase {
                // Stamped once, on the first terminal update. The unseen badge
                // is answered "since when", and the memo's own timestamp is the
                // moment it was *recorded* — an ask the wearer watched go out
                // and then walked away from would never read as unseen.
                if phase.isTerminal, recentMemos[index].settledAt == nil {
                    recentMemos[index].settledAt = Date()
                }
                recentMemos[index].phase = phase
            }
            // Only the terminal update carries delivery. Absent means "not said
            // yet", not "not spoken", so an earlier value is never cleared.
            if let delivery {
                recentMemos[index].delivery = delivery
            }
            saveRecentMemos()
        }
    }

    /// The phone sends the identical dictionary over all three carriers — live
    /// message, durable user info, and replayed application context — so all
    /// three read it the same way here rather than each picking their own subset
    /// of the fields.
    private func applyMemoUpdatePayload(_ payload: [String: Any]) {
        guard let memoId = payload["memoId"] as? String,
              let status = payload["status"] as? String else {
            return
        }
        handleMemoUpdate(
            memoId: memoId,
            status: status,
            preview: payload["preview"] as? String,
            delivery: payload["delivery"] as? String,
            phase: payload["phase"] as? String,
            readyHapticEnabled: payload["readyHaptic"] as? Bool ?? true
        )
    }

    func handleMemoUpdate(
        memoId: String,
        status: String,
        preview: String?,
        delivery: String? = nil,
        phase: String? = nil,
        readyHapticEnabled: Bool = true
    ) {
        guard let uuid = UUID(uuidString: memoId),
              let memoStatus = WatchMemo.MemoStatus(rawValue: status) else { return }

        switch memoStatus {
        case .received, .thinking, .transcribed, .answered, .failed:
            acknowledgePendingAudio(memoID: uuid)
        case .sending, .sent:
            break
        }
        let resolvedDelivery = delivery.flatMap(WatchAnswerDelivery.init(rawValue:))
        updateMemoStatus(
            uuid,
            status: memoStatus,
            preview: preview,
            phase: phase.flatMap(WatchAskPhase.init(rawValue:)),
            delivery: resolvedDelivery
        )
        signalReadyIfNeeded(
            memoID: uuid,
            status: memoStatus,
            delivery: resolvedDelivery,
            readyHapticEnabled: readyHapticEnabled
        )
    }

    // MARK: - Ready Signal

    /// Every carrier reaches the wrist through this one funnel — live message,
    /// durable user info, replayed application context, and the answer audio
    /// itself — so a finished answer is announced exactly once per memo no
    /// matter how many of them deliver it.
    ///
    /// Only a completed answer is announced. A failure is left to visual state
    /// and history: a tap the wearer has to look at to interpret is a tap that
    /// interrupts without informing.
    private func signalReadyIfNeeded(
        memoID: UUID,
        status: WatchMemo.MemoStatus,
        delivery: WatchAnswerDelivery?,
        readyHapticEnabled: Bool
    ) {
        guard status == .answered, !hasSignaled(memoID: memoID) else { return }

        guard delivery != .watchAudio else {
            // The answer is about to speak here. That playback carries its own
            // opening click, so defer and let `handleAIAudio` close the ledger.
            noteAwaitingWatchAudio(memoID: memoID, readyHapticEnabled: readyHapticEnabled)
            return
        }

        markSignaled(memoID: memoID)
        guard readyHapticEnabled else { return }
        WKInterfaceDevice.current().play(.notification)
        postAnswerNotification(memoID: memoID)
    }

    /// Leaves a card behind for an answer the wearer was not present for.
    ///
    /// Gated on the same switch as the wrist tap. That setting reads as "do not
    /// interrupt me when one lands", and a notification is a louder version of
    /// the same interruption, not a different question.
    private func postAnswerNotification(memoID: UUID) {
        guard !isForeground else { return }
        guard let memo = recentMemos.first(where: { $0.id == memoID }) else { return }
        WatchAnswerNotifier.shared.post(
            memoID: memoID,
            question: memo.askQuestion,
            answer: memo.transcriptionPreview
        )
    }

    private func noteAwaitingWatchAudio(memoID: UUID, readyHapticEnabled: Bool) {
        guard signalLedger.awaitingWatchAudio[memoID] == nil else { return }
        signalLedger.awaitingWatchAudio[memoID] = WatchSignalLedger.PendingAnswer(
            promisedAt: Date(),
            readyHapticEnabled: readyHapticEnabled
        )
        saveSignalLedger()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.watchAudioGrace))
            self?.resolveOverdueWatchAudio()
        }
    }

    /// The phone said audio was coming and it never arrived, so the wrist still
    /// owes the wearer a signal. Measured against the wall clock rather than the
    /// sleep above, because a suspended Watch app resolves the promise on its
    /// next wake instead of losing it.
    private func resolveOverdueWatchAudio() {
        let now = Date()
        let overdue = signalLedger.awaitingWatchAudio
            .filter { now.timeIntervalSince($0.value.promisedAt) >= Self.watchAudioGrace }
        guard !overdue.isEmpty else { return }

        for (memoID, pending) in overdue {
            signalLedger.awaitingWatchAudio[memoID] = nil
            guard !hasSignaled(memoID: memoID) else { continue }
            markSignaled(memoID: memoID)
            WatchConsole.info(
                "⌚️ [Watch] Promised answer audio never arrived; tapping instead memo=\(memoID)"
            )
            if pending.readyHapticEnabled {
                WKInterfaceDevice.current().play(.notification)
                postAnswerNotification(memoID: memoID)
            }
        }
        saveSignalLedger()
    }

    // MARK: - Codex State

    func selectCodexChannel(taskID: String) {
        guard taskID != selectedCodexTaskID,
              let snapshot = codexSnapshot,
              snapshot.channels.contains(where: { $0.taskID == taskID }) else {
            return
        }

        selectedCodexTaskID = taskID
        UserDefaults.standard.set(taskID, forKey: selectedCodexTaskKey)
        WatchConsole.info(
            "⌚️ [Watch] Local Codex selection changed task=\(taskID); iPhone UI unchanged"
        )
    }

    private func handleCodexSnapshot(_ propertyList: [String: Any]) {
        guard let snapshot = CodexWatchSnapshot(propertyList: propertyList) else {
            WatchConsole.info("⌚️ [Watch] ❌ Ignored malformed Codex snapshot")
            return
        }

        if let current = codexSnapshot,
           current.hostID == snapshot.hostID,
           snapshot.revision < current.revision {
            WatchConsole.info("⌚️ [Watch] Ignored stale Codex snapshot revision \(snapshot.revision)")
            return
        }

        let previousSelection = selectedCodexTaskID
        codexSnapshot = snapshot

        if let previousSelection,
           snapshot.channels.contains(where: { $0.taskID == previousSelection }) {
            selectedCodexTaskID = previousSelection
        } else {
            selectedCodexTaskID = snapshot.selectedTaskID ?? snapshot.channels.first?.taskID
        }
        if let selectedCodexTaskID {
            UserDefaults.standard.set(selectedCodexTaskID, forKey: selectedCodexTaskKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedCodexTaskKey)
        }

        WatchConsole.info(
            "⌚️ [Watch] Codex snapshot revision \(snapshot.revision), channels: \(snapshot.channels.count)"
        )
    }

    private func handleCodexDispatchUpdate(_ propertyList: [String: Any]) {
        guard let update = CodexWatchDispatchReceipt(propertyList: propertyList) else {
            WatchConsole.info("⌚️ [Watch] ❌ Ignored malformed Codex dispatch update")
            return
        }

        // Retire the durable transfer before the display-state monotonicity
        // guard. A repeated or older `received` update is still a valid
        // acknowledgement for the exact request/host/task tuple.
        acknowledgePendingCodexAudio(with: update)

        guard let current = codexDispatchReceipt,
              current.requestID == update.requestID,
              current.hostID == update.hostID,
              current.taskID == update.taskID,
              !current.state.isTerminal,
              update.state.progressRank >= current.state.progressRank,
              update.updatedAt >= current.updatedAt else {
            WatchConsole.info("⌚️ [Watch] Ignored stale or mismatched Codex dispatch update")
            return
        }

        codexDispatchReceipt = update
    }

    private func handleAIAudio(fileURL: URL, metadata: [String: Any]) {
        do {
            let memoID = (metadata["memoId"] as? String).flatMap(UUID.init(uuidString:))
            let audioURL = try storeAnswerAudio(from: fileURL, memoID: memoID)

            // Read before the update below can change it: the grace fallback may
            // already have tapped for this memo on this same wake, since audio
            // routinely lands seconds after activation and there is no way to
            // see an incoming transfer before it arrives. In that case playback
            // starting is cue enough and a click here would double up.
            let alreadySignaled = memoID.map(hasSignaled) ?? false
            // Read before `markSignaled` clears it: the promise carries the
            // haptic preference that was true when the answer completed.
            let readyHapticEnabled = memoID
                .flatMap { signalLedger.awaitingWatchAudio[$0]?.readyHapticEnabled } ?? true
            if let memoId = metadata["memoId"] as? String {
                handleMemoUpdate(
                    memoId: memoId,
                    status: "answered",
                    preview: metadata["preview"] as? String,
                    delivery: WatchAnswerDelivery.watchAudio.rawValue,
                    phase: WatchAskPhase.answered.rawValue
                )
            }

            guard shouldAutoPlayAnswer else {
                // Nobody is looking. The audio stays on the wrist and the key
                // switches to PLAY ANSWER; all that is owed now is the tap that
                // says an answer arrived.
                if let memoID { markSignaled(memoID: memoID) }
                if !alreadySignaled, readyHapticEnabled {
                    WKInterfaceDevice.current().play(.notification)
                    if let memoID { postAnswerNotification(memoID: memoID) }
                }
                WatchConsole.info("⌚️ [Watch] 🔈 Answer audio held for a tap; wrist is down")
                return
            }

            try startAnswerPlayback(url: audioURL, memoID: memoID)
            // The click below is this memo's arrival cue, so close the ledger
            // here. Doing it only once playback is actually set up means a
            // failure above still falls through to the plain tap.
            if let memoID {
                markSignaled(memoID: memoID)
            }
            if !alreadySignaled {
                WKInterfaceDevice.current().play(.click)
            }
            WatchConsole.info("⌚️ [Watch] 🔊 Playing AI answer on Watch")
        } catch {
            WatchConsole.info("⌚️ [Watch] ❌ AI audio playback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Answer audio

    /// Answers the phone narrated here, kept so the wearer can hear one again.
    ///
    /// Before this the file went to `temporaryDirectory` under a fresh UUID and
    /// was forgotten the moment playback ended, which made "play it again" not
    /// merely absent from the UI but impossible to build.
    private var answerAudioDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnswerAudio", isDirectory: true)
    }

    private func loadAnswerAudio() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: answerAudioDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        answerAudio = files.reduce(into: [:]) { map, file in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                return
            }
            map[id] = file
        }
    }

    /// Named for the memo so a relaunch can rebuild the index by listing the
    /// directory — the association has to survive the process, since the answer
    /// that most wants replaying is the one that arrived while the wrist was down.
    private func storeAnswerAudio(from fileURL: URL, memoID: UUID?) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: answerAudioDirectory, withIntermediateDirectories: true)

        let destination = answerAudioDirectory
            .appendingPathComponent((memoID ?? UUID()).uuidString)
            .appendingPathExtension("mp3")
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: fileURL, to: destination)

        if let memoID {
            answerAudio[memoID] = destination
        }
        return destination
    }

    /// Audio outlives nothing: once a memo has aged out of the display window
    /// there is no surface left that could offer to play it.
    private func pruneAnswerAudio() {
        let live = Set(recentMemos.map(\.id))
        for (memoID, url) in answerAudio where !live.contains(memoID) {
            if playingAnswerID == memoID { stopAnswerPlayback() }
            try? FileManager.default.removeItem(at: url)
            answerAudio[memoID] = nil
        }
    }

    func hasAnswerAudio(for memoID: UUID) -> Bool {
        answerAudio[memoID] != nil
    }

    // MARK: - Attention

    /// Called by the scene so the manager knows whether anyone is looking.
    func noteForegroundState(_ active: Bool) {
        // Stamped on the way *out*: while the app is frontmost the timestamp is
        // irrelevant, and taking it here means the window is measured from the
        // moment attention was actually lost.
        if isForeground, !active { lastForegroundAt = Date() }
        isForeground = active
        if active { reconcileAnswerPlayback() }
    }

    /// Straighten out playback state after time away.
    ///
    /// A player can stop without any of this app's code running: a suspension,
    /// an audio route that disappears, a session lost to something louder. None
    /// of those go through `stopAnswerPlayback`, so what is left behind is a
    /// `playingAnswerID` for audio that is not playing — the key reads STOP, and
    /// the one tap that ought to restart the answer instead appears to do
    /// nothing. Clearing it here restores the offer, which is the honest state:
    /// the answer was not heard, and it is still on the wrist.
    private func reconcileAnswerPlayback() {
        guard playingAnswerID != nil, aiAudioPlayer?.isPlaying != true else { return }
        WatchConsole.info("⌚️ [Watch] 🔈 Answer stopped while away; offering it again")
        stopAnswerPlayback()
    }

    /// Phone calls and Siri take the audio session away mid-answer.
    ///
    /// Nothing resumes automatically on `.ended`: an answer that starts talking
    /// again by itself after a call is a surprise, and the wearer has a PLAY
    /// ANSWER waiting the moment they look. All this does is make sure the UI
    /// agrees that the answer stopped.
    private func observeAudioInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in
                guard let self, self.playingAnswerID != nil else { return }
                WatchConsole.info("⌚️ [Watch] 🔈 Answer interrupted; it stays available to replay")
                self.stopAnswerPlayback()
            }
        }
    }

    /// Whether an answer landing right now should speak for itself.
    ///
    /// The audio is kept either way — this decides only whether it plays
    /// unprompted or waits behind the key's PLAY ANSWER. Declining is not a
    /// failure state: an answer held for a deliberate tap is the mode most
    /// people want, because it puts them in charge of when their watch talks.
    private var shouldAutoPlayAnswer: Bool {
        if isForeground { return true }
        guard let lastForegroundAt else { return false }
        return Date().timeIntervalSince(lastForegroundAt) <= Self.autoPlayWindow
    }

    /// Replay from the wrist. A second tap on a playing answer stops it, which
    /// is the only way off a long answer on a device with no scrubber.
    func toggleAnswerPlayback(memoID: UUID) {
        guard playingAnswerID != memoID else {
            stopAnswerPlayback()
            return
        }
        guard let url = answerAudio[memoID] else { return }

        do {
            try startAnswerPlayback(url: url, memoID: memoID)
            answerPlaybackWasRequested = true
            WKInterfaceDevice.current().play(.click)
        } catch {
            WatchConsole.info("⌚️ [Watch] ❌ Answer replay failed: \(error.localizedDescription)")
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func stopAnswerPlayback() {
        aiAudioPlayer?.stop()
        aiAudioPlayer = nil
        playingAnswerID = nil
        answerPlaybackWasRequested = false
        releaseAudioSession()
    }

    /// Hand the audio session back once there is nothing left to say.
    ///
    /// The app declares the `audio` background mode so an answer survives a
    /// lowered wrist; the other half of that bargain is letting go the moment
    /// the answer ends, so a finished playback does not quietly hold the watch
    /// awake or keep other audio ducked.
    private func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    /// Whether the playback now running was asked for, as opposed to the
    /// narration that auto-plays the moment an answer lands. Only a deliberate
    /// tap is evidence the wearer was actually listening.
    private var answerPlaybackWasRequested = false

    private func startAnswerPlayback(url: URL, memoID: UUID?) throws {
        answerPlaybackWasRequested = false
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        aiAudioPlayer = player
        playingAnswerID = memoID
        player.play()
    }
}

// MARK: - AVAudioPlayerDelegate

extension WatchSessionManager: AVAudioPlayerDelegate {
    /// Only the memo whose playback ended is cleared. A replay started while an
    /// earlier player was still winding down would otherwise be switched off by
    /// its predecessor's callback.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.aiAudioPlayer === player else { return }
            self.aiAudioPlayer = nil
            self.playingAnswerID = nil
            // Hearing a replay to the end is a stronger claim to having seen the
            // answer than opening a list is. Without this the capture key would
            // hold "PLAY ANSWER" indefinitely for an answer already listened to.
            // Stopping early does not count — an interrupted answer stays on the
            // key so it can be restarted.
            if flag, self.answerPlaybackWasRequested { self.markAsksSeen() }
            self.answerPlaybackWasRequested = false
            self.releaseAudioSession()
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                WatchConsole.info("⌚️ [Watch] Session activation failed: \(error.localizedDescription)")
            } else {
                let stateStr = switch activationState {
                    case .notActivated: "notActivated"
                    case .inactive: "inactive"
                    case .activated: "activated"
                    @unknown default: "unknown"
                }
                let device = WKInterfaceDevice.current()
                let watchBundleID = Bundle.main.bundleIdentifier ?? "unknown"
                let expectedCompanionID = watchBundleID.replacingOccurrences(of: ".watchkitapp", with: "")

                WatchConsole.info("⌚️ [Watch] ========== SESSION INFO ==========")
                WatchConsole.info("⌚️ [Watch] Watch Name: \(device.name)")
                WatchConsole.info("⌚️ [Watch] Watch Model: \(device.model)")
                WatchConsole.info("⌚️ [Watch] Watch OS: \(device.systemVersion)")
                WatchConsole.info("⌚️ [Watch] Watch Bundle ID: \(watchBundleID)")
                WatchConsole.info("⌚️ [Watch] Expected iOS Bundle: \(expectedCompanionID)")
                WatchConsole.info("⌚️ [Watch] State: \(stateStr)")
                WatchConsole.info("⌚️ [Watch] Reachable: \(session.isReachable)")
                WatchConsole.info("⌚️ [Watch] Companion installed: \(session.isCompanionAppInstalled)")
                WatchConsole.info("⌚️ [Watch] Outstanding transfers: \(session.outstandingFileTransfers.count)")
                WatchConsole.info("⌚️ [Watch] =====================================")
                self.isReachable = session.isReachable
                self.publishSharedState()
                if activationState == .activated {
                    self.resolveOverdueWatchAudio()
                    self.flushPendingAudioTransfers()
                    if session.isReachable {
                        session.sendMessage(
                            ["type": "appearanceThemeRequest"],
                            replyHandler: nil,
                            errorHandler: nil
                        )
                    }
                }
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.publishSharedState()
            self.resolveOverdueWatchAudio()
            self.flushPendingAudioTransfers()
            if session.isReachable {
                session.sendMessage(
                    ["type": "appearanceThemeRequest"],
                    replyHandler: nil,
                    errorHandler: nil
                )
            }
            let device = WKInterfaceDevice.current()
            WatchConsole.info("⌚️ [Watch] Reachability → \(session.isReachable) | Companion: \(session.isCompanionAppInstalled) | Watch: \(device.name)")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            let metadata = fileTransfer.file.metadata ?? [:]
            let memoIdString = metadata["memoId"] as? String
            let queueID = (metadata["queueID"] as? String).flatMap(UUID.init(uuidString:))
            let isCodexDispatch = metadata["intent"] as? String == "codex"
            let codexRequestID = (metadata["requestID"] as? String).flatMap(UUID.init(uuidString:))

            if let error = error {
                WatchConsole.info("⌚️ [Watch] ❌ File transfer FAILED: \(error.localizedDescription)")
                self.lastSentStatus = .sending
                if let queueID {
                    self.markTransferCompleted(queueID: queueID, at: nil)
                }

                if isCodexDispatch,
                   let codexRequestID,
                   let receipt = self.codexDispatchReceipt,
                   receipt.requestID == codexRequestID,
                   receipt.state.progressRank <= CodexWatchDispatchReceipt.State.queued.progressRank {
                    self.codexDispatchReceipt = CodexWatchDispatchReceipt(
                        requestID: receipt.requestID,
                        hostID: receipt.hostID,
                        taskID: receipt.taskID,
                        state: .queued,
                        detail: "Delivery interrupted; will retry"
                    )
                }
            } else {
                let file = fileTransfer.file
                WatchConsole.info("⌚️ [Watch] ✅ File transfer complete!")
                WatchConsole.info("⌚️ [Watch]    File: \(file.fileURL.lastPathComponent)")
                WatchConsole.info("⌚️ [Watch]    Metadata: \(metadata)")
                if let queueID, isCodexDispatch {
                    self.markTransferCompleted(queueID: queueID, at: .now)
                } else if let queueID {
                    self.completePendingAudioTransfer(queueID: queueID)
                }
                self.lastSentStatus = .sent

                // Update memo status to sent
                if let memoIdString, let memoId = UUID(uuidString: memoIdString) {
                    self.updateMemoStatus(memoId, status: .sent)
                }
                if isCodexDispatch,
                   let codexRequestID,
                   let receipt = self.codexDispatchReceipt,
                   receipt.requestID == codexRequestID,
                   receipt.state.progressRank < CodexWatchDispatchReceipt.State.received.progressRank {
                    self.codexDispatchReceipt = CodexWatchDispatchReceipt(
                        requestID: receipt.requestID,
                        hostID: receipt.hostID,
                        taskID: receipt.taskID,
                        state: .transferred,
                        detail: "Audio transferred; awaiting durable phone receipt"
                    )
                }

                // Reset status after delay
                try? await Task.sleep(for: .seconds(2))
                if self.lastSentStatus == .sent {
                    self.lastSentStatus = .idle
                }
            }
        }
    }

    // Handle messages from iPhone (memo status updates)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            WatchConsole.info("⌚️ [Watch] 📩 Received message: \(message)")

            switch message["type"] as? String {
            case "appearanceTheme":
                if let theme = message["theme"] as? String {
                    self.handleAppearanceTheme(theme)
                }
            case "memoUpdate":
                self.applyMemoUpdatePayload(message)
            case "codexSnapshot":
                self.handleCodexSnapshot(message)
            case "codexDispatchUpdate":
                self.handleCodexDispatchUpdate(message)
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard metadata["type"] as? String == "aiAudio" else {
            return
        }

        Task { @MainActor in
            self.handleAIAudio(fileURL: file.fileURL, metadata: metadata)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            WatchConsole.info("⌚️ [Watch] 📩 Received application context: \(applicationContext)")

            if let theme = applicationContext["appearanceTheme"] as? String {
                self.handleAppearanceTheme(theme)
            }

            // Handle bulk memo updates from iPhone
            if let updates = applicationContext["memoUpdates"] as? [[String: Any]] {
                for update in updates {
                    self.applyMemoUpdatePayload(update)
                }
            }

            if let snapshot = applicationContext["codexSnapshot"] as? [String: Any] {
                self.handleCodexSnapshot(snapshot)
            } else if applicationContext["type"] as? String == "codexSnapshot" {
                self.handleCodexSnapshot(applicationContext)
            }

            if let update = applicationContext["codexDispatchUpdate"] as? [String: Any] {
                self.handleCodexDispatchUpdate(update)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            switch userInfo["type"] as? String {
            case "codexDispatchUpdate":
                self.handleCodexDispatchUpdate(userInfo)
            case "memoUpdate":
                self.applyMemoUpdatePayload(userInfo)
            default:
                break
            }
        }
    }
}
