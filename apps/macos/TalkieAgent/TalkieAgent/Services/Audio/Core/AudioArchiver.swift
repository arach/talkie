//
//  AudioArchiver.swift
//  TalkieAgent
//
//  Background compression of PCM recordings to AAC for archival.
//  Runs after transcription completes - doesn't block the user.
//

import AVFoundation
import TalkieKit

private let log = Log(.audio)

/// Compresses PCM recordings to AAC in the background
final class AudioArchiver {

    /// Compression result
    enum CompressionResult {
        case success(aacURL: URL, originalSize: Int, compressedSize: Int)
        case failed(reason: String)
        case skipped(reason: String)
    }

    // MARK: - Public API

    /// Compress a PCM file to AAC in the background
    /// - Parameters:
    ///   - pcmPath: Path to the PCM recording
    ///   - deleteOriginal: Whether to delete the PCM file after successful compression
    ///   - completion: Called when compression completes (on background thread)
    func archiveToAAC(
        pcmPath: URL,
        deleteOriginal: Bool = true,
        completion: @escaping (CompressionResult) -> Void
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else {
                completion(.skipped(reason: "Archiver deallocated"))
                return
            }

            let result = await self.compress(pcmPath: pcmPath, deleteOriginal: deleteOriginal)
            completion(result)
        }
    }

    /// Synchronous compression for testing
    func compressSync(pcmPath: URL, deleteOriginal: Bool = false) async -> CompressionResult {
        return await compress(pcmPath: pcmPath, deleteOriginal: deleteOriginal)
    }

    // MARK: - Private Implementation

    private func compress(pcmPath: URL, deleteOriginal: Bool) async -> CompressionResult {
        // Small delay to ensure file is fully flushed to disk after AVAudioFile deinit
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Validate source exists
        guard FileManager.default.fileExists(atPath: pcmPath.path) else {
            return .failed(reason: "Source file not found: \(pcmPath.lastPathComponent)")
        }

        // Get original size
        let originalSize: Int
        if let attrs = try? FileManager.default.attributesOfItem(atPath: pcmPath.path),
           let size = attrs[.size] as? Int {
            originalSize = size
        } else {
            originalSize = 0
        }

        // Skip tiny files
        guard originalSize > 1000 else {
            return .skipped(reason: "File too small to compress (\(originalSize) bytes)")
        }

        // Validate PCM file is readable and has valid audio tracks
        let asset = AVURLAsset(url: pcmPath)
        let tracks = asset.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            return .failed(reason: "Invalid audio file - no audio tracks found")
        }

        // Create output path
        let aacPath = pcmPath
            .deletingPathExtension()
            .appendingPathExtension("m4a")

        // Remove existing output if present
        try? FileManager.default.removeItem(at: aacPath)

        // Use AVAssetExportSession for hardware-accelerated AAC encoding
        // (asset already validated above for audio tracks)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            return .failed(reason: "Failed to create export session")
        }

        exportSession.outputURL = aacPath
        exportSession.outputFileType = .m4a

        // Run export
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            // Get compressed size
            let compressedSize: Int
            if let attrs = try? FileManager.default.attributesOfItem(atPath: aacPath.path),
               let size = attrs[.size] as? Int {
                compressedSize = size
            } else {
                compressedSize = 0
            }

            let ratio = originalSize > 0 ? Double(compressedSize) / Double(originalSize) : 0
            log.info("Compressed to AAC",
                     detail: "\(originalSize) -> \(compressedSize) bytes (\(Int(ratio * 100))%)")

            // Delete original PCM if requested
            // Use retry with delay - AVAssetExportSession may hold file handles briefly after completion
            if deleteOriginal {
                await deleteWithRetry(pcmPath)
            }

            return .success(
                aacURL: aacPath,
                originalSize: originalSize,
                compressedSize: compressedSize
            )

        case .failed:
            let error = exportSession.error?.localizedDescription ?? "Unknown error"
            log.error("AAC compression failed", detail: error)
            return .failed(reason: error)

        case .cancelled:
            return .failed(reason: "Compression cancelled")

        default:
            return .failed(reason: "Unexpected export status: \(exportSession.status.rawValue)")
        }
    }

    /// Delete file with retry - handles cases where AVAssetExportSession holds file handles briefly
    private func deleteWithRetry(_ url: URL, maxAttempts: Int = 3) async {
        for attempt in 1...maxAttempts {
            do {
                try FileManager.default.removeItem(at: url)
                log.debug("Deleted original PCM", detail: url.lastPathComponent)
                return
            } catch {
                if attempt < maxAttempts {
                    // Wait before retry - file handles may still be releasing
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                } else {
                    log.warning("Failed to delete original PCM after \(maxAttempts) attempts",
                                detail: url.lastPathComponent, error: error)
                }
            }
        }
    }
}
