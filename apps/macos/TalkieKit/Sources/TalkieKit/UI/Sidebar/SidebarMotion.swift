//
//  SidebarMotion.swift
//
//  Animation tokens for the sidebar component.
//
//  Design contract:
//    • The transition uses a simple eased curve. No spring physics in the
//      hot path — the whole animation is a single duration + easing
//      function evaluation per frame.
//    • Duration and curve are tunable knobs. Hosts can read these defaults
//      or override per-call via `make(duration:curve:)`.
//    • `defaultAnimation` is what gets injected into the environment via
//      `\.sidebarTransition`. Components do NOT read this directly.
//

import SwiftUI

public enum SidebarMotion {
    // MARK: - Tunable params

    /// Default transition duration in seconds.
    public static let defaultDuration: Double = 0.22

    /// Default easing curve.
    public static let defaultCurve: AnimationCurve = .easeInOut

    // MARK: - Curves

    public enum AnimationCurve {
        case linear
        case easeIn
        case easeOut
        case easeInOut

        public func animation(duration: Double) -> Animation {
            switch self {
            case .linear:    return .linear(duration: duration)
            case .easeIn:    return .easeIn(duration: duration)
            case .easeOut:   return .easeOut(duration: duration)
            case .easeInOut: return .easeInOut(duration: duration)
            }
        }
    }

    // MARK: - Resolved animations

    /// The animation hosts should resolve and inject by default.
    /// Spring tuned for a quick, settled transition with no overshoot — wordmark
    /// and labels disappear cleanly, rail icons hold their position.
    public static var defaultAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// Build a custom animation from explicit params.
    public static func make(duration: Double = defaultDuration,
                            curve: AnimationCurve = defaultCurve) -> Animation {
        curve.animation(duration: duration)
    }

    /// Slow-mo helper for design-tool inspection. timeScale > 1 = slower.
    public static func scaled(timeScale: Double, curve: AnimationCurve = defaultCurve) -> Animation {
        let scale = max(0.1, timeScale)
        return curve.animation(duration: defaultDuration * scale)
    }

    // MARK: - Motion mode (test knob)

    /// How the sidebar handles the transition between expanded and compact.
    /// - `smoothFade`: opacities animate continuously with progress (default).
    /// - `quietTransition`: labels/underlay snap OFF the instant transition
    ///   begins; bottom accent bars snap ON only when fully compact. No
    ///   in-flight fading. Use this to isolate column-vs-icon behavior.
    /// - `snapEverything`: discrete state — no animations on anything; the
    ///   column still animates because that's AppKit's job.
    public enum MotionMode {
        case smoothFade
        case quietTransition
        case snapEverything
    }

    /// Process-wide motion mode. Mutable so design tools can switch at runtime.
    /// Lives here (not on `Sidebar`) because `Sidebar` is generic over `Selection`
    /// and Swift forbids static stored properties on generic types.
    public static var mode: MotionMode = .quietTransition

    // MARK: - Legacy tokens (kept for source compatibility)

    /// Horizontal offset applied to fully-collapsed labels. Currently unused.
    public static let hiddenLabelOffset: CGFloat = -6

    /// Source-compatibility shim. Prefer `defaultAnimation` going forward.
    public static var defaultSpring: Animation { defaultAnimation }

    /// Source-compatibility shim. Prefer `scaled(timeScale:)`.
    public static func spring(timeScale: Double = 1.0) -> Animation {
        scaled(timeScale: timeScale)
    }
}
