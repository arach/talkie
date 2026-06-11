//
//  SidebarTransition.swift
//
//  Single source of truth for the sidebar's expanded ↔ compact transition.
//
//  The host computes one `SidebarTransition` per render (from a boolean
//  preference + an optional debug-tool scrub override) and injects it into
//  the view tree via `@Environment(\.sidebarTransition)`. Every leaf view
//  reads the same value — no duplicated progress math, no per-view debug
//  singleton reads, no parameter chains.
//
//  Designed to be portable: no app-specific types referenced. Drop into
//  HudsonKit by renaming `Sidebar*` → `HudsonSidebar*`.
//

import SwiftUI

public struct SidebarTransition: Equatable {
    /// Continuous progress: 0 = fully expanded, 1 = fully compact.
    public let progress: Double

    /// Settled mode bit. Use for accessibility, tooltip gating, and anything
    /// that should snap to discrete states rather than animate.
    public let isCompact: Bool

    /// Current rail width spec — interpolated when scrubbing, snapped otherwise.
    public let width: WidthSpec

    /// Resolved animation curve to use for transition-driven changes.
    /// Provided by the host so the component can be tuned (e.g., slow-mo).
    public let animation: Animation

    /// Equality ignores `animation` — `Animation` isn't Equatable and two
    /// transitions with the same progress/isCompact/width are effectively
    /// the same for environment propagation. Without this conformance,
    /// SwiftUI invalidates every consumer of `\.sidebarTransition` on every
    /// AppNavigation body call, which was a significant perf cost.
    public static func == (lhs: SidebarTransition, rhs: SidebarTransition) -> Bool {
        lhs.progress == rhs.progress
            && lhs.isCompact == rhs.isCompact
            && lhs.width == rhs.width
    }

    public struct WidthSpec: Equatable {
        public let min: CGFloat
        public let ideal: CGFloat
        public let max: CGFloat

        public init(min: CGFloat, ideal: CGFloat, max: CGFloat) {
            self.min = min
            self.ideal = ideal
            self.max = max
        }
    }

    public init(progress: Double, isCompact: Bool, width: WidthSpec, animation: Animation) {
        self.progress = progress
        self.isCompact = isCompact
        self.width = width
        self.animation = animation
    }

    /// Convenience: 1 − progress, for fading content as the rail collapses.
    public var labelOpacity: Double { 1.0 - progress }
}

// MARK: - Resolution

public extension SidebarTransition {
    /// Resolve the transition from the settled boolean preference, optionally
    /// overridden by a continuous scrub value (for design-tool inspection).
    ///
    /// - Parameters:
    ///   - isCompact: settled preference; the boolean the user toggles.
    ///   - scrubOverride: when non-nil, drives `progress` and `width`
    ///     directly. Pass `nil` for normal operation.
    ///   - expanded: width spec when fully expanded.
    ///   - compact:  width spec when fully compact.
    ///   - animation: animation curve for transition-driven changes.
    static func resolve(
        isCompact: Bool,
        scrubOverride: Double?,
        expanded: WidthSpec,
        compact: WidthSpec,
        animation: Animation
    ) -> SidebarTransition {
        if let p = scrubOverride {
            return SidebarTransition(
                progress: p,
                isCompact: isCompact,
                width: .lerp(from: expanded, to: compact, t: CGFloat(p)),
                animation: animation
            )
        }
        return SidebarTransition(
            progress: isCompact ? 1.0 : 0.0,
            isCompact: isCompact,
            width: isCompact ? compact : expanded,
            animation: animation
        )
    }
}

public extension SidebarTransition.WidthSpec {
    static func lerp(from a: Self, to b: Self, t: CGFloat) -> Self {
        Self(
            min: a.min + (b.min - a.min) * t,
            ideal: a.ideal + (b.ideal - a.ideal) * t,
            max: a.max + (b.max - a.max) * t
        )
    }
}

// MARK: - Environment

private struct SidebarTransitionKey: EnvironmentKey {
    static let defaultValue = SidebarTransition(
        progress: 0,
        isCompact: false,
        width: SidebarTransition.WidthSpec(min: 140, ideal: 170, max: 220),
        animation: SidebarMotion.defaultSpring
    )
}

public extension EnvironmentValues {
    var sidebarTransition: SidebarTransition {
        get { self[SidebarTransitionKey.self] }
        set { self[SidebarTransitionKey.self] = newValue }
    }
}

// MARK: - Accent

private struct SidebarAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

public extension EnvironmentValues {
    /// Accent color used for the selection indicator. Default is `.accentColor`;
    /// hosts can override via `.environment(\.sidebarAccent, ...)`.
    var sidebarAccent: Color {
        get { self[SidebarAccentKey.self] }
        set { self[SidebarAccentKey.self] = newValue }
    }
}

// MARK: - Measurements (debug)

private struct SidebarShowMeasurementsKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    /// When true, components draw borders on their icon/label frames so the
    /// host can verify positions during the transition. Hosts wire this to a
    /// debug toggle; defaults to false.
    var sidebarShowMeasurements: Bool {
        get { self[SidebarShowMeasurementsKey.self] }
        set { self[SidebarShowMeasurementsKey.self] = newValue }
    }
}
