//
//  LiveUtterance.swift
//  TalkieLive
//
//  GRDB record for utterances
//

import Foundation
import GRDB

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

// MARK: - Live Utterance Model

struct LiveUtterance: Identifiable, Hashable {
    var id: Int64?
    var createdAt: Date
    var text: String
    var mode: String
    var appBundleID: String?
    var appName: String?
    var windowTitle: String?
    var durationSeconds: Double?
    var wordCount: Int?
    var whisperModel: String?
    var transcriptionMs: Int?
    var sessionID: String?
    var metadata: [String: String]?
    var audioFilename: String?

    // Promotion tracking
    var promotionStatus: PromotionStatus
    var talkieMemoID: String?   // ID of the memo if promoted to memo
    var commandID: String?       // ID of the command/workflow if promoted to command

    static let databaseTableName = "live_utterance"

    enum Columns: String, ColumnExpression {
        case id, createdAt, text, mode, appBundleID, appName, windowTitle
        case durationSeconds, wordCount, whisperModel, transcriptionMs
        case sessionID, metadata, audioFilename
        case promotionStatus, talkieMemoID, commandID
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
        whisperModel: String? = nil,
        transcriptionMs: Int? = nil,
        sessionID: String? = nil,
        metadata: [String: String]? = nil,
        audioFilename: String? = nil,
        promotionStatus: PromotionStatus = .none,
        talkieMemoID: String? = nil,
        commandID: String? = nil
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
        self.whisperModel = whisperModel
        self.transcriptionMs = transcriptionMs
        self.sessionID = sessionID
        self.metadata = metadata
        self.audioFilename = audioFilename
        self.promotionStatus = promotionStatus
        self.talkieMemoID = talkieMemoID
        self.commandID = commandID
    }
}

// MARK: - GRDB Protocols

extension LiveUtterance: FetchableRecord {
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
        whisperModel = row[Columns.whisperModel]
        transcriptionMs = row[Columns.transcriptionMs]
        sessionID = row[Columns.sessionID]
        audioFilename = row[Columns.audioFilename]

        // Promotion fields
        if let statusString: String = row[Columns.promotionStatus],
           let status = PromotionStatus(rawValue: statusString) {
            promotionStatus = status
        } else {
            promotionStatus = .none
        }
        talkieMemoID = row[Columns.talkieMemoID]
        commandID = row[Columns.commandID]

        if let json: String = row[Columns.metadata],
           let data = json.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            metadata = dict
        } else {
            metadata = nil
        }
    }
}

extension LiveUtterance: PersistableRecord {
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
        container[Columns.whisperModel] = whisperModel
        container[Columns.transcriptionMs] = transcriptionMs
        container[Columns.sessionID] = sessionID
        container[Columns.audioFilename] = audioFilename

        // Promotion fields
        container[Columns.promotionStatus] = promotionStatus.rawValue
        container[Columns.talkieMemoID] = talkieMemoID
        container[Columns.commandID] = commandID

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
