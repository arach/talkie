//
//  SidebarTooltipState.swift
//  TalkieKit
//
//  Tooltip state for one sidebar host/window in compact (rail-only) mode.
//  Rows emit hover events here; the host renders the tooltip above the sidebar
//  column boundary so it's never clipped. Lives in TalkieKit so the reusable
//  `Sidebar`/`SidebarRow` primitives can drive it without an app dependency.
//

import SwiftUI

@MainActor
@Observable
public final class SidebarTooltipState {
    /// Compatibility fallback for standalone sidebar users. App/window hosts
    /// should inject their own instance so hover state does not cross windows.
    public static let shared = SidebarTooltipState()
    public var label: String?
    public var anchor: CGPoint = .zero // In the host's layout coordinate space
    private var dismissTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?

    public init() {}

    public func show(label: String, anchor: CGPoint) {
        dismissTask?.cancel()
        autoDismissTask?.cancel()
        self.label = label
        self.anchor = anchor
        // Safety net: auto-dismiss after 4s in case onHover exit is missed
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.label == label {
                self.label = nil
            }
        }
    }

    public func updateAnchor(_ anchor: CGPoint) {
        self.anchor = anchor
    }

    public func dismiss(matching label: String) {
        // Delay dismissal so the tooltip doesn't flicker between adjacent items
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if self.label == label {
                self.label = nil
            }
        }
    }
}
