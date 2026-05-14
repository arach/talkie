//
//  ScopeConsoleRail.swift
//  Talkie macOS
//
//  Cream-phosphor Console tab rail. Slim 40pt channel rail that expands
//  to ~200pt on hover and reveals tab name + status. Channel pins
//  (CH-01, CH-02 …) read as monospace caps. Active tab gets an amber
//  inset stripe; running sessions get a phosphor dot.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//  ConsoleScreen branches on theme and renders ConsoleTabRail() for
//  every other theme.
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - Layout constants

private enum ScopeRailLayout {
    static let collapsedWidth: CGFloat = 40
    static let expandedWidth: CGFloat = 200
    static let rowHeight: CGFloat = 44
    static let cornerRadius: CGFloat = 3
    static let collapseDelay: TimeInterval = 0.16
}

// MARK: - ScopeConsoleRail

struct ScopeConsoleRail: View {
    let tabs: [TabDefinition]
    let errors: [String: String]
    @Binding var activeTabId: String
    let sessionPool: ConsoleSessionPool
    let onNewTab: () -> Void
    let onEdit: (TabDefinition) -> Void
    let onDuplicate: (TabDefinition) -> Void
    let onReveal: (TabDefinition) -> Void
    let onDelete: (TabDefinition) -> Void

    @State private var isExpanded: Bool = false
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(ScopeEdge.faint)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                        ScopeRailItem(
                            tab: tab,
                            channelPin: Self.channelPin(idx),
                            isExpanded: isExpanded,
                            isSelected: tab.id == activeTabId,
                            hasError: errors[tab.id] != nil,
                            isStale: sessionPool.isStale(tab.id),
                            sessionRunning: sessionPool.session(for: tab.id)?.isRunning ?? false,
                            onSelect: { activeTabId = tab.id },
                            onEdit: { onEdit(tab) },
                            onDuplicate: { onDuplicate(tab) },
                            onReveal: { onReveal(tab) },
                            onDelete: { onDelete(tab) },
                            onHoverActive: handleItemHover
                        )
                    }

                    let orphans = errors.keys.filter { key in
                        !tabs.contains(where: { $0.id == key })
                    }
                    ForEach(Array(orphans), id: \.self) { errorId in
                        ScopeRailErrorItem(
                            id: errorId,
                            error: errors[errorId] ?? "Unknown error",
                            isExpanded: isExpanded
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            Rectangle()
                .fill(ScopeEdge.faint)
                .frame(height: 1)

            ScopeRailNewItem(
                isExpanded: isExpanded,
                action: onNewTab,
                onHoverActive: handleItemHover
            )
        }
        .frame(width: isExpanded ? ScopeRailLayout.expandedWidth : ScopeRailLayout.collapsedWidth,
               alignment: .leading)
        // When floating over the console content, the rail reads as a
        // surface only while expanded. Collapsed (trigger) state keeps a
        // minimal silhouette so the channel pins look like they're sitting
        // on the terminal canvas itself.
        .background(isExpanded ? ScopeCanvas.surface : Color.clear)
        .overlay(alignment: .trailing) {
            if isExpanded {
                Rectangle().fill(ScopeEdge.faint).frame(width: 1)
            }
        }
        .animation(ScopeMotion.placement, value: isExpanded)
    }

    /// Expand only when the pointer enters an actual interactive cell
    /// (tab row or the new-tab button). Empty header/footer/gap zones
    /// keep the rail calm so the user can pass by without triggering it.
    private func handleItemHover(_ active: Bool) {
        if active {
            collapseTask?.cancel()
            collapseTask = nil
            if !isExpanded { isExpanded = true }
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ScopeRailLayout.collapseDelay * 1_000_000_000))
            if !Task.isCancelled {
                isExpanded = false
            }
        }
    }

    /// Channel pin for the index. Two-digit zero-padded so CH-01 …
    /// CH-12 stay aligned.
    static func channelPin(_ idx: Int) -> String {
        String(format: "CH-%02d", idx + 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            PhosphorDot(color: ScopeAmber.solid, size: 5)
            if isExpanded {
                Text("CONSOLE")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.30)
                    .transition(.opacity)
                Spacer(minLength: 0)
                Text("\(tabs.count)")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, isExpanded ? 12 : 0)
        .frame(width: isExpanded ? ScopeRailLayout.expandedWidth : ScopeRailLayout.collapsedWidth,
               height: 28, alignment: isExpanded ? .leading : .center)
    }
}

// MARK: - Rail item

private struct ScopeRailItem: View {
    let tab: TabDefinition
    let channelPin: String
    let isExpanded: Bool
    let isSelected: Bool
    let hasError: Bool
    let isStale: Bool
    let sessionRunning: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    let onHoverActive: (Bool) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                collapsedCell

                if isExpanded {
                    expandedSlice
                        .transition(.opacity)
                }
            }
            .frame(width: isExpanded ? ScopeRailLayout.expandedWidth : ScopeRailLayout.collapsedWidth,
                   height: ScopeRailLayout.rowHeight,
                   alignment: .leading)
            .background(backgroundFill)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(ScopeAmber.solid)
                        .frame(width: 2)
                        .shadow(color: ScopeAmber.glow, radius: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
            onHoverActive(hover)
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

    // Square cell rendered both collapsed and as the leading slice when
    // expanded. Shows channel pin (two-digit index) + status dot.
    private var collapsedCell: some View {
        ZStack {
            VStack(spacing: 3) {
                Text(shortIndex)
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(channelColor)

                if let dotColor = statusDotColor {
                    PhosphorDot(color: dotColor, size: 5)
                        .shadow(color: dotColor.opacity(0.5), radius: 3)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
        }
        .frame(width: ScopeRailLayout.collapsedWidth, height: ScopeRailLayout.rowHeight)
    }

    private var expandedSlice: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(channelPin)
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(channelColor)
                }
                Text(tab.label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            statusPill
        }
        .padding(.trailing, 12)
        .frame(maxHeight: .infinity)
    }

    private var shortIndex: String {
        // CH-01 → 01
        String(channelPin.suffix(2))
    }

    @ViewBuilder
    private var statusPill: some View {
        if hasError {
            pill(text: "ERR", color: errorAmber)
        } else if isStale {
            pill(text: "RESTART", color: errorAmber)
        } else if sessionRunning {
            pill(text: "LIVE", color: ScopeAmber.solid)
        } else {
            pill(text: "IDLE", color: ScopeInk.subtle)
        }
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(ScopeType.chrome)
            .tracking(ScopeType.Tracking.normal)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.4), lineWidth: 0.5)
            )
    }

    private var backgroundFill: Color {
        if isSelected { return ScopeAmber.tintSubtle }
        if isHovered { return ScopeCanvas.canvasOverlay }
        return .clear
    }

    private var channelColor: Color {
        if hasError { return errorAmber }
        if isSelected { return ScopeAmber.solid }
        return ScopeInk.faint
    }

    private var labelColor: Color {
        if hasError { return errorAmber }
        if isSelected { return ScopeInk.primary }
        return ScopeInk.dim
    }

    private var statusDotColor: Color? {
        if hasError { return errorAmber }
        if isStale { return errorAmber }
        if sessionRunning { return ScopeAmber.solid }
        return nil
    }

    // Burnt-rust warning amber; matches the Drafts review reject color.
    private var errorAmber: Color {
        Color(red: 0.72, green: 0.32, blue: 0.18)
    }
}

// MARK: - Orphan error item

private struct ScopeRailErrorItem: View {
    let id: String
    let error: String
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(errorAmber)
                Text("ERR")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(errorAmber)
            }
            .frame(width: ScopeRailLayout.collapsedWidth, height: ScopeRailLayout.rowHeight)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.uppercased())
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(errorAmber)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.muted)
                        .lineLimit(2)
                }
                .padding(.trailing, 12)
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .frame(width: isExpanded ? ScopeRailLayout.expandedWidth : ScopeRailLayout.collapsedWidth,
               height: ScopeRailLayout.rowHeight, alignment: .leading)
        .help("\(id): \(error)")
    }

    private var errorAmber: Color {
        Color(red: 0.72, green: 0.32, blue: 0.18)
    }
}

// MARK: - New tab button

private struct ScopeRailNewItem: View {
    let isExpanded: Bool
    let action: () -> Void
    let onHoverActive: (Bool) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isHovered ? ScopeAmber.solid : ScopeEdge.normal, lineWidth: 0.75)
                        .frame(width: 22, height: 22)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? ScopeAmber.solid : ScopeInk.faint)
                        .phosphorGlow(radius: 2, opacity: isHovered ? 0.32 : 0)
                }

                if isExpanded {
                    Text("NEW TAB")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(isHovered ? ScopeAmber.solid : ScopeInk.faint)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: isExpanded ? ScopeRailLayout.expandedWidth : ScopeRailLayout.collapsedWidth,
                   height: 40,
                   alignment: isExpanded ? .leading : .center)
            .padding(.horizontal, isExpanded ? 12 : 0)
            .contentShape(Rectangle())
            .background(isHovered ? ScopeCanvas.canvasOverlay : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
            onHoverActive(hover)
            if hover {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("New tab")
    }
}
