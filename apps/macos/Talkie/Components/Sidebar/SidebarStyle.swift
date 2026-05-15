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

// MARK: - Bundle

public struct SidebarStyle: Equatable {
    public var surface: SidebarSurfaceStyle
    public var indicator: SidebarIndicatorStyle
    public var icon: SidebarIconStyle
    public var motion: SidebarMotionStyle

    public init(
        surface: SidebarSurfaceStyle = .default,
        indicator: SidebarIndicatorStyle = .default,
        icon: SidebarIconStyle = .default,
        motion: SidebarMotionStyle = .default
    ) {
        self.surface = surface
        self.indicator = indicator
        self.icon = icon
        self.motion = motion
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
}
