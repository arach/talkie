//
//  DemoAnchors.swift
//  DemoKit
//
//  Anchor registration system for demo targets.
//  Views register themselves, script references them by ID.
//  No-op when DemoMode.isEnabled == false.
//

import SwiftUI

// MARK: - Anchor Registry

@Observable
public class DemoAnchorRegistry {
    public static let shared = DemoAnchorRegistry()

    /// Registered anchors: id -> frame in window coordinates
    public var anchors: [String: CGRect] = [:]

    private init() {}

    /// Register an anchor with its frame (no-op if demo mode disabled)
    public func register(_ id: String, frame: CGRect) {
        guard DemoMode.isEnabled else { return }
        anchors[id] = frame
    }

    /// Unregister an anchor
    public func unregister(_ id: String) {
        guard DemoMode.isEnabled else { return }
        anchors.removeValue(forKey: id)
    }

    /// Get center point of an anchor
    public func centerOf(_ id: String) -> CGPoint? {
        guard let frame = anchors[id] else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Get frame of an anchor
    public func frameOf(_ id: String) -> CGRect? {
        anchors[id]
    }

    /// Clear all anchors
    public func clear() {
        anchors.removeAll()
    }

    /// Debug: print all registered anchors
    public func dump() {
        print("📍 DemoAnchors (\(anchors.count) registered):")
        for (id, frame) in anchors.sorted(by: { $0.key < $1.key }) {
            print("   \(id): center=(\(Int(frame.midX)), \(Int(frame.midY))) size=\(Int(frame.width))x\(Int(frame.height))")
        }
    }

    /// Export anchors as JSON (for hybrid mode / external tools)
    public func exportJSON() -> String {
        let export = anchors.mapValues { frame in
            [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.width,
                "height": frame.height,
                "centerX": frame.midX,
                "centerY": frame.midY
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: export, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - Anchor Preference Key

struct DemoAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - View Extension

public extension View {
    /// Mark this view as a demo anchor (self-registers on appear, self-unregisters on disappear)
    func demoAnchor(_ id: String) -> some View {
        self.modifier(DemoAnchorModifier(id: id))
    }
}

// MARK: - Anchor Modifier

struct DemoAnchorModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: DemoAnchorPreferenceKey.self, value: .bounds) { anchor in
                [id: anchor]
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                // Use global coordinates for window-relative positioning
                // This works for both internal DemoKit cursor and external automation
                proxy.frame(in: .global)
            } action: { frame in
                DemoAnchorRegistry.shared.register(id, frame: frame)
            }
            .onDisappear {
                // Self-unregister when view disappears
                DemoAnchorRegistry.shared.unregister(id)
            }
    }
}

// MARK: - Anchor Reader (for root view)

public struct DemoAnchorReader<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .onPreferenceChange(DemoAnchorPreferenceKey.self) { anchors in
                // Preferences collected - frames registered via onGeometryChange
            }
    }
}
