//
//  AgentConsoleShell.swift
//  TalkieAgent
//
//  The agent Home's window shell — titlebar, navigation rail, inspector, and
//  status bar — in Talkie's rail style. Built entirely on TalkieKit's shared
//  `ConsoleKit` primitives/tokens; nothing Hudson, nothing copied. This file is
//  agent-local because it's app-shell chrome, not a general primitive.
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - Manifest

struct OpsManifest: Sendable {
    var name: String
    var version: String
    var accent: Color
    var accentSoft: Color
    var targetLabel: String

    init(name: String, version: String,
         accent: Color = OpsInk.accent, accentSoft: Color = OpsInk.accentSoft,
         targetLabel: String = "") {
        self.name = name; self.version = version
        self.accent = accent; self.accentSoft = accentSoft
        self.targetLabel = targetLabel
    }

    init(name: String, version: String, tint: OpsTint, targetLabel: String = "") {
        self.name = name; self.version = version
        self.accent = tint.color; self.accentSoft = tint.color.opacity(OpsOpacity.subtle)
        self.targetLabel = targetLabel
    }
}

private struct OpsManifestKey: EnvironmentKey {
    static let defaultValue = OpsManifest(name: "App", version: "0.0", targetLabel: "")
}

extension EnvironmentValues {
    var opsManifest: OpsManifest {
        get { self[OpsManifestKey.self] }
        set { self[OpsManifestKey.self] = newValue }
    }
}

extension View {
    func opsManifest(_ manifest: OpsManifest) -> some View {
        environment(\.opsManifest, manifest)
    }
}

// MARK: - Titlebar actions

enum OpsTitlebarPlacement: Sendable { case leading, trailing }
enum OpsTitlebarStyle: Sendable { case systemToolbar, contentBar }

struct OpsTitlebarAction {
    var id: String
    var placement: OpsTitlebarPlacement
    var label: String
    var systemImage: String
    var action: () -> Void

    init(id: String, placement: OpsTitlebarPlacement, label: String,
         systemImage: String, action: @escaping () -> Void) {
        self.id = id; self.placement = placement; self.label = label
        self.systemImage = systemImage; self.action = action
    }
}

private struct OpsActionButton: View {
    let action: OpsTitlebarAction
    @State private var hovering = false

    var body: some View {
        Button(action: action.action) {
            Image(systemName: action.systemImage)
                .font(OpsType.ui(OpsSize.md, weight: .medium))
                .foregroundStyle(hovering ? OpsInk.ink : OpsInk.muted)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: OpsRadius.standard).fill(hovering ? OpsSurface.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.label)
    }
}

// MARK: - Chrome shell

/// Talkie-shaped window chrome: slim dark titlebar (title + trailing actions),
/// sidebar | content | inspector body, and a bottom status bar.
struct OpsShell<Leading: View, Trailing: View, Content: View, StatusBar: View>: View {
    private let title: String?
    private let titlebarStyle: OpsTitlebarStyle
    private let titlebarActions: [OpsTitlebarAction]
    private let leading: Leading
    private let trailing: Trailing
    private let content: Content
    private let statusBar: StatusBar

    init(title: String? = nil,
         titlebarStyle: OpsTitlebarStyle = .systemToolbar,
         titlebarActions: [OpsTitlebarAction] = [],
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content,
         @ViewBuilder statusBar: () -> StatusBar) {
        self.title = title
        self.titlebarStyle = titlebarStyle
        self.titlebarActions = titlebarActions
        self.leading = leading()
        self.trailing = trailing()
        self.content = content()
        self.statusBar = statusBar()
    }

    var body: some View {
        // No custom titlebar — the window's native title bar is the only chrome
        // at the top. Body is just sidebar | content | inspector + status bar.
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                trailing
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(OpsHairline.standard).frame(height: 0.5)
            statusBar
        }
        .background(OpsInk.bg)
    }

    private var titleBar: some View {
        HStack(spacing: OpsSpacing.md) {
            ForEach(titlebarActions.filter { $0.placement == .leading }, id: \.id) {
                OpsActionButton(action: $0)
            }
            if let title {
                Text(title)
                    .font(OpsType.ui(OpsSize.sm, weight: .semibold))
                    .foregroundStyle(OpsInk.ink)
            }
            Spacer(minLength: 0)
            ForEach(titlebarActions.filter { $0.placement == .trailing }, id: \.id) {
                OpsActionButton(action: $0)
            }
        }
        .padding(.horizontal, OpsSpacing.xl)
        .frame(height: 34)
        .background(OpsInk.chrome)
    }
}

// MARK: - Inspector

struct OpsInspector<Header: View, Content: View>: View {
    @Binding var isCollapsed: Bool
    private let header: Header
    private let content: Content

    private let width: CGFloat = 280

    init(isCollapsed: Binding<Bool>, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self._isCollapsed = isCollapsed
        self.header = header()
        self.content = content()
    }

    var body: some View {
        if !isCollapsed {
            HStack(spacing: 0) {
                Rectangle().fill(OpsHairline.standard).frame(width: 0.5)
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, OpsSpacing.xl)
                        .padding(.vertical, OpsSpacing.lg)
                    Rectangle().fill(OpsHairline.subtle).frame(height: 0.5)
                    ScrollView { content.padding(OpsSpacing.xl) }
                }
                .frame(width: width)
                .background(OpsInk.chrome)
            }
            .frame(maxHeight: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

struct OpsInspectorToggle: View {
    @Binding var isCollapsed: Bool
    @State private var isHovering = false

    init(isCollapsed: Binding<Bool>) { self._isCollapsed = isCollapsed }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "sidebar.right")
                .font(OpsType.ui(OpsSize.base, weight: .medium))
                .foregroundStyle(isCollapsed ? OpsInk.dim : OpsInk.muted)
                .frame(width: OpsIconSize.medium, height: OpsIconSize.medium)
                .background(RoundedRectangle(cornerRadius: OpsRadius.standard).fill(isHovering ? OpsSurface.hover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: OpsRadius.standard))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isCollapsed ? "Show Inspector" : "Hide Inspector")
    }

    private func toggle() {
        withAnimation(OpsAnimation.chromeResize) { isCollapsed.toggle() }
    }
}
