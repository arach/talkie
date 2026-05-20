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
    @Published var isSyncing = false

    private let captureID: UUID?
    private var captureImage: UIImage?

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

    private func refreshLoadedAssets(for capture: Capture) {
        captureImage = loadCaptureImage(for: capture)
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
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store: CaptureDetailStore
    @State private var showCopied = false
    @State private var aiCommandsCapture: Capture?

    init(captureID: String? = nil) {
        _store = StateObject(wrappedValue: CaptureDetailStore(captureID: captureID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.capture.hasImage {
                        photoThumb
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                    }

                    contentCard
                        .padding(.horizontal, 12)
                        .padding(.top, store.capture.hasImage ? 0 : 12)

                    detailsCard
                        .padding(.horizontal, 12)

                    actionTray
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    Spacer(minLength: 120)   // breathing room above the chrome tray
                }
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $aiCommandsCapture) { capture in
            CaptureAICommandsSheet(capture: capture)
        }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
            store.refresh()
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

    private var photoThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            Image(systemName: "photo")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(height: 180)
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

    private func copyText() {
        UIPasteboard.general.string = store.capture.bodyText
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
        }
    }
}
