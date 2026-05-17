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
            // TALKIE wordmark — SF Mono, tight tracking. Reads as
            // channel-label vocabulary, not magazine title.
            Text("TALKIE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(3.2)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))
            Spacer()
            Button(action: { /* TODO: route to Settings */ }) {
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
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.6)
                        .foregroundStyle(theme.currentTheme.chrome.accent)

                    if let pickUp {
                        Text(pickUp.title)
                            .font(.system(size: 22, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(pickUp.meta)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(theme.colors.textTertiary)
                    } else {
                        Text("Nothing recent")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }

                Spacer()

                if let pickUp {
                    Button(action: pickUp.continueAction) {
                        Text("Continue ›")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.colors.cardBackground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .textCase(.uppercase)
                Spacer()
                if let cta = tally.cta {
                    Text(cta)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(theme.colors.textTertiary)
                        .textCase(.uppercase)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if !tally.cells.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(tally.cells.enumerated()), id: \.offset) { idx, cell in
                        VStack(spacing: 4) {
                            Text(cell.value)
                                .font(.system(size: 24, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                                .tracking(-0.5)
                            Text(cell.label)
                                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                                .tracking(1.8)
                                .foregroundStyle(theme.colors.textTertiary)
                                .textCase(.uppercase)
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
                Text("· RECENT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .textCase(.uppercase)

                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(theme.currentTheme.chrome.accentTint))

                Spacer()

                Text("ALL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.colors.textTertiary)
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
