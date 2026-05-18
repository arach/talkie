//
//  WebCaptureBrowserNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — in-app browser frame for link captures.
//  Chrome row (back/forward/url/reader/share) + content placeholder
//  + capture action bar. Donor is WebCaptureBrowser (543 lines)
//  with real WKWebView; this is the visual frame.
//

import SwiftUI

@MainActor
final class WebCaptureBrowserStore: ObservableObject {
    @Published var url: String = "arxiv.org/abs/2403.09919"
    @Published var pageTitle: String = "ArXiv: speculative decoding for long context"
    @Published var progress: Double = 1.0
    @Published var canGoBack: Bool = true
    @Published var canGoForward: Bool = false
    @Published var readerMode: Bool = false
}

struct WebCaptureBrowserNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = WebCaptureBrowserStore()

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            progressBar
            contentPlaceholder
            actionBar
        }
    }

    // MARK: - Chrome

    private var chromeBar: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: { AppShellRouter.shared.openHome() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                        Text("Close")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(store.pageTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: { /* TODO: share */ }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: store.url.hasPrefix("https") ? "lock.fill" : "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
                Text(store.url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button(action: { store.readerMode.toggle() }) {
                    Image(systemName: "book")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.readerMode
                            ? theme.currentTheme.chrome.accent
                            : theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(theme.colors.cardBackground)
                    .overlay(Capsule().strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    ))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(theme.currentTheme.chrome.accent)
                .frame(width: geo.size.width * store.progress, height: 2)
                .opacity(store.progress < 1.0 ? 1.0 : 0.0)
        }
        .frame(height: 2)
    }

    // MARK: - Content (placeholder)

    private var contentPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.background)
            VStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(theme.colors.textTertiary)
                Text("WKWebView lives here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                Text("Wired in M3 — visual frame only for now")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            navButton(systemImage: "chevron.left", enabled: store.canGoBack) { /* back */ }
            navButton(systemImage: "chevron.right", enabled: store.canGoForward) { /* forward */ }
            Spacer()
            Button(action: { /* TODO: capture */ }) {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill").font(.system(size: 11))
                    Text("Capture page")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(theme.colors.cardBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
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

    private func navButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled ? theme.colors.textSecondary : theme.colors.textTertiary.opacity(0.4))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(theme.colors.cardBackground)
                        .overlay(Circle().strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        ))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
