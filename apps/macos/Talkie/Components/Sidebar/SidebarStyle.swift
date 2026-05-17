//
//  SidebarStyle.swift
//
//  Per-axis style selectors for the sidebar. Each axis is independent so
//  the user can mix-and-match treatments (e.g. Editorial surface +
//  Kinetic icons + default selection). Selectors persist via AppStorage
//  and propagate via the `\.sidebarStyle` environment.
//
//  All defaults keep the current look — so this file is additive and
//  shipping-safe.
//

import SwiftUI

// MARK: - Axis enums

public enum SidebarSurfaceStyle: String, CaseIterable, Identifiable {
    case `default`
    case glass
    case editorial

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:   return "Base"
        case .glass:     return "Glass"
        case .editorial: return "Print"
        }
    }
}

public enum SidebarIndicatorStyle: String, CaseIterable, Identifiable {
    case `default`
    case glass
    case editorial
    case kinetic

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:   return "Base"
        case .glass:     return "Glass"
        case .editorial: return "Stripe"
        case .kinetic:   return "Spring"
        }
    }
}

public enum SidebarIconStyle: String, CaseIterable, Identifiable {
    case `default`
    case glass
    case editorial
    case kinetic

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:   return "Base"
        case .glass:     return "Bloom"
        case .editorial: return "Quiet"
        case .kinetic:   return "Live"
        }
    }
}

public enum SidebarMotionStyle: String, CaseIterable, Identifiable {
    case `default`
    case editorial
    case kinetic

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:   return "Base"
        case .editorial: return "Slow"
        case .kinetic:   return "Spring"
        }
    }

    /// Spring used for selection slide between rows. Tightened so the
    /// click→selection transition reads as snappy and matches the
    /// instant-tracking hover underlay; the old 0.32s default felt
    /// sluggish next to hover.
    public var selectionSlide: Animation {
        switch self {
        case .default:   return .spring(response: 0.20, dampingFraction: 0.85)
        case .editorial: return .spring(response: 0.30, dampingFraction: 0.92)
        case .kinetic:   return .spring(response: 0.22, dampingFraction: 0.72)
        }
    }
}

/// Depth / separation treatment for the sidebar's outer chrome. Sits
/// orthogonal to surface fill — any effect composes with any surface.
///
/// All shipped effects are GPU-cheap (no offscreen renders, no Gaussian
/// blurs). A `.floating` mode with `.shadow()`-based drop shadow was
/// prototyped and dropped because the blur recomputes per frame during
/// divider drag / resize — interacts poorly with the navigation
/// perceived-perf work and isn't worth the cost.
public enum SidebarEffectStyle: String, CaseIterable, Identifiable {
    /// Flush against window edges — no shadow, hairline only. Default.
    case flush
    /// Full-bleed sidebar + a soft gradient bleeds outward from the
    /// trailing edge into the content area. Subtle "lifted" feel.
    case shadowRail
    /// Full-bleed sidebar + an inner top-edge shadow and a soft bottom
    /// drop shadow. Reads as a recessed well.
    case recessed

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .flush:      return "Flush"
        case .shadowRail: return "Shadow"
        case .recessed:   return "Recessed"
        }
    }
}

// MARK: - Bundle

public struct SidebarStyle: Equatable {
    public var surface: SidebarSurfaceStyle
    public var indicator: SidebarIndicatorStyle
    public var icon: SidebarIconStyle
    public var motion: SidebarMotionStyle
    public var effect: SidebarEffectStyle

    public init(
        surface: SidebarSurfaceStyle = .default,
        indicator: SidebarIndicatorStyle = .default,
        icon: SidebarIconStyle = .default,
        motion: SidebarMotionStyle = .default,
        effect: SidebarEffectStyle = .flush
    ) {
        self.surface = surface
        self.indicator = indicator
        self.icon = icon
        self.motion = motion
        self.effect = effect
    }

    public static let `default` = SidebarStyle()
}

// MARK: - Environment

private struct SidebarStyleKey: EnvironmentKey {
    static let defaultValue: SidebarStyle = .default
}

public extension EnvironmentValues {
    var sidebarStyle: SidebarStyle {
        get { self[SidebarStyleKey.self] }
        set { self[SidebarStyleKey.self] = newValue }
    }
}

// MARK: - AppStorage keys

public enum SidebarStyleStorage {
    public static let surfaceKey   = "sidebar.style.surface"
    public static let indicatorKey = "sidebar.style.indicator"
    public static let iconKey      = "sidebar.style.icon"
    public static let motionKey    = "sidebar.style.motion"
    public static let effectKey    = "sidebar.style.effect"
}
