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
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Library")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text("\(count) / \(total)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
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
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.05)
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
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .textCase(.uppercase)
                    Spacer()
                    if earlierCount > 0 {
                        Text("\(earlierCount) MORE")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
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
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .tracking(-0.05)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.relativeTime)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        if let preview = item.preview {
                            Text(preview)
                                .font(.system(size: 12.5))
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
        VStack(spacing: 6) {
            Text("Nothing here yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
            Text(hint)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var hint: String {
        switch tab {
        case .memos:      return "Tap the mic to record a memo"
        case .dictations: return "Dictate from the keyboard or Compose"
        case .items:      return "Share links or scans into Talkie"
        }
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
                .font(.system(size: 13))
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
