//
//  StructuralGuidesOverlay.swift
//  Talkie macOS
//
//  Interactive structural guides — draggable horizontal/vertical datum lines.
//  Built-in guides mark header band boundaries. User guides are freely placed.
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Interactive guide overlay — draggable lines with create/delete support.
struct StructuralGuidesOverlay: View {
    @Bindable private var designMode = DesignModeManager.shared

    var body: some View {
        GeometryReader { geometry in
            // Use Canvas for visual lines (non-interactive, always visible)
            Canvas { context, size in
                for guide in designMode.layoutGuides where !guide.isHidden {
                    let color = guide.color
                    if guide.axis == .horizontal {
                        let y = guide.position
                        guard y >= 0 && y <= size.height else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 0.5)
                    } else {
                        let x = guide.position
                        guard x >= 0 && x <= size.width else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 0.5)
                    }
                }
            }
            .allowsHitTesting(false)

            // Interactive labels + drag handles (individual, non-overlapping)
            ForEach(Array(designMode.layoutGuides.enumerated()), id: \.element.id) { index, guide in
                if !guide.isHidden {
                GuideHandle(
                    guide: guide,
                    containerSize: geometry.size,
                    onDrag: { newPos in
                        guard index < designMode.layoutGuides.count else { return }
                        let clamped: CGFloat
                        if guide.axis == .horizontal {
                            clamped = max(0, min(newPos, geometry.size.height))
                        } else {
                            clamped = max(0, min(newPos, geometry.size.width))
                        }
                        designMode.layoutGuides[index].position = clamped
                    },
                    onDelete: guide.isBuiltIn ? nil : {
                        designMode.removeGuide(id: guide.id)
                    }
                )
                }
            }

            // Guide tray (bottom-left)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                GuideTray()
            }
            .padding(.leading, 4)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Guide Handle

/// A single guide's interactive handle.
/// The full line length is a drag target (invisible wide strip).
/// A small colored tab on the edge gives visual affordance; label shows on hover.
private struct GuideHandle: View {
    let guide: LayoutGuide
    let containerSize: CGSize
    let onDrag: (CGFloat) -> Void
    let onDelete: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStart: CGFloat = 0
    @State private var hoverDismissTask: Task<Void, Never>?

    /// How thick the invisible drag strip is (generous for easy grabbing)
    private let stripThickness: CGFloat = 16

    /// Safety net: auto-dismiss hover label after a delay to prevent sticky labels
    private func scheduleHoverDismiss() {
        hoverDismissTask?.cancel()
        hoverDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !isDragging {
                isHovered = false
            }
        }
    }

    var body: some View {
        if guide.axis == .horizontal {
            horizontalHandle
        } else {
            verticalHandle
        }
    }

    // MARK: - Horizontal

    private var horizontalHandle: some View {
        ZStack(alignment: .topLeading) {
            // Full-width invisible drag strip centered on the guide line
            Color.clear
                .frame(width: containerSize.width, height: stripThickness)
                .contentShape(Rectangle())
                .position(x: containerSize.width / 2, y: guide.position)
                .gesture(horizontalDrag)
                .cursor(.resizeUpDown)
                .onHover { hovering in
                    isHovered = hovering
                    if hovering { scheduleHoverDismiss() }
                }

            // Small colored tab at left edge — always visible
            RoundedRectangle(cornerRadius: 2)
                .fill(guide.color.opacity(isDragging ? 1 : 0.7))
                .frame(width: 20, height: isDragging ? 4 : 3)
                .position(x: 10, y: guide.position)
                .allowsHitTesting(false)

            // Label — shown on hover/drag, near left edge
            if isHovered || isDragging {
                labelPill
                    .position(x: 60, y: guide.position - 12)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.1), value: isHovered)
            }
        }
    }

    private var horizontalDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = guide.position
                }
                onDrag(dragStart + value.translation.height)
            }
            .onEnded { _ in isDragging = false }
    }

    // MARK: - Vertical

    private var verticalHandle: some View {
        ZStack(alignment: .topLeading) {
            // Full-height invisible drag strip centered on the guide line
            Color.clear
                .frame(width: stripThickness, height: containerSize.height)
                .contentShape(Rectangle())
                .position(x: guide.position, y: containerSize.height / 2)
                .gesture(verticalDrag)
                .cursor(.resizeLeftRight)
                .onHover { hovering in
                    isHovered = hovering
                    if hovering { scheduleHoverDismiss() }
                }

            // Small colored tab at top edge — always visible
            RoundedRectangle(cornerRadius: 2)
                .fill(guide.color.opacity(isDragging ? 1 : 0.7))
                .frame(width: isDragging ? 4 : 3, height: 20)
                .position(x: guide.position, y: 10)
                .allowsHitTesting(false)

            // Label — shown on hover/drag
            if isHovered || isDragging {
                labelPill
                    .position(x: guide.position + 50, y: 24)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.1), value: isHovered)
            }
        }
    }

    private var verticalDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = guide.position
                }
                onDrag(dragStart + value.translation.width)
            }
            .onEnded { _ in isDragging = false }
    }

    // MARK: - Label (hover only)

    private var labelPill: some View {
        HStack(spacing: 3) {
            Text(guide.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
            Text("\(Int(guide.position))pt")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(guide.color.opacity(0.85)))
        .fixedSize()
    }
}

// MARK: - Guide Tray

/// Expandable tray at the bottom showing all guides. Click a row to scroll/flash that guide.
private struct GuideTray: View {
    @Bindable private var designMode = DesignModeManager.shared
    @State private var isExpanded = false
    @State private var flashingGuideId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                guideList
            }
            trayHeader
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(width: 180)
    }

    // MARK: - Header

    private var trayHeader: some View {
        HStack(spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 8, weight: .bold))

                    Text("\(designMode.layoutGuides.count) guides")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(designMode.guidesSummary, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Copy all guide positions")

            let userCount = designMode.layoutGuides.filter { !$0.isBuiltIn }.count
            if userCount > 0 {
                Button(action: { designMode.clearUserGuides() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Clear custom guides")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Guide List

    private var guideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(designMode.layoutGuides) { guide in
                guideRow(guide)
            }

            Divider().background(Color.white.opacity(0.1))

            // Add guide buttons
            HStack(spacing: 6) {
                Button(action: { designMode.addGuide(axis: .horizontal, position: 100) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 7, weight: .bold))
                        Text("Horizontal").font(.system(size: 8, weight: .medium))
                    }
                    .foregroundColor(.green.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button(action: { designMode.addGuide(axis: .vertical, position: 200) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 7, weight: .bold))
                        Text("Vertical").font(.system(size: 8, weight: .medium))
                    }
                    .foregroundColor(.purple.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func guideRow(_ guide: LayoutGuide) -> some View {
        HStack(spacing: 6) {
            // Color picker (click to cycle / menu to pick)
            Menu {
                ForEach(GuideColor.allCases) { gc in
                    Button(action: { designMode.setGuideColor(id: guide.id, color: gc) }) {
                        HStack {
                            Circle().fill(gc.color).frame(width: 8, height: 8)
                            Text(gc.rawValue.capitalized)
                            if gc == guide.guideColor {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(guide.color)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Axis indicator
            Image(systemName: guide.axis == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down")
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            // Label (click to flash)
            Button(action: { flashGuide(guide.id) }) {
                Text(guide.label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Spacer()

            // Position
            Text("\(Int(guide.position))pt")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            // Visibility toggle
            Button(action: { designMode.toggleGuideHidden(id: guide.id) }) {
                Image(systemName: guide.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(guide.isHidden ? .white.opacity(0.2) : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(guide.isHidden ? "Show guide" : "Hide guide")

            // Delete button (custom only)
            if !guide.isBuiltIn {
                Button(action: { designMode.removeGuide(id: guide.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .opacity(guide.isHidden ? 0.4 : 1.0)
        .background(flashingGuideId == guide.id ? guide.color.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }

    private func flashGuide(_ id: UUID) {
        flashingGuideId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if flashingGuideId == id {
                flashingGuideId = nil
            }
        }
    }
}

#endif
