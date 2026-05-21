//
//  VoiceMemoDetailNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — Next-style memo detail. Header + waveform
//  + playback transport + transcript + actions.
//

import Combine
import CoreData
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class VoiceMemoDetailStore: ObservableObject {
    @Published var memo: MemoDisplay
    @Published var attachments: [MemoImageAttachment] = []
    @Published var transcriptVersions: [TranscriptVersionDisplay] = []

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
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store: VoiceMemoDetailStore
    @StateObject private var aiService = OnDeviceAIService.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var isPickerActive: Bool = false
    @State private var previewAttachment: MemoImageAttachment?
    @State private var isEditingTitle: Bool = false
    @State private var editedTitle: String = ""
    @State private var titleEditError: String?
    @State private var isGeneratingTitle: Bool = false
    @State private var isEditingTranscript: Bool = false
    @State private var editedTranscript: String = ""
    @State private var transcriptEditError: String?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var showingCLISheet: Bool = false
    @State private var showingVersionHistory: Bool = false
    @FocusState private var titleFieldFocused: Bool

    init(memoID: String? = nil) {
        _store = StateObject(wrappedValue: VoiceMemoDetailStore(memoID: memoID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    metaRow
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    playbackCard
                        .padding(.horizontal, 12)

                    // NOTE: Legacy VoiceMemoDetailView surfaces a lot
                    // more — version history, reminders, mac workflows,
                    // and OCR. Parity slices now restore title/transcript
                    // editing, sharing, and memo-scoped CLI commands.

                    transcriptSection
                        .padding(.horizontal, 12)

                    attachmentsSection
                        .padding(.horizontal, 12)

                    actionBar
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    Spacer(minLength: 120)   // breathing room above the chrome tray
                }
            }
            .scrollIndicators(.hidden)
        }
        .photosPicker(isPresented: $isPickerActive, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    _ = store.addAttachment(data: data)
                }
                pickerItem = nil
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            attachmentPreview(attachment)
        }
        .sheet(isPresented: $isEditingTranscript) {
            transcriptEditorSheet
        }
        .sheet(isPresented: $showingShareSheet) {
            VoiceMemoShareSheet(items: store.shareItems())
        }
        .sheet(isPresented: $showingCLISheet) {
            MemoCLISheetNext(memo: store.memo)
        }
        .sheet(isPresented: $showingVersionHistory) {
            TranscriptVersionHistoryNext(versions: store.transcriptVersions)
        }
        .alert("Delete memo?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteMemo)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the memo, its audio file, and saved attachments from this device.")
        }
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

            Spacer()

            Text("Memo")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Menu {
                Button("Share", systemImage: "square.and.arrow.up") {
                    showingShareSheet = true
                }
                Button("Run CLI", systemImage: "terminal") {
                    showingCLISheet = true
                }
                if store.hasTranscriptVersionHistory {
                    Button("Version history", systemImage: "clock.arrow.circlepath") {
                        showingVersionHistory = true
                    }
                }
                if store.canEditTranscript {
                    Button("Edit transcript", systemImage: "text.quote", action: beginTranscriptEdit)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditingTitle {
                titleEditor
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.memo.title)
                        .talkieType(.headline)
                        .foregroundStyle(theme.colors.textPrimary)

                    if store.canEditTitle {
                        Button(action: beginTitleEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                                .accessibilityLabel("Edit title")
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("· MEMO · \(store.memo.createdAtLabel.uppercased()) · \(store.memo.durationLabel)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
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

    /// Matches the donor's `transcriptInstrumentPlayer` — a single
    /// compact horizontal rail: play button (30pt circle, accent
    /// fill when playing) + InteractiveWaveformView (28pt with
    /// played/unplayed coloring) + monospaced "current / total"
    /// time readout right-aligned.
    private var playbackCard: some View {
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
                .frame(width: 78, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· TRANSCRIPT")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                if store.canEditTranscript {
                    Button(action: beginTranscriptEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                            Text("EDIT")
                                .talkieType(.channelLabelTiny)
                        }
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit transcript")
                }
                Text("\(wordCount) WORDS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 4)

            Text(store.memo.transcript)
                .talkieType(.listTitle)
                .lineSpacing(5)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.colors.cardBackground).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)))
                .contextMenu {
                    if store.hasTranscriptVersionHistory {
                        Button("Version History", systemImage: "clock.arrow.circlepath") {
                            showingVersionHistory = true
                        }
                    }
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = store.memo.transcript
                    }
                }
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
                Button(action: { isPickerActive = true }) {
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

            if store.attachments.isEmpty {
                emptyAttachmentsTile
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(store.attachments) { attachment in
                        attachmentTile(attachment)
                    }
                }
            }
        }
    }

    private var emptyAttachmentsTile: some View {
        Button(action: { isPickerActive = true }) {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Add screenshots or photos")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Keep visual context with the memo.")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                theme.currentTheme.chrome.edgeFaint,
                                style: StrokeStyle(
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth,
                                    dash: [5, 3]
                                )
                            )
                    )
            )
        }
        .buttonStyle(.plain)
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

    /// Inline action row — lives at the foot of the scrollable content
    /// rather than pinned to the screen bottom. Short memos: chips
    /// sit right under the transcript card. Long memos: chips scroll
    /// to the bottom of the content. Either way they never start
    /// stacked on top of the chrome tray.
    private var actionBar: some View {
        HStack(spacing: 8) {
            actionChip(label: "Share", isPrimary: false) {
                showingShareSheet = true
            }
            actionChip(label: "Listen", isPrimary: false) {
                AppShellRouter.shared.openReadAloud(source: ReadAloudSource(
                    title: store.memo.title,
                    text: store.memo.transcript,
                    meta: "MEMO · \(wordCount) WORDS · \(store.memo.durationLabel)",
                    sourceURL: nil
                ))
            }
            actionChip(label: "CLI", isPrimary: false) {
                showingCLISheet = true
            }
            actionChip(label: "Refine ›", isPrimary: true) { AppShellRouter.shared.openCompose(documentID: store.memo.id) }
        }
    }

    private func actionChip(label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(isPrimary ? theme.colors.cardBackground : theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(isPrimary ? theme.currentTheme.chrome.accent : Color.clear).overlay(Capsule().strokeBorder(isPrimary ? Color.clear : theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)))
        }
        .buttonStyle(.plain)
    }

    private var wordCount: Int {
        store.memo.transcript.split { $0.isWhitespace || $0.isNewline }.count
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
