//
//  SidebarTooltipOverlay.swift
//  TalkieKit
//
//  Renders the sidebar's compact (rail-only) hover tooltip. The shared `Sidebar`
//  writes hover state into `SidebarTooltipState.shared`; the host mounts this
//  view (as an overlay spanning the window) to draw the label beside the rail.
//  Colors are host-supplied so it matches each app's theme — the Talkie app
//  passes its `Theme` colors, TalkieAgent passes Ops tokens.
//

import SwiftUI

public struct SidebarTooltipOverlay: View {
    private let surface: Color
    private let foreground: Color
    private var tooltip: SidebarTooltipState { SidebarTooltipState.shared }
    /// Measured height of the tooltip pill for vertical centering.
    @State private var tooltipHeight: CGFloat = 0

    public init(surface: Color, foreground: Color) {
        self.surface = surface
        self.foreground = foreground
    }

    public var body: some View {
        GeometryReader { geo in
            if let label = tooltip.label {
                // Convert the row's global anchor into overlay-local coordinates.
                let overlayOrigin = geo.frame(in: .global).origin
                let localX = tooltip.anchor.x - overlayOrigin.x
                let localY = tooltip.anchor.y - overlayOrigin.y

                HStack(spacing: 0) {
                    SidebarTooltipArrow()
                        .fill(surface)
                        .frame(width: 6, height: 10)

                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(surface)
                                .shadow(color: .black.opacity(0.5), radius: 8, x: 3, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(foreground.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .fixedSize()
                .background {
                    GeometryReader { tipGeo in
                        Color.clear.onAppear { tooltipHeight = tipGeo.size.height }
                    }
                }
                // Left edge at the row's right edge, vertically centered on the row.
                .offset(x: localX, y: localY - tooltipHeight / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.08), value: label)
            }
        }
    }
}

/// Left-pointing triangle for the sidebar hover tooltip.
struct SidebarTooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
