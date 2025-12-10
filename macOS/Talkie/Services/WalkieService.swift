//
//  WalkieService.swift
//  Talkie macOS
//
//  Walkie = the response that talks back!
//  Talkie + Walkie = Walkie-Talkie
//
//  Manages audio responses stored in CloudKit for cross-device delivery.
//  - Uploads TTS audio to CloudKit as CKAsset
//  - Links Walkies to source memos
//  - Auto-cleans Walkies older than 7 days
//

import Foundation
import CloudKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Walkie")

// MARK: - Walkie Model

/// Who sent this Walkie?
enum WalkieSender: String, Codable {
    case user = "user"      // User's voice reply
    case assistant = "ai"   // AI/workflow response
}

/// A Walkie is a conversational audio message in a thread
/// - AI Walkies: Responses from workflows/LLMs
/// - User Walkies: Quick voice replies (ephemeral, not full memos)
///
/// Thread structure: VoiceMemo (Talkie) → Walkie → Walkie → Walkie → ...
struct Walkie: Identifiable, Codable {
    let id: String                  // CloudKit record ID
    let memoId: String              // Links to root VoiceMemo (anchor of conversation)
    let parentWalkieId: String?     // Previous Walkie in thread (nil = first response to memo)
    let sender: WalkieSender        // Who sent this: user or AI
    let transcript: String          // What was said (TTS text or user transcription)
    var audioURL: URL?              // Local URL after download (not persisted)
    let createdAt: Date
    let expiresAt: Date             // TTL: 7 days from creation
    let workflowName: String?       // Which workflow generated this (AI only)

    var isExpired: Bool {
        Date() > expiresAt
    }

    /// Is this from the AI/workflow?
    var isFromAssistant: Bool {
        sender == .assistant
    }

    /// Is this a user reply?
    var isFromUser: Bool {
        sender == .user
    }

    // Codable - exclude audioURL (it's transient/local)
    enum CodingKeys: String, CodingKey {
        case id, memoId, parentWalkieId, sender, transcript, createdAt, expiresAt, workflowName
    }
}

// MARK: - WalkieService

@MainActor
class WalkieService: ObservableObject {
    static let shared = WalkieService()

    private let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
    private let recordType = "Walkie"
    private let ttlDays: Int = 7

    @Published var isUploading = false
    @Published var lastError: String?

    // Cache of downloaded Walkies
    private var walkieCache: [String: URL] = [:]  // memoId -> local audio URL

    private init() {}

    // MARK: - Upload Walkie

    /// Upload a Walkie audio response to CloudKit
    /// - Parameters:
    ///   - audioURL: Local URL of the audio file
    ///   - memoId: ID of the root VoiceMemo (anchor of conversation)
    ///   - parentWalkieId: Previous Walkie in thread (nil = first response to memo)
    ///   - sender: Who is sending this (user or AI)
    ///   - transcript: Text content (TTS text for AI, transcription for user)
    ///   - workflowName: Name of the workflow that generated this (AI only)
    /// - Returns: The created Walkie record ID
    @discardableResult
    func uploadWalkie(
        audioURL: URL,
        memoId: String,
        parentWalkieId: String? = nil,
        sender: WalkieSender = .assistant,
        transcript: String,
        workflowName: String? = nil
    ) async throws -> String {
        logger.info("Uploading \(sender.rawValue) Walkie for memo: \(memoId)")

        isUploading = true
        defer { isUploading = false }

        let database = container.privateCloudDatabase

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: "walkie-\(UUID().uuidString)")
        let record = CKRecord(recordType: recordType, recordID: recordID)

        // Set fields
        record["memoId"] = memoId
        record["parentWalkieId"] = parentWalkieId
        record["sender"] = sender.rawValue
        record["transcript"] = transcript
        record["workflowName"] = workflowName
        record["createdAt"] = Date()
        record["expiresAt"] = Calendar.current.date(byAdding: .day, value: ttlDays, to: Date())!

        // Attach audio as CKAsset
        let asset = CKAsset(fileURL: audioURL)
        record["audioAsset"] = asset

        // Save to CloudKit
        do {
            let savedRecord = try await database.save(record)
            let walkieId = savedRecord.recordID.recordName

            logger.info("Walkie uploaded: \(walkieId)")

            // Post notification for iOS to receive
            NotificationCenter.default.post(
                name: .walkieUploaded,
                object: nil,
                userInfo: [
                    "walkieId": walkieId,
                    "memoId": memoId,
                    "sender": sender.rawValue
                ]
            )

            return walkieId
        } catch {
            logger.error("Failed to upload Walkie: \(error.localizedDescription)")
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Fetch conversation thread for a memo (all Walkies in chronological order)
    func fetchConversation(for memoId: String) async throws -> [Walkie] {
        logger.info("Fetching conversation for memo: \(memoId)")

        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: "memoId == %@", memoId)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]  // Chronological

        let (results, _) = try await database.records(matching: query)

        var walkies: [Walkie] = []
        for (_, result) in results {
            switch result {
            case .success(let record):
                if let walkie = walkie(from: record) {
                    walkies.append(walkie)
                }
            case .failure(let error):
                logger.warning("Failed to fetch record: \(error.localizedDescription)")
            }
        }

        logger.info("Found \(walkies.count) Walkie(s) in conversation")
        return walkies
    }

    // MARK: - Fetch Walkies

    /// Fetch all Walkies for a specific memo
    func fetchWalkies(for memoId: String) async throws -> [Walkie] {
        logger.info("Fetching Walkies for memo: \(memoId)")

        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: "memoId == %@", memoId)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await database.records(matching: query)

        var walkies: [Walkie] = []
        for (_, result) in results {
            switch result {
            case .success(let record):
                if let walkie = walkie(from: record) {
                    walkies.append(walkie)
                }
            case .failure(let error):
                logger.warning("Failed to fetch record: \(error.localizedDescription)")
            }
        }

        logger.info("Found \(walkies.count) Walkie(s) for memo")
        return walkies
    }

    /// Fetch the latest Walkie for a memo (most recent response)
    func fetchLatestWalkie(for memoId: String) async throws -> Walkie? {
        let walkies = try await fetchWalkies(for: memoId)
        return walkies.first
    }

    /// Fetch all unexpired Walkies
    func fetchAllWalkies() async throws -> [Walkie] {
        logger.info("Fetching all Walkies")

        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: "expiresAt > %@", Date() as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await database.records(matching: query)

        var walkies: [Walkie] = []
        for (_, result) in results {
            switch result {
            case .success(let record):
                if let walkie = walkie(from: record) {
                    walkies.append(walkie)
                }
            case .failure(let error):
                logger.warning("Failed to fetch record: \(error.localizedDescription)")
            }
        }

        logger.info("Found \(walkies.count) total Walkie(s)")
        return walkies
    }

    // MARK: - Download Audio

    /// Download Walkie audio to local cache
    func downloadAudio(for walkie: Walkie) async throws -> URL {
        // Check cache first
        if let cachedURL = walkieCache[walkie.id], FileManager.default.fileExists(atPath: cachedURL.path) {
            logger.info("Using cached audio for Walkie: \(walkie.id)")
            return cachedURL
        }

        logger.info("Downloading audio for Walkie: \(walkie.id)")

        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: walkie.id)

        let record = try await database.record(for: recordID)

        guard let asset = record["audioAsset"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw WalkieError.noAudioData
        }

        // Copy to cache directory
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw WalkieError.noAudioData
        }
        let cacheDir = cachesURL.appendingPathComponent("Walkies", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("\(walkie.id).caf")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.copyItem(at: assetURL, to: localURL)

        walkieCache[walkie.id] = localURL
        logger.info("Downloaded Walkie audio to: \(localURL.lastPathComponent)")

        return localURL
    }

    // MARK: - TTL Cleanup

    /// Clean up expired Walkies (older than 7 days)
    func cleanupExpiredWalkies() async {
        logger.info("Starting Walkie cleanup...")

        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: "expiresAt <= %@", Date() as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        do {
            let (results, _) = try await database.records(matching: query)

            var deleteCount = 0
            for (recordID, result) in results {
                switch result {
                case .success:
                    try await database.deleteRecord(withID: recordID)
                    deleteCount += 1

                    // Also clean local cache
                    if let cachedURL = walkieCache[recordID.recordName] {
                        try? FileManager.default.removeItem(at: cachedURL)
                        walkieCache.removeValue(forKey: recordID.recordName)
                    }
                case .failure:
                    continue
                }
            }

            if deleteCount > 0 {
                logger.info("Cleaned up \(deleteCount) expired Walkie(s)")
            }
        } catch {
            logger.error("Walkie cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Clean local cache (called on app termination or memory pressure)
    func cleanLocalCache() {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            walkieCache.removeAll()
            return
        }
        let cacheDir = cachesURL.appendingPathComponent("Walkies", isDirectory: true)

        try? FileManager.default.removeItem(at: cacheDir)
        walkieCache.removeAll()
        logger.info("Local Walkie cache cleared")
    }

    // MARK: - Helpers

    private func walkie(from record: CKRecord) -> Walkie? {
        guard let memoId = record["memoId"] as? String,
              let transcript = record["transcript"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let expiresAt = record["expiresAt"] as? Date else {
            return nil
        }

        // Check if expired
        if Date() > expiresAt {
            return nil
        }

        let parentWalkieId = record["parentWalkieId"] as? String
        let senderRaw = record["sender"] as? String ?? "ai"
        let sender = WalkieSender(rawValue: senderRaw) ?? .assistant
        let workflowName = record["workflowName"] as? String

        return Walkie(
            id: record.recordID.recordName,
            memoId: memoId,
            parentWalkieId: parentWalkieId,
            sender: sender,
            transcript: transcript,
            audioURL: walkieCache[record.recordID.recordName],
            createdAt: createdAt,
            expiresAt: expiresAt,
            workflowName: workflowName
        )
    }
}

// MARK: - Errors

enum WalkieError: LocalizedError {
    case noAudioData
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioData:
            return "No audio data available"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let walkieUploaded = Notification.Name("walkieUploaded")
    static let walkieReceived = Notification.Name("walkieReceived")
}
