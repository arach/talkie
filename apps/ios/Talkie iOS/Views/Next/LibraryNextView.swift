//
//  LibraryNextView.swift
//  Talkie iOS
//
//  Phase 3 paint — Library / all-docs surface. Soft brass underline
//  tabs (Memos · Dictations · Items), 2-line iOS-Notes rows, search
//  bar flush as footer. The shell voice button floats above.
//
//  Spec: design/studio/app/library/SWIFT_PORT.md
//  Visual reference: design/studio/app/library/page.tsx
//

import SwiftUI

enum LibraryTab: CaseIterable {
    case memos, dictations, items

    var label: String {
        switch self {
        case .memos:      return "Memos"
        case .dictations: return "Dictations"
        case .items:      return "Items"
        }
    }
}

struct LibraryNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var library: LibraryFeed
    @State private var activeTab: LibraryTab = .memos

    init(feed: LibraryFeed? = nil) {
        _library = StateObject(wrappedValue: feed ?? LibraryFeed())
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(
                count: library.items(for: activeTab).count,
                total: library.totalCount(for: activeTab),
                onBack: { AppShellRouter.shared.openHome() }
            )
            TabRow(active: $activeTab)
            ScrollView {
                VStack(spacing: 12) {
                    LibraryListCard(
                        items: library.items(for: activeTab),
                        earlierCount: library.earlierCount(for: activeTab),
                        activeTab: activeTab
                    )
                    .padding(.horizontal, 12)

                    if activeTab == .dictations {
                        FullHistoryLink {
                            AppShellRouter.shared.openDictationHistory()
                        }
                        .padding(.horizontal, 12)
                    }

                    SearchBar(placeholder: searchPlaceholder)
                        .padding(.horizontal, 12)

                    Spacer(minLength: 80)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var searchPlaceholder: String {
        switch activeTab {
        case .memos:      return "Search memos"
        case .dictations: return "Search dictations"
        case .items:      return "Search items"
        }
    }
}

// MARK: - Header

private struct LibraryHeader: View {
    let count: Int
    let total: Int
    let onBack: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Library")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text("\(count) / \(total)")
                .talkieType(.channelLabelSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(theme.colors.cardBackground)
                        .overlay(Capsule().strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        ))
                )
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
}

// MARK: - Tab row (soft underline)

private struct TabRow: View {
    @Binding var active: LibraryTab
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func tabButton(_ tab: LibraryTab) -> some View {
        let isActive = (active == tab)
        return Button(action: {
            withAnimation(.easeOut(duration: 0.18)) { active = tab }
        }) {
            VStack(spacing: 4) {
                Text(tab.label)
                    .talkieType(.preview)
                    .foregroundStyle(isActive
                        ? theme.currentTheme.chrome.accent
                        : theme.colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                Rectangle()
                    .fill(isActive ? theme.currentTheme.chrome.accent : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List card

private struct LibraryListCard: View {
    let items: [LibraryFeed.Item]
    let earlierCount: Int
    let activeTab: LibraryTab

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyTabState(tab: activeTab)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    LibraryRow(item: item, showDivider: idx > 0)
                }

                HStack(spacing: 6) {
                    Text("· EARLIER · THIS WEEK")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .textCase(.uppercase)
                    Spacer()
                    if earlierCount > 0 {
                        Text("\(earlierCount) MORE")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .overlay(
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeSubtle)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)
                        .padding(.leading, 36),
                    alignment: .top
                )

                Color.clear.frame(height: 12)
            }
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
    }
}

private struct LibraryRow: View {
    let item: LibraryFeed.Item
    let showDivider: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: openItem) {
            VStack(spacing: 0) {
                if showDivider {
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeSubtle)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)
                        .padding(.leading, 36)
                }
                HStack(alignment: .top, spacing: 8) {
                    sourceGlyph
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .talkieType(.listTitle)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.relativeTime)
                                .talkieType(.channelLabel)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        if let preview = item.preview {
                            Text(preview)
                                .talkieType(.preview)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private func openItem() {
        switch item.source {
        case .dictation:        AppShellRouter.shared.openMemoDetail(memoID: item.id)
        case .typed:            AppShellRouter.shared.openCompose(documentID: item.id)
        case .link, .scan:      AppShellRouter.shared.openCaptureDetail(captureID: item.id)
        }
    }

    @ViewBuilder
    private var sourceGlyph: some View {
        switch item.source {
        case .dictation:
            Image(systemName: "waveform").font(.system(size: 13))
        case .typed:
            Image(systemName: "keyboard").font(.system(size: 12))
        case .link:
            Image(systemName: "link").font(.system(size: 12))
        case .scan:
            Image(systemName: "viewfinder").font(.system(size: 12))
        }
    }
}

private struct EmptyTabState: View {
    let tab: LibraryTab
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.currentTheme.chrome.accent.opacity(0.10))
                    .frame(width: 56, height: 56)
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            VStack(spacing: 6) {
                Text(headline)
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(hint)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)

            if let cta {
                Button(action: cta.action) {
                    HStack(spacing: 6) {
                        Image(systemName: cta.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(cta.label)
                            .talkieType(.chipLabel)
                    }
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 14)
    }

    private var iconName: String {
        switch tab {
        case .memos:      return "waveform"
        case .dictations: return "text.cursor"
        case .items:      return "tray"
        }
    }

    private var headline: String {
        switch tab {
        case .memos:      return "No memos yet"
        case .dictations: return "No dictations yet"
        case .items:      return "Nothing in the tray"
        }
    }

    private var hint: String {
        switch tab {
        case .memos:      return "Long-press the mic anywhere in Talkie to start a recording."
        case .dictations: return "Use the Talkie keyboard or Compose to capture text by voice."
        case .items:      return "Share links from Safari, or run a camera scan to add items here."
        }
    }

    private struct CTA {
        let label: String
        let icon: String
        let action: () -> Void
    }

    private var cta: CTA? {
        switch tab {
        case .memos:
            return CTA(label: "RECORD", icon: "mic.fill") {
                // Mic is the global FAB; surface the tray.
                // (No direct invoke API exposed; nudge user toward voice button.)
            }
        case .dictations:
            return CTA(label: "ENABLE KEYBOARD", icon: "keyboard") {
                AppShellRouter.shared.openKeyboardActivation()
            }
        case .items:
            return CTA(label: "OPEN CAMERA", icon: "camera") {
                AppShellRouter.shared.openCameraCapture()
            }
        }
    }
}

// MARK: - Full history link (Dictations tab only)

/// Bridges Library's in-place Dictations filter to the dedicated
/// DictationHistoryNext surface — keyboard-dictation entries with
/// pagination, swipe actions, and richer detail than the filtered
/// memo list.
private struct FullHistoryLink: View {
    let action: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
                Text("View full dictation history")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

private struct SearchBar: View {
    let placeholder: String
    @ObservedObject private var theme = ThemeManager.shared
    @State private var query: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textTertiary)
            TextField(placeholder, text: $query)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(theme.colors.cardBackground)
                .overlay(Capsule().strokeBorder(
                    theme.currentTheme.chrome.edgeFaint,
                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                ))
        )
    }
}
