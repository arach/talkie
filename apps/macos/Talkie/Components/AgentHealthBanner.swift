//
//  AgentHealthBanner.swift
//  Talkie
//
//  Compact toast-style banner that surfaces critical agent health issues
//  (missing permissions, agent not running) so users don't silently fail.
//

import AVFoundation
import SwiftUI
import TalkieKit

private let log = Log(.system)

struct AgentHealthBanner: View {
    private let sm = ServiceManager.shared
    @State private var dismissed = false
    @State private var appeared = false
    @State private var appearTask: Task<Void, Never>?

    private var agentState: AgentServiceState { sm.live }

    private var issue: HealthIssue? {
        if dismissed { return nil }
        guard TalkieEnvironment.current == .production else { return nil }

        if !agentState.isRunning && !agentState.isXPCConnected {
            return .agentNotRunning
        }

        let missingPermissions = productionMissingPermissions
        if !missingPermissions.isEmpty {
            return .missingPermissions(missingPermissions)
        }

        return nil
    }

    private var productionMissingPermissions: [String] {
        var missing: [String] = []
        if agentState.hasAccessibilityPermission == false { missing.append("Accessibility") }
        return missing
    }

    var body: some View {
        Group {
            if let issue, appeared {
                bannerContent(issue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: issue?.id)
        .task(id: issue?.id) {
            // While a permission issue is visible, poll so the banner clears promptly
            // when the user grants access in System Settings and returns.
            guard case .missingPermissions = issue else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                sm.live.refreshPermissions()
            }
        }
        .onAppear {
            // Delay appearance so we don't flash during startup connection
            appearTask = Task {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                appeared = true
            }
        }
        .onDisappear {
            appearTask?.cancel()
        }
    }

    private func bannerContent(_ issue: HealthIssue) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: issue.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(issue.color)

            VStack(alignment: .leading, spacing: 1) {
                Text(issue.title)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foreground)

                Text(issue.subtitle)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Spacing.sm)

            if let action = issue.action {
                Button(action.label) {
                    performAction(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                withAnimation { dismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.backgroundTertiary)
                .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(issue.color.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func performAction(_ action: HealthAction) {
        switch action.kind {
        case .launchAgent:
            sm.launchLive(resolvingConflicts: true)
        case .fixMicrophonePermission:
            Task {
                // Request for Talkie itself — in prod, TalkieAgent is an embedded Login Item
                // so macOS scopes mic access under the parent app's permission.
                await AVAudioApplication.requestRecordPermission()
                let granted = await sm.live.requestMicrophonePermission()
                await MainActor.run {
                    sm.live.refreshPermissions()
                    if granted != true,
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .openSettings:
            NavigationState.shared.navigate(to: .settings)
        case .openSystemPreferences(let pane):
            // NOTE: Pane identifiers (Privacy_Microphone, Privacy_Accessibility) are macOS 13+.
            // Apple may change these across OS versions — no public API for this.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Health Issue Model

private enum HealthIssue: Identifiable {
    case agentNotRunning
    case missingPermissions([String])

    var id: String {
        switch self {
        case .agentNotRunning: return "agent-not-running"
        case .missingPermissions(let p): return "missing-\(p.joined(separator: "-"))"
        }
    }

    var icon: String {
        switch self {
        case .agentNotRunning: return "exclamationmark.triangle.fill"
        case .missingPermissions: return "lock.shield"
        }
    }

    var color: Color {
        switch self {
        case .agentNotRunning: return .orange
        case .missingPermissions: return .red
        }
    }

    var title: String {
        switch self {
        case .agentNotRunning:
            return "Talkie Agent not running"
        case .missingPermissions(let permissions):
            if permissions == ["Accessibility"] {
                return "TalkieAgent accessibility permission missing"
            }
            return "TalkieAgent permissions missing"
        }
    }

    var subtitle: String {
        switch self {
        case .agentNotRunning:
            return "Voice recording and live dictation require the background agent."
        case .missingPermissions(let permissions):
            if permissions.contains("Accessibility") {
                return "Text will be copied to clipboard instead of inserted directly."
            }
            return "Talkie Agent needs attention before background actions can run."
        }
    }

    var action: HealthAction? {
        switch self {
        case .agentNotRunning:
            return HealthAction(label: "Launch", kind: .launchAgent)
        case .missingPermissions:
            return HealthAction(label: "Fix", kind: .openSystemPreferences(pane: "Privacy_Accessibility"))
        }
    }
}

private struct HealthAction {
    let label: String
    let kind: HealthActionKind
}

private enum HealthActionKind {
    case launchAgent
    case fixMicrophonePermission
    case openSettings
    case openSystemPreferences(pane: String)
}
