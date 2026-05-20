//
//  HomeNextView.swift
//  Talkie iOS
//
//  M1 — Talkie's canonical iPhone home, painted to match the
//  studio mock at http://localhost:3000/home.
//
//  Composition: TALKIE wordmark · PICK UP card (continue last
//  document) · smart Action Bus (auto-rolling 24h→7d→30d) ·
//  Recent list (2-line iOS-Notes style). The ambient voice
//  button lives in AppShellNext, not here.
//
//  Spec: design/studio/app/home/SWIFT_PORT.md
//  Visual reference: design/studio/app/home/page.tsx
//
//  Type system: TalkieTypeStyle tokens (see TalkieType.swift).
//  No raw .font(.system(...)) calls here — channel labels, body
//  serif, and instrument readouts all flow through .talkieType(...).
//

import SwiftUI

struct HomeNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var feed: HomeFeed

    init(feed: HomeFeed? = nil) {
        _feed = StateObject(wrappedValue: feed ?? HomeFeed())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHeader()

                StationCard(
                    pickUp: feed.lastDocument,
                    tally: feed.recentTally
                )
                .padding(.horizontal, 12)

                RecentSection(items: feed.recentItems)
                    .padding(.horizontal, 12)

                Spacer(minLength: 80)   // breathing room for the shell voice button
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Color.clear.frame(width: 28, height: 28)
            Spacer()
            Text("TALKIE")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))
            Spacer()
            Button(action: { AppShellRouter.shared.openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.colors.cardBackground)
                            .overlay(
                                Circle().strokeBorder(
                                    theme.currentTheme.chrome.edgeFaint,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - STATION (PICK UP + Action Bus)

private struct StationCard: View {
    let pickUp: HomeFeed.PickUp?
    let tally: HomeFeed.Tally

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PICK UP")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)

                    if let pickUp {
                        Text(pickUp.title)
                            .talkieType(.headline)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(pickUp.meta)
                            .talkieType(.metaMono)
                            .foregroundStyle(theme.colors.textTertiary)
                    } else {
                        Text("Nothing recent")
                            .talkieType(.headlineSecondary)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer()

                if let pickUp {
                    Button(action: pickUp.continueAction) {
                        Text("CONTINUE ›")
                            .talkieType(.chipLabel)
                            .foregroundStyle(theme.colors.cardBackground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(theme.currentTheme.chrome.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ActionBus(tally: tally)
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct ActionBus: View {
    let tally: HomeFeed.Tally
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.currentTheme.chrome.accent)
                    .frame(width: 5, height: 5)
                Text(tally.eyebrow)
                    .talkieType(.channelLabelSmall)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
                if let cta = tally.cta {
                    Text(cta)
                        .talkieType(.channelLabelSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if !tally.cells.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(tally.cells.enumerated()), id: \.offset) { idx, cell in
                        VStack(spacing: 4) {
                            Text(cell.value)
                                .talkieType(.instrumentReadout)
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                            Text(cell.label)
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        if idx < tally.cells.count - 1 {
                            Rectangle()
                                .fill(theme.currentTheme.chrome.edgeFaint)
                                .frame(width: theme.currentTheme.chrome.hairlineWidth)
                                .padding(.vertical, 8)
                        }
                    }
                }
            } else {
                Color.clear.frame(height: 10)
            }
        }
        .background(theme.colors.background)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }
}

// MARK: - RECENT

private struct RecentSection: View {
    let items: [HomeFeed.RecentItem]
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· RECENT · \(items.count)")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)

                Spacer()

                Button(action: { AppShellRouter.shared.openLibrary() }) {
                    Text("ALL ›")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    RecentRow(item: item, showDivider: idx > 0)
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
}

private struct RecentRow: View {
    let item: HomeFeed.RecentItem
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
                                .talkieType(.timestamp)
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
