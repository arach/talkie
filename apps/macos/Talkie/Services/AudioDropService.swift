//
//  AudioDropService.swift
//  Talkie
//
//  App-wide drop handling. Audio drops become transcribed memos; URLs, text,
//  images, video, code, PDFs, and other safe file drops become Talkie captures.
//

import AppKit
import AVFoundation
import Foundation
import ImageIO
import TalkieKit
import UniformTypeIdentifiers

private let log = Log(.system)
private let databaseLog = Log(.database)

// MARK: - Audio Drop Service

/// Handles app-wide drops and creates Talkie content from them.
actor AudioDropService {
    static let shared = AudioDropService()

    private let memoRepository = LocalRepository()
    private let recordingRepository = TalkieObjectRepository()

    /// Audio file extensions that should take the transcription path when dropped alone.
    static let supportedAudioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "flac", "ogg", "caf", "aiff", "aif", "mp4"
    ]

    /// Backward-compatible alias used by older drop call sites.
    static let supportedExtensions = supportedAudioExtensions

    private static let textLikeExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "rtf", "json", "jsonl", "yaml", "yml", "toml", "xml",
        "html", "htm", "css", "csv", "tsv", "log", "swift", "js", "jsx", "ts", "tsx", "py",
        "rb", "go", "rs", "java", "kt", "kts", "c", "cc", "cpp", "cxx", "h", "hpp", "m",
        "mm", "sh", "zsh", "bash", "fish", "sql", "graphql", "proto", "plist", "env"
    ]

    private static let maxImportFileSize: Int64 = 750_000_000
    private static let maxTextPreviewBytes = 512_000

    /// UTTypes we accept for app-wide drop.
    static let supportedUTTypes: [UTType] = [
        .fileURL,
        .url,
        .text,
        .plainText,
        .utf8PlainText,
        .image,
        .pdf,
        .movie,
        .audiovisualContent,
        .audio,
        .data,
    ]

    private init() {}

    // MARK: - Public Interface

    static func shouldAcceptDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        guard !TalkieInternalDrag.isInternal(providers) else { return false }

        return providers.contains { provider in
            supportedUTTypes.contains { type in
                provider.hasItemConformingToTypeIdentifier(type.identifier)
            }
        }
    }

    /// Process any supported app-wide drop.
    func processDroppedItems(
        providers: [NSItemProvider],
        onProgress: (@MainActor (DropProgress) -> Void)? = nil
    ) async throws -> IngestResult {
        guard !providers.isEmpty else {
            throw DropError.noValidProvider
        }

        guard !TalkieInternalDrag.isInternal(providers) else {
            log.debug("Ignoring internal Talkie drag dropped back into Talkie")
            return .noop
        }

        await onProgress?(.validating)
        try Task.checkCancellation()

        let representedFiles = await extractFileRepresentations(from: providers)
        if !representedFiles.isEmpty {
            defer { cleanupTemporaryFiles(representedFiles) }
            return try await processDroppedFiles(representedFiles, onProgress: onProgress)
        }

        if let url = await extractURL(from: providers) {
            return .recording(try await importURL(url, onProgress: onProgress))
        }

        if let text = await extractText(from: providers) {
            if let url = URL(string: text.trimmedForImport), url.scheme != nil {
                return .recording(try await importURL(url, onProgress: onProgress))
            }
            return .recording(try await importText(text, title: "Dropped Text", onProgress: onProgress))
        }

        if let dataFile = await extractDataRepresentation(from: providers) {
            defer { cleanupTemporaryFiles([dataFile]) }
            return try await processDroppedFiles([dataFile], onProgress: onProgress)
        }

        throw DropError.noValidProvider
    }

    /// Process dropped audio files and create a VoiceMemo.
    func processDroppedAudio(
        providers: [NSItemProvider],
        onProgress: (@MainActor (DropProgress) -> Void)? = nil
    ) async throws -> MemoModel {
        let result = try await processDroppedItems(providers: providers, onProgress: onProgress)
        switch result {
        case .memo(let memo):
            return memo
        case .recording, .noop:
            throw DropError.noValidProvider
        }
    }

    // MARK: - Import Routing

    private func processDroppedFiles(
        _ files: [DroppedFile],
        onProgress: (@MainActor (DropProgress) -> Void)?
    ) async throws -> IngestResult {
        guard !files.isEmpty else { throw DropError.noValidProvider }

        if files.count == 1, let file = files.first, Self.shouldTranscribe(file.url) {
            return .memo(try await importAudioFile(file, onProgress: onProgress))
        }

        let objectID = try await importFilesAsCapture(files, onProgress: onProgress)
        return .recording(objectID)
    }

    private func importURL(
        _ url: URL,
        onProgress: (@MainActor (DropProgress) -> Void)?
    ) async throws -> UUID {
        try Task.checkCancellation()

        if url.isFileURL {
            let file = DroppedFile(
                url: url,
                originalFilename: url.lastPathComponent,
                typeIdentifier: UTType.fileURL.identifier,
                isTemporary: false
            )
            return try await importFilesAsCapture([file], onProgress: onProgress)
        }

        await onProgress?(.importingURL(url.absoluteString))

        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            do {
                let objectID = try await URLBookmarkImportService.shared.importBookmark(
                    from: url,
                    sourceApplicationName: nil,
                    ingestionMethod: "drop"
                )
                await MainActor.run {
                    SoundManager.shared.playPasted()
                }
                await onProgress?(.complete)
                return objectID
            } catch {
                log.debug("Bookmark import fell back to URL note: \(error.localizedDescription)")
            }
        }

        return try await importText(
            "URL: \(url.absoluteString)",
            title: title(for: url),
            metadata: [
                "ingestSourceType": "url",
                "sourceURL": url.absoluteString,
                "ingestMethod": "drop",
            ],
            onProgress: onProgress
        )
    }

    private func importText(
        _ text: String,
        title: String,
        metadata: [String: String] = [
            "ingestSourceType": "text",
            "ingestMethod": "drop",
        ],
        onProgress: (@MainActor (DropProgress) -> Void)?
    ) async throws -> UUID {
        await onProgress?(.importingText)
        try Task.checkCancellation()

        let objectID = UUID()
        var object = TalkieObject.newNote(id: objectID, text: text.trimmedForImport, title: title)
        object.metadataJSON = metadataJSON(metadata)

        try await recordingRepository.saveRecording(object)
        await RecordingsViewModel.shared.loadRecordings()

        await MainActor.run {
            SoundManager.shared.playPasted()
        }
        await onProgress?(.complete)
        log.info("Created note from dropped text: \(objectID)")
        return objectID
    }

    private func importFilesAsCapture(
        _ files: [DroppedFile],
        onProgress: (@MainActor (DropProgress) -> Void)?
    ) async throws -> UUID {
        guard !files.isEmpty else { throw DropError.noValidProvider }

        let objectID = UUID()
        var attachments: [RecordingAttachment] = []
        var textSections: [String] = []

        for file in files {
            try Task.checkCancellation()
            try validateSafeFile(file.url, originalFilename: file.originalFilename)

            let ext = file.url.pathExtension.lowercased()
            let kind = AttachmentKind.from(extension: ext)
            await onProgress?(.saving(filename: file.originalFilename, kind: kind.displayName))

            guard let saved = AttachmentStorage.save(from: file.url, recordingId: objectID) else {
                throw DropError.copyFailed
            }

            let dimensions = kind == .image ? imageDimensions(for: file.url) : nil
            let attachment = RecordingAttachment(
                filename: saved.filename,
                originalName: file.originalFilename,
                kind: kind,
                fileSizeBytes: saved.size,
                width: dimensions?.width,
                height: dimensions?.height
            )
            attachments.append(attachment)

            if let preview = textPreview(for: file.url) {
                textSections.append(Self.previewSection(filename: file.originalFilename, extension: ext, text: preview))
            }
        }

        let title = files.count == 1
            ? fileTitle(from: files[0].originalFilename)
            : "\(files.count) Imported Files"

        let text = importTextSummary(files: files, previews: textSections)
        let hasVisualAsset = attachments.contains { $0.kind == .image || $0.kind == .video }
        var object = hasVisualAsset
            ? TalkieObject.newCapture(id: objectID, text: text, title: title)
            : TalkieObject.newNote(id: objectID, text: text, title: title)

        object.assetsJSON = TalkieObjectAssets(attachments: attachments).toJSON()
        object.metadataJSON = metadataJSON([
            "ingestSourceType": "file",
            "ingestMethod": "drop",
            "fileCount": "\(files.count)",
        ])

        try await recordingRepository.saveRecording(object)
        await RecordingsViewModel.shared.loadRecordings()

        await MainActor.run {
            SoundManager.shared.playPasted()
        }
        await onProgress?(.complete)
        log.info("Created recording from dropped file(s): \(objectID) count=\(files.count)")
        return objectID
    }

    private func importAudioFile(
        _ file: DroppedFile,
        onProgress: (@MainActor (DropProgress) -> Void)?
    ) async throws -> MemoModel {
        try Task.checkCancellation()
        await onProgress?(.copying)

        let storedFilename = try copyAudioToStorage(file.url)
        let storedURL = AudioStorage.url(for: storedFilename)

        do {
            try Task.checkCancellation()
            await onProgress?(.extractingMetadata)
            let metadata = await extractMetadata(from: storedURL)

            let fileSize = metadata.fileSize
            let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

            try Task.checkCancellation()
            await onProgress?(.transcribing(filename: file.originalFilename, size: fileSizeStr))
            log.info("Transcribing dropped file: \(file.originalFilename) (\(fileSizeStr))")

            let transcription = try await EngineClient.shared.transcribe(
                audioPath: storedURL.path,
                modelId: AgentSettings.shared.selectedModelId,
                priority: .userInitiated,
                postProcess: .inverseTextNormalization
            )

            try Task.checkCancellation()
            let memo = MemoModel(
                id: UUID(),
                createdAt: Date(),
                lastModified: Date(),
                title: generateTitle(from: file.originalFilename, transcription: transcription),
                duration: metadata.duration ?? 0,
                transcription: transcription,
                audioFilePath: storedFilename,
                originDeviceId: "mac-drop"
            )

            try await memoRepository.saveMemo(memo)
            try await recordingRepository.saveRecording(TalkieObject(from: memo))

            await MemosViewModel.shared.loadMemos()
            await RecordingsViewModel.shared.loadRecordings()

            await onProgress?(.complete)
            log.info("Created memo from dropped audio: \(memo.id)")
            databaseLog.info("Created unified recording for dropped audio: \(memo.id)")

            await MainActor.run {
                SoundManager.shared.playPasted()
            }

            return memo
        } catch is CancellationError {
            AudioStorage.delete(filename: storedFilename)
            throw CancellationError()
        } catch {
            AudioStorage.delete(filename: storedFilename)
            throw DropError.transcriptionFailed(error)
        }
    }

    // MARK: - Provider Extraction

    private func extractFileRepresentations(from providers: [NSItemProvider]) async -> [DroppedFile] {
        var files: [DroppedFile] = []

        for provider in providers {
            try? Task.checkCancellation()
            if let file = await extractFileRepresentation(from: provider) {
                files.append(file)
            }
        }

        return files
    }

    private func extractFileRepresentation(from provider: NSItemProvider) async -> DroppedFile? {
        let typeIdentifiers = prioritizedFileTypeIdentifiers(for: provider)

        for typeID in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeID) {
            do {
                return try await copyFileRepresentation(from: provider, typeIdentifier: typeID)
            } catch is CancellationError {
                return nil
            } catch {
                log.debug("Failed to load file representation \(typeID): \(error.localizedDescription)")
            }
        }

        return nil
    }

    private func extractDataRepresentation(from providers: [NSItemProvider]) async -> DroppedFile? {
        for provider in providers {
            let typeIdentifiers = prioritizedDataTypeIdentifiers(for: provider)
            for typeID in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeID) {
                do {
                    return try await copyDataRepresentation(from: provider, typeIdentifier: typeID)
                } catch {
                    log.debug("Failed to load data representation \(typeID): \(error.localizedDescription)")
                }
            }
        }
        return nil
    }

    private func extractURL(from providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            guard let item = try? await loadItem(from: provider, typeIdentifier: UTType.url.identifier),
                  let url = decodeURL(from: item) else {
                continue
            }
            return url
        }
        return nil
    }

    private func extractText(from providers: [NSItemProvider]) async -> String? {
        let typeIdentifiers = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            UTType.text.identifier,
        ]

        for provider in providers {
            for typeID in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeID) {
                guard let item = try? await loadItem(from: provider, typeIdentifier: typeID),
                      let text = decodeText(from: item)?.trimmedNonEmpty else {
                    continue
                }
                return text
            }
        }

        return nil
    }

    private func copyFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> DroppedFile {
        let providerSuggestedName = provider.suggestedName?.trimmedNonEmpty
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DroppedFile, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: DropError.providerError(error))
                    return
                }

                guard let url else {
                    continuation.resume(throwing: DropError.noValidProvider)
                    return
                }

                do {
                    let originalFilename = providerSuggestedName ?? url.lastPathComponent
                    let copied = try Self.copyToTemporaryFile(from: url, suggestedName: originalFilename)
                    continuation.resume(returning: DroppedFile(
                        url: copied,
                        originalFilename: Self.originalFilename(suggestedName: originalFilename, sourceURL: url),
                        typeIdentifier: typeIdentifier,
                        isTemporary: true
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> DroppedFile {
        let providerSuggestedName = provider.suggestedName?.trimmedNonEmpty
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DroppedFile, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: DropError.providerError(error))
                    return
                }

                guard let data else {
                    continuation.resume(throwing: DropError.noValidProvider)
                    return
                }

                do {
                    let type = UTType(typeIdentifier)
                    let ext = type?.preferredFilenameExtension ?? "bin"
                    let suggestedName = providerSuggestedName ?? "Dropped Data.\(ext)"
                    guard Int64(data.count) <= Self.maxImportFileSize else {
                        throw DropError.fileTooLarge(suggestedName, Int64(data.count), Self.maxImportFileSize)
                    }

                    let tempURL = FileManager.default.temporaryDirectory
                        .appending(path: UUID().uuidString)
                        .appendingPathExtension(Self.extensionForTemporaryFile(suggestedName: suggestedName, fallback: ext))
                    try data.write(to: tempURL, options: .atomic)

                    continuation.resume(returning: DroppedFile(
                        url: tempURL,
                        originalFilename: Self.originalFilename(suggestedName: suggestedName, sourceURL: tempURL),
                        typeIdentifier: typeIdentifier,
                        isTemporary: true
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: DropError.providerError(error))
                    return
                }

                guard let item else {
                    continuation.resume(throwing: DropError.noValidProvider)
                    return
                }

                continuation.resume(returning: item)
            }
        }
    }

    private static func copyToTemporaryFile(from sourceURL: URL, suggestedName: String) throws -> URL {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .totalFileSizeKey])
        if values.isDirectory == true || values.isPackage == true {
            throw DropError.unsupportedItem("Folders and packages are not imported from drops yet.")
        }

        let size = Int64(values.totalFileSize ?? values.fileSize ?? 0)
        if size > maxImportFileSize {
            throw DropError.fileTooLarge(sourceURL.lastPathComponent, size, maxImportFileSize)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(extensionForTemporaryFile(suggestedName: suggestedName, sourceURL: sourceURL))
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        return tempURL
    }

    // MARK: - Metadata and Formatting

    /// Extract audio metadata using AVFoundation.
    private func extractMetadata(from url: URL) async -> AudioMetadata {
        var metadata = AudioMetadata()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            metadata.fileSize = (attrs[.size] as? Int64) ?? 0
            metadata.createdAt = attrs[.creationDate] as? Date
            metadata.modifiedAt = attrs[.modificationDate] as? Date
        }

        metadata.fileExtension = url.pathExtension.lowercased()
        metadata.sourceFilename = url.lastPathComponent

        let asset = AVURLAsset(url: url)

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

    private func validateSafeFile(_ url: URL, originalFilename: String) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .totalFileSizeKey])
        if values.isDirectory == true || values.isPackage == true {
            throw DropError.unsupportedItem("Folders and packages are not imported from drops yet.")
        }

        let size = Int64(values.totalFileSize ?? values.fileSize ?? 0)
        if size > Self.maxImportFileSize {
            throw DropError.fileTooLarge(originalFilename, size, Self.maxImportFileSize)
        }
    }

    private func copyAudioToStorage(_ sourceURL: URL) throws -> String {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destinationURL = AudioStorage.audioDirectory.appending(path: filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            let size = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            log.info("Copied dropped audio file: \(filename) (\(size) bytes)")
            return filename
        } catch {
            log.error("Failed to copy dropped audio file: \(error.localizedDescription)")
            throw DropError.copyFailed
        }
    }

    private func imageDimensions(for url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        guard let width, let height else { return nil }
        return (width, height)
    }

    private func textPreview(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        let conformsToText = UTType(filenameExtension: ext)?.conforms(to: .text) == true
        guard Self.textLikeExtensions.contains(ext) || conformsToText else {
            return nil
        }

        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size <= Self.maxTextPreviewBytes,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)?.trimmedNonEmpty else {
            return nil
        }

        return text
    }

    private func importTextSummary(files: [DroppedFile], previews: [String]) -> String {
        if files.count == 1 {
            if let preview = previews.first {
                return preview
            }
            return "Imported attachment: \(files[0].originalFilename)"
        }

        var lines = ["Imported files:"]
        lines.append(contentsOf: files.map { "- \($0.originalFilename)" })

        if !previews.isEmpty {
            lines.append("")
            lines.append(contentsOf: previews)
        }

        return lines.joined(separator: "\n")
    }

    private static func previewSection(filename: String, extension ext: String, text: String) -> String {
        guard textLikeExtensions.contains(ext), !ext.isEmpty else {
            return "\(filename)\n\n\(text)"
        }
        return "\(filename)\n\n```\(ext)\n\(text)\n```"
    }

    private static func shouldTranscribe(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedAudioExtensions.contains(ext) else { return false }

        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .movie),
           !type.conforms(to: .audio) {
            return false
        }

        return true
    }

    private func generateTitle(from filename: String, transcription: String) -> String {
        let baseName = (filename as NSString).deletingPathExtension

        let looksGenerated = baseName.count > 30 ||
            baseName.contains("-") && baseName.filter({ $0 == "-" }).count >= 4

        if looksGenerated && !transcription.isEmpty {
            let prefix = String(transcription.prefix(50))
            if let lastSpace = prefix.lastIndex(of: " "), prefix.count >= 50 {
                return String(prefix[..<lastSpace]) + "..."
            }
            return prefix
        }

        return baseName
    }

    private func fileTitle(from filename: String) -> String {
        let title = (filename as NSString).deletingPathExtension.trimmedNonEmpty
        return title ?? filename
    }

    private func title(for url: URL) -> String {
        if let host = url.host?.trimmedNonEmpty {
            return host
        }
        return url.lastPathComponent.trimmedNonEmpty ?? url.absoluteString
    }

    private func metadataJSON(_ dictionary: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(dictionary) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func cleanupTemporaryFiles(_ files: [DroppedFile]) {
        for file in files where file.isTemporary {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private func prioritizedFileTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        uniqueTypeIdentifiers([
            UTType.fileURL.identifier,
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.audiovisualContent.identifier,
            UTType.image.identifier,
            UTType.pdf.identifier,
        ] + provider.registeredTypeIdentifiers)
    }

    private func prioritizedDataTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        uniqueTypeIdentifiers([
            UTType.image.identifier,
            UTType.pdf.identifier,
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.audiovisualContent.identifier,
            UTType.data.identifier,
        ] + provider.registeredTypeIdentifiers)
    }

    private func uniqueTypeIdentifiers(_ identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        return identifiers.filter { seen.insert($0).inserted }
    }

    private func decodeURL(from item: NSSecureCoding) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string.trimmedForImport) }
        if let string = item as? NSString { return URL(string: (string as String).trimmedForImport) }
        return nil
    }

    private func decodeText(from item: NSSecureCoding) -> String? {
        if let text = item as? String { return text }
        if let text = item as? NSString { return text as String }
        if let text = item as? NSAttributedString { return text.string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        if let url = item as? URL { return url.absoluteString }
        if let url = item as? NSURL { return (url as URL).absoluteString }
        return nil
    }

    private static func originalFilename(suggestedName: String, sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension
        let name = suggestedName.trimmedForImport
        guard !name.isEmpty else { return sourceURL.lastPathComponent }
        guard !ext.isEmpty, (name as NSString).pathExtension.isEmpty else { return name }
        return "\(name).\(ext)"
    }

    private static func extensionForTemporaryFile(suggestedName: String, sourceURL: URL? = nil, fallback: String = "bin") -> String {
        let suggestedExt = (suggestedName as NSString).pathExtension
        if !suggestedExt.isEmpty { return suggestedExt }
        if let sourceURL, !sourceURL.pathExtension.isEmpty { return sourceURL.pathExtension }
        return fallback
    }
}

// MARK: - Types

extension AudioDropService {
    enum IngestResult {
        case memo(MemoModel)
        case recording(UUID)
        case noop
    }

    /// Progress states for UI feedback.
    enum DropProgress: Equatable {
        case validating
        case copying
        case extractingMetadata
        case importingURL(String)
        case importingText
        case saving(filename: String, kind: String)
        case transcribing(filename: String, size: String)
        case complete

        var isComplete: Bool {
            if case .complete = self { return true }
            return false
        }
    }

    /// Errors during drop processing.
    enum DropError: LocalizedError {
        case noValidProvider
        case unsupportedFormat(String)
        case unsupportedItem(String)
        case fileTooLarge(String, Int64, Int64)
        case copyFailed
        case transcriptionFailed(Error)
        case providerError(Error)

        var errorDescription: String? {
            switch self {
            case .noValidProvider:
                return "Nothing importable found"
            case .unsupportedFormat(let ext):
                return "Unsupported format: .\(ext)"
            case .unsupportedItem(let message):
                return message
            case .fileTooLarge(let name, let size, let limit):
                let actual = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                let maximum = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
                return "\(name) is \(actual). The drop limit is \(maximum)."
            case .copyFailed:
                return "Failed to copy dropped item"
            case .transcriptionFailed(let error):
                return "Transcription failed: \(error.localizedDescription)"
            case .providerError(let error):
                return "Could not read dropped item: \(error.localizedDescription)"
            }
        }
    }

    /// Structured audio metadata.
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

    private struct DroppedFile {
        let url: URL
        let originalFilename: String
        let typeIdentifier: String
        let isTemporary: Bool
    }
}

private extension AttachmentKind {
    var displayName: String {
        switch self {
        case .image: return "image"
        case .pdf: return "PDF"
        case .document: return "document"
        case .video: return "video"
        case .audio: return "audio"
        case .other: return "file"
        }
    }
}

private extension String {
    var trimmedForImport: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNonEmpty: String? {
        let value = trimmedForImport
        return value.isEmpty ? nil : value
    }
}
