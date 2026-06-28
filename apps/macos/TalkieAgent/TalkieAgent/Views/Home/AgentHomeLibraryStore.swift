//
//  AgentHomeLibraryStore.swift
//  TalkieAgent
//
//  Read-only Library/History snapshot for Agent Home. Talkie owns the
//  full editing surface; Agent Home only observes the shared recordings table.
//

import Foundation
import GRDB
import TalkieKit

private let agentHomeLibraryLog = Log(.database)

enum AgentHomeLibraryFilter: Equatable {
    case all
    case captures

    var title: String {
        switch self {
        case .all: return "History"
        case .captures: return "Captures"
        }
    }

    var eyebrow: String {
        switch self {
        case .all: return "· History"
        case .captures: return "· Captures"
        }
    }

    var subtitle: String {
        switch self {
        case .all:
            return "Read-only history from Talkie's shared recordings table."
        case .captures:
            return "Screenshots and clips from Talkie's shared recordings table."
        }
    }

    var sectionSubtitle: String {
        switch self {
        case .all:
            return "Memos, dictations, notes, captures, and selections from Talkie."
        case .captures:
            return "Screenshots, screen recordings, and visual context captured by Talkie."
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "NO LIBRARY ITEMS YET"
        case .captures: return "NO CAPTURES YET"
        }
    }

    var emptyDetail: String {
        switch self {
        case .all:
            return "New memos, dictations, captures, notes, and selections will appear here after Talkie writes them."
        case .captures:
            return "New screenshots and clips will appear here after Talkie writes them."
        }
    }

    fileprivate var typeRawValue: String? {
        switch self {
        case .all: return nil
        case .captures: return TalkieObjectType.capture.rawValue
        }
    }
}

@MainActor
final class AgentHomeLibraryStore: ObservableObject {
    struct Summary: Equatable {
        var total: Int = 0
        var memos: Int = 0
        var dictations: Int = 0
        var notes: Int = 0
        var captures: Int = 0
        var selections: Int = 0

        static let empty = Summary()

        mutating func setCount(_ count: Int, for rawType: String) {
            switch TalkieObjectType(rawValue: rawType) {
            case .memo:
                memos = count
            case .dictation:
                dictations = count
            case .note:
                notes = count
            case .capture:
                captures = count
            case .selection:
                selections = count
            case .segment, .none:
                break
            }
        }
    }

    @Published private(set) var items: [TalkieObject] = []
    @Published private(set) var summary: Summary = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let displayLimit: Int?
    let filter: AgentHomeLibraryFilter

    private var observation: AnyDatabaseCancellable?

    init(displayLimit: Int? = 200, filter: AgentHomeLibraryFilter = .all) {
        self.displayLimit = displayLimit
        self.filter = filter
    }

    func start() {
        observation?.cancel()
        observation = nil
        isLoading = true
        errorMessage = nil

        let displayLimit = displayLimit
        let typeRawValue = filter.typeRawValue
        let valueObservation = ValueObservation.tracking { db -> AgentHomeLibrarySnapshot in
            let rows: [TalkieObject]
            if let typeRawValue, let displayLimit {
                rows = try TalkieObject.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM recordings
                    WHERE deletedAt IS NULL AND type != 'segment' AND type = ?
                    ORDER BY createdAt DESC
                    LIMIT ?
                    """,
                    arguments: [typeRawValue, displayLimit]
                )
            } else if let typeRawValue {
                rows = try TalkieObject.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM recordings
                    WHERE deletedAt IS NULL AND type != 'segment' AND type = ?
                    ORDER BY createdAt DESC
                    """,
                    arguments: [typeRawValue]
                )
            } else if let displayLimit {
                rows = try TalkieObject.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM recordings
                    WHERE deletedAt IS NULL AND type != 'segment'
                    ORDER BY createdAt DESC
                    LIMIT ?
                    """,
                    arguments: [displayLimit]
                )
            } else {
                rows = try TalkieObject.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM recordings
                    WHERE deletedAt IS NULL AND type != 'segment'
                    ORDER BY createdAt DESC
                    """
                )
            }

            var summary = AgentHomeLibraryStore.Summary.empty
            let countRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT type, COUNT(*) AS count
                    FROM recordings
                    WHERE deletedAt IS NULL AND type != 'segment'
                    GROUP BY type
                    """
            )

            for row in countRows {
                let rawType: String = row["type"]
                let count: Int = row["count"]
                summary.total += count
                summary.setCount(count, for: rawType)
            }

            return AgentHomeLibrarySnapshot(items: rows, summary: summary)
        }

        observation = valueObservation.start(
            in: UnifiedDatabase.shared,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.items = []
                    self.summary = .empty
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    agentHomeLibraryLog.error("Library observation failed: \(error.localizedDescription)")
                }
            },
            onChange: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.items = snapshot.items
                    self.summary = snapshot.summary
                    self.isLoading = false
                    self.errorMessage = nil
                }
            }
        )
    }

    func stop() {
        observation?.cancel()
        observation = nil
        isLoading = false
    }
}

private struct AgentHomeLibrarySnapshot: Equatable {
    let items: [TalkieObject]
    let summary: AgentHomeLibraryStore.Summary
}
