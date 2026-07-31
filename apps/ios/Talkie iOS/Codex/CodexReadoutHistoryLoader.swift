//
//  CodexReadoutHistoryLoader.swift
//  Talkie iOS
//

import CloudKit
import Foundation

/// Loads the same private CloudKit records that drive spoken agent-report pushes.
@MainActor
enum CodexReadoutHistoryLoader {
    private static let zoneName = "TalkieNotifications"
    private static let recordType = "TalkieReportNotification"

    enum LoadError: LocalizedError {
        case cloudKitUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .cloudKitUnavailable(let reason):
                return reason
            }
        }
    }

    static func load(limit: Int = 40) async throws -> [CodexReadout] {
        guard let container = CloudKitContainerProvider.container() else {
            throw LoadError.cloudKitUnavailable(
                CloudKitContainerProvider.unavailableReason ?? "iCloud is unavailable."
            )
        }

        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let page = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: ["title", "body", "detail", "sessionId", "source", "createdAt"],
            resultsLimit: limit
        )

        var firstFailure: Error?
        let readouts = page.matchResults.compactMap { recordID, result -> CodexReadout? in
            guard case .success(let record) = result else {
                if case .failure(let error) = result, firstFailure == nil {
                    firstFailure = error
                }
                return nil
            }

            let title = (record["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = (record["body"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = (record["detail"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let source = (record["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionID = (record["sessionId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? recordID.recordName

            let displayTitle = if let title, !title.isEmpty {
                title
            } else {
                "Talkie response"
            }
            let readout = CodexReadout(
                id: recordID.recordName,
                title: displayTitle,
                body: body,
                detail: detail?.isEmpty == false ? detail : nil,
                sessionID: sessionID,
                source: source?.isEmpty == false ? source : nil,
                createdAt: (record["createdAt"] as? Date) ?? record.creationDate ?? .distantPast
            )
            return readout.spokenText.isEmpty ? nil : readout
        }

        if readouts.isEmpty, let firstFailure {
            throw firstFailure
        }

        return readouts.sorted { $0.createdAt > $1.createdAt }
    }
}
