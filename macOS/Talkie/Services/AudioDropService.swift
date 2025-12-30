//
//  AudioDropService.swift
//  Talkie
//
//  App-wide audio file drop handling - creates VoiceMemos from dropped audio files
//

import Foundation
import UniformTypeIdentifiers
import AVFoundation
import TalkieKit

private let log = Log(.system)

// MARK: - Audio Drop Service

/// Handles dropped audio files and creates VoiceMemos
/// Use from any view via: AudioDropService.shared.processDroppedAudio(providers:onProgress:)
actor AudioDropService {
    static let shared = AudioDropService()

    /// Supported audio file extensions
    static let supportedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "flac", "ogg", "mp4", "caf"
    ]

    /// UTTypes we accept for drop
    static let supportedUTTypes: [UTType] = [
        .audio,
        .mpeg4Audio,
        .mp3,
        .wav,
        .aiff,
        .fileURL
    ]

    private init() {}

    // MARK: - Public Interface

    /// Process dropped audio files and create a VoiceMemo
    /// - Parameters:
    ///   - providers: NSItemProviders from the drop operation
    ///   - onProgress: Optional callback for UI updates (called on MainActor)
    /// - Returns: The created MemoModel
    /// - Throws: DropError if processing fails
    func processDroppedAudio(
        providers: [NSItemProvider],
        onProgress: (@MainActor (DropProgress) -> Void)? = nil
    ) async throws -> MemoModel {
        guard let provider = providers.first else {
            throw DropError.noValidProvider
        }

        // Update progress
        await onProgress?(.validating)
        log.info("Processing dropped audio file...")

        // Extract file from provider
        let (tempURL, originalFilename) = try await extractFile(from: provider)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Validate extension
        let ext = tempURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw DropError.unsupportedFormat(ext)
        }

        // Copy to permanent storage
        await onProgress?(.copying)
        guard let storedFilename = AudioStorage.copyToStorage(tempURL) else {
            throw DropError.copyFailed
        }
        let storedURL = AudioStorage.url(for: storedFilename)

        // Extract metadata
        await onProgress?(.extractingMetadata)
        let metadata = await extractMetadata(from: storedURL)

        // Get file size for progress display
        let fileSize = metadata.fileSize
        let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

        // Transcribe
        await onProgress?(.transcribing(filename: originalFilename, size: fileSizeStr))
        log.info("Transcribing dropped file: \(originalFilename) (\(fileSizeStr))")

        let transcription: String
        do {
            transcription = try await EngineClient.shared.transcribe(
                audioPath: storedURL.path,
                modelId: LiveSettings.shared.selectedModelId,
                priority: .userInitiated
            )
        } catch {
            // Delete the stored audio if transcription fails
            AudioStorage.delete(filename: storedFilename)
            throw DropError.transcriptionFailed(error)
        }

        // Create memo
        let memo = MemoModel(
            id: UUID(),
            createdAt: Date(),
            lastModified: Date(),
            title: generateTitle(from: originalFilename, transcription: transcription),
            duration: metadata.duration ?? 0,
            transcription: transcription,
            audioFilePath: storedFilename,
            originDeviceId: "mac-drop"
        )

        // Save to database
        let repository = LocalRepository()
        try await repository.saveMemo(memo)

        await onProgress?(.complete)
        log.info("Created memo from dropped audio: \(memo.id)")

        // Play success sound
        await MainActor.run {
            SoundManager.shared.playPasted()
        }

        return memo
    }

    // MARK: - Private Implementation

    /// Extract file URL from NSItemProvider
    private func extractFile(from provider: NSItemProvider) async throws -> (URL, String) {
        // Try each supported type
        let typeIdentifiers = [
            UTType.audio.identifier,
            UTType.mpeg4Audio.identifier,
            UTType.mp3.identifier,
            UTType.wav.identifier,
            "public.aac-audio",
            "org.xiph.flac",
            UTType.fileURL.identifier
        ]

        for typeId in typeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(typeId) {
                return try await withCheckedThrowingContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, error in
                        if let error = error {
                            continuation.resume(throwing: DropError.providerError(error))
                            return
                        }

                        guard let url = url else {
                            continuation.resume(throwing: DropError.noValidProvider)
                            return
                        }

                        // Copy to temp location (provider's file may be deleted after callback)
                        let tempDir = FileManager.default.temporaryDirectory
                        let tempURL = tempDir.appendingPathComponent(
                            UUID().uuidString + "." + url.pathExtension
                        )

                        do {
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            continuation.resume(returning: (tempURL, url.lastPathComponent))
                        } catch {
                            continuation.resume(throwing: DropError.copyFailed)
                        }
                    }
                }
            }
        }

        throw DropError.noValidProvider
    }

    /// Extract audio metadata using AVFoundation
    private func extractMetadata(from url: URL) async -> AudioMetadata {
        var metadata = AudioMetadata()

        // File attributes
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            metadata.fileSize = (attrs[.size] as? Int64) ?? 0
            metadata.createdAt = attrs[.creationDate] as? Date
            metadata.modifiedAt = attrs[.modificationDate] as? Date
        }

        metadata.fileExtension = url.pathExtension.lowercased()
        metadata.sourceFilename = url.lastPathComponent

        // AVAsset metadata
        let asset = AVURLAsset(url: url)

        // Load duration
        do {
            let duration = try await asset.load(.duration)
            if duration.isValid && !duration.isIndefinite {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    metadata.duration = seconds
                }
            }
        } catch {
            log.debug("Failed to load duration: \(error.localizedDescription)")
        }

        // Load audio track info
        do {
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                let formatDescriptions = try await track.load(.formatDescriptions)
                if let desc = formatDescriptions.first,
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    metadata.sampleRate = Int(asbd.pointee.mSampleRate)
                    metadata.channels = Int(asbd.pointee.mChannelsPerFrame)
                }
                metadata.bitrate = Int(try await track.load(.estimatedDataRate))
            }
        } catch {
            log.debug("Failed to load track info: \(error.localizedDescription)")
        }

        return metadata
    }

    /// Generate a title from filename or first words of transcription
    private func generateTitle(from filename: String, transcription: String) -> String {
        // Remove extension from filename
        let baseName = (filename as NSString).deletingPathExtension

        // If filename looks like a UUID or timestamp, use transcription instead
        let looksGenerated = baseName.count > 30 ||
            baseName.contains("-") && baseName.filter({ $0 == "-" }).count >= 4

        if looksGenerated && !transcription.isEmpty {
            // Use first ~50 chars of transcription
            let prefix = String(transcription.prefix(50))
            if let lastSpace = prefix.lastIndex(of: " "), prefix.count >= 50 {
                return String(prefix[..<lastSpace]) + "..."
            }
            return prefix
        }

        return baseName
    }
}

// MARK: - Types

extension AudioDropService {
    /// Progress states for UI feedback
    enum DropProgress: Equatable {
        case validating
        case copying
        case extractingMetadata
        case transcribing(filename: String, size: String)
        case complete
    }

    /// Errors during drop processing
    enum DropError: LocalizedError {
        case noValidProvider
        case unsupportedFormat(String)
        case copyFailed
        case transcriptionFailed(Error)
        case providerError(Error)

        var errorDescription: String? {
            switch self {
            case .noValidProvider:
                return "No valid audio file found"
            case .unsupportedFormat(let ext):
                return "Unsupported format: .\(ext)"
            case .copyFailed:
                return "Failed to copy audio file"
            case .transcriptionFailed(let error):
                return "Transcription failed: \(error.localizedDescription)"
            case .providerError(let error):
                return "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    /// Structured audio metadata
    struct AudioMetadata {
        var duration: TimeInterval?
        var sampleRate: Int?
        var channels: Int?
        var bitrate: Int?
        var fileSize: Int64 = 0
        var sourceFilename: String = ""
        var fileExtension: String = ""
        var createdAt: Date?
        var modifiedAt: Date?
    }
}
