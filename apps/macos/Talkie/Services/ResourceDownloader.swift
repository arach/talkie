//
//  ResourceDownloader.swift
//  Talkie
//
//  Downloads optional resources (fonts, presets, workflows) on first install
//  Resources are hosted separately to keep the app bundle small
//

import Foundation
import TalkieKit

/// Downloads and installs optional resources on first launch
@MainActor
public class ResourceDownloader: ObservableObject {
    public static let shared = ResourceDownloader()

    private let log = Log(.system)

    // Resource bundle URL - update this when hosting is set up
    // For now, using GitHub releases as the host
    private let resourcesURL = URL(string: "https://github.com/ArachTch/talkie/releases/download/resources/talkie-resources.zip")!

    @Published public var isDownloading = false
    @Published public var progress: Double = 0
    @Published public var error: Error?
    @Published public var isComplete = false

    private var downloadTask: URLSessionDownloadTask?

    /// Check if resources need to be downloaded
    public var needsResourceDownload: Bool {
        let resourcesPath = resourcesDirectory
        // Check if key directories exist
        let fontsExist = FileManager.default.fileExists(atPath: resourcesPath.appendingPathComponent("Fonts").path)
        let presetsExist = FileManager.default.fileExists(atPath: resourcesPath.appendingPathComponent("Presets").path)
        return !fontsExist || !presetsExist
    }

    /// Directory where resources are stored
    private var resourcesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Talkie/Resources")
    }

    /// Download and install resources
    public func downloadResources() async throws {
        guard !isDownloading else { return }

        log.info("Starting resource download from \(resourcesURL)")

        await MainActor.run {
            isDownloading = true
            progress = 0
            error = nil
        }

        do {
            // Download the zip file
            let (tempURL, _) = try await downloadWithProgress(from: resourcesURL)

            await MainActor.run {
                progress = 0.8
            }

            // Extract to resources directory
            try await extractResources(from: tempURL)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            await MainActor.run {
                progress = 1.0
                isComplete = true
                isDownloading = false
            }

            log.info("Resources downloaded and installed successfully")

        } catch {
            log.error("Resource download failed: \(error)")
            await MainActor.run {
                self.error = error
                isDownloading = false
            }
            throw error
        }
    }

    /// Download with progress tracking
    private func downloadWithProgress(from url: URL) async throws -> (URL, URLResponse) {
        let session = URLSession.shared

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let tempURL = tempURL, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                // Move to a persistent temp location
                let persistentTemp = FileManager.default.temporaryDirectory.appendingPathComponent("talkie-resources.zip")
                try? FileManager.default.removeItem(at: persistentTemp)

                do {
                    try FileManager.default.moveItem(at: tempURL, to: persistentTemp)
                    continuation.resume(returning: (persistentTemp, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Track progress
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    self?.progress = progress.fractionCompleted * 0.8 // Reserve 20% for extraction
                }
            }

            // Store observation to keep it alive
            objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

            self.downloadTask = task
            task.resume()
        }
    }

    /// Extract downloaded resources
    private func extractResources(from zipURL: URL) async throws {
        let destination = resourcesDirectory

        // Create destination directory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        // Use unzip command (built into macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(domain: "ResourceDownloader", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to extract resources"])
        }

        log.info("Resources extracted to \(destination.path)")
    }

    /// Cancel ongoing download
    public func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }
}
