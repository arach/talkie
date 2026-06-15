//
//  HomeCardStyle.swift
//  Talkie
//
//  Shared card styling for Home surfaces.
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Card Style Modifier

/// Unified card styling - uses Liquid Glass on macOS 26+, falls back to shadow-based on older
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = CornerRadius.cardLarge
    var padding: CGFloat = Spacing.cardInset

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .liquidGlassCard(
                cornerRadius: cornerRadius,
                fallbackFill: Theme.current.surface2,
                fallbackStroke: Theme.current.divider
            )
            .clipped() // Prevent content from showing outside bounds during transitions
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = CornerRadius.cardLarge, padding: CGFloat = Spacing.cardInset) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - AppKit Hover Chrome

/// Layer-backed hover chrome for hot Home rows/cards.
///
/// Hover is handled inside AppKit so pointer enter/exit does not publish
/// SwiftUI state through every repeated row.
struct HomeHoverChromeStyle {
    var cornerRadius: CGFloat
    var restingFill: NSColor = .clear
    var hoverFill: NSColor
    var restingBorder: NSColor? = nil
    var hoverBorder: NSColor? = nil
    var borderWidth: CGFloat = 0
    var leadingAccent: NSColor? = nil
    var leadingAccentWidth: CGFloat = 0
    var animationDuration: CFTimeInterval = 0.12

    @MainActor
    static func standardRow(cornerRadius: CGFloat = 8) -> HomeHoverChromeStyle {
        HomeHoverChromeStyle(
            cornerRadius: cornerRadius,
            hoverFill: NSColor(Theme.current.surfaceHover).withAlphaComponent(0.72),
            hoverBorder: NSColor(Theme.current.border).withAlphaComponent(0.25),
            borderWidth: 0.5
        )
    }

    static func scopeTipCard(cornerRadius: CGFloat = 6) -> HomeHoverChromeStyle {
        HomeHoverChromeStyle(
            cornerRadius: cornerRadius,
            hoverFill: NSColor(ScopeAmber.tintSubtle),
            hoverBorder: NSColor(ScopeAmber.solid).withAlphaComponent(0.32),
            borderWidth: 0.5
        )
    }

    static func scopeCaptureCard(cornerRadius: CGFloat = 6) -> HomeHoverChromeStyle {
        HomeHoverChromeStyle(
            cornerRadius: cornerRadius,
            hoverFill: NSColor(ScopeAmber.tintSubtle),
            restingBorder: NSColor(ScopeEdge.faint),
            hoverBorder: NSColor(ScopeEdge.normal),
            borderWidth: 0.5
        )
    }

    static func scopeSignalRow() -> HomeHoverChromeStyle {
        HomeHoverChromeStyle(
            cornerRadius: 0,
            hoverFill: NSColor(ScopeCanvas.canvasAlt),
            leadingAccent: NSColor(ScopeAmber.solid),
            leadingAccentWidth: 2
        )
    }
}

struct HomeHoverChrome: NSViewRepresentable {
    let style: HomeHoverChromeStyle

    func makeNSView(context: Context) -> HomeHoverChromeView {
        HomeHoverChromeView(style: style)
    }

    func updateNSView(_ nsView: HomeHoverChromeView, context: Context) {
        nsView.configure(style)
    }
}

final class HomeHoverChromeView: NSView {
    private var style: HomeHoverChromeStyle
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let accentLayer = CALayer()

    override var isFlipped: Bool { true }

    init(style: HomeHoverChromeStyle) {
        self.style = style
        super.init(frame: .zero)

        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.addSublayer(accentLayer)

        applyHover(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ style: HomeHoverChromeStyle) {
        self.style = style
        needsLayout = true
        applyHover(animated: false)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let next = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        trackingArea = next

        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()

        layer?.cornerRadius = style.cornerRadius

        if style.leadingAccentWidth > 0 {
            accentLayer.frame = CGRect(x: 0, y: 0, width: style.leadingAccentWidth, height: bounds.height)
        } else {
            accentLayer.frame = .zero
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyHover(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHover(animated: true)
    }

    private func applyHover(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(style.animationDuration)

        let borderColor = isHovered ? style.hoverBorder : style.restingBorder
        layer?.backgroundColor = (isHovered ? style.hoverFill : style.restingFill).cgColor
        layer?.borderColor = borderColor?.cgColor
        layer?.borderWidth = borderColor == nil ? 0 : style.borderWidth
        accentLayer.backgroundColor = style.leadingAccent?.cgColor
        accentLayer.opacity = isHovered ? 1 : 0

        CATransaction.commit()
    }
}
