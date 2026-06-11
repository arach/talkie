//
//  VoiceMemoDetailNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — Next-style memo detail. Header + waveform
//  + playback transport + transcript + actions.
//

import Combine
import CoreData
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class VoiceMemoDetailStore: ObservableObject {
    @Published var memo: MemoDisplay
    @Published var attachments: [MemoImageAttachment] = []
    @Published var transcriptVersions: [TranscriptVersionDisplay] = []
    @Published var workflowRuns: [WorkflowRunDisplay] = []

    struct MemoDisplay {
        let id: String
        let title: String
        let createdAtLabel: String
        let durationLabel: String
        let transcript: String
        let summary: String?
        let levels: [Float]
        let isPlaying: Bool
        let playheadProgress: Double
    }

    struct TranscriptVersionDisplay: Identifiable, Equatable {
        let id: String
        let version: Int32
        let content: String
        let sourceDescription: String
        let formattedDate: String
        let isLatest: Bool
        let sourceIcon: String
    }

    struct WorkflowRunDisplay: Identifiable, Equatable {
        let id: String
        let workflowName: String
        let status: String
        let outputPreview: String?
        let runDateLabel: String
        let icon: String

        var statusLabel: String {
            switch status.lowercased() {
            case "completed", "success", "succeeded":
                return "Complete"
            case "failed", "failure", "error":
                return "Failed"
            case "running", "in_progress", "processing":
                return "Running"
            case "queued", "pending":
                return "Queued"
            default:
                return status.isEmpty ? "Pending" : status.capitalized
            }
        }

        var isFinished: Bool {
            switch status.lowercased() {
            case "completed", "success", "succeeded", "failed", "failure", "error":
                return true
            default:
                return false
            }
        }

        var isFailure: Bool {
            switch status.lowercased() {
            case "failed", "failure", "error":
                return true
            default:
                return false
            }
        }
    }

    private let audioPlayer = AudioPlayerManager()
    private var cancellables: Set<AnyCancellable> = []
    private var sourceMemo: VoiceMemo?
    private var audioData: Data?
    private var audioURL: URL?
    private var durationSeconds: TimeInterval
    private var isMock: Bool

    var canEditTitle: Bool {
        isMock || sourceMemo != nil
    }

    var canEditTranscript: Bool {
        isMock || sourceMemo != nil
    }

    var hasTranscriptVersionHistory: Bool {
        transcriptVersions.count > 1
    }

    var canDeleteMemo: Bool {
        !isMock && sourceMemo != nil
    }

    var canGenerateTitle: Bool {
        let transcript = memo.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return canEditTitle && !transcript.isEmpty && transcript != "No transcript yet."
    }

    init(memoID: String?) {
        let id = memoID ?? "mock"
        self.isMock = id == "mock"
        self.durationSeconds = Self.mockDuration
        self.memo = Self.mockMemo

        if !isMock, let loaded = Self.fetchMemo(id: id) {
            sourceMemo = loaded
            audioData = loaded.audioData
            audioURL = Self.audioURL(for: loaded)
            durationSeconds = loaded.duration
            memo = Self.display(from: loaded, isPlaying: false, currentTime: 0, duration: durationSeconds)
            if let audioURL { audioPlayer.preloadDuration(for: audioURL) }
        }

        audioPlayer.$isPlaying
            .combineLatest(audioPlayer.$currentTime, audioPlayer.$duration)
            .sink { [weak self] isPlaying, currentTime, playerDuration in
                self?.refreshPlayback(isPlaying: isPlaying, currentTime: currentTime, playerDuration: playerDuration)
            }
            .store(in: &cancellables)

        reloadAttachments()
        reloadTranscriptVersions()
        reloadWorkflowRuns()
    }

    // MARK: - Title

    @discardableResult
    func saveTitle(_ rawTitle: String) -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        if isMock {
            memo = memo.withTitle(title)
            return true
        }

        guard let sourceMemo else { return false }
        sourceMemo.title = title

        do {
            try sourceMemo.managedObjectContext?.save()
            refreshSourceMemoDisplay()
            reloadTranscriptVersions()
            return true
        } catch {
            sourceMemo.managedObjectContext?.rollback()
            refreshSourceMemoDisplay()
            reloadTranscriptVersions()
            return false
        }
    }

    func generateSmartTitle(using aiService: OnDeviceAIService) async throws -> String {
        if isMock {
            let title = Self.localTitle(from: memo.summary ?? memo.transcript, fallback: "Generated memo title")
            memo = memo.withTitle(title)
            return title
        }

        guard let sourceMemo else { throw OnDeviceAIError.noTranscript }
        let context = sourceMemo.managedObjectContext ?? PersistenceController.shared.container.viewContext
        try await aiService.applySmartTitle(to: sourceMemo, context: context)
        refreshSourceMemoDisplay()
        return memo.title
    }

    // MARK: - Transcript

    @discardableResult
    func saveTranscript(_ rawTranscript: String) -> Bool {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return false }

        if isMock {
            memo = memo.withTranscript(transcript)
            return true
        }

        guard let sourceMemo else { return false }
        sourceMemo.addUserTranscript(content: transcript)

        do {
            try sourceMemo.managedObjectContext?.save()
            refreshSourceMemoDisplay()
            reloadTranscriptVersions()
            return true
        } catch {
            sourceMemo.managedObjectContext?.rollback()
            refreshSourceMemoDisplay()
            reloadTranscriptVersions()
            return false
        }
    }

    // MARK: - Attachments

    var memoUUID: UUID? {
        UUID(uuidString: memo.id) ?? sourceMemo?.id
    }

    var attachmentFingerprint: String {
        attachments
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: "|")
    }

    var hasPersistentMemo: Bool {
        !isMock && sourceMemo?.id != nil
    }

    func reloadAttachments() {
        guard let uuid = memoUUID else {
            attachments = []
            return
        }
        attachments = MemoAttachmentStore.shared.attachments(for: uuid)
    }

    func reloadTranscriptVersions() {
        guard let sourceMemo else {
            transcriptVersions = []
            return
        }

        let latestObjectID = sourceMemo.latestTranscriptVersion?.objectID
        transcriptVersions = sourceMemo.sortedTranscriptVersions.map { version in
            TranscriptVersionDisplay(
                id: version.id?.uuidString ?? version.objectID.uriRepresentation().absoluteString,
                version: version.version,
                content: version.content ?? "",
                sourceDescription: version.sourceDescription,
                formattedDate: version.formattedDate,
                isLatest: version.objectID == latestObjectID,
                sourceIcon: Self.sourceIcon(for: version)
            )
        }
    }

    func reloadWorkflowRuns() {
        guard let sourceMemo, let runs = sourceMemo.workflowRuns as? Set<WorkflowRun> else {
            workflowRuns = []
            return
        }

        workflowRuns = runs
            .sorted { lhs, rhs in
                (lhs.runDate ?? .distantPast) > (rhs.runDate ?? .distantPast)
            }
            .map(Self.workflowRunDisplay(from:))
    }

    func reloadSourceMemo() {
        guard !isMock, let sourceMemo else { return }
        sourceMemo.managedObjectContext?.refresh(sourceMemo, mergeChanges: true)
        audioData = sourceMemo.audioData
        audioURL = Self.audioURL(for: sourceMemo)
        durationSeconds = sourceMemo.duration
        refreshSourceMemoDisplay()
        reloadTranscriptVersions()
        reloadWorkflowRuns()
        reloadAttachments()
    }

    @discardableResult
    func addAttachment(data: Data, originalName: String? = nil) -> MemoImageAttachment? {
        guard let uuid = memoUUID else { return nil }
        let attachment = MemoAttachmentStore.shared.saveImage(
            data: data,
            preferredName: originalName,
            memoID: uuid
        )
        reloadAttachments()
        return attachment
    }

    func removeAttachment(_ attachment: MemoImageAttachment) {
        guard let uuid = memoUUID else { return }
        MemoAttachmentStore.shared.delete(attachment, memoID: uuid)
        reloadAttachments()
    }

    @discardableResult
    func appendOCRTextToNotes(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        if isMock {
            memo = memo.withTranscript(memo.transcript + "\n\n--- Scanned Text ---\n" + text)
            return true
        }

        guard let sourceMemo else { return false }
        let separator = "\n\n--- Scanned Text ---\n"
        let currentNotes = sourceMemo.notes ?? ""
        if currentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceMemo.notes = text
        } else {
            sourceMemo.notes = currentNotes + separator + text
        }
        sourceMemo.lastModified = Date()

        do {
            try sourceMemo.managedObjectContext?.save()
            refreshSourceMemoDisplay()
            return true
        } catch {
            sourceMemo.managedObjectContext?.rollback()
            refreshSourceMemoDisplay()
            return false
        }
    }

    func buildAttachmentUploadRequest() throws -> MemoAttachmentUploadRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let items = try attachments.map { attachment in
            let data = try Data(contentsOf: MemoAttachmentStore.shared.url(for: attachment))
            return MemoAttachmentUploadItem(
                id: attachment.id.uuidString,
                originalName: attachment.originalName,
                addedAt: formatter.string(from: attachment.addedAt),
                fileSizeBytes: attachment.fileSizeBytes,
                pixelWidth: attachment.pixelWidth,
                pixelHeight: attachment.pixelHeight,
                recordingOffsetSeconds: nil,
                mimeType: Self.mimeType(for: attachment.originalName),
                dataBase64: data.base64EncodedString()
            )
        }

        let createdAt = sourceMemo?.createdAt ?? Date()
        return MemoAttachmentUploadRequest(
            memoTitle: memo.title,
            memoCreatedAt: formatter.string(from: createdAt),
            attachments: items
        )
    }

    func shareItems() -> [Any] {
        var items: [Any] = [
            """
            \(memo.title)
            \(memo.createdAtLabel) · \(memo.durationLabel)

            \(memo.transcript)
            """
        ]
        items.append(contentsOf: attachments.compactMap { image(for: $0) })
        return items
    }

    @discardableResult
    func deleteMemo() -> Bool {
        guard !isMock, let sourceMemo else { return false }
        audioPlayer.stopPlayback()
        VoiceMemoStore.shared.delete(sourceMemo)
        self.sourceMemo = nil
        attachments = []
        transcriptVersions = []
        return true
    }

    /// Re-runs transcription on the existing audio file. Sets
    /// isTranscribing → true on the entity; TranscriptionService
    /// overwrites the transcript field when the pass settles.
    @discardableResult
    func retranscribe() -> Bool {
        guard !isMock, let sourceMemo else { return false }
        let context = sourceMemo.managedObjectContext
            ?? PersistenceController.shared.container.viewContext
        TranscriptionService.shared.transcribeVoiceMemo(sourceMemo, context: context)
        return true
    }

    func image(for attachment: MemoImageAttachment) -> UIImage? {
        MemoAttachmentStore.shared.image(for: attachment)
    }

    func togglePlayback() {
        guard !isMock else {
            memo = Self.mockMemo.withPlayback(isPlaying: !memo.isPlaying, progress: memo.playheadProgress)
            return
        }
        if let audioData {
            audioPlayer.togglePlayPause(data: audioData)
        } else if let audioURL {
            audioPlayer.togglePlayPause(url: audioURL)
        }
    }

    func skipBackward() { seek(to: max(0, currentTime - 15)) }
    func skipForward() { seek(to: min(duration, currentTime + 15)) }
    func seek(progress: Double) { seek(to: min(max(0, progress), 1) * duration) }
    var currentTimeLabel: String { Self.formatDuration(currentTime) }

    private var duration: TimeInterval {
        let playerDuration = audioPlayer.duration
        return playerDuration > 0 ? playerDuration : max(durationSeconds, 0)
    }

    private var currentTime: TimeInterval {
        memo.playheadProgress * max(duration, 1)
    }

    private func seek(to time: TimeInterval) {
        guard duration > 0 else { return }
        if audioPlayer.duration > 0 || audioPlayer.isPlaying {
            audioPlayer.seek(to: time)
        }
        refreshPlayback(isPlaying: audioPlayer.isPlaying, currentTime: time, playerDuration: audioPlayer.duration)
    }

    private func refreshPlayback(isPlaying: Bool, currentTime: TimeInterval, playerDuration: TimeInterval) {
        let effectiveDuration = playerDuration > 0 ? playerDuration : durationSeconds
        let progress = effectiveDuration > 0 ? min(max(currentTime / effectiveDuration, 0), 1) : 0
        if let sourceMemo {
            memo = Self.display(from: sourceMemo, isPlaying: isPlaying, currentTime: currentTime, duration: effectiveDuration)
        } else if isMock {
            memo = Self.mockMemo.withPlayback(isPlaying: isPlaying, progress: progress)
        }
    }

    private func refreshSourceMemoDisplay() {
        guard sourceMemo != nil else { return }
        refreshPlayback(
            isPlaying: audioPlayer.isPlaying,
            currentTime: currentTime,
            playerDuration: audioPlayer.duration
        )
    }

    private static func fetchMemo(id: String) -> VoiceMemo? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private static func audioURL(for memo: VoiceMemo) -> URL? {
        guard let filename = memo.fileURL, !filename.isEmpty else { return nil }
        return URL.documentsDirectory.appending(path: filename)
    }

    private static func display(from memo: VoiceMemo, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) -> MemoDisplay {
        let effectiveDuration = duration > 0 ? duration : memo.duration
        let progress = effectiveDuration > 0 ? min(max(currentTime / effectiveDuration, 0), 1) : 0
        return MemoDisplay(
            id: memo.id?.uuidString ?? memo.objectID.uriRepresentation().absoluteString,
            title: cleanTitle(memo.title, fallback: "Recording"),
            createdAtLabel: createdAtLabel(memo.createdAt ?? Date()),
            durationLabel: formatDuration(effectiveDuration),
            transcript: firstNonEmpty([memo.currentTranscript, memo.notes]) ?? "No transcript yet.",
            summary: firstNonEmpty([memo.summary]),
            levels: waveformLevels(from: memo.waveformData),
            isPlaying: isPlaying,
            playheadProgress: progress
        )
    }

    private static func waveformLevels(from data: Data?) -> [Float] {
        guard let data, let levels = try? JSONDecoder().decode([Float].self, from: data), !levels.isEmpty else { return mockLevels }
        return levels
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func cleanTitle(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        return value
    }

    private static func createdAtLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
    }

    private static func localTitle(from text: String, fallback: String) -> String {
        let words = text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        let title = words.prefix(5).joined(separator: " ")
        return title.isEmpty ? fallback : title
    }

    private static func workflowRunDisplay(from run: WorkflowRun) -> WorkflowRunDisplay {
        let name = firstNonEmpty([run.workflowName]) ?? "Mac workflow"
        let outputPreview = firstNonEmpty([run.output])
        return WorkflowRunDisplay(
            id: run.id?.uuidString ?? run.objectID.uriRepresentation().absoluteString,
            workflowName: name,
            status: run.status ?? "",
            outputPreview: outputPreview.map { previewText($0) },
            runDateLabel: workflowRunDateLabel(run.runDate),
            icon: firstNonEmpty([run.workflowIcon]) ?? "bolt.horizontal.circle"
        )
    }

    private static func workflowRunDateLabel(_ date: Date?) -> String {
        guard let date else { return "Waiting" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return "Today · \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday · \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
    }

    private static func previewText(_ text: String) -> String {
        let normalized = text
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 140 else { return normalized }
        return String(normalized.prefix(140)) + "…"
    }

    private static func sourceIcon(for version: TranscriptVersion) -> String {
        guard let sourceType = version.sourceTypeEnum else {
            return "doc.text"
        }

        switch sourceType {
        case .systemIOS:
            return "iphone"
        case .systemMacOS:
            return "desktopcomputer"
        case .user:
            return "pencil"
        }
    }

    private static func mimeType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private static let mockDuration: TimeInterval = 222
    private static let mockLevels: [Float] = (0..<100).map { i in
        let v = 0.3 + 0.5 * sin(Double(i) * 0.4) + 0.2 * cos(Double(i) * 0.13)
        return Float(abs(v).truncatingRemainder(dividingBy: 1.0))
    }

    static let mockMemo = MemoDisplay(
        id: "mock",
        title: "Meeting notes — product review",
        createdAtLabel: "Today · 9:34 AM",
        durationLabel: "3:42",
        transcript: """
        alex pushed back on the migration timeline; said we should move it to q3 instead of pushing through in q2. the rest of the team seems fine with that. main concern is the downstream impact on the analytics rewrite which depends on the new schema.

        action items: ship the spec by friday, get sam to sign off, schedule the migration window for the first week of july.
        """,
        summary: "Migration timeline shifts to Q3; spec ships Friday, downstream analytics rewrite affected.",
        levels: VoiceMemoDetailStore.mockLevels,
        isPlaying: false,
        playheadProgress: 0.32
    )
}

private extension VoiceMemoDetailStore.MemoDisplay {
    func withPlayback(isPlaying: Bool, progress: Double) -> Self {
        .init(id: id, title: title, createdAtLabel: createdAtLabel, durationLabel: durationLabel, transcript: transcript, summary: summary, levels: levels, isPlaying: isPlaying, playheadProgress: progress)
    }

    func withTitle(_ title: String) -> Self {
        .init(id: id, title: title, createdAtLabel: createdAtLabel, durationLabel: durationLabel, transcript: transcript, summary: summary, levels: levels, isPlaying: isPlaying, playheadProgress: playheadProgress)
    }

    func withTranscript(_ transcript: String) -> Self {
        .init(id: id, title: title, createdAtLabel: createdAtLabel, durationLabel: durationLabel, transcript: transcript, summary: summary, levels: levels, isPlaying: isPlaying, playheadProgress: playheadProgress)
    }
}

struct VoiceMemoDetailNext: View {
    @EnvironmentObject private var chrome: ShellChrome
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var workflows = WorkflowsStore.shared
    @StateObject private var store: VoiceMemoDetailStore
    @StateObject private var aiService = OnDeviceAIService.shared
    @State private var selectedAttachmentItems: [PhotosPickerItem] = []
    @State private var ocrPhotoPickerItems: [PhotosPickerItem] = []
    @State private var showingAttachmentPickerSheet: Bool = false
    @State private var showingAttachmentPhotoPicker: Bool = false
    @State private var showingAttachmentCamera: Bool = false
    @State private var showingOCRPhotoPicker: Bool = false
    @State private var previewAttachment: MemoImageAttachment?
    @State private var runningWorkflowID: String?
    @State private var recentAttachmentAssets: [PHAsset] = []
    @State private var attachmentPhotoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var hasLoadedRecentAttachmentAssets: Bool = false
    @State private var isImportingAttachments: Bool = false
    @State private var isRunningOCR: Bool = false
    @State private var ocrResultText: String?
    @State private var attachmentError: String?
    @State private var isSendingAttachmentsToMac: Bool = false
    @State private var lastSentAttachmentFingerprint: String?
    @State private var showingSendToMacAlert: Bool = false
    @State private var sendToMacAlertTitle: String = ""
    @State private var sendToMacAlertMessage: String = ""
    @State private var isEditingTitle: Bool = false
    @State private var editedTitle: String = ""
    @State private var titleEditError: String?
    @State private var isGeneratingTitle: Bool = false
    @State private var isEditingTranscript: Bool = false
    @State private var editedTranscript: String = ""
    @State private var transcriptEditError: String?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var showingAgentSheet: Bool = false
    @State private var pendingAgentInstruction: String?
    @State private var showingCLISheet: Bool = false
    @State private var showingVersionHistory: Bool = false
    @State private var knownWorkflowStatuses: [String: String] = [:]
    @State private var workflowToast: VoiceMemoDetailStore.WorkflowRunDisplay?
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var transcriptFieldFocused: Bool

    init(memoID: String? = nil) {
        _store = StateObject(wrappedValue: VoiceMemoDetailStore(memoID: memoID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                // Sections share a 16pt left margin (matching the back
                // button) — EXCEPT the workflow carousel, which spans full
                // width and re-insets its own content so cards bleed off the
                // right edge.
                VStack(alignment: .leading, spacing: 16) {
                    // The whole memo as one component: identity (title +
                    // source) → tape strip → words, on one raised paper.
                    // Tapping the body — or Edit/Done — turns it into an
                    // inline editor; no modal sheet.
                    documentCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // Reading-only chrome. While editing, the words are the
                    // whole job — tools + workflows step out of the way.
                    if !isEditingTranscript {
                        toolRail
                            .padding(.horizontal, 16)

                        // Memo-scoped workflow triggers — full-bleed carousel.
                        if !memoWorkflowTemplates.isEmpty {
                            workflowTriggersSection
                        }

                        // Mac workflow runs — only when runs synced back.
                        if !store.workflowRuns.isEmpty {
                            workflowRunsSection
                                .padding(.horizontal, 16)
                        }

                        if shouldShowAttachmentsSection {
                            attachmentsSection
                                .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.bottom, 80)   // clear the ~64pt summon-button band
            }
            .scrollIndicators(.hidden)
        }
        .photosPicker(
            isPresented: $showingAttachmentPhotoPicker,
            selection: $selectedAttachmentItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .photosPicker(
            isPresented: $showingOCRPhotoPicker,
            selection: $ocrPhotoPickerItems,
            maxSelectionCount: 1,
            matching: .images
        )
        .onChange(of: selectedAttachmentItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importSelectedAttachmentItems(newItems)
            }
        }
        .onChange(of: ocrPhotoPickerItems) { _, newItems in
            guard let item = newItems.first else { return }
            ocrPhotoPickerItems = []
            Task {
                await performOCR(from: item)
            }
        }
        .sheet(isPresented: $showingAttachmentPickerSheet) {
            MemoAttachmentPickerSheetNext(
                recentAssets: recentAttachmentAssets,
                photoAuthorizationStatus: attachmentPhotoAuthorizationStatus,
                onChooseFromLibrary: {
                    showingAttachmentPickerSheet = false
                    showingAttachmentPhotoPicker = true
                },
                onTakePhoto: {
                    showingAttachmentPickerSheet = false
                    showingAttachmentCamera = true
                },
                onScanText: {
                    showingAttachmentPickerSheet = false
                    showingOCRPhotoPicker = true
                },
                onSelectRecentAsset: { asset in
                    showingAttachmentPickerSheet = false
                    Task {
                        await importRecentAttachmentAsset(asset)
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAttachmentCamera) {
            CameraImagePicker { image in
                Task {
                    await importCapturedImage(image)
                }
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            attachmentPreview(attachment)
        }
        .sheet(isPresented: $showingShareSheet) {
            VoiceMemoShareSheet(items: store.shareItems())
        }
        .sheet(isPresented: $showingAgentSheet, onDismiss: {
            pendingAgentInstruction = nil
        }) {
            MemoAgentSheetNext(memo: store.memo, initialInstruction: pendingAgentInstruction)
        }
        .sheet(isPresented: $showingCLISheet) {
            MemoCLISheetNext(memo: store.memo)
        }
        .sheet(isPresented: $showingVersionHistory) {
            TranscriptVersionHistoryNext(versions: store.transcriptVersions)
        }
        .alert("Scanned Text", isPresented: Binding(
            get: { ocrResultText != nil },
            set: { if !$0 { ocrResultText = nil } }
        )) {
            Button("Append to Notes") {
                appendOCRTextToNotes()
            }
            Button("Cancel", role: .cancel) {
                ocrResultText = nil
            }
        } message: {
            if let ocrResultText {
                let preview = ocrResultText.prefix(200)
                Text(String(preview) + (ocrResultText.count > 200 ? "..." : ""))
            }
        }
        .alert(sendToMacAlertTitle, isPresented: $showingSendToMacAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sendToMacAlertMessage)
        }
        .alert("Delete memo?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteMemo)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the memo, its audio file, and saved attachments from this device.")
        }
        .onChange(of: showingAttachmentPickerSheet) { _, isPresented in
            if isPresented {
                loadRecentAttachmentAssetsIfNeeded()
            }
        }
        .overlay(alignment: .top) {
            if let workflowToast {
                workflowToastBanner(workflowToast)
                    .padding(.horizontal, 16)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: workflowToast?.id)
        .onAppear {
            chrome.voiceCommandHandler = { transcript in
                pendingAgentInstruction = transcript
                showingAgentSheet = true
            }
        }
        .onDisappear {
            // Auto-save any in-progress inline edit — leaving is committing.
            if isEditingTranscript {
                _ = store.saveTranscript(editedTranscript)
            }
            chrome.voiceCommandHandler = { transcript in
                AppShellRouter.shared.submitVoiceCommand(transcript)
            }
        }
        .task(id: store.memo.id) {
            await pollWorkflowRuns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemosDidChange)) { _ in
            guard !isEditingTitle && !isEditingTranscript else { return }
            store.reloadSourceMemo()
        }
        .accessibilityIdentifier("memo.detail.screen")
    }

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Memos")
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
            .yieldsToChromeZone(.topLeading)

            Spacer()

            // No centered nav title — the body title carries the screen's
            // identity, so a sans "Memo" stacked above the serif "Memo Jun 4
            // · …" was redundant and a font clash. Edit ↔ Done is the
            // iOS-canonical text-edit control; Done commits (auto-saves,
            // undo is the net) so there's no Cancel.
            if isEditingTranscript {
                Button(action: commitTranscriptEdit) {
                    Text("Done")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done editing")
            } else if store.canEditTranscript {
                Button(action: beginInlineTranscriptEdit) {
                    Text("Edit")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit memo")
            }

            if !isEditingTranscript {
            Menu {
                Button("Share", systemImage: "square.and.arrow.up") {
                    showingShareSheet = true
                }
                Button("Ask Agent", systemImage: "brain.head.profile") {
                    showingAgentSheet = true
                }
                Button("Run CLI", systemImage: "terminal") {
                    showingCLISheet = true
                }
                Button("Retranscribe", systemImage: "arrow.clockwise") {
                    retranscribe()
                }
                if store.hasTranscriptVersionHistory {
                    Button("Version history", systemImage: "clock.arrow.circlepath") {
                        showingVersionHistory = true
                    }
                }
                if store.canDeleteMemo {
                    Button("Delete memo", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("More options")
            }
            .buttonStyle(.plain)
            .yieldsToChromeZone(.topTrailing)
            }   // end if !isEditingTranscript (overflow menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }

    // Identity zone — just the title now. The capture date/time moved down
    // to the metadata footer (with word count), so the top of the card is
    // clean and the title stands alone.
    private var identityZone: some View {
        Group {
            if isEditingTitle {
                titleEditor
            } else {
                Text(store.memo.title)
                    .talkieType(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginTitleEdit() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $editedTitle)
                .talkieType(.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .submitLabel(.done)
                .focused($titleFieldFocused)
                .onSubmit(saveTitleEdit)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    titleEditError == nil
                                        ? theme.currentTheme.chrome.accent.opacity(0.6)
                                        : Color.red.opacity(0.55),
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                        )
                )

            HStack(spacing: 8) {
                Button("Cancel", action: cancelTitleEdit)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer(minLength: 0)

                Button(action: generateSmartTitle) {
                    HStack(spacing: 5) {
                        if isGeneratingTitle {
                            ProgressView()
                                .scaleEffect(0.55)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(isGeneratingTitle ? "Generating" : "Generate")
                    }
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.45),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
                }
                .disabled(isGeneratingTitle || !store.canGenerateTitle)
                .opacity(store.canGenerateTitle ? 1 : 0.5)

                Button("Save", action: saveTitleEdit)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)

            if let titleEditError {
                Text(titleEditError)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(Color.red.opacity(0.85))
            }
        }
    }

    // Tape strip — the recording, fused to the top of the document. Play +
    // mag-tape waveform + time. No card of its own; the documentCard is the
    // paper it sits on.
    private var tapeStrip: some View {
        HStack(spacing: 10) {
            Button(action: { store.togglePlayback() }) {
                ZStack {
                    Circle()
                        .fill(store.memo.isPlaying ? theme.currentTheme.chrome.accent : Color.clear)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().strokeBorder(theme.currentTheme.chrome.accent, lineWidth: 1.5)
                        )
                    Image(systemName: store.memo.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.memo.isPlaying
                            ? theme.colors.cardBackground
                            : theme.currentTheme.chrome.accent)
                        .offset(x: store.memo.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)

            InteractiveWaveformView(
                levels: store.memo.levels,
                height: 28,
                progress: store.memo.playheadProgress,
                playedColor: theme.currentTheme.chrome.accent,
                unplayedColor: theme.colors.textTertiary.opacity(0.35),
                onSeek: { p in store.seek(progress: p) }
            )

            Text("\(store.currentTimeLabel) / \(store.memo.durationLabel)")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // While editing, the transport recedes to a quiet label — the words are
    // the focus, not the audio.
    private var tapeChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 9))
                .foregroundStyle(theme.colors.textTertiary)
            Text("TAPE · \(store.memo.durationLabel)")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // The whole memo as one component: identity (title + source) → the
    // recording (tape strip) → the words, all on one raised paper. The
    // border lifts to amber while editing so the surface reads as "live".
    private var documentCard: some View {
        VStack(spacing: 0) {
            identityZone

            cardDivider

            if isEditingTranscript { tapeChip } else { tapeStrip }

            cardDivider

            if isEditingTranscript { editingField } else { readingBody }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isEditingTranscript
                                ? theme.currentTheme.chrome.accent
                                : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: isEditingTranscript ? 1.5 : theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }

    // Full-width hairline between the card's zones (identity · recording ·
    // words) so the unified paper still reads as distinct sections.
    private var cardDivider: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
    }

    // Reading body — the transcript as the audio made readable. During
    // playback the played words take full ink, the rest dim, with an amber
    // playhead between; idle, it's full ink for plain reading. Tap to edit.
    private var readingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            TranscriptRolloutText(
                text: store.memo.transcript,
                attributedText: playheadTranscript,
                canEdit: store.canEditTranscript,
                onTap: beginInlineTranscriptEdit
            )

            // Consolidated metadata footer — capture date/time + word count
            // + source, all in one quiet technical line at the foot of the
            // words (so the title stands alone up top).
            HStack(spacing: 6) {
                // Word count anchors left (it's about the words above it);
                // capture date/time + source glyph ride the right edge.
                Text("\(wordCount) WORDS")
                Spacer(minLength: 8)
                Image(systemName: "iphone")
                    .font(.system(size: 9, weight: .medium))
                Text(store.memo.createdAtLabel)
            }
            .talkieType(.channelLabelTiny)
            .foregroundStyle(theme.colors.textTertiary.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contextMenu {
            if store.hasTranscriptVersionHistory {
                Button("Version History", systemImage: "clock.arrow.circlepath") {
                    showingVersionHistory = true
                }
            }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = store.memo.transcript
            }
            if store.canEditTranscript {
                Button("Edit", systemImage: "pencil") { beginInlineTranscriptEdit() }
            }
        }
    }

    private struct TranscriptRolloutText: View {
        let text: String
        let attributedText: AttributedString
        let canEdit: Bool
        let onTap: () -> Void

        @ObservedObject private var theme = ThemeManager.shared
        @State private var renderedText: String = ""
        @State private var hasAppeared = false
        @State private var isRollingOut = false
        @State private var rolloutTask: Task<Void, Never>?

        var body: some View {
            Group {
                if isRollingOut {
                    rolloutViewport
                } else {
                    Text(attributedText)
                        .talkieType(.listTitle)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if canEdit { onTap() }
            }
            .onAppear {
                guard !hasAppeared else { return }
                renderedText = text
                hasAppeared = true
            }
            .onChange(of: text) { oldText, newText in
                handleTextChange(from: oldText, to: newText)
            }
            .onDisappear {
                rolloutTask?.cancel()
            }
            .accessibilityLabel(text)
        }

        private var rolloutViewport: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(renderedText)
                            .talkieType(.listTitle)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Color.clear
                            .frame(height: 1)
                            .id("transcript-rollout-bottom")
                    }
                }
                .frame(minHeight: 126, maxHeight: rolloutViewportHeight)
                .scrollIndicators(.hidden)
                .onChange(of: renderedText) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("transcript-rollout-bottom", anchor: .bottom)
                    }
                }
            }
        }

        private var rolloutViewportHeight: CGFloat {
            if text.count > 1_200 { return 260 }
            if text.count > 520 { return 220 }
            return 170
        }

        private func handleTextChange(from oldText: String, to newText: String) {
            rolloutTask?.cancel()
            guard Self.shouldRollout(from: oldText, to: newText), hasAppeared else {
                renderedText = newText
                isRollingOut = false
                return
            }
            startRollout(newText)
        }

        private func startRollout(_ fullText: String) {
            renderedText = ""
            isRollingOut = true

            let chunks = Self.rolloutChunks(from: fullText)
            let delayMilliseconds = Self.delayMilliseconds(for: fullText)
            rolloutTask = Task { @MainActor in
                for chunk in chunks {
                    if Task.isCancelled { return }
                    renderedText += chunk
                    try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                }
                if Task.isCancelled { return }
                renderedText = fullText
                isRollingOut = false
            }
        }

        private static func shouldRollout(from oldText: String, to newText: String) -> Bool {
            let old = normalized(oldText)
            let new = normalized(newText)
            guard !new.isEmpty, old != new, !isPlaceholder(new) else { return false }
            return old.isEmpty || isPlaceholder(old)
        }

        private static func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func isPlaceholder(_ text: String) -> Bool {
            text == "No transcript yet."
        }

        private static func rolloutChunks(from text: String) -> [String] {
            let wordsPerChunk = text.count > 1_200 ? 4 : 2
            var chunks: [String] = []
            var current = ""
            var boundaryCount = 0

            for scalar in text.unicodeScalars {
                current.append(String(scalar))
                if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    boundaryCount += 1
                    if boundaryCount >= wordsPerChunk {
                        chunks.append(current)
                        current = ""
                        boundaryCount = 0
                    }
                }
            }

            if !current.isEmpty {
                chunks.append(current)
            }
            return chunks.isEmpty ? [text] : chunks
        }

        private static func delayMilliseconds(for text: String) -> Int {
            if text.count > 1_600 { return 24 }
            if text.count > 800 { return 32 }
            return 42
        }
    }

    // Inline editing field — tap puts a caret in the words. Plain editable
    // text; Done (header) commits. Auto-saves, undo is the safety net — no
    // Accept/Cancel.
    private var editingField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $editedTranscript)
                .talkieType(.listTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, maxHeight: 340)
                .focused($transcriptFieldFocused)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 9))
                Text("SAVES AUTOMATICALLY · SHAKE TO UNDO")
            }
            .talkieType(.channelLabelTiny)
            .foregroundStyle(theme.colors.textTertiary.opacity(0.7))

            if let transcriptEditError {
                Text(transcriptEditError)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(Color.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // Two-tone transcript driven by playback progress. Idle → full ink so
    // it reads as plain text, not "half transcribed".
    private var playheadTranscript: AttributedString {
        let text = store.memo.transcript
        let progress = store.memo.playheadProgress
        guard store.memo.isPlaying, progress > 0.001, !text.isEmpty else {
            var full = AttributedString(text)
            full.foregroundColor = theme.colors.textPrimary
            return full
        }
        let offset = max(0, min(text.count, Int((Double(text.count) * progress).rounded())))
        let splitIndex = text.index(text.startIndex, offsetBy: offset)
        var played = AttributedString(String(text[text.startIndex..<splitIndex]))
        played.foregroundColor = theme.colors.textPrimary
        var caret = AttributedString("▏")
        caret.foregroundColor = theme.currentTheme.chrome.accent
        var rest = AttributedString(String(text[splitIndex...]))
        rest.foregroundColor = theme.colors.textTertiary
        return played + caret + rest
    }

    // Tool rail — one flat row of secondary verbs. Refine ✨ (the AI
    // transform) lives here now, honestly labelled; it no longer
    // masquerades as the editor. Listen is gone — the tape strip does it.
    // Ask Agent / Run CLI keep their home in the overflow menu.
    private var toolRail: some View {
        HStack(spacing: 6) {
            toolRailButton(label: "Share", systemImage: "square.and.arrow.up") {
                showingShareSheet = true
            }
            toolRailButton(label: "Copy", systemImage: "doc.on.doc", action: copyTranscript)
            toolRailButton(label: "Attach", systemImage: "paperclip") {
                showingAttachmentPickerSheet = true
            }
            toolRailButton(label: "Refine", systemImage: "sparkles",
                           isEnabled: canRefineMemo, action: openMemoInCompose)
        }
    }

    private func toolRailButton(
        label: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(height: 18)
                Text(label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func copyTranscript() {
        UIPasteboard.general.string = normalizedTranscript.isEmpty
            ? store.memo.title
            : normalizedTranscript
        Haptics.toggle.fire()
    }

    private var workflowRunsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· MAC WORKFLOWS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Button(action: {
                    store.reloadWorkflowRuns()
                    knownWorkflowStatuses = workflowStatusSnapshot
                }) {
                    Text("REFRESH")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if store.workflowRuns.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(theme.currentTheme.chrome.accent.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Waiting for Mac workflow runs")
                            .talkieType(.fieldLabel)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("Runs synced back from the Mac will appear here and toast when they finish.")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(workflowCardBackground)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.workflowRuns.prefix(3)) { run in
                        workflowRunRow(run)
                    }
                }
            }
        }
    }

    private func workflowRunRow(_ run: VoiceMemoDetailStore.WorkflowRunDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: run.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(workflowStatusColor(run))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(workflowStatusColor(run).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(run.workflowName)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(run.statusLabel.uppercased())
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(workflowStatusColor(run))
                }

                Text(run.runDateLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                if let outputPreview = run.outputPreview {
                    Text(outputPreview)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(workflowCardBackground)
    }

    private var workflowCardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
    }

    private func workflowToastBanner(_ run: VoiceMemoDetailStore.WorkflowRunDisplay) -> some View {
        HStack(spacing: 10) {
            Image(systemName: run.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(workflowStatusColor(run))
            VStack(alignment: .leading, spacing: 2) {
                Text(run.workflowName)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                Text(run.isFailure ? "Mac workflow failed" : "Mac workflow complete")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(workflowStatusColor(run).opacity(0.45), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        )
    }

    private func workflowStatusColor(_ run: VoiceMemoDetailStore.WorkflowRunDisplay) -> Color {
        if run.isFailure { return .red.opacity(0.85) }
        if run.isFinished { return theme.currentTheme.chrome.accent }
        switch run.status.lowercased() {
        case "running", "in_progress", "processing":
            return .orange.opacity(0.9)
        default:
            return theme.colors.textTertiary
        }
    }

    private var transcriptEditorSheet: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Cancel", action: cancelTranscriptEdit)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)

                    Spacer()

                    Text("Edit transcript")
                        .talkieType(.headlineSecondary)
                        .foregroundStyle(theme.colors.textPrimary)

                    Spacer()

                    Button("Save", action: saveTranscriptEdit)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 18)

                if let transcriptEditError {
                    Text(transcriptEditError)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(Color.red.opacity(0.85))
                        .padding(.horizontal, 16)
                }

                TextEditor(text: $editedTranscript)
                    .talkieType(.listTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.colors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        transcriptEditError == nil
                                            ? theme.currentTheme.chrome.edgeFaint
                                            : Color.red.opacity(0.55),
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                                    )
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· ATTACHMENTS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                if !store.attachments.isEmpty {
                    Text("\(store.attachments.count)")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                Spacer()
                if !store.attachments.isEmpty {
                    Button(action: sendAttachmentsToPairedMac) {
                        HStack(spacing: 4) {
                            if isSendingAttachmentsToMac {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Image(systemName: hasSentCurrentAttachmentsToMac ? "checkmark.circle.fill" : "desktopcomputer")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(hasSentCurrentAttachmentsToMac ? "SENT" : "SEND MAC")
                                .talkieType(.channelLabelTiny)
                        }
                        .foregroundStyle(hasSentCurrentAttachmentsToMac ? theme.colors.textTertiary : theme.currentTheme.chrome.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    hasSentCurrentAttachmentsToMac
                                        ? theme.currentTheme.chrome.edgeFaint
                                        : theme.currentTheme.chrome.accent.opacity(0.5),
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendingAttachmentsToMac || hasSentCurrentAttachmentsToMac)
                }
                Button(action: { showingAttachmentPickerSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("ADD")
                            .talkieType(.channelLabelTiny)
                    }
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.5),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Compact empty state: when there are no attachments, the
            // section header (with the · ADD chip) is enough — skip
            // the large "Add screenshots or photos" tile that was
            // taking up a third of the viewport on every memo. Tap
            // the · ADD chip in the header to open the picker.
            if !store.attachments.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(store.attachments) { attachment in
                        attachmentTile(attachment)
                    }
                }
            }

            if isImportingAttachments || isRunningOCR || isSendingAttachmentsToMac {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.58)
                    Text(attachmentBusyLabel)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(.horizontal, 4)
            }

            if let attachmentError {
                Text(attachmentError)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Donor parity: restores the per-memo WorkflowActionSheet entry point
    /// without regressing the Next hub. These chips run the memo-scoped
    /// templates directly against the active memo and record the run in the
    /// shared WorkflowsStore history.
    // Full-bleed carousel. The section spans the screen (no outer padding);
    // the header and the first card re-inset to the 16pt column, and cards
    // scroll off the right edge instead of clipping inside a tight box.
    private var workflowTriggersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· WORKFLOWS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Button(action: { AppShellRouter.shared.openWorkflows() }) {
                    Text("HUB")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(memoWorkflowTemplates) { template in
                        workflowTriggerCard(template)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    private var memoWorkflowTemplates: [WorkflowTemplate] {
        workflows.templates.filter { $0.id.hasPrefix("memo-") }
    }

    private func workflowTriggerCard(_ template: WorkflowTemplate) -> some View {
        let isRunning = runningWorkflowID == template.id
        return Button {
            runMemoWorkflow(template)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(theme.currentTheme.chrome.accent.opacity(0.12))
                        )
                    Spacer()
                    Text(isRunning ? "RUNNING" : "RUN")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(isRunning ? theme.colors.textTertiary : theme.currentTheme.chrome.accent)
                }

                Text(memoCardLabel(for: template))
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Tighter card — was 154pt wide with a verbose blurb;
            // now icon + short verb. Three fit in a screen-width
            // scroll on 13 mini without horizontal scrolling.
            .frame(width: 120, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(runningWorkflowID != nil)
    }

    /// Short verb-phrase label for the memo workflow trigger card.
    /// Source templates have full sentences (`"Summarize this memo"`
    /// etc) that work in the Hub but read as wordy on the per-memo
    /// trigger card next to the icon. Map to 1-2 word forms.
    private func memoCardLabel(for template: WorkflowTemplate) -> String {
        switch template.id {
        case "memo-summary": return "Summarize"
        case "memo-tasks": return "Taskify"
        case "memo-reminders": return "Remind"
        default: return template.name
        }
    }

    /// Re-runs transcription via the store, which holds the
    /// underlying VoiceMemo entity. Useful when the original attempt
    /// produced 'No transcript yet.' or you want to redo the pass.
    private func retranscribe() {
        store.retranscribe()
        AppLogger.transcription.info("User-triggered retranscribe for memo \(store.memo.id)")
    }

    private func runMemoWorkflow(_ template: WorkflowTemplate) {
        guard runningWorkflowID == nil else { return }
        runningWorkflowID = template.id
        Task { @MainActor in
            await workflows.run(template: template, on: store.memo.title)
            runningWorkflowID = nil
        }
    }

    private func attachmentTile(_ attachment: MemoImageAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { previewAttachment = attachment }) {
                Group {
                    if let image = store.image(for: attachment) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            theme.colors.cardBackground
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            }
            .buttonStyle(.plain)

            Button(action: { store.removeAttachment(attachment) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.cardBackground)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 18, height: 18)
                    )
            }
            .buttonStyle(.plain)
            .padding(5)
        }
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) {
                store.removeAttachment(attachment)
            }
        }
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: MemoImageAttachment) -> some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text(attachment.originalName.uppercased())
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(attachment.formattedSize)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                if let image = store.image(for: attachment) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 16)
                } else {
                    Text("Could not load image.")
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer(minLength: 24)
            }
        }
    }

    private func openMemoReadAloud() {
        AppShellRouter.shared.openReadAloud(source: ReadAloudSource(
            title: store.memo.title,
            text: primaryMemoText,
            meta: "MEMO · \(wordCount) WORDS · \(store.memo.durationLabel)",
            sourceURL: nil
        ))
    }

    private func openMemoInCompose() {
        AppShellRouter.shared.openComposeSeeded(text: memoComposeSeedText)
    }

    private var canRefineMemo: Bool {
        !memoComposeSeedText.isEmpty
    }

    private var memoComposeSeedText: String {
        var parts: [String] = []
        let title = store.memo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = store.memo.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = normalizedTranscript

        if !title.isEmpty {
            parts.append(title)
        }
        if let summary, !summary.isEmpty {
            parts.append("Summary\n\(summary)")
        }
        if !transcript.isEmpty {
            parts.append(transcript)
        }

        return parts.joined(separator: "\n\n")
    }

    private var primaryMemoText: String {
        let transcript = normalizedTranscript
        if !transcript.isEmpty { return transcript }
        if let summary = store.memo.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        return store.memo.title
    }

    private var normalizedTranscript: String {
        let transcript = store.memo.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript == "No transcript yet." ? "" : transcript
    }

    private var wordCount: Int {
        normalizedTranscript.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var hasSentCurrentAttachmentsToMac: Bool {
        !store.attachmentFingerprint.isEmpty && lastSentAttachmentFingerprint == store.attachmentFingerprint
    }

    private var shouldShowAttachmentsSection: Bool {
        !store.attachments.isEmpty || isImportingAttachments || isRunningOCR || isSendingAttachmentsToMac || attachmentError != nil
    }

    private var attachmentBusyLabel: String {
        if isRunningOCR { return "SCANNING TEXT" }
        if isSendingAttachmentsToMac { return "SENDING TO MAC" }
        return "IMPORTING ATTACHMENTS"
    }

    private var workflowStatusSnapshot: [String: String] {
        Dictionary(uniqueKeysWithValues: store.workflowRuns.map { ($0.id, $0.status) })
    }

    private func pollWorkflowRuns() async {
        store.reloadWorkflowRuns()
        knownWorkflowStatuses = workflowStatusSnapshot

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { break }
            refreshWorkflowRunsForToast()
        }
    }

    private func refreshWorkflowRunsForToast() {
        let previous = knownWorkflowStatuses
        store.reloadWorkflowRuns()

        if let completedRun = store.workflowRuns.first(where: { run in
            let oldStatus = previous[run.id]
            guard run.isFinished else { return false }
            guard let oldStatus else { return !previous.isEmpty }
            return !Self.workflowStatusIsFinished(oldStatus) || oldStatus != run.status
        }) {
            showWorkflowToast(completedRun)
        }

        knownWorkflowStatuses = workflowStatusSnapshot
    }

    private func showWorkflowToast(_ run: VoiceMemoDetailStore.WorkflowRunDisplay) {
        workflowToast = run
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if workflowToast?.id == run.id {
                workflowToast = nil
            }
        }
    }

    private static func workflowStatusIsFinished(_ status: String) -> Bool {
        switch status.lowercased() {
        case "completed", "success", "succeeded", "failed", "failure", "error":
            return true
        default:
            return false
        }
    }

    private func beginTitleEdit() {
        editedTitle = store.memo.title
        titleEditError = nil
        isEditingTitle = true
        titleFieldFocused = true
    }

    private func cancelTitleEdit() {
        editedTitle = ""
        titleEditError = nil
        isEditingTitle = false
        titleFieldFocused = false
    }

    private func generateSmartTitle() {
        guard !isGeneratingTitle else { return }
        titleEditError = nil
        isGeneratingTitle = true

        Task { @MainActor in
            defer { isGeneratingTitle = false }
            do {
                let title = try await store.generateSmartTitle(using: aiService)
                editedTitle = title
                isEditingTitle = true
            } catch {
                titleEditError = error.localizedDescription
            }
        }
    }

    private func saveTitleEdit() {
        guard store.saveTitle(editedTitle) else {
            titleEditError = "Enter a title before saving."
            return
        }
        cancelTitleEdit()
    }

    private func beginTranscriptEdit() {
        editedTranscript = store.memo.transcript == "No transcript yet." ? "" : store.memo.transcript
        transcriptEditError = nil
        isEditingTranscript = true
    }

    private func cancelTranscriptEdit() {
        editedTranscript = ""
        transcriptEditError = nil
        isEditingTranscript = false
    }

    private func saveTranscriptEdit() {
        guard store.saveTranscript(editedTranscript) else {
            transcriptEditError = "Enter transcript text before saving."
            return
        }
        cancelTranscriptEdit()
    }

    // Inline editing: tap/Edit drops a caret in the words; Done commits.
    private func beginInlineTranscriptEdit() {
        beginTranscriptEdit()
        Haptics.confirm.fire()
        transcriptFieldFocused = true
    }

    private func commitTranscriptEdit() {
        transcriptFieldFocused = false
        // Done = commit. Auto-saves; if the field was emptied we just exit
        // (saveTranscript declines empty, leaving the prior text intact).
        _ = store.saveTranscript(editedTranscript)
        transcriptEditError = nil
        editedTranscript = ""
        isEditingTranscript = false
        Haptics.transition.fire()
    }

    private func importSelectedAttachmentItems(_ items: [PhotosPickerItem]) async {
        isImportingAttachments = true
        attachmentError = nil

        var importedCount = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                if store.addAttachment(data: data) != nil {
                    importedCount += 1
                }
            } catch {
                attachmentError = "Couldn’t import one of the selected images."
            }
        }

        selectedAttachmentItems = []
        isImportingAttachments = false

        if importedCount == 0 && attachmentError == nil {
            attachmentError = "No image data was available."
        }
    }

    private func importCapturedImage(_ image: UIImage) async {
        isImportingAttachments = true
        attachmentError = nil

        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92) else {
            isImportingAttachments = false
            attachmentError = "Couldn’t prepare the captured photo."
            return
        }

        let preferredName = "Camera_\(Int(Date().timeIntervalSince1970))"
        let saved = store.addAttachment(data: data, originalName: preferredName)
        isImportingAttachments = false

        if saved == nil {
            attachmentError = "Couldn’t attach the captured photo."
        }
    }

    private func performOCR(from pickerItem: PhotosPickerItem) async {
        guard let data = try? await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            attachmentError = "Couldn't load the selected image."
            return
        }

        isRunningOCR = true
        attachmentError = nil

        do {
            let result = try await ScreenshotOCRService.extractText(from: image)
            _ = store.addAttachment(
                data: data,
                originalName: "OCR_\(Int(Date().timeIntervalSince1970))"
            )
            isRunningOCR = false
            ocrResultText = result.text
        } catch {
            isRunningOCR = false
            attachmentError = error.localizedDescription
        }
    }

    private func appendOCRTextToNotes() {
        guard let text = ocrResultText else { return }
        if store.appendOCRTextToNotes(text) {
            ocrResultText = nil
            attachmentError = nil
        } else {
            attachmentError = "Couldn’t append scanned text to this memo."
        }
    }

    private func loadRecentAttachmentAssetsIfNeeded(force: Bool = false) {
        if hasLoadedRecentAttachmentAssets && !force { return }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        attachmentPhotoAuthorizationStatus = currentStatus

        switch currentStatus {
        case .authorized, .limited:
            hasLoadedRecentAttachmentAssets = true
            recentAttachmentAssets = fetchRecentAttachmentAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    attachmentPhotoAuthorizationStatus = status
                    if status == .authorized || status == .limited {
                        hasLoadedRecentAttachmentAssets = true
                        recentAttachmentAssets = fetchRecentAttachmentAssets()
                    } else {
                        recentAttachmentAssets = []
                    }
                }
            }
        default:
            recentAttachmentAssets = []
        }
    }

    private func fetchRecentAttachmentAssets(limit: Int = 12) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let screenshotCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )

        if let screenshots = screenshotCollections.firstObject {
            let screenshotAssets = PHAsset.fetchAssets(in: screenshots, options: options)
            if screenshotAssets.count > 0 {
                return screenshotAssets.objects(at: IndexSet(integersIn: 0..<screenshotAssets.count))
            }
        }

        let imageAssets = PHAsset.fetchAssets(with: .image, options: options)
        guard imageAssets.count > 0 else { return [] }
        return imageAssets.objects(at: IndexSet(integersIn: 0..<imageAssets.count))
    }

    private func importRecentAttachmentAsset(_ asset: PHAsset) async {
        isImportingAttachments = true
        attachmentError = nil

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<(Data, String?)?, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                let preferredName = asset.value(forKey: "filename") as? String
                continuation.resume(returning: data.map { ($0, preferredName) })
            }
        }

        guard let (data, preferredName) = result else {
            isImportingAttachments = false
            attachmentError = "That photo isn’t available on this iPhone yet."
            return
        }

        let saved = store.addAttachment(data: data, originalName: preferredName)
        isImportingAttachments = false

        if saved == nil {
            attachmentError = "Couldn’t attach that image."
        }
    }

    private func sendAttachmentsToPairedMac() {
        guard !isSendingAttachmentsToMac else { return }

        DirectMacRegistry.shared.refresh()

        guard let memoID = store.memoUUID?.uuidString, store.hasPersistentMemo else {
            presentSendToMacAlert(title: "To Mac", message: "This memo is not ready yet.")
            return
        }

        guard !store.attachments.isEmpty else {
            presentSendToMacAlert(title: "To Mac", message: "Add an attachment first.")
            return
        }

        guard BridgeManager.shared.isPaired else {
            let knownMacs = DirectMacRegistry.shared.macs
            let subtitle: String
            if knownMacs.contains(where: \.hasTerminalAccess) {
                subtitle = "This iPhone can reach your Mac for terminal access, but direct file send still needs Talkie Mac pairing."
            } else if !knownMacs.isEmpty {
                subtitle = "Direct send needs a Talkie Mac pairing on this iPhone."
            } else {
                subtitle = "Scan a Talkie Mac QR first to enable direct send."
            }
            presentSendToMacAlert(title: "To Mac", message: subtitle)
            return
        }

        let fingerprint = store.attachmentFingerprint
        isSendingAttachmentsToMac = true
        attachmentError = nil

        Task { @MainActor in
            do {
                let request = try store.buildAttachmentUploadRequest()
                let response = try await BridgeManager.shared.sendMemoAttachments(memoId: memoID, body: request)
                isSendingAttachmentsToMac = false
                lastSentAttachmentFingerprint = fingerprint

                let macName = BridgeManager.shared.pairedMacName ?? "your Mac"
                let noun = response.savedCount == 1 ? "attachment" : "attachments"
                presentSendToMacAlert(
                    title: "Sent to Mac",
                    message: "Sent \(response.savedCount) \(noun) directly to \(macName)."
                )
            } catch {
                isSendingAttachmentsToMac = false
                attachmentError = error.localizedDescription
                presentSendToMacAlert(title: "To Mac", message: error.localizedDescription)
            }
        }
    }

    private func presentSendToMacAlert(title: String, message: String) {
        sendToMacAlertTitle = title
        sendToMacAlertMessage = message
        showingSendToMacAlert = true
    }

    private func deleteMemo() {
        guard store.deleteMemo() else { return }
        AppShellRouter.shared.openHome()
    }
}

private struct VoiceMemoShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TranscriptVersionHistoryNext: View {
    let versions: [VoiceMemoDetailStore.TranscriptVersionDisplay]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if versions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(versions) { version in
                                TranscriptVersionRowNext(version: version)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .talkieType(.fieldLabel)
            .foregroundStyle(theme.colors.textSecondary)

            Spacer()

            Text("Version History")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text("\(versions.count)")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)

            Text("No version history")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Text("Saved transcript edits and system transcripts will appear here.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Spacer()
        }
    }
}

private struct TranscriptVersionRowNext: View {
    let version: VoiceMemoDetailStore.TranscriptVersionDisplay

    @ObservedObject private var theme = ThemeManager.shared
    @State private var isExpanded: Bool = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text("v\(version.version)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.colors.textPrimary)

                        if version.isLatest {
                            Text("CURRENT")
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(theme.currentTheme.chrome.accent.opacity(0.12))
                                )
                        }
                    }

                    Spacer()

                    Image(systemName: version.sourceIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.colors.textTertiary)
                }

                HStack(spacing: 6) {
                    Text(version.sourceDescription.uppercased())
                        .talkieType(.channelLabelTiny)
                    Text("·")
                        .talkieType(.channelLabelTiny)
                    Text(version.formattedDate)
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(theme.colors.textTertiary)

                Text(version.content)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineSpacing(4)
                    .lineLimit(isExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                if !isExpanded && version.content.count > 150 {
                    Text("TAP TO EXPAND")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        version.isLatest
                            ? theme.currentTheme.chrome.accent.opacity(0.07)
                            : theme.colors.cardBackground
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                version.isLatest
                                    ? theme.currentTheme.chrome.accent.opacity(0.35)
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = version.content
            }
        }
    }
}
