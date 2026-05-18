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
//  - Bottom CaptureActionTray with TTS playback, AI Commands sheet,
//    Open in Compose.
//  - Toolbar: Done (stops playback), Copy with checkmark feedback.
//
//  This port carries the visual shape and field set. Wires that
//  belong to Codex (image loading via MemoAttachmentStore, real
//  TTS via SpeechSynthesisService, AI commands sheet, Mac sync
//  retry against BridgeManager) are placeholders here.
//

import SwiftUI

@MainActor
final class CaptureDetailStore: ObservableObject {
    @Published var capture: CaptureDisplay

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
        self.capture = Self.mockCapture
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

struct CaptureDetailNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store: CaptureDetailStore
    @State private var showCopied = false
    @State private var isPlayingTTS = false

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

                    Spacer(minLength: 100)
                }
            }
            .scrollIndicators(.hidden)

            actionTray
        }
    }

    // MARK: - Header (Done · Capture · Copy)

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Capture")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Button(action: copyText) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                    Text(showCopied ? "Copied" : "Copy")
                        .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.colors.textTertiary)

            Text(store.capture.bodyText)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textPrimary)
                .tracking(-0.05)
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
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
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
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default))
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
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer()

                if store.capture.syncedToMac {
                    Text("Synced")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Button(action: { /* TODO M3+ wire: BridgeManager retry */ }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Retry")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let err = store.capture.syncError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 26)
            }
        }
    }

    // MARK: - Action tray (Listen · AI commands · Compose)

    private var actionTray: some View {
        HStack(spacing: 8) {
            trayChip(systemImage: isPlayingTTS ? "stop.circle" : "play.circle",
                     label: isPlayingTTS ? "Stop" : "Listen") {
                isPlayingTTS.toggle()
                // TODO M3+ wire: SpeechSynthesisService.shared.speak/stop
            }
            trayChip(systemImage: "sparkles", label: "AI") {
                // TODO M3+ wire: present CaptureAICommandsSheet
            }
            Spacer()
            primaryChip(label: "Compose ›") {
                AppShellRouter.shared.openCompose(documentID: store.capture.id)
            }
        }
        .padding(.leading, 72)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }

    private func trayChip(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 12, weight: .semibold))
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
