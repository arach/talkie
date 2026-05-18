//
//  CaptureDetailNext.swift
//  Talkie iOS
//
//  Phase 3 paint — minimal Next-style capture detail. Source-aware
//  hero (link card / scan thumb / text quote) with three primary
//  actions: open in Compose, save to library, discard. Full feature
//  set lives in the legacy CaptureDetailView (983 lines); this is
//  the rebuilt entry that future flows route into.
//

import SwiftUI

@MainActor
final class CaptureDetailStore: ObservableObject {
    @Published var capture: CaptureDisplay

    struct CaptureDisplay {
        let id: String
        let source: Source
        let title: String
        let body: String?
        let url: String?
        let imagePreviewName: String?  // SF Symbol fallback if no real image
        let capturedAt: String

        enum Source { case link, scan, dictation, typed }
    }

    init(captureID: String?) {
        // Codex wires real lookup against Capture entity / CaptureStore.
        // For now this returns the mock for paint verification.
        self.capture = Self.mockCapture
    }

    static let mockCapture = CaptureDisplay(
        id: "mock",
        source: .link,
        title: "ArXiv: speculative decoding for long context",
        body: "We present a speculative decoding scheme for long-context inference that achieves up to 3.2× wall-clock speedup with no quality regression on standard benchmarks.",
        url: "arxiv.org/abs/2403.09919",
        imagePreviewName: nil,
        capturedAt: "9:12 AM today"
    )
}

struct CaptureDetailNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store: CaptureDetailStore

    init(captureID: String? = nil) {
        _store = StateObject(wrappedValue: CaptureDetailStore(captureID: captureID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceBadge
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    hero
                        .padding(.horizontal, 12)

                    if let body = store.capture.body {
                        Text(body)
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .foregroundStyle(theme.colors.textPrimary)
                            .tracking(-0.05)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    // NOTE: The legacy CaptureDetailView surfaces a lot
                    // more — audio player (when capture has audio),
                    // image viewer (when capture has photo/scan), AI
                    // commands sheet, sync state, full compose hand-off.
                    // None of that is brought across yet. This shell
                    // intentionally stops at hero + body for now.

                    Spacer(minLength: 100)
                }
            }
            .scrollIndicators(.hidden)

            actionBar
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Capture")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Button(action: { /* TODO: more menu */ }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    // MARK: - Source badge

    private var sourceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: sourceGlyph)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text("· \(sourceLabel.uppercased()) · \(store.capture.capturedAt.uppercased())")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Hero (source-typed)

    @ViewBuilder
    private var hero: some View {
        switch store.capture.source {
        case .link:    linkHero
        case .scan:    scanHero
        case .dictation, .typed: textHero
        }
    }

    private var linkHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.capture.title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(3)
            if let url = store.capture.url {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                    Text(url)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(16)
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

    private var scanHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            VStack(spacing: 10) {
                Image(systemName: store.capture.imagePreviewName ?? "viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(theme.colors.textTertiary)
                Text(store.capture.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity)
    }

    private var textHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.capture.title)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(theme.colors.textPrimary)
        }
        .padding(16)
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

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            actionChip(
                label: "Discard",
                isPrimary: false,
                action: { AppShellRouter.shared.openHome() }
            )
            actionChip(
                label: "Save",
                isPrimary: false,
                action: { /* TODO: persist */ }
            )
            actionChip(
                label: "Compose ›",
                isPrimary: true,
                action: { AppShellRouter.shared.openCompose(documentID: store.capture.id) }
            )
        }
        // Leading inset clears the shell voice button (bottom-left,
        // 48pt + 20pt padding).
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

    private func actionChip(label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPrimary
                    ? theme.colors.cardBackground
                    : theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(isPrimary ? theme.currentTheme.chrome.accent : Color.clear)
                        .overlay(
                            Capsule().strokeBorder(
                                isPrimary
                                    ? Color.clear
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source helpers

    private var sourceGlyph: String {
        switch store.capture.source {
        case .link:      return "link"
        case .scan:      return "viewfinder"
        case .dictation: return "waveform"
        case .typed:     return "keyboard"
        }
    }

    private var sourceLabel: String {
        switch store.capture.source {
        case .link:      return "Link"
        case .scan:      return "Scan"
        case .dictation: return "Voice memo"
        case .typed:     return "Text"
        }
    }
}
