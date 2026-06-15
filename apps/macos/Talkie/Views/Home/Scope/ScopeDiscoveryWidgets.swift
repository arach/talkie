//
//  ScopeDiscoveryWidgets.swift
//  Talkie macOS
//

import SwiftUI
import TalkieKit

// "Did you know" card - full-width editorial card pulled from the
// Learn screen's RecapCard vocabulary. Outline glyph + serif hook on
// top, body excerpt, hairline divider, amber action with arrow.
// Three per row in the Home midsection.
struct DidYouKnowCard: View {
    enum Glyph { case voiceEdit, smartActions, tray }
    let glyph: Glyph
    let marker: String
    let hook: String
    let detail: String
    let action: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 10) {
                    glyphMark
                    Text("TIP \(marker)")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(hook)
                        .font(ScopeType.display(size: 17, weight: .medium))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ScopeInk.faint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)
                ScopeRule(.section)

                HStack(spacing: 4) {
                    Text(action.uppercased())
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                    Text("→").font(.system(size: 10))
                }
                .foregroundStyle(ScopeBrass.solid)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeHoverChrome(style: .scopeTipCard(cornerRadius: 6)))
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(ScopeEdge.subtle)
                    .frame(width: 34, height: 1)
                    .padding(.leading, 20)
            }

        }
        .buttonStyle(.plain)
    }

    private var glyphMark: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .overlay(
                    Circle()
                        .stroke(ScopeBrass.solid.opacity(0.24), lineWidth: 0.5)
                )
            glyphIcon
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private var glyphIcon: some View {
        let brass = ScopeBrass.solid
        switch glyph {
        case .voiceEdit:
            Path { p in
                p.move(to: .init(x: 5, y: 11));   p.addLine(to: .init(x: 8, y: 11))
                p.move(to: .init(x: 14, y: 11));  p.addLine(to: .init(x: 17, y: 11))
                p.move(to: .init(x: 8, y: 6));    p.addLine(to: .init(x: 8, y: 16))
                p.move(to: .init(x: 11, y: 8));   p.addLine(to: .init(x: 11, y: 14))
                p.move(to: .init(x: 14, y: 6));   p.addLine(to: .init(x: 14, y: 16))
            }
            .stroke(brass, style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round))
            .frame(width: 22, height: 22)
        case .smartActions:
            Path { p in
                p.move(to: .init(x: 5, y: 7));    p.addLine(to: .init(x: 17, y: 7))
                p.move(to: .init(x: 5, y: 11));   p.addLine(to: .init(x: 13, y: 11))
                p.move(to: .init(x: 5, y: 15));   p.addLine(to: .init(x: 14, y: 15))
                p.move(to: .init(x: 15, y: 10));  p.addLine(to: .init(x: 18, y: 13)); p.addLine(to: .init(x: 15, y: 16))
            }
            .stroke(brass, style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round))
            .frame(width: 22, height: 22)
        case .tray:
            ZStack {
                Path { p in
                    p.addRoundedRect(in: CGRect(x: 5, y: 6, width: 12, height: 8), cornerSize: CGSize(width: 2, height: 2))
                    p.move(to: .init(x: 8, y: 17)); p.addLine(to: .init(x: 14, y: 17))
                }
                .stroke(brass, style: StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round))
                Circle().fill(brass).frame(width: 2, height: 2).offset(x: 0, y: -1.5)
            }
            .frame(width: 22, height: 22)
        }
    }
}

// Legacy TodayWidget - dead from the Discovery row, kept for any
// callers we might have missed. Will be removed in a cleanup pass.
private struct TodayWidget: View {
    private struct Event { let hour: Double; let label: String }
    private let events: [Event] = [
        .init(hour: 9.5,  label: "09:30 · Design review"),
        .init(hour: 11.0, label: "11:00 · Standup"),
        .init(hour: 14.0, label: "14:00 · Bay polish merge"),
    ]

    var body: some View {
        DiscoveryWidgetCard(title: "Today", eyebrow: "Calendar") {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(ScopeEdge.faint)
                            .frame(height: 0.5)
                            .offset(y: 10)
                        ForEach([0, 4, 8, 12, 16, 20, 24], id: \.self) { h in
                            let x = CGFloat(h) / 24.0 * geo.size.width
                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(ScopeEdge.faint)
                                    .frame(width: 1, height: 4)
                                Text(h < 10 ? "0\(h)" : "\(h)")
                                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundStyle(ScopeInk.subtle)
                            }
                            .offset(x: x - 6, y: 6)
                        }
                        ForEach(events.indices, id: \.self) { index in
                            let event = events[index]
                            let x = CGFloat(event.hour) / 24.0 * geo.size.width
                            Circle()
                                .fill(ScopeBrass.solid)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle().stroke(ScopeCanvas.surface, lineWidth: 2)
                                )
                                .offset(x: x - 5, y: 5)
                        }
                    }
                }
                .frame(height: 26)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events.indices, id: \.self) { index in
                        let event = events[index]
                        HStack {
                            let parts = event.label.split(separator: " · ", maxSplits: 1).map(String.init)
                            Text(parts.first ?? event.label)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ScopeInk.primary)
                            Spacer()
                            Text(parts.count > 1 ? parts[1] : "")
                                .font(.system(size: 11))
                                .foregroundStyle(ScopeInk.faint)
                        }
                    }
                }
            }
        }
    }
}

/// Shortcuts - proper key-cap glyphs grouped vertically.
private struct ShortcutsWidget: View {
    private struct Shortcut { let keys: [String]; let label: String }
    private let shortcuts: [Shortcut] = [
        .init(keys: ["⌃", "⇧", "⌘", "M"], label: "New Memo"),
        .init(keys: ["⌃", "⇧", "⌘", "D"], label: "Dictate"),
        .init(keys: ["⌃", "⇧", "⌘", "S"], label: "Capture screen"),
        .init(keys: ["⌃", "⇧", "⌘", "L"], label: "Library"),
    ]

    var body: some View {
        DiscoveryWidgetCard(title: "Shortcuts", eyebrow: "Keyboard") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shortcuts.indices, id: \.self) { index in
                    let shortcut = shortcuts[index]
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(shortcut.keys, id: \.self) { key in
                                Text(key)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ScopeInk.primary)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(ScopeCanvas.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(ScopeEdge.normal, lineWidth: 0.5)
                                    )
                            }
                        }
                        Text(shortcut.label)
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.faint)
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Trending - tag + horizontal bar + count. Mini histogram, not a list.
private struct TrendingWidget: View {
    private struct Trend { let tag: String; let count: Int }
    private let trends: [Trend] = [
        .init(tag: "Standups",       count: 8),
        .init(tag: "Compose drafts", count: 5),
        .init(tag: "Code review",    count: 3),
        .init(tag: "Design notes",   count: 2),
    ]
    private var maxCount: Int { trends.map(\.count).max() ?? 1 }

    var body: some View {
        DiscoveryWidgetCard(title: "Trending", eyebrow: "This week") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(trends.indices, id: \.self) { index in
                    let trend = trends[index]
                    HStack(spacing: 10) {
                        Text(trend.tag)
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.primary)
                            .frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(ScopeEdge.faint)
                                Rectangle()
                                    .fill(ScopeBrass.solid)
                                    .frame(width: geo.size.width * CGFloat(trend.count) / CGFloat(maxCount))
                            }
                        }
                        .frame(height: 6)
                        .clipShape(.rect(cornerRadius: 1))
                        Text("\(trend.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                            .frame(width: 16, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Shared discovery widget chrome - title + trailing eyebrow + content.
/// Named `DiscoveryWidgetCard` to avoid colliding with `WidgetCard` in
/// `HomeWidgets.swift`, which serves the original (non-Scope) Home grid.
private struct DiscoveryWidgetCard<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(ScopeType.display(size: 13, weight: .medium))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
                Text(eyebrow.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                ScopeRule(.section)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScopeCanvas.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
        .clipShape(.rect(cornerRadius: 6))
    }
}
