//
//  ConsoleTabRail.swift
//  Talkie
//
//  Vertical tab rail for the Console — icon above label, selected state with accent.
//

import AppKit
import SwiftUI
import TalkieKit

struct ConsoleTabRail: View {
    let tabs: [TabDefinition]
    let errors: [String: String]
    @Binding var activeTabId: String
    let sessionPool: ConsoleSessionPool
    var tooltipState: SidebarTooltipState = .shared
    let onNewTab: () -> Void
    let onEdit: (TabDefinition) -> Void
    let onDuplicate: (TabDefinition) -> Void
    let onReveal: (TabDefinition) -> Void
    let onDelete: (TabDefinition) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tabs) { tab in
                        ConsoleTabRailItem(
                            tab: tab,
                            isSelected: tab.id == activeTabId,
                            hasError: errors[tab.id] != nil,
                            isStale: sessionPool.isStale(tab.id),
                            hasSession: sessionPool.hasSession(tab.id),
                            sessionRunning: sessionPool.session(for: tab.id)?.isRunning ?? false,
                            tooltipState: tooltipState,
                            onSelect: { activeTabId = tab.id },
                            onEdit: { onEdit(tab) },
                            onDuplicate: { onDuplicate(tab) },
                            onReveal: { onReveal(tab) },
                            onDelete: { onDelete(tab) }
                        )
                    }

                    ForEach(Array(errors.keys.filter { key in !tabs.contains(where: { $0.id == key }) }), id: \.self) { errorId in
                        ConsoleTabRailErrorItem(
                            id: errorId,
                            error: errors[errorId] ?? "Unknown error"
                        )
                    }

                    ConsoleTabRailNewItem(
                        action: onNewTab,
                        tooltipState: tooltipState
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, ConsoleRailLayout.headerAlignedLeadingInset)
        .frame(width: ConsoleRailLayout.totalWidth, alignment: .leading)
        .background(Theme.current.surface1.opacity(0.6))
    }
}

enum ConsoleRailLayout {
    /// Reuse the core sidebar's compact rail geometry so the console rail
    /// doesn't drift away from the main navigation rhythm.
    static let contentWidth: CGFloat = SidebarLayout.compactWidth
    static let iconFrameWidth: CGFloat = SidebarLayout.iconFrameWidth
    static let iconLeading: CGFloat = (contentWidth - iconFrameWidth) / 2
    static let iconArtSize: CGFloat = 16
    static let rowHeight: CGFloat = 28
    static let accentBarHeight: CGFloat = SidebarLayout.accentBarHeight
    static let accentToIconGap: CGFloat = SidebarLayout.accentToIconVerticalGap

    /// The page header title begins at PageLayout.horizontalPadding. Shift the
    /// full rail until the first pixel column of the 16pt icon art sits under
    /// that same starting edge.
    static let headerAlignedLeadingInset: CGFloat = max(
        0,
        PageLayout.horizontalPadding - iconArtworkLeading
    )
    static let totalWidth: CGFloat = contentWidth + headerAlignedLeadingInset

    private static let iconArtworkLeading: CGFloat = iconLeading + ((iconFrameWidth - iconArtSize) / 2)
}

private struct ConsoleTabRailNewItem: View {
    let action: () -> Void
    let tooltipState: SidebarTooltipState
    @State private var isHovered = false
    @State private var rowFrame: CGRect = .zero

    var body: some View {
        Button(action: action) {
            VStack(spacing: ConsoleRailLayout.accentToIconGap) {
                HStack(spacing: 0) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .frame(width: ConsoleRailLayout.iconFrameWidth, height: ConsoleRailLayout.iconFrameWidth, alignment: .center)
                        .padding(.leading, ConsoleRailLayout.iconLeading)
                    Spacer(minLength: 0)
                }
                .frame(width: ConsoleRailLayout.contentWidth, height: ConsoleRailLayout.rowHeight)
                .background(
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isHovered ? Theme.current.foreground.opacity(0.04) : .clear)
                            .frame(width: ConsoleRailLayout.iconFrameWidth + 4, height: ConsoleRailLayout.iconFrameWidth + 4)
                            .padding(.leading, ConsoleRailLayout.iconLeading - 2)
                        Spacer(minLength: 0)
                    }
                )

                Color.clear.frame(height: ConsoleRailLayout.accentBarHeight)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        rowFrame = newFrame
                    }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovered = true
                NSCursor.pointingHand.push()
                let anchor = CGPoint(x: rowFrame.maxX, y: rowFrame.midY)
                if tooltipState.label == "New tab" {
                    tooltipState.updateAnchor(anchor)
                } else {
                    tooltipState.show(label: "New tab", anchor: anchor)
                }
            case .ended:
                isHovered = false
                NSCursor.pop()
                tooltipState.dismiss(matching: "New tab")
            }
        }
    }
}

private struct ConsoleTabRailItem: View {
    let tab: TabDefinition
    let isSelected: Bool
    let hasError: Bool
    let isStale: Bool
    let hasSession: Bool
    let sessionRunning: Bool
    let tooltipState: SidebarTooltipState
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var rowFrame: CGRect = .zero

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: ConsoleRailLayout.accentToIconGap) {
                HStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        TabIconView(tab: tab, size: ConsoleRailLayout.iconArtSize, weight: isSelected ? .semibold : .regular)
                            .foregroundStyle(iconColor)
                            .frame(width: ConsoleRailLayout.iconFrameWidth, height: ConsoleRailLayout.iconFrameWidth, alignment: .center)

                        statusDot
                    }
                    .padding(.leading, ConsoleRailLayout.iconLeading)

                    Spacer(minLength: 0)
                }
                .frame(width: ConsoleRailLayout.contentWidth, height: ConsoleRailLayout.rowHeight)
                .background(
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isHovered && !isSelected ? Theme.current.foreground.opacity(0.04) : .clear)
                            .frame(width: ConsoleRailLayout.iconFrameWidth + 4, height: ConsoleRailLayout.iconFrameWidth + 4)
                            .padding(.leading, ConsoleRailLayout.iconLeading - 2)
                        Spacer(minLength: 0)
                    }
                )

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(isSelected ? Theme.current.accent : .clear)
                        .frame(width: ConsoleRailLayout.iconFrameWidth, height: ConsoleRailLayout.accentBarHeight)
                        .padding(.leading, ConsoleRailLayout.iconLeading)
                    Spacer(minLength: 0)
                }
                .frame(width: ConsoleRailLayout.contentWidth)
            }
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        rowFrame = newFrame
                    }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovered = true
                let anchor = CGPoint(x: rowFrame.maxX, y: rowFrame.midY)
                if tooltipState.label == tooltipLabel {
                    tooltipState.updateAnchor(anchor)
                } else {
                    tooltipState.show(label: tooltipLabel, anchor: anchor)
                }
            case .ended:
                isHovered = false
                tooltipState.dismiss(matching: tooltipLabel)
            }
        }
        .contextMenu {
            Button("Edit Tab") { onEdit() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Reveal in Finder") { onReveal() }
            Divider()
            if !tab.readOnly {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.orange)
                .offset(x: 4, y: -3)
        } else if isStale {
            Circle()
                .fill(.orange)
                .frame(width: 6, height: 6)
                .offset(x: 3, y: -2)
        } else if sessionRunning {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .offset(x: 3, y: -2)
        }
    }

    private var tooltipLabel: String {
        var parts: [String] = [tab.label]
        if sessionRunning {
            parts.append("Running")
        } else if isStale {
            parts.append("Restart needed")
        } else if hasError {
            parts.append("Launch error")
        }
        return parts.joined(separator: " · ")
    }

    private var iconColor: Color {
        if hasError { return .orange }
        if isSelected { return Theme.current.accent }
        return Theme.current.foregroundSecondary
    }
}

private struct ConsoleTabRailErrorItem: View {
    let id: String
    let error: String

    var body: some View {
        VStack(spacing: ConsoleRailLayout.accentToIconGap) {
            HStack(spacing: 0) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.orange)
                    .frame(width: ConsoleRailLayout.iconFrameWidth, height: ConsoleRailLayout.iconFrameWidth, alignment: .center)
                    .padding(.leading, ConsoleRailLayout.iconLeading)
                Spacer(minLength: 0)
            }
            .frame(width: ConsoleRailLayout.contentWidth, height: ConsoleRailLayout.rowHeight)

            Color.clear.frame(height: ConsoleRailLayout.accentBarHeight)
        }
        .help("\(id): \(error)")
    }
}

struct TabIconView: View {
    let tab: TabDefinition
    var size: CGFloat = 16
    var weight: Font.Weight = .regular

    var body: some View {
        if tab.harness == .pi, let piImage = NSImage(named: "PiIcon") {
            Image(nsImage: piImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if tab.harness == .claudeCode, let claudeImage = NSImage(named: "ProviderLogos/Anthropic") {
            Image(nsImage: claudeImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if tab.harness == .pi {
            Text("π")
                .font(.system(size: size + 2, weight: weight, design: .serif))
        } else {
            Image(systemName: tab.symbolName)
                .font(.system(size: size, weight: weight))
        }
    }
}
