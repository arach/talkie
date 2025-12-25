//
//  LiveDictation.swift
//  TalkieLive
//
//  GRDB record for dictations
//

import Foundation
import GRDB

// MARK: - Transcription Status

/// Tracks the transcription state of a Live
enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending    // Audio saved, transcription not yet attempted
    case failed     // Transcription failed, can retry
    case success    // Transcription completed successfully

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .failed: return "Failed"
        case .success: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .failed: return "exclamationmark.triangle"
        case .success: return "checkmark.circle"
        }
    }
}

// MARK: - Promotion Status

/// Tracks what happened to a Live after capture
enum PromotionStatus: String, Codable, CaseIterable {
    case none       // Just a Live, no follow-up
    case memo       // Promoted to a Talkie memo
    case command    // Turned into a workflow/command
    case ignored    // Explicitly marked as "don't bother me again"

    var displayName: String {
        switch self {
        case .none: return "Raw"
        case .memo: return "Memo"
        case .command: return "Command"
        case .ignored: return "Ignored"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle"
        case .memo: return "doc.text"
        case .command: return "terminal"
        case .ignored: return "eye.slash"
        }
    }
}

// MARK: - Quick Action Kind

/// Defines what a Quick Action does with a Live
enum QuickActionKind: String, Codable, CaseIterable {
    // Execute-only actions (no promotion)
    case typeAgain          // Type this into front app again
    case copyToClipboard    // Copy text to clipboard
    case retryTranscription // Re-transcribe from saved audio

    // Promote-to-memo actions
    case promoteToMemo      // Save as Talkie memo
    case createResearchMemo // Create research memo from this Live

    // Promote-to-command actions
    case sendToClaude       // Send to Claude as follow-up
    case runWorkflow        // Kick off a workflow

    // Meta actions
    case markIgnored        // Don't bother me again about this Live

    /// What promotion (if any) this action triggers
    var promotionResult: PromotionStatus? {
        switch self {
        case .typeAgain, .copyToClipboard, .retryTranscription:
            return nil  // No promotion
        case .promoteToMemo, .createResearchMemo:
            return .memo
        case .sendToClaude, .runWorkflow:
            return .command
        case .markIgnored:
            return .ignored
        }
    }

    var displayName: String {
        switch self {
        case .typeAgain: return "Type Again"
        case .copyToClipboard: return "Copy"
        case .retryTranscription: return "Retry Transcription"
        case .promoteToMemo: return "Save as Memo"
        case .createResearchMemo: return "Research Memo"
        case .sendToClaude: return "Send to Claude"
        case .runWorkflow: return "Run Workflow"
        case .markIgnored: return "Ignore"
        }
    }

    var icon: String {
        switch self {
        case .typeAgain: return "keyboard"
        case .copyToClipboard: return "doc.on.clipboard"
        case .retryTranscription: return "arrow.clockwise"
        case .promoteToMemo: return "doc.text"
        case .createResearchMemo: return "magnifyingglass.circle"
        case .sendToClaude: return "brain"
        case .runWorkflow: return "play.circle"
        case .markIgnored: return "eye.slash"
        }
    }

    var shortcut: String? {
        switch self {
        case .copyToClipboard: return "⌘C"
        case .typeAgain: return "⌘T"
        case .promoteToMemo: return "⌘S"
        default: return nil
        }
    }
}

// MARK: - Live Dictation Model

struct LiveDictation: Identifiable, Hashable {
    var id: Int64?
    var createdAt: Date
    var text: String
    var mode: String
    var appBundleID: String?
    var appName: String?
    var windowTitle: String?
    var durationSeconds: Double?       // Recording duration (how long user talked)
    var wordCount: Int?
    var transcriptionModel: String?
    var perfEngineMs: Int?             // Time in TalkieEngine (transcription)
    var perfEndToEndMs: Int?           // Total: stop recording → delivery
    var perfInAppMs: Int?              // TalkieLive in-app processing (endToEnd - engine)
    var sessionID: String?
    var metadata: [String: String]?
    var audioFilename: String?

    // Transcription tracking
    var transcriptionStatus: TranscriptionStatus
    var transcriptionError: String?  // Error message if failed

    // Promotion tracking
    var promotionStatus: PromotionStatus
    var talkieMemoID: String?   // ID of the memo if promoted to memo
    var commandID: String?       // ID of the command/workflow if promoted to command

    // Queue tracking (implicit queue)
    var createdInTalkieView: Bool   // Was this recorded inside Talkie Live UI?
    var pasteTimestamp: Date?       // When was this pasted? (nil = still queued)

    static let databaseTableName = "dictations"

    enum Columns: String, ColumnExpression {
        case id, createdAt, text, mode, appBundleID, appName, windowTitle
        case durationSeconds, wordCount, transcriptionModel
        case perfEngineMs, perfEndToEndMs, perfInAppMs
        case sessionID, metadata, audioFilename
        case transcriptionStatus, transcriptionError
        case promotionStatus, talkieMemoID, commandID
        case createdInTalkieView, pasteTimestamp
    }

    /// Full URL to the audio file if it exists
    var audioURL: URL? {
        guard let filename = audioFilename else { return nil }
        return AudioStorage.audioDirectory.appendingPathComponent(filename)
    }

    /// Whether the audio file exists on disk
    var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Whether this Live needs action (not promoted, not ignored)
    var needsAction: Bool {
        promotionStatus == .none
    }

    /// Whether this Live can still be promoted
    var canPromote: Bool {
        promotionStatus == .none
    }

    /// Whether this Live is queued (created in Talkie, never pasted, not promoted)
    var isQueued: Bool {
        createdInTalkieView && pasteTimestamp == nil && promotionStatus == .none
    }

    /// Whether this Live can be retried (failed transcription with audio available)
    var canRetryTranscription: Bool {
        (transcriptionStatus == .failed || transcriptionStatus == .pending) && hasAudio
    }

    init(
        id: Int64? = nil,
        createdAt: Date = Date(),
        text: String,
        mode: String = "typing",
        appBundleID: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        durationSeconds: Double? = nil,
        wordCount: Int? = nil,
        transcriptionModel: String? = nil,
        perfEngineMs: Int? = nil,
        perfEndToEndMs: Int? = nil,
        perfInAppMs: Int? = nil,
        sessionID: String? = nil,
        metadata: [String: String]? = nil,
        audioFilename: String? = nil,
        transcriptionStatus: TranscriptionStatus = .success,
        transcriptionError: String? = nil,
        promotionStatus: PromotionStatus = .none,
        talkieMemoID: String? = nil,
        commandID: String? = nil,
        createdInTalkieView: Bool = false,
        pasteTimestamp: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.mode = mode
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount ?? text.split(separator: " ").count
        self.transcriptionModel = transcriptionModel
        self.perfEngineMs = perfEngineMs
        self.perfEndToEndMs = perfEndToEndMs
        self.perfInAppMs = perfInAppMs
        self.sessionID = sessionID
        self.metadata = metadata
        self.audioFilename = audioFilename
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.promotionStatus = promotionStatus
        self.talkieMemoID = talkieMemoID
        self.commandID = commandID
        self.createdInTalkieView = createdInTalkieView
        self.pasteTimestamp = pasteTimestamp
    }
}

// MARK: - GRDB Protocols

extension LiveDictation: FetchableRecord {
    init(row: Row) {
        id = row[Columns.id]
        let ts: Double = row[Columns.createdAt]
        createdAt = Date(timeIntervalSince1970: ts)
        text = row[Columns.text]
        mode = row[Columns.mode]
        appBundleID = row[Columns.appBundleID]
        appName = row[Columns.appName]
        windowTitle = row[Columns.windowTitle]
        durationSeconds = row[Columns.durationSeconds]
        wordCount = row[Columns.wordCount]
        transcriptionModel = row[Columns.transcriptionModel]
        perfEngineMs = row[Columns.perfEngineMs]
        perfEndToEndMs = row[Columns.perfEndToEndMs]
        perfInAppMs = row[Columns.perfInAppMs]
        sessionID = row[Columns.sessionID]
        audioFilename = row[Columns.audioFilename]

        // Transcription status fields
        if let statusString: String = row[Columns.transcriptionStatus],
           let status = TranscriptionStatus(rawValue: statusString) {
            transcriptionStatus = status
        } else {
            transcriptionStatus = .success  // Default for existing records
        }
        transcriptionError = row[Columns.transcriptionError]

        // Promotion fields
        if let statusString: String = row[Columns.promotionStatus],
           let status = PromotionStatus(rawValue: statusString) {
            promotionStatus = status
        } else {
            promotionStatus = .none
        }
        talkieMemoID = row[Columns.talkieMemoID]
        commandID = row[Columns.commandID]

        // Queue fields
        let createdInTalkieViewInt: Int? = row[Columns.createdInTalkieView]
        createdInTalkieView = (createdInTalkieViewInt ?? 0) == 1
        if let pasteTs: Double = row[Columns.pasteTimestamp] {
            pasteTimestamp = Date(timeIntervalSince1970: pasteTs)
        } else {
            pasteTimestamp = nil
        }

        if let json: String = row[Columns.metadata],
           let data = json.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            metadata = dict
        } else {
            metadata = nil
        }
    }
}

extension LiveDictation: PersistableRecord {
    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.createdAt] = createdAt.timeIntervalSince1970
        container[Columns.text] = text
        container[Columns.mode] = mode
        container[Columns.appBundleID] = appBundleID
        container[Columns.appName] = appName
        container[Columns.windowTitle] = windowTitle
        container[Columns.durationSeconds] = durationSeconds
        container[Columns.wordCount] = wordCount
        container[Columns.transcriptionModel] = transcriptionModel
        container[Columns.perfEngineMs] = perfEngineMs
        container[Columns.perfEndToEndMs] = perfEndToEndMs
        container[Columns.perfInAppMs] = perfInAppMs
        container[Columns.sessionID] = sessionID
        container[Columns.audioFilename] = audioFilename

        // Transcription status fields
        container[Columns.transcriptionStatus] = transcriptionStatus.rawValue
        container[Columns.transcriptionError] = transcriptionError

        // Promotion fields
        container[Columns.promotionStatus] = promotionStatus.rawValue
        container[Columns.talkieMemoID] = talkieMemoID
        container[Columns.commandID] = commandID

        // Queue fields
        container[Columns.createdInTalkieView] = createdInTalkieView ? 1 : 0
        container[Columns.pasteTimestamp] = pasteTimestamp?.timeIntervalSince1970

        if let metadata {
            let data = try? JSONEncoder().encode(metadata)
            container[Columns.metadata] = data.flatMap { String(data: $0, encoding: .utf8) }
        } else {
            container[Columns.metadata] = nil
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
