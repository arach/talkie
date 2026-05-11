//
//  IngestWatcher.swift
//  Talkie
//
//  Watches the Bridge/Ingested directory for content sent from iOS.
//  When a manifest JSON appears, imports it as a TalkieObject in GRDB
//  and optionally triggers TTS readout.
//

import Foundation
import ImageIO
import TalkieKit
import UniformTypeIdentifiers

private let log = Log(.sync)

@MainActor
final class IngestWatcher {
    static let shared = IngestWatcher()

    private static let ingestDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Talkie/Bridge/Ingested")
    }()

    private var watchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var processedIDs: Set<String> = []

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let dir = Self.ingestDir
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            log.warning("IngestWatcher: couldn't open \(dir.path) for watching")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                // Brief debounce — file may still be mid-write when the event fires
                try? await Task.sleep(for: .milliseconds(200))
                await self?.scanForNewManifests()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchSource = source

        log.info("IngestWatcher: watching \(dir.path)")

        // Process anything already there
        Task {
            await scanForNewManifests()
        }
    }

    func stop() {
        watchSource?.cancel()
        watchSource = nil
        fileDescriptor = -1
    }

    // MARK: - Scanning

    private func scanForNewManifests() async {
        let dir = Self.ingestDir

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let manifests = files.filter { $0.pathExtension == "json" }

        for manifest in manifests {
            let id = manifest.deletingPathExtension().lastPathComponent
            guard !processedIDs.contains(id) else { continue }

            await processManifest(at: manifest, id: id)
        }
    }

    // MARK: - Processing

    private func processManifest(at url: URL, id: String) async {
        do {
            let data = try Data(contentsOf: url)
            let manifest: IngestManifest
            do {
                manifest = try JSONDecoder().decode(IngestManifest.self, from: data)
            } catch {
                log.error("IngestWatcher: JSON decode failed for \(id): \(error)")
                return
            }

            let objectId = UUID(uuidString: manifest.id) ?? UUID()

            // Save image to ScreenshotStorage before cleanup
            var assets = TalkieObjectAssets()
            if let imageFilename = manifest.imageFilename {
                let imageURL = Self.ingestDir.appendingPathComponent(imageFilename)
                if let imageData = try? Data(contentsOf: imageURL) {
                    let normalizedData = normalizedScreenshotData(from: imageData) ?? imageData
                    if let savedURL = ScreenshotStorage.save(
                        normalizedData,
                        recordingId: objectId,
                        timestampMs: 0,
                        captureMode: "capture",
                        windowTitle: manifest.title
                    ) {
                        let screenshot = RecordingScreenshot(
                            filename: savedURL.lastPathComponent,
                            timestampMs: 0,
                            captureMode: "capture"
                        )
                        assets.screenshots = [screenshot]
                        log.info("IngestWatcher: saved image → \(savedURL.lastPathComponent)")
                    } else {
                        log.warning("IngestWatcher: ScreenshotStorage.save failed for \(imageFilename)")
                    }
                } else {
                    log.warning("IngestWatcher: image file not found: \(imageFilename)")
                }
            }

            // Generate a title if one wasn't provided or is generic
            let title: String? = if let t = manifest.title, !t.isEmpty, t.lowercased() != "screenshot" {
                t
            } else {
                await generateTitle(from: manifest.text)
            }

            // Create TalkieObject
            let object = TalkieObject(
                id: objectId,
                type: .selection,
                text: manifest.text,
                title: title,
                duration: 0,
                createdAt: ISO8601DateFormatter().date(from: manifest.createdAt) ?? Date(),
                source: .iphone,
                sourceDeviceId: manifest.sourceDeviceId,
                transcriptionStatus: .success,
                assetsJSON: assets.isEmpty ? nil : assets.toJSON(),
                metadataJSON: encodeMetadata(manifest)
            )

            // Save to GRDB
            let repo = TalkieObjectRepository()
            try await repo.saveRecording(object)

            log.info("IngestWatcher: imported \(manifest.sourceType) → \(id) (\(manifest.text.count) chars, title: \(title ?? "nil"))")

            // Cleanup manifest + original image from ingest dir
            processedIDs.insert(id)
            try? FileManager.default.removeItem(at: url)
            if let imageFilename = manifest.imageFilename {
                let imageURL = Self.ingestDir.appendingPathComponent(imageFilename)
                try? FileManager.default.removeItem(at: imageURL)
            }
        } catch {
            log.error("IngestWatcher: failed to process \(id): \(error)")
        }
    }

    // MARK: - Helpers

    /// Generate a concise title from OCR text using Apple Intelligence (on-device).
    /// Falls back to extracting the first meaningful line if Apple Intelligence is unavailable.
    private func generateTitle(from text: String) async -> String? {
        let trimmed = String(text.prefix(1500))
        guard !trimmed.isEmpty else { return nil }

        // Try Apple Intelligence first
        let provider = AppleLocalProvider()
        if await provider.isAvailable {
            do {
                let result = try await provider.generate(
                    prompt: trimmed,
                    model: "apple-on-device",
                    options: GenerationOptions(
                        temperature: 0.3,
                        maxTokens: 30,
                        systemPrompt: "Generate a short title (3-8 words) for this captured text. Return ONLY the title, no quotes, no explanation."
                    )
                )
                let title = result.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
                if !title.isEmpty && title.count < 80 {
                    log.info("IngestWatcher: Apple Intelligence title: \(title)")
                    return title
                }
            } catch {
                log.debug("IngestWatcher: Apple Intelligence title gen failed: \(error.localizedDescription)")
            }
        }

        // Fallback: first non-empty line, trimmed
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces)

        if let line = firstLine, line.count <= 60 {
            return line
        } else if let line = firstLine {
            return String(line.prefix(57)) + "…"
        }

        return nil
    }

    private func encodeMetadata(_ manifest: IngestManifest) -> String? {
        var meta: [String: String] = [:]
        meta["ingestSourceType"] = manifest.sourceType
        if let sourceURL = manifest.sourceURL {
            meta["sourceURL"] = sourceURL
        }
        if let imageFilename = manifest.imageFilename {
            meta["imageFilename"] = imageFilename
        }
        guard let data = try? JSONEncoder().encode(meta) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func normalizedScreenshotData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source) else {
            return nil
        }

        if UTType(sourceType as String)?.conforms(to: .png) == true {
            return data
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        log.info("IngestWatcher: normalized incoming image to PNG before screenshot save")
        return mutableData as Data
    }
}

// MARK: - Manifest Model

private struct IngestManifest: Codable {
    let id: String
    let type: String
    let sourceType: String
    let text: String
    let title: String?
    let sourceURL: String?
    let imageFilename: String?
    let source: String
    let sourceDeviceId: String?
    let createdAt: String
}
