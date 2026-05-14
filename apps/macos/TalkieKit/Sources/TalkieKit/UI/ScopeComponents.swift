//
//  ScopeComponents.swift
//  TalkieKit
//
//  Small reusable shapes drawn from the oscilloscope vocabulary on
//  usetalkie.com. Each component is a thin convenience over native
//  SwiftUI — the goal is to keep the *vocabulary* portable, not to
//  hide structure behind heavy abstractions.
//
//  Pairs with ScopeDesign.swift for tokens.
//

import SwiftUI

// MARK: - Graticule background

/// Cross-hatched grid background — the "oscilloscope screen" texture.
/// Drawn with a Canvas at a fixed grid pitch and trace-faint stroke.
///
/// Use as a `.background` or in a ZStack behind content. The grid is
/// non-interactive and respects accessibility (skipped under reduce
/// motion / transparency? — no, it's static, so always rendered).
public struct GraticuleBackground: View {
    /// Distance between gridlines in points. 24pt = fine (Security
    /// panel etc.), 48pt = section background.
    public let pitch: CGFloat
    /// Stroke color — defaults to `ScopeTrace.faint`.
    public let color: Color
    /// Overall opacity multiplier — section graticules typically run
    /// 0.30–0.55 in the homepage CSS.
    public let opacity: Double

    public init(
        pitch: CGFloat = 48,
        color: Color = ScopeTrace.faint,
        opacity: Double = 0.40
    ) {
        self.pitch = pitch
        self.color = color
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += pitch
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += pitch
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Eyebrow

/// Leading-dot uppercase caption — the homepage's section header
/// pattern (`· OWNERSHIP`, `· CAPTURE MODES`).
public struct Eyebrow: View {
    public let text: String
    public let color: Color
    public let glow: Bool

    public init(
        _ text: String,
        color: Color = ScopeAmber.solid,
        glow: Bool = true
    ) {
        self.text = text
        self.color = color
        self.glow = glow
    }

    public var body: some View {
        Text("· \(text.uppercased())")
            .font(ScopeType.eyebrow)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(color)
            .modifier(PhosphorGlow(color: color, enabled: glow, radius: 4, opacity: 0.32))
    }
}

// MARK: - ChannelLabel

/// Tiny bordered uppercase tag — the homepage's pin badge pattern
/// (`U1`, `CH-01`, `AG-01`). Rectangular, hairline stroke, no fill.
public struct ChannelLabel: View {
    public let text: String
    public let color: Color
    public let strokeColor: Color

    public init(
        _ text: String,
        color: Color = ScopeAmber.solid,
        strokeColor: Color = ScopeEdge.faint
    ) {
        self.text = text
        self.color = color
        self.strokeColor = strokeColor
    }

    public var body: some View {
        Text(text.uppercased())
            .font(ScopeType.channel)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }
}

// MARK: - PhosphorDot

/// Glowing status dot — the "trigger / live / armed" indicator.
/// 6pt diameter with a soft colored halo.
public struct PhosphorDot: View {
    public let color: Color
    public let size: CGFloat

    public init(color: Color = ScopeAmber.solid, size: CGFloat = 6) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.45), radius: size * 0.6)
    }
}

// MARK: - PhosphorGlow modifier

/// Adds a soft colored halo to text or symbols — the analog of the
/// homepage's `text-shadow: 0 0 4px color-mix(...)` rule.
public struct PhosphorGlow: ViewModifier {
    public let color: Color
    public let enabled: Bool
    public let radius: CGFloat
    public let opacity: Double

    public init(
        color: Color = ScopeAmber.solid,
        enabled: Bool = true,
        radius: CGFloat = 4,
        opacity: Double = 0.32
    ) {
        self.color = color
        self.enabled = enabled
        self.radius = radius
        self.opacity = opacity
    }

    public func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: color.opacity(opacity), radius: radius)
        } else {
            content
        }
    }
}

public extension View {
    /// Apply a phosphor halo for amber / trace-colored text or dots.
    func phosphorGlow(
        color: Color = ScopeAmber.solid,
        radius: CGFloat = 4,
        opacity: Double = 0.32
    ) -> some View {
        modifier(PhosphorGlow(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - InsetStripe modifier

/// Left-edge accent stripe — the "lit row" / "armed channel" affordance.
/// CSS analog: `box-shadow: inset 2px 0 0 0 var(--trace)`.
///
/// Applied as an overlay so it doesn't push layout. Width is 2pt by
/// default; pass a different `Color.clear` to remove without restructuring.
public struct InsetStripe: ViewModifier {
    public let color: Color
    public let width: CGFloat

    public init(color: Color, width: CGFloat = 2) {
        self.color = color
        self.width = width
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: width)
                .allowsHitTesting(false)
        }
    }
}

public extension View {
    /// Apply a left-edge accent stripe (active / armed indicator).
    func insetStripe(_ color: Color, width: CGFloat = 2) -> some View {
        modifier(InsetStripe(color: color, width: width))
    }
}

// MARK: - ScopeDivider

/// Hairline gradient divider that fades at both ends — the homepage's
/// `.hairline` utility. Avoids the heavy "rule" feeling of a solid 1pt
/// line by tapering to transparent at the edges.
public struct ScopeDivider: View {
    public let color: Color
    public let height: CGFloat

    public init(color: Color = ScopeEdge.faint, height: CGFloat = 1) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        LinearGradient(
            colors: [.clear, color, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
    }
}

// MARK: - SignalPath

/// Two-node connector with a glowing gradient arrow — the homepage's
/// `SecurityArrow` pattern. Used between architecture diagram nodes.
public struct SignalPath: View {
    public let color: Color
    public let width: CGFloat

    public init(color: Color = ScopeAmber.solid, width: CGFloat = 40) {
        self.color = color
        self.width = width
    }

    public var body: some View {
        LinearGradient(
            colors: [color.opacity(0.10), color, color.opacity(0.10)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width, height: 1)
        .shadow(color: color.opacity(0.35), radius: 3)
    }
}
