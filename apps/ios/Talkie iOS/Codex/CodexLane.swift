//
//  CodexLane.swift
//  Talkie iOS
//
//  Models for the Command Deck's Codex lanes.
//
//  A lane is a stable numbered slot bound to ONE exact Codex Desktop task —
//  not a repository, not the frontmost window. The whole point of the lane is
//  that the user knows precisely which conversation will receive the next
//  instruction, so every type here keeps the exact task ID as the identity and
//  treats "we could not confirm it" as a first-class state rather than a
//  cosmetic detail.
//

import Foundation

/// How a message spoken while Codex is working should be delivered.
///
/// Queue is the default because it preserves the current turn and starts a new
/// one afterward. Steer deliberately adds context to the turn already running.
enum CodexMessageMode: String, Codable, Equatable, Sendable {
    case auto
    case queue
    case steer

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .queue: return "Queue"
        case .steer: return "Steer"
        }
    }
}

/// A recent Codex Desktop task, as offered by the lane mapper.
struct CodexTaskSummary: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let preview: String
    let cwd: String
    let project: String?
    let gitBranch: String?
    let gitOriginURL: String?
    /// Seconds since epoch, as reported by the Mac-side adapter.
    let updatedAt: Double

    init(
        id: String,
        title: String,
        preview: String,
        cwd: String,
        project: String? = nil,
        gitBranch: String? = nil,
        gitOriginURL: String? = nil,
        updatedAt: Double
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.cwd = cwd
        self.project = project
        self.gitBranch = gitBranch
        self.gitOriginURL = gitOriginURL
        self.updatedAt = updatedAt
    }

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }

    /// Last path component of the working directory — the label a developer
    /// actually recognizes when two tasks share a title.
    var projectName: String {
        if let project = project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            return project
        }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    var compactPath: String {
        let home = URL.homeDirectory.path
        if cwd == home { return "~" }
        if cwd.hasPrefix("\(home)/") {
            return "~\(cwd.dropFirst(home.count))"
        }
        return cwd
    }

    var shortID: String { String(id.suffix(8)) }

    var branchName: String? {
        guard let branch = gitBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else { return nil }
        return branch
    }

    /// Matches when every whitespace-separated term appears somewhere in the
    /// task's title, preview, project path, or ID. Term-wise (rather than
    /// substring-of-the-whole-query) so "talkie ios" finds a task titled
    /// "iOS build" in the talkie project.
    func matchesSearch(_ query: String) -> Bool {
        let terms = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return true }

        let haystack = [title, preview, projectName, cwd, gitBranch ?? "", gitOriginURL ?? "", id]
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return terms.allSatisfy(haystack.contains)
    }

    /// Compact recency label ("now", "12m", "3h") for the mapper rows.
    func activityLabel(relativeTo now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(updatedDate))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }
        return "\(Int(seconds / 604_800))w"
    }
}

/// Which delivery the Mac performed. The deck reports this verbatim: starting a
/// new turn and steering one already in flight are meaningfully different
/// outcomes and hiding the distinction would make the deck untrustworthy.
enum CodexTurnDelivery: String, Codable, Equatable, Sendable {
    case startedTurn = "started-turn"
    case queuedTurn = "queued-turn"
    case steeredActiveTurn = "steered-active-turn"

    var label: String {
        switch self {
        case .startedTurn: return "Started a new turn"
        case .queuedTurn: return "Ran the queued turn"
        case .steeredActiveTurn: return "Steered the active turn"
        }
    }

    var detailLabel: String {
        switch self {
        case .startedTurn: return "Started a new turn in the exact task"
        case .queuedTurn: return "Started a queued turn after the active turn"
        case .steeredActiveTurn: return "Steered the active turn in the exact task"
        }
    }
}

/// A numbered deck lane bound to one exact Codex task.
///
/// `task` is the assignment the user made; it persists across launches and
/// disconnects. Whether that assignment is currently *trustworthy* is tracked
/// separately by the store, because a stored binding says nothing about whether
/// Codex Desktop still owns the task right now.
struct CodexLane: Codable, Equatable, Identifiable, Sendable {
    /// Six bindings power the lid's lane picker and the current physical lane
    /// shortcuts. Selection and mapping remain separate from task ownership.
    static let range = 1...6

    let number: Int
    var task: CodexTaskSummary
    /// Optional per-lane narration voice. Left open deliberately — the brief
    /// wants room for it without making it a launch blocker.
    var voiceOverride: CodexLaneVoiceOverride?

    var id: Int { number }

    /// Short spoken form of the task title, for narration preambles.
    var spokenTitle: String {
        let words = task.title
            .split(whereSeparator: \Character.isWhitespace)
            .prefix(7)
            .joined(separator: " ")
        return words.isEmpty ? "Task \(number)" : words
    }
}

/// Per-lane speech provider/voice selection. Reuses the app's existing provider
/// IDs rather than introducing a second TTS configuration system.
struct CodexLaneVoiceOverride: Codable, Equatable, Sendable {
    let provider: String
    let voiceID: String

    init?(provider: String, voiceID: String) {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedVoiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProvider.isEmpty, !normalizedVoiceID.isEmpty else { return nil }
        self.provider = normalizedProvider
        self.voiceID = normalizedVoiceID
    }
}

/// Honest phases of the voice loop. Every state the user can be left sitting in
/// is nameable, including the failure — a deck that silently returns to idle
/// after a dropped turn is the failure mode this enum exists to prevent.
enum CodexLanePhase: Equatable, Sendable {
    case idle
    /// Confirming Codex Desktop still owns the exact task before claiming a lock.
    case validating
    case listening
    case transcribing
    /// Instruction sent; waiting for the Codex turn to complete.
    case submitting
    case preparingSpeech
    case speaking
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .validating: return "Validating"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .submitting: return "Waiting for Codex"
        case .preparingSpeech: return "Preparing speech"
        case .speaking: return "Speaking"
        case .failed(let message): return message
        }
    }

    var isBusy: Bool {
        switch self {
        case .idle, .failed: return false
        case .validating, .listening, .transcribing, .submitting, .preparingSpeech, .speaking: return true
        }
    }

    /// True while the mic is open — used to decide whether a press should stop
    /// capture rather than start a new one.
    var isCapturing: Bool {
        self == .listening || self == .transcribing
    }
}

/// One completed exchange, retained so the response stays readable after
/// narration ends (or when narration never happened at all).
struct CodexTurnRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let laneNumber: Int
    let taskID: String
    let taskTitle: String
    let instruction: String
    let response: String
    let delivery: CodexTurnDelivery
    let completedAt: Date
    /// Set when narration was attempted and failed. A speech failure is
    /// reported alongside a successful turn, never as a failed turn.
    var speechFailure: String?
    /// True when the configured output route intentionally stayed silent.
    var narrationSuppressed: Bool

    init(
        id: UUID = UUID(),
        laneNumber: Int,
        taskID: String,
        taskTitle: String,
        instruction: String,
        response: String,
        delivery: CodexTurnDelivery,
        completedAt: Date = Date(),
        speechFailure: String? = nil,
        narrationSuppressed: Bool = false
    ) {
        self.id = id
        self.laneNumber = laneNumber
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.instruction = instruction
        self.response = response
        self.delivery = delivery
        self.completedAt = completedAt
        self.speechFailure = speechFailure
        self.narrationSuppressed = narrationSuppressed
    }
}

/// Why a lane is not currently locked. Carries the Mac's recovery hint so the
/// deck explains the fix instead of only reporting the symptom.
struct CodexLaneFailure: Equatable, Sendable {
    let message: String
    let hint: String?

    var combined: String {
        guard let hint, !hint.isEmpty else { return message }
        return "\(message) \(hint)"
    }
}
