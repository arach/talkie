//
//  TalkieTooltip.swift
//  Talkie
//
//  Shared hover tooltip — styled pill with directional arrow.
//  Replaces .help() for a consistent, themed look across the app.
//
//  Usage:
//    .talkieTooltip("Screenshot")
//    .talkieTooltip("3 items", edge: .top)
//    .talkieTooltip("Adaptive", preferredEdge: .top)  // flips if clipped
//

import SwiftUI

// MARK: - Tuning

@Observable
@MainActor
final class TooltipTuning {
    static let shared = TooltipTuning()

    var offsetDistance: CGFloat = 8
    var fontSize: CGFloat = 11
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 4
    var cornerRadius: CGFloat = 6
    var shadowRadius: CGFloat = 6
    var shadowOpacity: CGFloat = 0.4
    var arrowSize: CGFloat = 6

    private init() {}
}

// MARK: - Tooltip Modifier

extension View {
    /// Fixed-edge tooltip.
    func talkieTooltip(_ text: String?, edge: Edge = .top, delay: Duration = .milliseconds(400)) -> some View {
        modifier(TalkieTooltipModifier(text: text, preferredEdge: edge, adaptive: false, delay: delay))
    }

    /// Adaptive tooltip — prefers `preferredEdge` but flips if not enough room.
    func talkieTooltip(_ text: String?, preferredEdge: Edge, delay: Duration = .milliseconds(400)) -> some View {
        modifier(TalkieTooltipModifier(text: text, preferredEdge: preferredEdge, adaptive: true, delay: delay))
    }
}

private struct TalkieTooltipModifier: ViewModifier {
    let text: String?
    let preferredEdge: Edge
    let adaptive: Bool
    let delay: Duration

    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var resolvedEdge: Edge?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: delay)
                        guard !Task.isCancelled else { return }
                        showTooltip = true
                    }
                } else {
                    showTooltip = false
                    resolvedEdge = nil
                }
            }
            .background {
                if adaptive && showTooltip {
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            resolvedEdge = resolveEdge(frame: geo.frame(in: .global))
                        }
                    }
                }
            }
            .overlay(alignment: alignment(for: activeEdge)) {
                if showTooltip, let text {
                    TalkieTooltipPill(text: text, arrowEdge: activeEdge)
                        .offset(offset(for: activeEdge))
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: anchorUnit(for: activeEdge))))
                        .allowsHitTesting(false)
                        .zIndex(999)
                }
            }
            .animation(.easeOut(duration: 0.12), value: showTooltip)
    }

    private var activeEdge: Edge {
        resolvedEdge ?? preferredEdge
    }

    private func resolveEdge(frame: CGRect) -> Edge {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return preferredEdge }
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 120

        switch preferredEdge {
        case .trailing:
            if frame.maxX + margin > screenFrame.maxX { return .leading }
        case .leading:
            if frame.minX - margin < screenFrame.minX { return .trailing }
        case .bottom:
            if frame.maxY + margin > screenFrame.maxY { return .top }
        case .top:
            if frame.minY - margin < screenFrame.minY { return .bottom }
        }
        return preferredEdge
    }

    private func alignment(for edge: Edge) -> Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private func offset(for edge: Edge) -> CGSize {
        let d = TooltipTuning.shared.offsetDistance + TooltipTuning.shared.arrowSize
        switch edge {
        case .top: return CGSize(width: 0, height: -d)
        case .bottom: return CGSize(width: 0, height: d)
        case .leading: return CGSize(width: -d, height: 0)
        case .trailing: return CGSize(width: d, height: 0)
        }
    }

    private func anchorUnit(for edge: Edge) -> UnitPoint {
        switch edge {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}

// MARK: - Tooltip Pill + Arrow

private struct TalkieTooltipPill: View {
    let text: String
    let arrowEdge: Edge
    private var tune: TooltipTuning { TooltipTuning.shared }

    var body: some View {
        // Stack pill + arrow in the right direction
        switch arrowEdge {
        case .top:
            // Tooltip above target → arrow points down
            VStack(spacing: 0) {
                pillContent
                TooltipArrow(direction: .down)
                    .fill(Theme.current.surfaceBase)
                    .frame(width: tune.arrowSize * 2, height: tune.arrowSize)
            }
        case .bottom:
            // Tooltip below target → arrow points up
            VStack(spacing: 0) {
                TooltipArrow(direction: .up)
                    .fill(Theme.current.surfaceBase)
                    .frame(width: tune.arrowSize * 2, height: tune.arrowSize)
                pillContent
            }
        case .leading:
            // Tooltip to the left → arrow points right
            HStack(spacing: 0) {
                pillContent
                TooltipArrow(direction: .right)
                    .fill(Theme.current.surfaceBase)
                    .frame(width: tune.arrowSize, height: tune.arrowSize * 2)
            }
        case .trailing:
            // Tooltip to the right → arrow points left
            HStack(spacing: 0) {
                TooltipArrow(direction: .left)
                    .fill(Theme.current.surfaceBase)
                    .frame(width: tune.arrowSize, height: tune.arrowSize * 2)
                pillContent
            }
        }
    }

    private var pillContent: some View {
        Text(text)
            .font(.system(size: tune.fontSize, weight: .medium))
            .foregroundColor(Theme.current.foreground)
            .padding(.horizontal, tune.horizontalPadding)
            .padding(.vertical, tune.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: tune.cornerRadius)
                    .fill(Theme.current.surfaceBase)
                    .shadow(color: .black.opacity(tune.shadowOpacity), radius: tune.shadowRadius, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tune.cornerRadius)
                    .stroke(Theme.current.foreground.opacity(0.12), lineWidth: 0.5)
            )
            .fixedSize()
    }
}

// MARK: - Tooltip Arrow

enum TooltipArrowDirection {
    case up, down, left, right
}

struct TooltipArrow: Shape {
    let direction: TooltipArrowDirection

    func path(in rect: CGRect) -> Path {
        Path { p in
            switch direction {
            case .down:
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            case .up:
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .left:
                p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .right:
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            p.closeSubpath()
        }
    }
}
