import CloudKit
import Foundation
#if os(macOS)
import Security
#endif

public enum CloudKitReportNotificationError: LocalizedError, Sendable {
    case invalidContainerIdentifier(String)
    case missingCloudKitEntitlement(String)

    public var errorDescription: String? {
        switch self {
        case .invalidContainerIdentifier(let identifier):
            return "Invalid CloudKit container identifier: \(identifier)"
        case .missingCloudKitEntitlement(let identifier):
            return "Current app is not signed with the CloudKit entitlement for \(identifier)"
        }
    }
}

public struct CloudKitReportNotificationSender: Sendable {
    public static let zoneName = "TalkieNotifications"
    public static let recordType = "TalkieReportNotification"

    private let containerIdentifier: String

    public init(containerIdentifier: String = TalkieEnvironment.current.cloudKitContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    @discardableResult
    public func sendReport(
        title: String,
        body: String,
        sessionId: String,
        source: String?
    ) async throws -> CKRecord.ID {
        let containerIdentifier = containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containerIdentifier.hasPrefix("iCloud.") else {
            throw CloudKitReportNotificationError.invalidContainerIdentifier(containerIdentifier)
        }
        guard Self.currentProcessCanUseCloudKitContainer(containerIdentifier) else {
            throw CloudKitReportNotificationError.missingCloudKitEntitlement(containerIdentifier)
        }

        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        try await ensureZone(zoneID, in: database)

        let recordID = CKRecord.ID(
            recordName: "\(sessionId)-\(UUID().uuidString)",
            zoneID: zoneID
        )
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["kind"] = "agent_report" as CKRecordValue
        record["title"] = sanitized(title, maxLength: 90) as CKRecordValue
        record["body"] = sanitized(body, maxLength: 800) as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["source"] = (source ?? "") as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        return try await saveRecord(record, in: database).recordID
    }

    private func ensureZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        do {
            _ = try await fetchZone(zoneID, in: database)
        } catch {
            guard Self.isMissingZone(error, zoneID: zoneID) else { throw error }
            do {
                _ = try await saveZone(CKRecordZone(zoneID: zoneID), in: database)
            } catch {
                guard !Self.isZoneAlreadyExists(error) else { return }
                throw error
            }
        }
    }

    private func fetchZone(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordZoneID: zoneID) { zone, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let zone {
                    continuation.resume(returning: zone)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func saveZone(_ zone: CKRecordZone, in database: CKDatabase) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { continuation in
            database.save(zone) { savedZone, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedZone {
                    continuation.resume(returning: savedZone)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private func saveRecord(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private func sanitized(_ text: String, maxLength: Int) -> String {
        let clean = text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard clean.count > maxLength else { return clean }
        return String(clean.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func currentProcessCanUseCloudKitContainer(_ identifier: String) -> Bool {
        #if os(macOS)
        let entitlementKeys = [
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.icloud-container-development-container-identifiers",
        ]

        guard let task = SecTaskCreateFromSelf(nil) else { return false }

        for entitlementKey in entitlementKeys {
            guard let entitlementValue = SecTaskCopyValueForEntitlement(
                task,
                entitlementKey as CFString,
                nil
            ) else {
                continue
            }

            if let identifiers = entitlementValue as? [String],
               identifiers.contains(identifier) {
                return true
            }
        }

        return false
        #else
        _ = identifier
        return true
        #endif
    }

    private static func isMissingZone(_ error: Error, zoneID: CKRecordZone.ID) -> Bool {
        guard let ckError = error as? CKError else { return false }

        switch ckError.code {
        case .unknownItem, .zoneNotFound:
            return true
        case .partialFailure:
            guard let partialErrors = ckError.partialErrorsByItemID else { return false }
            return partialErrors.contains { itemID, partialError in
                guard let partialZoneID = itemID as? CKRecordZone.ID,
                      partialZoneID == zoneID else {
                    return false
                }
                return isMissingZone(partialError, zoneID: zoneID)
            }
        default:
            return false
        }
    }

    private static func isZoneAlreadyExists(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }

        if [.serverRejectedRequest, .constraintViolation].contains(ckError.code),
           ckError.localizedDescription.localizedCaseInsensitiveContains("already exists") {
            return true
        }

        return false
    }
}
