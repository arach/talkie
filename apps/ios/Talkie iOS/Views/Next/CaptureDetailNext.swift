//
//  CaptureDetailNext.swift
//  Talkie iOS
//
//  Port of CaptureDetailView (apps/ios/Talkie iOS/Views/
//  CaptureDetailView.swift, 983 lines). The donor structure:
//
//  - Optional photo thumbnail at the top (when capture is a scan/
//    photo with a loaded UIImage).
//  - "Content" card — eyebrow + selectable body text.
//  - "Details" card — Type / Words / Captured / Site (if bookmark) /
//    Shared Via (if bookmark) / Source URL (if any) / Mac Sync row
//    with synced badge or retry button + sync error.
//  - Bottom CaptureActionTray with Listen (routes to ReadAloud),
//    AI Commands sheet, Open in Compose.
//  - Toolbar: Done, Copy with checkmark feedback.
//
//  This port carries the visual shape and field set. Wires that
//  belong to Codex (image loading via MemoAttachmentStore, AI
//  commands sheet, Mac sync retry against BridgeManager) are
//  placeholders here.
//

import SwiftUI
import TalkieMobileKit

@MainActor
final class CaptureDetailStore: ObservableObject {
    @Published var capture: CaptureDisplay
    @Published private(set) var sourceCapture: Capture?
    @Published private(set) var captureImage: UIImage?
    @Published private(set) var audioURL: URL?
    @Published var isSyncing = false
    @Published var isLoadingTTS = false
    @Published var ttsError: String?

    private let captureID: UUID?

    struct CaptureDisplay {
        let id: String
        let kind: Kind
        let bodyText: String
        let wordCount: Int
        let typeLabel: String          // e.g. "Url", "Photo", "Text"
        let capturedAtLabel: String    // formatFullDate(capture.timestamp)
        let siteName: String?          // capture.bookmark?.siteName
        let sharedVia: String?         // bookmark source description
        let sourceURL: String?         // capture.sourceURL
        let syncedToMac: Bool
        let syncError: String?
        let hasImage: Bool

        enum Kind { case link, photo, text }
    }

    init(captureID: String?) {
        self.captureID = captureID.flatMap(UUID.init(uuidString:))
        self.capture = Self.mockCapture
        refresh()
    }

    func refresh() {
        guard let captureID else { return }
        CaptureStore.shared.reload()
        guard let loaded = CaptureStore.shared.all().first(where: { $0.id == captureID }) else { return }
        sourceCapture = loaded
        refreshLoadedAssets(for: loaded)
        capture = Self.display(from: loaded, syncError: capture.syncError, hasImage: captureImage != nil)
    }

    func retrySync() {
        guard !isSyncing, let sourceCapture else { return }
        setSyncError(nil)
        isSyncing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            var workingCapture = sourceCapture
            defer { isSyncing = false }

            if BridgeManager.shared.status != .connected {
                if BridgeManager.shared.isPaired {
                    setSyncError("Reconnecting to Mac…")
                    await BridgeManager.shared.retry()

                    guard BridgeManager.shared.status == .connected else {
                        setSyncError("Could not reach Mac — \(BridgeManager.shared.errorMessage ?? "check that Talkie is running on your Mac")")
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return
                    }
                    setSyncError(nil)
                } else {
                    setSyncError("Not paired — open Bridge settings to pair with your Mac")
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
            }

            var imageBase64: String?
            if let filename = workingCapture.imageFilename,
               let imageData = CaptureStore.shared.loadImageData(filename: filename) {
                imageBase64 = imageData.base64EncodedString()
            }

            let request = IngestRequest(
                sourceType: workingCapture.sourceType == "photo" ? "ocr" : workingCapture.sourceType,
                text: workingCapture.text,
                title: workingCapture.title,
                sourceURL: workingCapture.sourceURL,
                imageBase64: imageBase64,
                imageFilename: workingCapture.imageFilename,
                bookmarkCanonicalURL: workingCapture.bookmark?.canonicalURL,
                bookmarkHost: workingCapture.bookmark?.host,
                bookmarkSiteName: workingCapture.bookmark?.siteName,
                bookmarkSummary: workingCapture.bookmark?.summary,
                bookmarkImageURL: workingCapture.bookmark?.imageURL,
                sourceApplicationBundleID: workingCapture.bookmark?.sourceApplicationBundleID,
                sourceApplicationName: workingCapture.bookmark?.sourceApplicationName,
                sourceDevice: workingCapture.bookmark?.sourceDevice,
                ingestMethod: workingCapture.bookmark?.ingestionMethod
            )

            do {
                let response = try await BridgeManager.shared.client.ingestContent(body: request)
                if response.ok {
                    CaptureStore.shared.markSynced(workingCapture.id)
                    workingCapture.syncedToMac = true
                    self.sourceCapture = workingCapture
                    setSyncError(nil)
                    refresh()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    setSyncError(response.error ?? "Sync failed — Mac rejected the request")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                setSyncError("Could not reach Mac — \(error.localizedDescription)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    func updateCapture(title: String?, text: String) {
        guard let sourceCapture else { return }
        CaptureStore.shared.update(title: title, text: text, for: sourceCapture.id)
        refresh()
    }

    func deleteCapture() {
        guard let sourceCapture else { return }
        CaptureStore.shared.delete(sourceCapture)
    }

    private func refreshLoadedAssets(for capture: Capture) {
        captureImage = loadCaptureImage(for: capture)
        audioURL = CaptureStore.shared.audioURL(for: capture.id)
    }

    private func loadCaptureImage(for capture: Capture) -> UIImage? {
        guard let filename = capture.imageFilename,
              let imageData = CaptureStore.shared.loadImageData(filename: filename) else {
            return nil
        }
        return UIImage(data: imageData)
    }

    private func setSyncError(_ syncError: String?) {
        guard let sourceCapture else {
            capture = capture.withSyncError(syncError)
            return
        }
        capture = Self.display(from: sourceCapture, syncError: syncError, hasImage: capture.hasImage)
    }

    private static func display(from capture: Capture, syncError: String?, hasImage: Bool) -> CaptureDisplay {
        CaptureDisplay(
            id: capture.id.uuidString,
            kind: kind(for: capture),
            bodyText: capture.text,
            wordCount: capture.wordCount,
            typeLabel: capture.sourceType.capitalized,
            capturedAtLabel: formatFullDate(capture.timestamp),
            siteName: capture.bookmark?.siteName ?? capture.bookmark?.host,
            sharedVia: bookmarkSourceDescription(for: capture),
            sourceURL: capture.sourceURL,
            syncedToMac: capture.syncedToMac,
            syncError: syncError,
            hasImage: hasImage
        )
    }

    private static func kind(for capture: Capture) -> CaptureDisplay.Kind {
        switch capture.sourceType.lowercased() {
        case "url", "link": return .link
        case "photo", "scan", "ocr": return .photo
        default: return .text
        }
    }

    private static func bookmarkSourceDescription(for capture: Capture) -> String? {
        switch (capture.bookmark?.sourceApplicationName, capture.bookmark?.sourceDevice) {
        case let (applicationName?, sourceDevice?):
            return "\(applicationName) on \(sourceDevice)"
        case let (applicationName?, nil):
            return applicationName
        case let (nil, sourceDevice?):
            return sourceDevice
        case (nil, nil):
            return nil
        }
    }

    private static func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static let mockCapture = CaptureDisplay(
        id: "mock",
        kind: .link,
        bodyText: "We present a speculative decoding scheme for long-context inference that achieves up to 3.2× wall-clock speedup with no quality regression on standard benchmarks. The method generalizes to arbitrary autoregressive decoders and requires no fine-tuning.",
        wordCount: 38,
        typeLabel: "Url",
        capturedAtLabel: "May 18 · 9:12 AM",
        siteName: "arxiv.org",
        sharedVia: "Safari",
        sourceURL: "https://arxiv.org/abs/2403.09919",
        syncedToMac: true,
        syncError: nil,
        hasImage: false
    )
}

private extension CaptureDetailStore.CaptureDisplay {
    func withSyncError(_ syncError: String?) -> Self {
        .init(id: id, kind: kind, bodyText: bodyText, wordCount: wordCount, typeLabel: typeLabel, capturedAtLabel: capturedAtLabel, siteName: siteName, sharedVia: sharedVia, sourceURL: sourceURL, syncedToMac: syncedToMac, syncError: syncError, hasImage: hasImage)
    }
}

struct CaptureDetailNext: View {
    @EnvironmentObject private var chrome: ShellChrome
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store: CaptureDetailStore
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var speechService = SpeechSynthesisService.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var showCopied = false
    @State private var isShowingImageViewer = false
    @State private var aiCommandsCapture: Capture?
    @State private var pendingAICommandInstruction: String?
    @State private var isEditingCapture = false
    @State private var editedTitle = ""
    @State private var editedText = ""
    @State private var showingDeleteConfirmation = false

    init(captureID: String? = nil) {
        _store = StateObject(wrappedValue: CaptureDetailStore(captureID: captureID))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let image = store.captureImage {
                            photoThumb(image: image)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                        }

                        contentCard
                            .padding(.horizontal, 12)
                            .padding(.top, store.capture.hasImage ? 0 : 12)

                        detailsCard
                            .padding(.horizontal, 12)

                        if store.sourceCapture != nil {
                            CaptureAudioPlaybackCard(
                                title: store.capture.siteName ?? "Capture audio",
                                bodyText: store.capture.bodyText,
                                audioURL: store.audioURL,
                                isLoadingTTS: store.isLoadingTTS,
                                ttsError: store.ttsError,
                                audioPlayer: audioPlayer,
                                speechService: speechService,
                                appSettings: appSettings,
                                onGenerateTTS: requestTTS
                            )
                            .padding(.horizontal, 12)
                        }

                        actionTray
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                        Spacer(minLength: 120)   // breathing room above the chrome tray
                    }
                }
                .scrollIndicators(.hidden)
            }

            if isShowingImageViewer, let image = store.captureImage {
                CaptureDetailImageViewerNext(image: image) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingImageViewer = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isShowingImageViewer)
        .sheet(item: $aiCommandsCapture, onDismiss: {
            pendingAICommandInstruction = nil
            store.refresh()
        }) { capture in
            CaptureAICommandsSheet(capture: capture, initialInstruction: pendingAICommandInstruction) {
                store.refresh()
            }
        }
        .sheet(isPresented: $isEditingCapture) {
            CaptureEditSheetNext(
                title: $editedTitle,
                text: $editedText,
                onCancel: { isEditingCapture = false },
                onSave: saveEditedCapture
            )
        }
        .alert("Delete capture?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteCapture()
                audioPlayer.stopPlayback()
                speechService.stop()
                AppShellRouter.shared.openHome()
            }
        } message: {
            Text("This removes the capture and its stored image or audio files from this iPhone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
            store.refresh()
        }
        .onChange(of: store.audioURL) { _, newURL in
            audioPlayer.preloadDuration(for: newURL)
        }
        .onAppear {
            chrome.voiceCommandHandler = { transcript in
                pendingAICommandInstruction = transcript
                aiCommandsCapture = store.sourceCapture
            }
        }
        .onDisappear {
            chrome.voiceCommandHandler = { transcript in
                AppShellRouter.shared.submitVoiceCommand(transcript)
            }
            audioPlayer.stopPlayback()
            speechService.stop()
        }
    }

    // MARK: - Header (Done · Capture · Copy)

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                Text("Done")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Capture")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Button(action: copyText) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                    Text(showCopied ? "Copied" : "Copy")
                        .talkieType(.preview)
                }
                .foregroundStyle(showCopied ? .green : theme.currentTheme.chrome.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    // MARK: - Photo thumb (donor's CaptureDetailImageThumbnail)

    private func photoThumb(image: UIImage) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingImageViewer = true
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 180)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )

                Label("Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                    .talkieType(.hint)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityLabel("Open image viewer")
    }

    // MARK: - Content card

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· CONTENT")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)

            Text(store.capture.bodyText)
                .talkieType(.listTitle)
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textPrimary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Details card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("· DETAILS")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            metadataRow(icon: "tray.and.arrow.down", label: "Type",     value: store.capture.typeLabel)
            metadataRow(icon: "text.word.spacing",   label: "Words",    value: "\(store.capture.wordCount)")
            metadataRow(icon: "clock",               label: "Captured", value: store.capture.capturedAtLabel)
            if let site = store.capture.siteName {
                metadataRow(icon: "globe",           label: "Site",     value: site)
            }
            if let shared = store.capture.sharedVia {
                metadataRow(icon: "safari",          label: "Shared",   value: shared)
            }
            if let url = store.capture.sourceURL {
                metadataRow(icon: "link",            label: "Source",   value: url, monospaced: true)
            }

            macSyncRow
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
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

    private func metadataRow(icon: String, label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 16)

            Text(label)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .talkieType(monospaced ? .fieldValue : .preview)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var macSyncRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: store.capture.syncedToMac ? "checkmark.icloud" : "icloud.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundStyle(store.capture.syncedToMac ? .green : theme.colors.textTertiary)
                    .frame(width: 16)

                Text("Mac Sync")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer()

                if store.capture.syncedToMac {
                    Text("Synced")
                        .talkieType(.preview)
                        .foregroundStyle(.green)
                } else {
                    Button(action: { store.retrySync() }) {
                        HStack(spacing: 4) {
                            if store.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(store.isSyncing ? "Syncing…" : "Retry")
                                .talkieType(.preview)
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSyncing)
                }
            }
            if let err = store.capture.syncError {
                Text(err)
                    .talkieType(.hint)
                    .foregroundStyle(.red)
                    .padding(.leading, 26)
            }
        }
    }

    // MARK: - Action tray (Listen · AI commands · Compose)

    /// Inline action row — lives at the foot of the scrollable content,
    /// not pinned to the screen bottom. Stays close to the content
    /// instead of starting stacked on top of the chrome tray.
    private var actionTray: some View {
        HStack(spacing: 8) {
            trayChip(systemImage: "play.circle", label: "Listen") {
                AppShellRouter.shared.openReadAloud(source: ReadAloudSource(
                    title: store.capture.siteName ?? "Capture",
                    text: store.capture.bodyText,
                    meta: "CAPTURE · \(store.capture.wordCount) WORDS",
                    sourceURL: store.capture.sourceURL.flatMap(URL.init(string:))
                ))
            }
            trayChip(systemImage: "sparkles", label: "AI") {
                aiCommandsCapture = store.sourceCapture
            }
            trayChip(systemImage: "pencil", label: "Edit") {
                beginEditingCapture()
            }
            trayChip(systemImage: "trash", label: "Delete") {
                showingDeleteConfirmation = true
            }
            Spacer()
            primaryChip(label: "Compose ›") {
                AppShellRouter.shared.openCompose(documentID: store.capture.id)
            }
        }
    }

    private func trayChip(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 12))
                Text(label).talkieType(.fieldLabel)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule().strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                       lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func primaryChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.cardBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(theme.currentTheme.chrome.accent))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func beginEditingCapture() {
        guard let sourceCapture = store.sourceCapture else { return }
        editedTitle = sourceCapture.title ?? ""
        editedText = sourceCapture.text
        isEditingCapture = true
    }

    private func saveEditedCapture() {
        let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateCapture(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            text: trimmedText
        )
        isEditingCapture = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func requestTTS() {
        guard !store.isLoadingTTS, let capture = store.sourceCapture else { return }

        store.isLoadingTTS = true
        store.ttsError = nil
        speechService.stop()
        audioPlayer.stopPlayback()

        Task {
            defer {
                store.isLoadingTTS = false
            }

            do {
                let audioData = try await TTSService.synthesizeConfigured(
                    text: capture.text,
                    settings: appSettings
                )
                guard let url = CaptureStore.shared.saveAudio(audioData, id: capture.id) else {
                    store.ttsError = "Generated speech could not be saved."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                store.refresh()
                audioPlayer.playAudio(url: url)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                store.ttsError = "Couldn’t generate speech — \(error.localizedDescription)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func copyText() {
        UIPasteboard.general.string = store.capture.bodyText
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
        }
    }
}

private struct CaptureDetailImageViewerNext: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero
    @State private var showsHint = true

    private let maximumScale: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let scale = clampedScale(steadyScale * gestureScale)
            let offset = constrainedOffset(
                proposed: CGSize(
                    width: steadyOffset.width + gestureOffset.width,
                    height: steadyOffset.height + gestureOffset.height
                ),
                in: proxy.size,
                scale: scale
            )

            ZStack {
                Color.black
                    .ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: proxy.size, currentScale: scale))
                    .simultaneousGesture(magnifyGesture(in: proxy.size))
                    .onTapGesture(count: 2) {
                        toggleZoom()
                    }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        if scale > 1.01 {
                            Button("Reset", systemImage: "arrow.counterclockwise") {
                                showsHint = false
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    resetZoom()
                                }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.52), in: Capsule())
                        }

                        Spacer()

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.52), in: Circle())
                        }
                        .accessibilityLabel("Close image viewer")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Spacer()

                    if showsHint {
                        Text("Pinch to zoom. Drag to pan. Double-tap to reset.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, 24)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private func magnifyGesture(in containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                showsHint = false
                gestureScale = value.magnification
            }
            .onEnded { value in
                let nextScale = clampedScale(steadyScale * value.magnification)
                let proposedOffset = CGSize(
                    width: steadyOffset.width + gestureOffset.width,
                    height: steadyOffset.height + gestureOffset.height
                )

                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    steadyScale = nextScale
                    steadyOffset = nextScale <= 1.01
                        ? .zero
                        : constrainedOffset(proposed: proposedOffset, in: containerSize, scale: nextScale)
                    gestureScale = 1
                    gestureOffset = .zero
                }
            }
    }

    private func dragGesture(in containerSize: CGSize, currentScale: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard currentScale > 1.01 else { return }
                showsHint = false
                gestureOffset = value.translation
            }
            .onEnded { value in
                guard currentScale > 1.01 else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        steadyOffset = .zero
                        gestureOffset = .zero
                    }
                    return
                }

                let proposedOffset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )

                withAnimation(.easeInOut(duration: 0.18)) {
                    steadyOffset = constrainedOffset(proposed: proposedOffset, in: containerSize, scale: currentScale)
                    gestureOffset = .zero
                }
            }
    }

    private func toggleZoom() {
        showsHint = false

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if steadyScale > 1.01 {
                resetZoom()
            } else {
                steadyScale = 2
                gestureScale = 1
                steadyOffset = .zero
                gestureOffset = .zero
            }
        }
    }

    private func resetZoom() {
        steadyScale = 1
        gestureScale = 1
        steadyOffset = .zero
        gestureOffset = .zero
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 1), maximumScale)
    }

    private func constrainedOffset(proposed: CGSize, in containerSize: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 1.01 else { return .zero }

        let fittedSize = fittedImageSize(in: containerSize)
        let scaledSize = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        let horizontalLimit = max(0, (scaledSize.width - containerSize.width) / 2)
        let verticalLimit = max(0, (scaledSize.height - containerSize.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposed.height, -verticalLimit), verticalLimit)
        )
    }

    private func fittedImageSize(in containerSize: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return containerSize }

        let widthScale = containerSize.width / image.size.width
        let heightScale = containerSize.height / image.size.height
        let scale = min(widthScale, heightScale)

        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}

private struct CaptureEditSheetNext: View {
    @Binding var title: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @FocusState private var isTextFocused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)

                    TextField("Optional title", text: $title)
                        .talkieType(.preview)
                        .textInputAutocapitalization(.sentences)
                        .padding(12)
                        .background(theme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Content")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                        Spacer()
                        Text("\(wordCount(text)) words")
                            .talkieType(.hint)
                            .foregroundStyle(theme.colors.textTertiary)
                    }

                    TextEditor(text: $text)
                        .focused($isTextFocused)
                        .scrollContentBackground(.hidden)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(10)
                        .frame(minHeight: 280)
                        .background(theme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle("Edit Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                isTextFocused = true
            }
        }
    }

    private func wordCount(_ value: String) -> Int {
        value.split { $0.isWhitespace || $0.isNewline }.count
    }
}

private struct CaptureAudioPlaybackCard: View {
    let title: String
    let bodyText: String
    let audioURL: URL?
    let isLoadingTTS: Bool
    let ttsError: String?
    @ObservedObject var audioPlayer: AudioPlayerManager
    let speechService: SpeechSynthesisService
    let appSettings: TalkieAppSettings
    let onGenerateTTS: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private var hasCloudAudio: Bool { audioURL != nil }
    private var canGenerateCloudTTS: Bool {
        TTSService.canSynthesizeConfiguredAudio(
            settings: appSettings,
            bridgeStatus: BridgeManager.shared.status
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: hasCloudAudio ? "waveform" : "speaker.wave.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.currentTheme.chrome.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasCloudAudio ? "Capture audio" : "Read aloud")
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(hasCloudAudio ? title : "On-device voice with optional generated audio")
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                CapturePlaybackSpeedMenuNext(
                    selectedRate: appSettings.ttsPlaybackRate,
                    onSelect: updatePlaybackRate
                )
            }

            if hasCloudAudio {
                cloudPlaybackBar
                cloudControlsRow
            } else {
                localControlsRow
            }

            if let ttsError {
                Text(ttsError)
                    .talkieType(.hint)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
        .onAppear {
            applyPlaybackRate(appSettings.ttsPlaybackRate)
        }
        .onChange(of: appSettings.ttsPlaybackRate) { _, newRate in
            applyPlaybackRate(newRate)
        }
    }

    private var cloudPlaybackBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.colors.textTertiary.opacity(0.22))
                    .frame(height: 4)

                Capsule()
                    .fill(theme.currentTheme.chrome.accent)
                    .frame(width: geometry.size.width * playbackProgress, height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        seekCloudAudio(at: value.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 12)
    }

    private var cloudControlsRow: some View {
        HStack(spacing: 12) {
            Text(formatDuration(displayedCurrentTime))
                .talkieType(.hint)
                .foregroundStyle(theme.colors.textTertiary)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .leading)

            Spacer()

            Button {
                if let audioURL {
                    speechService.stop()
                    audioPlayer.togglePlayPause(url: audioURL)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(audioPlayer.isPlaying ? theme.colors.cardBackground : theme.colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(audioPlayer.isPlaying ? theme.currentTheme.chrome.accent : theme.colors.background)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioPlayer.isPlaying ? "Pause capture audio" : "Play capture audio")

            Spacer()

            Text(formatDuration(audioPlayer.duration))
                .talkieType(.hint)
                .foregroundStyle(theme.colors.textTertiary)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
        }
    }

    private var localControlsRow: some View {
        HStack(spacing: 12) {
            Button {
                audioPlayer.stopPlayback()
                speechService.toggleReadout(bodyText)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: speechService.isSpeaking ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(speechService.isSpeaking ? .orange : theme.colors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(speechService.isSpeaking ? Color.orange.opacity(0.14) : theme.colors.background)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speechService.isSpeaking ? "Stop reading capture" : "Read capture aloud")

            VStack(alignment: .leading, spacing: 3) {
                Text(speechService.isSpeaking ? "Reading aloud…" : "On-device voice")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
                if speechService.isSpeaking {
                    CaptureReadoutPulseBarNext()
                        .frame(maxWidth: 128)
                } else {
                    Text(canGenerateCloudTTS ? "Generate reusable audio when you want a scrubber." : "Pair Mac or configure TTS to generate audio.")
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }

            Spacer()

            if canGenerateCloudTTS && !speechService.isSpeaking {
                Button(action: onGenerateTTS) {
                    HStack(spacing: 6) {
                        if isLoadingTTS {
                            ProgressView()
                                .scaleEffect(0.68)
                        } else {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                        }

                        Text(isLoadingTTS ? "Generating…" : "Generate")
                            .talkieType(.fieldLabel)
                    }
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingTTS)
            }
        }
    }

    private var displayedCurrentTime: TimeInterval {
        audioPlayer.currentPlayingURL == audioURL ? audioPlayer.currentTime : 0
    }

    private var playbackProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(max(displayedCurrentTime / audioPlayer.duration, 0), 1)
    }

    private func seekCloudAudio(at locationX: CGFloat, width: CGFloat) {
        guard width > 0, audioPlayer.duration > 0 else { return }
        let fraction = min(max(locationX / width, 0), 1)
        let targetTime = audioPlayer.duration * Double(fraction)

        if audioPlayer.isPlaying {
            audioPlayer.seek(to: targetTime)
        } else if let audioURL {
            speechService.stop()
            audioPlayer.playAudio(url: audioURL)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                audioPlayer.seek(to: targetTime)
            }
        }
    }

    private func updatePlaybackRate(_ rate: Double) {
        appSettings.ttsPlaybackRate = rate
        applyPlaybackRate(rate)
    }

    private func applyPlaybackRate(_ rate: Double) {
        audioPlayer.setPlaybackRate(Float(rate))
        speechService.setPlaybackRate(Float(rate))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        let paddedSeconds = remainingSeconds < 10 ? "0\(remainingSeconds)" : "\(remainingSeconds)"
        return "\(minutes):\(paddedSeconds)"
    }
}

private struct CapturePlaybackSpeedMenuNext: View {
    let selectedRate: Double
    let onSelect: (Double) -> Void

    @ObservedObject private var theme = ThemeManager.shared
    private let rates = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Menu {
            ForEach(rates, id: \.self) { rate in
                Button {
                    onSelect(rate)
                } label: {
                    if selectedRate == rate {
                        Label(label(for: rate), systemImage: "checkmark")
                    } else {
                        Text(label(for: rate))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.system(size: 10, weight: .semibold))

                Text(label(for: selectedRate))
                    .talkieType(.hint)
                    .monospacedDigit()
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.colors.background, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
    }

    private func label(for rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0 ... 2))))x"
    }
}

private struct CaptureReadoutPulseBarNext: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.28))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * 0.3, height: 3)
                        .offset(x: animate ? geometry.size.width * 0.7 : 0)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: animate
                        )
                }
        }
        .frame(height: 3)
        .onAppear { animate = true }
    }
}
