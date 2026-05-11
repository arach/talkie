//
//  NotchCommunicationView.swift
//  Talkie
//
//  Communication surface demo for the notch area.
//  Grid layout of registered communication modules (capture, dictation, workflow).
//

import SwiftUI

// MARK: - Module Model

enum NotchCommunicationModuleSize: String, CaseIterable {
    case compact
    case wide
    case large

    var columns: Int {
        switch self {
        case .compact: 1
        case .wide, .large: 2
        }
    }

    var rows: Int {
        switch self {
        case .compact, .wide: 1
        case .large: 2
        }
    }

    var label: String {
        "\(columns)x\(rows)"
    }
}

struct NotchCommunicationModule: Identifiable, Equatable {
    let id: String
    let source: String
    let priority: Int
    let symbol: String
    let title: String
    let subtitle: String
    let collapsedSize: NotchCommunicationModuleSize
    let expandedSize: NotchCommunicationModuleSize
}

// MARK: - Registry

@MainActor
@Observable
final class NotchCommunicationRegistry {
    static let shared = NotchCommunicationRegistry()

    private(set) var modules: [NotchCommunicationModule] = []
    private var demoInstalled = false

    private init() {}

    func register(_ module: NotchCommunicationModule) {
        modules.removeAll { $0.id == module.id }
        modules.append(module)
        modules.sort { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.id < rhs.id
            }
            return lhs.priority < rhs.priority
        }
    }

    func unregister(id: String) {
        modules.removeAll { $0.id == id }
    }

    /// Demo seed showing how sub-components can register content cards for the notch.
    /// Any service can call `register(...)` / `unregister(...)` with its own lifecycle.
    func installDemoModulesIfNeeded() {
        guard !demoInstalled else { return }
        demoInstalled = true

        register(
            NotchCommunicationModule(
                id: "capture.quick",
                source: "Capture",
                priority: 10,
                symbol: "camera.viewfinder",
                title: "Quick Capture",
                subtitle: "Screenshot, clip, annotate",
                collapsedSize: .compact,
                expandedSize: .compact
            )
        )

        register(
            NotchCommunicationModule(
                id: "memo.live",
                source: "Dictation",
                priority: 20,
                symbol: "mic.fill",
                title: "Start Memo",
                subtitle: "Voice note with context",
                collapsedSize: .compact,
                expandedSize: .compact
            )
        )

        register(
            NotchCommunicationModule(
                id: "workflow.queue",
                source: "Workflow",
                priority: 30,
                symbol: "bolt.fill",
                title: "Workflow Queue",
                subtitle: "3 cards pending review",
                collapsedSize: .wide,
                expandedSize: .wide
            )
        )
    }
}

// MARK: - Communication Surface View

struct NotchCommunicationSurface: View {
    let modules: [NotchCommunicationModule]
    let baselineWidth: CGFloat
    let trayItemCount: Int
    let rows: Int
    let bottomCornerRadius: CGFloat
    let surfaceColor: Color

    private let columns = 2
    private let spacing: CGFloat = 9
    private let tileHeight: CGFloat = 42
    private let horizontalPadding: CGFloat = 10

    private var clampedWidth: CGFloat {
        max(172, baselineWidth)
    }

    private var contentWidth: CGFloat {
        max(140, clampedWidth - (horizontalPadding * 2))
    }

    private var slotWidth: CGFloat {
        max(64, (contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
    }

    private var activeRows: Int {
        max(1, min(2, rows))
    }

    private var placements: [NotchCommunicationPlacement] {
        NotchCommunicationPlacement.build(
            modules: modules,
            rows: activeRows,
            columns: columns
        )
    }

    private var surfaceHeight: CGFloat {
        (CGFloat(activeRows) * tileHeight) + (CGFloat(max(0, activeRows - 1)) * spacing)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Communication")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if trayItemCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(trayItemCount)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                }
                Text(activeRows == 2 ? "2x2" : "1x2")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            ZStack(alignment: .topLeading) {
                ForEach(placements) { placement in
                    NotchCommunicationModuleTile(module: placement.module)
                        .frame(
                            width: widthForPlacement(placement),
                            height: heightForPlacement(placement)
                        )
                        .offset(
                            x: CGFloat(placement.column) * (slotWidth + spacing),
                            y: CGFloat(placement.row) * (tileHeight + spacing)
                        )
                }
            }
            .frame(width: contentWidth, height: surfaceHeight, alignment: .topLeading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: clampedWidth)
        .background(backgroundShape)
    }

    private var backgroundShape: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomCornerRadius,
            bottomTrailingRadius: bottomCornerRadius,
            topTrailingRadius: 0
        )
            .fill(surfaceColor)
    }

    private func widthForPlacement(_ placement: NotchCommunicationPlacement) -> CGFloat {
        (CGFloat(placement.columnSpan) * slotWidth) + (CGFloat(max(0, placement.columnSpan - 1)) * spacing)
    }

    private func heightForPlacement(_ placement: NotchCommunicationPlacement) -> CGFloat {
        (CGFloat(placement.rowSpan) * tileHeight) + (CGFloat(max(0, placement.rowSpan - 1)) * spacing)
    }
}

// MARK: - Module Tile

private struct NotchCommunicationModuleTile: View {
    let module: NotchCommunicationModule

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: module.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(module.subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(module.source.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.5)
        )
    }
}

// MARK: - Grid Placement Algorithm

private struct NotchCommunicationPlacement: Identifiable {
    let module: NotchCommunicationModule
    let row: Int
    let column: Int
    let rowSpan: Int
    let columnSpan: Int

    var id: String { module.id }

    static func build(
        modules: [NotchCommunicationModule],
        rows: Int,
        columns: Int
    ) -> [NotchCommunicationPlacement] {
        guard rows > 0, columns > 0, !modules.isEmpty else { return [] }

        var occupied = Array(
            repeating: Array(repeating: false, count: columns),
            count: rows
        )
        var placements: [NotchCommunicationPlacement] = []

        for module in modules {
            let preferred = span(for: module, rows: rows)
            let candidates = fallbackSpans(preferred: preferred)

            var placed = false
            for candidate in candidates {
                if let placement = findPlacement(
                    module: module,
                    span: candidate,
                    rows: rows,
                    columns: columns,
                    occupied: &occupied
                ) {
                    placements.append(placement)
                    placed = true
                    break
                }
            }

            if !placed {
                continue
            }
        }

        return placements
    }

    private static func span(for module: NotchCommunicationModule, rows: Int) -> GridSpan {
        let size = rows > 1 ? module.expandedSize : module.collapsedSize
        if rows == 1 {
            return GridSpan(columns: size.columns, rows: 1)
        }
        return GridSpan(columns: size.columns, rows: size.rows)
    }

    private static func fallbackSpans(preferred: GridSpan) -> [GridSpan] {
        var result: [GridSpan] = [preferred]
        if preferred.columns == 2 && preferred.rows == 2 {
            result.append(GridSpan(columns: 2, rows: 1))
        }
        if preferred.columns == 2 || preferred.rows == 2 {
            result.append(GridSpan(columns: 1, rows: 1))
        }
        return result
    }

    private static func findPlacement(
        module: NotchCommunicationModule,
        span: GridSpan,
        rows: Int,
        columns: Int,
        occupied: inout [[Bool]]
    ) -> NotchCommunicationPlacement? {
        guard span.columns <= columns, span.rows <= rows else { return nil }

        for row in 0...(rows - span.rows) {
            for column in 0...(columns - span.columns) {
                if canPlace(row: row, column: column, span: span, occupied: occupied) {
                    markOccupied(row: row, column: column, span: span, occupied: &occupied)
                    return NotchCommunicationPlacement(
                        module: module,
                        row: row,
                        column: column,
                        rowSpan: span.rows,
                        columnSpan: span.columns
                    )
                }
            }
        }
        return nil
    }

    private static func canPlace(
        row: Int,
        column: Int,
        span: GridSpan,
        occupied: [[Bool]]
    ) -> Bool {
        for r in row..<(row + span.rows) {
            for c in column..<(column + span.columns) {
                if occupied[r][c] {
                    return false
                }
            }
        }
        return true
    }

    private static func markOccupied(
        row: Int,
        column: Int,
        span: GridSpan,
        occupied: inout [[Bool]]
    ) {
        for r in row..<(row + span.rows) {
            for c in column..<(column + span.columns) {
                occupied[r][c] = true
            }
        }
    }
}

private struct GridSpan: Equatable {
    let columns: Int
    let rows: Int
}
