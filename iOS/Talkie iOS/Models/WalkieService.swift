//
//  WalkieService.swift
//  Talkie iOS
//
//  Walkie = the response that talks back!
//  Talkie + Walkie = Walkie-Talkie
//
//  Fetches and plays audio responses from CloudKit.
//  - Fetches Walkies uploaded by macOS
//  - Downloads audio for playback
//  - Supports conversation threading
//

import Foundation
import CloudKit
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie", category: "Walkie")

// MARK: - Walkie Model

/// Who sent this Walkie?
enum WalkieSender: String, Codable {
    case user = "user"      // User's voice reply (refinement/follow-up)
    case assistant = "ai"   // AI/workflow response
}

/// A Walkie is a conversational message within a Talkie thread
///
/// Talkies (VoiceMemos) = Fresh threads, new topics
/// Walkies = Refinement/details within a thread (both user & AI)
///
/// Thread: Talkie → Walkie → Walkie → Walkie → ... (ephemeral, 7-day TTL)
struct Walkie: Identifiable, Codable {
    let id: String                  // CloudKit record ID
    let memoId: String              // Root VoiceMemo - the thread anchor
    let parentWalkieId: String?     // Previous Walkie in thread (nil = first response)
    let sender: WalkieSender        // Who sent this: user or AI
    let transcript: String          // What was said
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

    @Published var isLoading = false
    @Published var isPlaying = false
    @Published var currentWalkie: Walkie?
    @Published var lastError: String?

    // Cache of downloaded Walkies
    private var walkieCache: [String: URL] = [:]  // walkieId -> local audio URL

    // Audio player
    private var audioPlayer: AVAudioPlayer?

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Walkies

    /// Fetch all Walkies for a specific memo
    func fetchWalkies(for memoId: String) async throws -> [Walkie] {
        logger.info("Fetching Walkies for memo: \(memoId)")

        isLoading = true
        defer { isLoading = false }

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

        logger.info("Found \(walkies.count) Walkie(s) for memo")
        return walkies
    }

    /// Fetch the latest Walkie for a memo (most recent response)
    func fetchLatestWalkie(for memoId: String) async throws -> Walkie? {
        let walkies = try await fetchWalkies(for: memoId)
        return walkies.last  // Most recent
    }

    /// Check if a memo has any Walkies (quick check without downloading all)
    func hasWalkies(for memoId: String) async -> Bool {
        do {
            let database = container.privateCloudDatabase
            let predicate = NSPredicate(format: "memoId == %@", memoId)
            let query = CKQuery(recordType: recordType, predicate: predicate)

            let (results, _) = try await database.records(matching: query, desiredKeys: ["memoId"])
            return !results.isEmpty
        } catch {
            logger.warning("Failed to check for Walkies: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetch all recent Walkies (for notification badge, etc.)
    func fetchRecentWalkies(limit: Int = 10) async throws -> [Walkie] {
        logger.info("Fetching recent Walkies")

        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: "expiresAt > %@", Date() as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await database.records(matching: query, resultsLimit: limit)

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

        logger.info("Found \(walkies.count) recent Walkie(s)")
        return walkies
    }

    // MARK: - Download & Play Audio

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
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Walkies", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("\(walkie.id).caf")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.copyItem(at: assetURL, to: localURL)

        walkieCache[walkie.id] = localURL
        logger.info("Downloaded Walkie audio to: \(localURL.lastPathComponent)")

        return localURL
    }

    /// Play a Walkie's audio
    func play(_ walkie: Walkie) async {
        do {
            let audioURL = try await downloadAudio(for: walkie)

            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            currentWalkie = walkie
            isPlaying = true

            logger.info("Playing Walkie: \(walkie.id)")

            // Monitor playback completion
            Task {
                while audioPlayer?.isPlaying == true {
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                }
                await MainActor.run {
                    self.isPlaying = false
                    self.currentWalkie = nil
                }
            }
        } catch {
            logger.error("Failed to play Walkie: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Stop current playback
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentWalkie = nil
    }

    /// Pause current playback
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    /// Resume paused playback
    func resume() {
        audioPlayer?.play()
        isPlaying = true
    }

    // MARK: - Cache Management

    /// Clean local cache
    func cleanLocalCache() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Walkies", isDirectory: true)

        try? FileManager.default.removeItem(at: cacheDir)
        walkieCache.removeAll()
        logger.info("Local Walkie cache cleared")
    }

    // MARK: - Upload User Reply

    /// Upload a user's voice reply to the conversation
    /// - Parameters:
    ///   - audioURL: Local URL of the recorded audio
    ///   - memoId: Root VoiceMemo ID (thread anchor)
    ///   - parentWalkieId: The Walkie being replied to
    ///   - transcript: Transcription of user's reply
    /// - Returns: The created Walkie ID
    @discardableResult
    func uploadReply(
        audioURL: URL,
        memoId: String,
        parentWalkieId: String?,
        transcript: String
    ) async throws -> String {
        logger.info("Uploading user reply to thread: \(memoId)")

        isLoading = true
        defer { isLoading = false }

        let database = container.privateCloudDatabase

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: "walkie-\(UUID().uuidString)")
        let record = CKRecord(recordType: recordType, recordID: recordID)

        // Set fields
        record["memoId"] = memoId
        record["parentWalkieId"] = parentWalkieId
        record["sender"] = WalkieSender.user.rawValue
        record["transcript"] = transcript
        record["createdAt"] = Date()
        record["expiresAt"] = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

        // Attach audio as CKAsset
        let asset = CKAsset(fileURL: audioURL)
        record["audioAsset"] = asset

        // Save to CloudKit
        let savedRecord = try await database.save(record)
        let walkieId = savedRecord.recordID.recordName

        logger.info("User reply uploaded: \(walkieId)")
        return walkieId
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
    case downloadFailed(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioData:
            return "No audio data available"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        }
    }
}
