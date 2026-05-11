//
//  CaptureDetailView.swift
//  Talkie iOS
//
//  Detail view for a captured item (shared content).
//

import SwiftUI
import TalkieMobileKit

struct CaptureDetailView: View {
    @State var capture: Capture
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedFeedback = false
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var captureImage: UIImage?
    @State private var audioURL: URL?
    @State private var isLoadingTTS = false
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var isShowingImageViewer = false
    @State private var isShowingAICommands = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Photo thumbnail if available
                        if let captureImage {
                            CaptureDetailImageThumbnail(image: captureImage) {
                                withAnimation(TalkieAnimation.fast) {
                                    isShowingImageViewer = true
                                }
                            }
                        }

                        // Main text
                        Text(capture.text)
                            .font(.body)
                            .foregroundColor(.textPrimary)
                            .textSelection(.enabled)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(12)

                        // Metadata
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            metadataRow(icon: "tray.and.arrow.down", label: "Type", value: capture.sourceType.capitalized)
                            metadataRow(icon: "text.word.spacing", label: "Words", value: "\(capture.wordCount)")
                            metadataRow(icon: "clock", label: "Captured", value: formatFullDate(capture.timestamp))
                            if let siteName = capture.bookmark?.siteName ?? capture.bookmark?.host {
                                metadataRow(icon: "globe", label: "Site", value: siteName)
                            }
                            if let sourceDescription = bookmarkSourceDescription {
                                metadataRow(icon: "safari", label: "Shared Via", value: sourceDescription)
                            }
                            if let url = capture.sourceURL {
                                metadataRow(icon: "link", label: "Source", value: url)
                            }
                            VStack(spacing: Spacing.xs) {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: capture.syncedToMac ? "checkmark.icloud" : "icloud.and.arrow.up")
                                        .font(.system(size: 12))
                                        .foregroundColor(capture.syncedToMac ? .success : .textTertiary)
                                        .frame(width: 16)

                                    Text("Mac Sync")
                                        .font(.system(size: 13))
                                        .foregroundColor(.textSecondary)

                                    Spacer()

                                    if capture.syncedToMac {
                                        Text("Synced")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.success)
                                    } else {
                                        Button {
                                            retrySync()
                                        } label: {
                                            HStack(spacing: 4) {
                                                if isSyncing {
                                                    ProgressView()
                                                        .scaleEffect(0.6)
                                                        .frame(width: 14, height: 14)
                                                } else {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                Text(isSyncing ? "Syncing…" : "Retry")
                                                    .font(.system(size: 13, weight: .medium))
                                            }
                                            .foregroundColor(.orange)
                                        }
                                        .disabled(isSyncing)
                                    }
                                }

                                if let syncError {
                                    Text(syncError)
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 16 + Spacing.sm)
                                }
                            }
                        }
                        .padding(Spacing.md)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(12)

                        Spacer()
                    }
                    .padding(Spacing.md)
                }

                if isShowingImageViewer, let captureImage {
                    CaptureDetailImageViewer(image: captureImage) {
                        withAnimation(TalkieAnimation.fast) {
                            isShowingImageViewer = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !capture.text.isEmpty && !isShowingImageViewer {
                    CaptureActionTray(
                        capture: capture,
                        audioPlayer: audioPlayer,
                        audioURL: audioURL,
                        isLoadingTTS: isLoadingTTS,
                        onRequestTTS: requestTTS,
                        onOpenAICommands: openAICommands
                    )
                }
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        audioPlayer.stopPlayback()
                        SpeechSynthesisService.shared.stop()
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: copyText) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            Text(showCopiedFeedback ? "Copied" : "Copy")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(showCopiedFeedback ? .success : .accentColor)
                    }
                }
            }
            .onAppear {
                refreshLoadedAssets()
            }
            .onChange(of: audioURL) { _, newURL in
                audioPlayer.preloadDuration(for: newURL)
            }
            .onDisappear {
                audioPlayer.stopPlayback()
                SpeechSynthesisService.shared.stop()
            }
            .sheet(isPresented: $isShowingAICommands) {
                CaptureAICommandsSheet(capture: capture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
                // Refresh sync status and audio availability
                CaptureStore.shared.reload()
                if let updated = CaptureStore.shared.all().first(where: { $0.id == capture.id }) {
                    capture = updated
                }
                refreshLoadedAssets()
            }
        }
    }

    // MARK: - Sync Retry

    private func retrySync() {
        guard !isSyncing else { return }
        syncError = nil
        isSyncing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            defer { isSyncing = false }

            // If bridge isn't connected, try to connect first
            if BridgeManager.shared.status != .connected {
                if BridgeManager.shared.isPaired {
                    syncError = "Reconnecting to Mac…"
                    await BridgeManager.shared.retry()

                    guard BridgeManager.shared.status == .connected else {
                        syncError = "Could not reach Mac — \(BridgeManager.shared.errorMessage ?? "check that Talkie is running on your Mac")"
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return
                    }
                    syncError = nil
                } else {
                    syncError = "Not paired — open Bridge settings to pair with your Mac"
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
            }

            var imageBase64: String?
            if let filename = capture.imageFilename,
               let imageData = CaptureStore.shared.loadImageData(filename: filename) {
                imageBase64 = imageData.base64EncodedString()
            }

            let request = IngestRequest(
                sourceType: capture.sourceType == "photo" ? "ocr" : capture.sourceType,
                text: capture.text,
                title: capture.title,
                sourceURL: capture.sourceURL,
                imageBase64: imageBase64,
                imageFilename: capture.imageFilename,
                bookmarkCanonicalURL: capture.bookmark?.canonicalURL,
                bookmarkHost: capture.bookmark?.host,
                bookmarkSiteName: capture.bookmark?.siteName,
                bookmarkSummary: capture.bookmark?.summary,
                bookmarkImageURL: capture.bookmark?.imageURL,
                sourceApplicationBundleID: capture.bookmark?.sourceApplicationBundleID,
                sourceApplicationName: capture.bookmark?.sourceApplicationName,
                sourceDevice: capture.bookmark?.sourceDevice,
                ingestMethod: capture.bookmark?.ingestionMethod
            )

            do {
                let response = try await BridgeManager.shared.client.ingestContent(body: request)
                if response.ok {
                    CaptureStore.shared.markSynced(capture.id)
                    capture.syncedToMac = true
                    syncError = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    syncError = response.error ?? "Sync failed — Mac rejected the request"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                syncError = "Could not reach Mac — \(error.localizedDescription)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - TTS

    private func requestTTS() {
        guard !isLoadingTTS else { return }

        isLoadingTTS = true
        Task {
            defer { isLoadingTTS = false }
            do {
                let audioData = try await TTSService.synthesizeConfigured(text: capture.text)

                if let url = CaptureStore.shared.saveAudio(audioData, id: capture.id) {
                    audioURL = url
                    audioPlayer.playAudio(url: url)
                }
            } catch {
                AppLogger.app.warning("TTS request failed: \(error.localizedDescription)")
            }
        }
    }

    private func openAICommands() {
        audioPlayer.stopPlayback()
        SpeechSynthesisService.shared.stop()
        isShowingAICommands = true
    }

    // MARK: - Helpers

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
        }
    }

    private func refreshLoadedAssets() {
        captureImage = loadCaptureImage()
        audioURL = CaptureStore.shared.audioURL(for: capture.id)
    }

    private var bookmarkSourceDescription: String? {
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

    private func loadCaptureImage() -> UIImage? {
        guard let filename = capture.imageFilename,
              let imageData = CaptureStore.shared.loadImageData(filename: filename) else {
            return nil
        }

        return UIImage(data: imageData)
    }

    private func copyText() {
        UIPasteboard.general.string = capture.text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { showCopiedFeedback = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedFeedback = false }
        }
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct CaptureDetailImageThumbnail: View {
    let image: UIImage
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 200)
                    .clipShape(.rect(cornerRadius: CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .strokeBorder(Color.borderPrimary.opacity(0.3), lineWidth: 0.5)
                    }

                Label("Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(Spacing.sm)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: CornerRadius.md))
        .accessibilityLabel("Open image viewer")
    }
}

private struct CaptureDetailImageViewer: View {
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
                    .aspectRatio(contentMode: .fit)
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
                    HStack(spacing: Spacing.sm) {
                        if scale > 1.01 {
                            Button("Reset", systemImage: "arrow.counterclockwise") {
                                showsHint = false
                                withAnimation(TalkieAnimation.spring) {
                                    resetZoom()
                                }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.5), in: Capsule())
                        }

                        Spacer()

                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)

                    Spacer()

                    if showsHint {
                        Text("Pinch to zoom. Drag to pan. Double-tap to reset.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, Spacing.xl)
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

                withAnimation(TalkieAnimation.spring) {
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
                    withAnimation(TalkieAnimation.fast) {
                        steadyOffset = .zero
                        gestureOffset = .zero
                    }
                    return
                }

                let proposedOffset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )

                withAnimation(TalkieAnimation.fast) {
                    steadyOffset = constrainedOffset(proposed: proposedOffset, in: containerSize, scale: currentScale)
                    gestureOffset = .zero
                }
            }
    }

    private func toggleZoom() {
        showsHint = false

        withAnimation(TalkieAnimation.spring) {
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

// MARK: - Player Bar

/// Bottom action tray with two modes:
/// 1. Cloud audio available → fixed playback tray with thin scrubber
/// 2. No audio → on-device TTS fallback + "Generate" button
struct CaptureActionTray: View {
    let capture: Capture
    @ObservedObject var audioPlayer: AudioPlayerManager
    let audioURL: URL?
    let isLoadingTTS: Bool
    let onRequestTTS: () -> Void
    let onOpenAICommands: () -> Void
    @State private var appSettings = TalkieAppSettings.shared
    @State private var speechService = SpeechSynthesisService.shared

    var hasCloudAudio: Bool { audioURL != nil }

    private var canGenerateCloudTTS: Bool {
        TTSService.canSynthesizeConfiguredAudio(
            settings: appSettings,
            bridgeStatus: BridgeManager.shared.status
        )
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            aiCommandsButton

            if hasCloudAudio {
                cloudPlaybackBar
            }

            controlRow
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            BottomTrayBackground()
        }
        .onAppear {
            applyPlaybackRate(appSettings.ttsPlaybackRate)
        }
        .onChange(of: appSettings.ttsPlaybackRate) { _, newRate in
            applyPlaybackRate(newRate)
        }
    }

    private var aiCommandsButton: some View {
        Button(action: onOpenAICommands) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Commands")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Summarize, explain, or ask something about this capture.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surfaceSecondary)
            .clipShape(.rect(cornerRadius: CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.borderPrimary.opacity(0.8), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
    }

    private var controlRow: some View {
        Group {
            if hasCloudAudio {
                cloudControlsRow
            } else {
                localPlayerBar
            }
        }
    }

    // MARK: - Cloud Audio Player

    private var cloudPlaybackBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.textTertiary.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.active)
                    .frame(width: geo.size.width * playbackProgress, height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard audioPlayer.duration > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        let targetTime = audioPlayer.duration * Double(fraction)
                        if audioPlayer.isPlaying {
                            audioPlayer.seek(to: targetTime)
                        } else if let url = audioURL {
                            audioPlayer.playAudio(url: url)
                            Task {
                                try? await Task.sleep(for: .milliseconds(50))
                                audioPlayer.seek(to: targetTime)
                            }
                        }
                    }
            )
        }
        .frame(height: 12)
    }

    private var playbackProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return displayedCurrentTime / audioPlayer.duration
    }

    private var cloudControlsRow: some View {
        ZStack {
            HStack(spacing: Spacing.md) {
                Text("0:00")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.textTertiary)
                    .frame(minWidth: 40, alignment: .leading)

                Spacer()

                Text(formatDuration(audioPlayer.duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.textTertiary)
                    .frame(minWidth: 40, alignment: .trailing)
            }

            HStack(spacing: Spacing.sm) {
                compactPlaybackSpeedMenu
                    .hidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                playbackButton

                compactPlaybackSpeedMenu
            }
        }
    }

    private var compactPlaybackSpeedMenu: some View {
        PlaybackSpeedMenu(
            selectedRate: appSettings.ttsPlaybackRate,
            onSelect: updatePlaybackRate,
            isCompact: true
        )
    }

    private var playbackButton: some View {
        Button {
            if let url = audioURL {
                audioPlayer.togglePlayPause(url: url)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(audioPlayer.isPlaying ? Color.active : Color.surfaceTertiary)
                    .frame(width: 40, height: 40)

                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(audioPlayer.isPlaying ? .white : .textPrimary)
                    .offset(x: audioPlayer.isPlaying ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Local TTS Fallback

    private var localPlayerBar: some View {
        HStack(spacing: Spacing.md) {
            // On-device play/stop
            Button {
                speechService.toggleReadout(capture.text)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack {
                    Circle()
                        .fill(speechService.isSpeaking ? Color.orange.opacity(0.15) : Color.surfaceTertiary)
                        .frame(width: 44, height: 44)

                    Image(systemName: speechService.isSpeaking ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(speechService.isSpeaking ? .orange : .textSecondary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if speechService.isSpeaking {
                    Text("Reading aloud…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                    ReadoutPulseBar()
                } else {
                    Text("On-device voice")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("Tap play, or generate audio")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                // Generate TTS button — show if Bridge connected OR direct TTS configured
                if canGenerateCloudTTS && !speechService.isSpeaking {
                    Button(action: onRequestTTS) {
                        if isLoadingTTS {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 28, height: 28)
                        } else {
                            Label("Generate", systemImage: "waveform.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.surfaceTertiary)
                                .clipShape(Capsule())
                        }
                    }
                    .disabled(isLoadingTTS)
                }
            }
        }
    }

    private var displayedCurrentTime: TimeInterval {
        audioPlayer.currentPlayingURL == audioURL ? audioPlayer.currentTime : 0
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        let paddedSeconds = remainingSeconds < 10 ? "0\(remainingSeconds)" : "\(remainingSeconds)"
        return "\(minutes):\(paddedSeconds)"
    }

    private func updatePlaybackRate(_ rate: Double) {
        appSettings.ttsPlaybackRate = rate
        applyPlaybackRate(rate)
    }

    private func applyPlaybackRate(_ rate: Double) {
        audioPlayer.setPlaybackRate(Float(rate))
        speechService.setPlaybackRate(Float(rate))
    }
}

private struct PlaybackSpeedMenu: View {
    let selectedRate: Double
    let onSelect: (Double) -> Void
    var isCompact = false

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
                if !isCompact {
                    Image(systemName: "speedometer")
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(label(for: selectedRate))
                    .font(
                        .system(size: isCompact ? 11 : 12, weight: .semibold)
                            .monospacedDigit()
                    )
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, isCompact ? 8 : 10)
            .padding(.vertical, isCompact ? 6 : 8)
            .background(Color.surfaceTertiary)
            .clipShape(Capsule())
        }
        .contentShape(Capsule())
    }

    private func label(for rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0 ... 2))))x"
    }
}

/// Animated pulse bar shown during on-device TTS playback
struct ReadoutPulseBar: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.3))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: geo.size.width * 0.3, height: 3)
                        .offset(x: animate ? geo.size.width * 0.7 : 0)
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
