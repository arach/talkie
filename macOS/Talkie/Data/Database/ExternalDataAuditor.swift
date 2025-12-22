//
//  ExternalDataAuditor.swift
//  Talkie
//
//  Diagnostic utility to audit and clean up orphaned external data files
//

import Foundation
import CoreData
import GRDB

@Observable
final class ExternalDataAuditor {
    var isAuditing = false
    var auditResults: AuditResults?
    var lastError: Error?

    struct AuditResults {
        let timestamp: Date

        // CoreData external storage
        let coreDataExternalFiles: Set<String>        // Files in _EXTERNAL_DATA/
        let coreDataReferencedUUIDs: Set<String>      // UUIDs referenced in database
        let coreDataOrphanedFiles: Set<String>        // Files with no DB reference
        let coreDataMissingFiles: Set<String>         // DB references with no file

        // GRDB audio storage
        let grdbAudioFiles: Set<String>               // Files in Audio/
        let grdbReferencedFiles: Set<String>          // Files referenced in database
        let grdbOrphanedFiles: Set<String>            // Files with no DB reference
        let grdbMissingFiles: Set<String>             // DB references with no file

        var totalStorageBytes: Int64
        var coreDataStorageBytes: Int64
        var grdbStorageBytes: Int64

        var hasIssues: Bool {
            !coreDataOrphanedFiles.isEmpty ||
            !coreDataMissingFiles.isEmpty ||
            !grdbOrphanedFiles.isEmpty ||
            !grdbMissingFiles.isEmpty
        }

        var summary: String {
            """
            External Data Audit Report
            Generated: \(timestamp.formatted())

            === CoreData External Storage ===
            Location: ~/Library/Application Support/Talkie/.talkie_SUPPORT/_EXTERNAL_DATA/
            Total Files: \(coreDataExternalFiles.count)
            Referenced by DB: \(coreDataReferencedUUIDs.count)
            Orphaned Files: \(coreDataOrphanedFiles.count)
            Missing Files: \(coreDataMissingFiles.count)
            Storage: \(ByteCountFormatter.string(fromByteCount: coreDataStorageBytes, countStyle: .file))

            === GRDB Audio Storage ===
            Location: ~/Library/Application Support/Talkie/Audio/
            Total Files: \(grdbAudioFiles.count)
            Referenced by DB: \(grdbReferencedFiles.count)
            Orphaned Files: \(grdbOrphanedFiles.count)
            Missing Files: \(grdbMissingFiles.count)
            Storage: \(ByteCountFormatter.string(fromByteCount: grdbStorageBytes, countStyle: .file))

            === Total Storage ===
            \(ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file))

            Status: \(hasIssues ? "⚠️ Issues Found" : "✅ All Clear")
            """
        }
    }

    // MARK: - Audit

    func performAudit() async throws -> AuditResults {
        isAuditing = true
        defer { isAuditing = false }

        // CoreData external storage paths
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let coreDataExternalDir = appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent(".talkie_SUPPORT", isDirectory: true)
            .appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)

        let grdbAudioDir = appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)

        // 1. Scan CoreData external files
        let coreDataFiles = scanDirectory(coreDataExternalDir)
        let coreDataSize = directorySize(coreDataExternalDir)

        // 2. Scan GRDB audio files
        let grdbFiles = scanDirectory(grdbAudioDir)
        let grdbSize = directorySize(grdbAudioDir)

        // 3. Get CoreData references
        let coreDataRefs = try await getCoreDataExternalReferences()

        // 4. Get GRDB references
        let grdbRefs = try await getGRDBReferences()

        // 5. Calculate orphaned and missing
        let coreDataOrphaned = coreDataFiles.subtracting(coreDataRefs)
        let coreDataMissing = coreDataRefs.subtracting(coreDataFiles)

        let grdbOrphaned = grdbFiles.subtracting(grdbRefs)
        let grdbMissing = grdbRefs.subtracting(grdbFiles)

        let results = AuditResults(
            timestamp: Date(),
            coreDataExternalFiles: coreDataFiles,
            coreDataReferencedUUIDs: coreDataRefs,
            coreDataOrphanedFiles: coreDataOrphaned,
            coreDataMissingFiles: coreDataMissing,
            grdbAudioFiles: grdbFiles,
            grdbReferencedFiles: grdbRefs,
            grdbOrphanedFiles: grdbOrphaned,
            grdbMissingFiles: grdbMissing,
            totalStorageBytes: coreDataSize + grdbSize,
            coreDataStorageBytes: coreDataSize,
            grdbStorageBytes: grdbSize
        )

        self.auditResults = results
        return results
    }

    // MARK: - Cleanup

    func cleanupOrphanedFiles() async throws -> (coreDataDeleted: Int, grdbDeleted: Int, bytesFreed: Int64) {
        guard let results = auditResults else {
            throw AuditorError.noAuditResults
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        var coreDataDeleted = 0
        var grdbDeleted = 0
        var bytesFreed: Int64 = 0

        // Delete CoreData orphaned files
        let coreDataDir = appSupport
            .appendingPathComponent("Talkie/.talkie_SUPPORT/_EXTERNAL_DATA", isDirectory: true)

        for filename in results.coreDataOrphanedFiles {
            let fileURL = coreDataDir.appendingPathComponent(filename)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                bytesFreed += size
            }
            try? FileManager.default.removeItem(at: fileURL)
            coreDataDeleted += 1
        }

        // Delete GRDB orphaned files
        let grdbDir = appSupport.appendingPathComponent("Talkie/Audio", isDirectory: true)

        for filename in results.grdbOrphanedFiles {
            let fileURL = grdbDir.appendingPathComponent(filename)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                bytesFreed += size
            }
            try? FileManager.default.removeItem(at: fileURL)
            grdbDeleted += 1
        }

        return (coreDataDeleted, grdbDeleted, bytesFreed)
    }

    // MARK: - Private Helpers

    private func scanDirectory(_ url: URL) -> Set<String> {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return Set(files.map { $0.lastPathComponent })
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    private func getCoreDataExternalReferences() async throws -> Set<String> {
        // Query all ZAUDIODATA blobs that are external references (small size = 38 bytes)
        // These contain the UUID of the external file
        let context = PersistenceController.shared.container.viewContext

        return try await context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "VoiceMemo")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["audioData"]
            request.predicate = NSPredicate(format: "audioData != nil")

            guard let results = try context.fetch(request) as? [[String: Any]] else {
                return []
            }

            var uuids = Set<String>()

            for result in results {
                if let audioData = result["audioData"] as? Data,
                   audioData.count < 100,  // External references are ~38 bytes
                   let uuid = self.extractUUIDFromExternalReference(audioData) {
                    uuids.insert(uuid)
                }
            }

            return uuids
        }
    }

    private func getGRDBReferences() async throws -> Set<String> {
        let db = try DatabaseManager.shared.database()

        return try await db.read { db in
            let filenames = try String.fetchAll(
                db,
                sql: "SELECT audioFilePath FROM voice_memos WHERE audioFilePath IS NOT NULL"
            )
            return Set(filenames)
        }
    }

    private func extractUUIDFromExternalReference(_ data: Data) -> String? {
        // External reference format: Binary plist containing UUID string
        // Example hex: 02 + ASCII UUID bytes + 00
        guard data.count > 2 else { return nil }

        // Skip first 2 bytes (binary plist header)
        let uuidData = data.dropFirst(2).prefix(36)

        if let uuidString = String(data: Data(uuidData), encoding: .ascii),
           uuidString.count == 36,
           uuidString.contains("-") {
            return uuidString
        }

        return nil
    }

    enum AuditorError: LocalizedError {
        case noAuditResults

        var errorDescription: String? {
            switch self {
            case .noAuditResults:
                return "No audit results available. Run performAudit() first."
            }
        }
    }
}
