//
//  ConsoleKit.swift
//  TalkieKit
//
//  Talkie's "console" design vocabulary — the dense, dark operational surface
//  used by TalkieAgent's Home and settings. Shared and maintained here in
//  TalkieKit (not copied into a target), Talkie-named, with status color sourced
//  from Talkie's own `SemanticColor`.
//
//  Tokens: OpsInk (palette), OpsSpacing, OpsRadius, OpsType
//  (fonts + size scale), OpsSurface, OpsHairline, OpsTint, plus a
//  few metric helpers. Primitives: OpsCard, OpsInset, OpsKVRow,
//  OpsBadge, OpsStatusDot, OpsSectionLabel, OpsDivider,
//  OpsButton.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Adaptive color

/// A color that resolves to `light` or `dark` based on the view's effective
/// appearance, so Ops surfaces follow the user's light/dark setting instead of
/// being pinned to one palette. The dark values are the original console palette.
@inline(__always)
public func opsAdaptive(light: Color, dark: Color) -> Color {
    #if canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(dark) : NSColor(light)
    })
    #else
    return dark
    #endif
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255)
}

// MARK: - Palette

public enum OpsInk {
    public static let bg      = opsAdaptive(light: rgb(247, 247, 248), dark: rgb(10, 10, 10))
    public static let surface = opsAdaptive(light: rgb(255, 255, 255), dark: rgb(23, 23, 23))
    public static let chrome  = opsAdaptive(light: rgb(237, 237, 239), dark: rgb(6, 6, 6))

    public static let ink   = opsAdaptive(light: rgb(24, 24, 27),    dark: rgb(229, 229, 229))
    public static let muted = opsAdaptive(light: rgb(82, 82, 91),    dark: rgb(163, 163, 163))
    public static let dim   = opsAdaptive(light: rgb(148, 148, 156), dark: rgb(115, 115, 115))

    public static let border = opsAdaptive(light: rgb(228, 228, 231), dark: rgb(39, 39, 39))

    public static let accent     = Color.accentColor
    public static let accentSoft = Color.accentColor.opacity(0.08)

    // Status — sourced from Talkie's own SemanticColor.
    public static let statusOk    = SemanticColor.success
    public static let statusWarn  = SemanticColor.warning
    public static let statusError = SemanticColor.error
    public static let statusInfo  = SemanticColor.info
}

public enum OpsTint: String, CaseIterable, Sendable {
    case red, amber, green, teal, blue, cyan, violet, pink

    public var color: Color {
        switch self {
        case .red:    return Color(red: 0.95, green: 0.40, blue: 0.42)
        case .amber:  return Color(red: 0.96, green: 0.74, blue: 0.36)
        case .green:  return Color(red: 0.43, green: 0.86, blue: 0.55)
        case .teal:   return Color(red: 0.43, green: 0.83, blue: 0.84)
        case .blue:   return Color(red: 0.49, green: 0.71, blue: 0.97)
        case .cyan:   return Color(red: 0.42, green: 0.85, blue: 0.95)
        case .violet: return Color(red: 0.74, green: 0.59, blue: 0.99)
        case .pink:   return Color(red: 0.97, green: 0.58, blue: 0.81)
        }
    }
}

public enum OpsHairline {
    public static let subtle   = opsAdaptive(light: rgb(236, 236, 238), dark: rgb(24, 24, 24))
    public static let standard = opsAdaptive(light: rgb(221, 221, 224), dark: rgb(38, 38, 38))
}

public enum OpsSurface {
    public static let base    = OpsInk.bg
    public static let raised  = OpsInk.surface
    public static let chrome  = OpsInk.chrome
    // Lift/press overlays: white-on-dark, flipped to black-on-light so they
    // read as a subtle darkening rather than vanishing on a light surface.
    public static let inset   = opsAdaptive(light: Color.black.opacity(0.035), dark: Color.white.opacity(0.025))
    public static let hover   = opsAdaptive(light: Color.black.opacity(0.055), dark: Color.white.opacity(0.045))
    public static let press   = opsAdaptive(light: Color.black.opacity(0.075), dark: Color.white.opacity(0.065))
    public static let control = opsAdaptive(light: Color.black.opacity(0.05),  dark: Color.white.opacity(0.05))

    public static func controlHover(isHovering: Bool) -> Color {
        isHovering
            ? opsAdaptive(light: Color.black.opacity(0.085), dark: Color.white.opacity(0.08))
            : control
    }
    public static func tint(_ color: Color, opacity: Double = 0.14) -> Color { color.opacity(opacity) }
    public static func selected(_ color: Color) -> Color { color.opacity(0.10) }
    public static func tintGhost(_ color: Color)  -> Color { color.opacity(0.08) }
    public static func tintFill(_ color: Color)   -> Color { color.opacity(0.14) }
    public static func tintAccent(_ color: Color) -> Color { color.opacity(0.20) }
    public static func tintBorder(_ color: Color) -> Color { color.opacity(0.32) }
    public static func tintMuted(_ color: Color)  -> Color { color.opacity(0.45) }
    public static func tintStrong(_ color: Color) -> Color { color.opacity(0.60) }
    public static func tintFocus(_ color: Color)  -> Color { color.opacity(0.85) }
}

public enum OpsFocus {
    public static let ring = OpsInk.statusInfo.opacity(0.85)
    public static let ringWidth: CGFloat = 1.5
}

// MARK: - Metrics

public enum OpsSpacing {
    public static let xxs: CGFloat = 2
    public static let xs:  CGFloat = 4
    public static let sm:  CGFloat = 6
    public static let md:  CGFloat = 8
    public static let lg:  CGFloat = 10
    public static let xl:  CGFloat = 12
    public static let xxl: CGFloat = 14
    public static let xxxl: CGFloat = 20
    public static let huge: CGFloat = 28
}

public enum OpsRadius {
    public static let tight:    CGFloat = 3
    public static let standard: CGFloat = 6
    public static let card:     CGFloat = 8
}

public enum OpsStroke {
    public static let thin:     CGFloat = 0.5
    public static let standard: CGFloat = 1
    public static let bold:     CGFloat = 2
}

public enum OpsLayout {
    public static let navHeight:        CGFloat = 48
    public static let statusBarHeight:  CGFloat = 28
    public static let buttonHeight:     CGFloat = 32
    public static let rowHeightCompact: CGFloat = 28
    public static let rowHeightRegular: CGFloat = 44
}

public enum OpsOpacity {
    public static let muted:  Double = 0.40
    public static let subtle: Double = 0.08
    public static let ghost:  Double = 0.04
}

public enum OpsDot {
    public static let tiny: CGFloat = 6
}

public enum OpsIconSize {
    public static let small:  CGFloat = 18
    public static let medium: CGFloat = 24
}

public enum OpsAnimation {
    public static let chromeResize = Animation.spring(response: 0.32, dampingFraction: 0.85)
}

// MARK: - Typography

public enum OpsType {
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    public static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

public enum OpsSize {
    public static let micro: CGFloat = 9
    public static let xxs:   CGFloat = 10
    public static let xs:    CGFloat = 11
    public static let sm:    CGFloat = 12
    public static let base:  CGFloat = 13
    public static let md:    CGFloat = 14
    public static let lgm:   CGFloat = 15
    public static let lg:    CGFloat = 16
    public static let xl:    CGFloat = 18
    public static let xxl:   CGFloat = 22
    public static let xxxl:  CGFloat = 28
    public static let hero:  CGFloat = 32
}

// MARK: - Primitives

public struct OpsCard<Content: View>: View {
    public var padding: CGFloat
    public var radius: CGFloat?
    public var fill: Color?
    public var stroke: Color?
    @ViewBuilder public var content: () -> Content

    public init(padding: CGFloat = OpsSpacing.xxl, radius: CGFloat? = nil,
                fill: Color? = nil, stroke: Color? = nil,
                @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.radius = radius
        self.fill = fill; self.stroke = stroke; self.content = content
    }

    public var body: some View {
        let r = radius ?? OpsRadius.card
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: r).fill(fill ?? OpsInk.surface))
            .overlay(RoundedRectangle(cornerRadius: r).stroke(stroke ?? OpsHairline.standard, lineWidth: 1))
    }
}

public struct OpsInset<Content: View>: View {
    public var padding: CGFloat
    public var radius: CGFloat?
    @ViewBuilder public var content: () -> Content

    public init(padding: CGFloat = OpsSpacing.xl, radius: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.radius = radius; self.content = content
    }

    public var body: some View {
        let r = radius ?? OpsRadius.standard
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: r).fill(OpsSurface.inset))
            .overlay(RoundedRectangle(cornerRadius: r).stroke(OpsHairline.subtle, lineWidth: 1))
    }
}

public struct OpsKVRow: View {
    public let key: String
    public let value: String
    public var valueColor: Color
    public var valueLineLimit: Int?

    public init(_ key: String, value: String, valueColor: Color = OpsInk.ink, valueLineLimit: Int? = 2) {
        self.key = key; self.value = value
        self.valueColor = valueColor; self.valueLineLimit = valueLineLimit
    }

    public var body: some View {
        HStack {
            Text(key.uppercased())
                .font(OpsType.mono(9)).tracking(0.8)
                .foregroundStyle(OpsInk.dim).lineLimit(1)
            Spacer()
            Text(value)
                .font(OpsType.mono(11))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(valueLineLimit)
                .truncationMode(.middle)
        }
    }
}

public enum OpsButtonStyle {
    case primary(OpsTint)
    case secondary
    case ghost
}

public struct OpsButton: View {
    public let title: String
    public var icon: String?
    public var style: OpsButtonStyle
    public var instrumentationID: String?
    public var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    public init(_ title: String, icon: String? = nil, style: OpsButtonStyle = .secondary,
                instrumentationID: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.style = style
        self.instrumentationID = instrumentationID; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: OpsSpacing.md) {
                if let icon {
                    Image(systemName: icon).font(OpsType.ui(OpsSize.xs, weight: .semibold))
                }
                Text(title).font(OpsType.mono(OpsSize.xs, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, OpsSpacing.xl)
            .frame(minHeight: OpsLayout.rowHeightCompact)
            .background(RoundedRectangle(cornerRadius: OpsRadius.standard).fill(background))
            .overlay(RoundedRectangle(cornerRadius: OpsRadius.standard).stroke(border, lineWidth: OpsStroke.standard))
            .contentShape(RoundedRectangle(cornerRadius: OpsRadius.standard))
            .opacity(isEnabled ? 1 : OpsOpacity.muted)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }

    private var foreground: Color {
        switch style {
        case .primary(let tint): return isEnabled ? tint.color : OpsInk.dim
        case .secondary:         return isEnabled ? OpsInk.ink : OpsInk.dim
        case .ghost:             return isEnabled ? OpsInk.muted : OpsInk.dim
        }
    }
    private var background: Color {
        switch style {
        case .primary(let tint):
            return OpsSurface.tint(tint.color, opacity: isHovering && isEnabled ? 0.18 : 0.12)
        case .secondary:
            return OpsInk.ink.opacity(isHovering && isEnabled ? OpsOpacity.subtle : OpsOpacity.ghost)
        case .ghost:
            return isHovering && isEnabled ? OpsInk.ink.opacity(OpsOpacity.ghost) : .clear
        }
    }
    private var border: Color {
        switch style {
        case .primary(let tint):
            return isHovering && isEnabled ? OpsSurface.tintFocus(tint.color) : OpsSurface.tintStrong(tint.color)
        case .secondary:
            return isHovering && isEnabled ? OpsSurface.tintMuted(OpsInk.statusInfo) : OpsHairline.standard
        case .ghost:
            return isHovering && isEnabled ? OpsHairline.standard : OpsHairline.subtle
        }
    }
}

public struct OpsBadge: View {
    public let text: String
    public var tint: Color
    public var dot: Bool

    public init(_ text: String, tint: Color = OpsInk.muted, dot: Bool = false) {
        self.text = text; self.tint = tint; self.dot = dot
    }

    public var body: some View {
        HStack(spacing: OpsSpacing.xs) {
            if dot {
                Circle().fill(tint).frame(width: OpsDot.tiny, height: OpsDot.tiny)
            }
            Text(text)
                .font(OpsType.mono(OpsSize.micro, weight: .semibold))
                .tracking(0.8).textCase(.uppercase)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, OpsSpacing.md)
        .padding(.vertical, OpsSpacing.xxs)
        .background(RoundedRectangle(cornerRadius: OpsRadius.tight).fill(OpsSurface.tintFill(tint)))
        .overlay(RoundedRectangle(cornerRadius: OpsRadius.tight).stroke(OpsSurface.tintBorder(tint), lineWidth: OpsStroke.standard))
    }
}

public struct OpsStatusDot: View {
    public var color: Color
    public var size: CGFloat
    public var pulses: Bool
    public var label: String?

    public init(color: Color = OpsInk.statusOk, size: CGFloat = 8, pulses: Bool = false, label: String? = nil) {
        self.color = color; self.size = size; self.pulses = pulses; self.label = label
    }

    public var body: some View {
        ZStack {
            if pulses {
                Circle().fill(OpsSurface.tintBorder(color))
                    .frame(width: size * 1.75, height: size * 1.75).opacity(0.28)
            }
            Circle().fill(color).frame(width: size, height: size)
        }
        .accessibilityHidden(label == nil)
    }
}

public struct OpsSectionLabel: View {
    public let text: String
    public var tint: Color

    public init(_ text: String, tint: Color = OpsInk.muted) {
        self.text = text; self.tint = tint
    }

    public var body: some View {
        Text(text.uppercased())
            .font(OpsType.mono(9, weight: .bold)).tracking(2.0)
            .foregroundStyle(tint)
    }
}

public struct OpsDivider: View {
    public var color: Color
    public var axis: Axis

    public init(color: Color = OpsHairline.subtle, axis: Axis = .horizontal) {
        self.color = color; self.axis = axis
    }

    public var body: some View {
        Rectangle().fill(color)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}
