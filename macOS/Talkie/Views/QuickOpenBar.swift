//
//  QuickOpenBar.swift
//  Talkie
//
//  Quick open content in external apps (Claude, ChatGPT, Notes, etc.)
//

import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "QuickOpenBar")

// MARK: - Quick Open Bar

/// Horizontal bar of app icons for quick-opening content in external apps
struct QuickOpenBar: View {
    let content: String
    var showCopyButton: Bool = true
    var compactMode: Bool = false

    @State private var quickOpenService = QuickOpenService.shared
    @State private var activeTarget: String? = nil  // Currently activated target ID
    @State private var feedbackMessage: String? = nil
    @State private var copiedState = false

    var body: some View {
        HStack(spacing: compactMode ? 4 : 6) {
            // Copy button (always first)
            if showCopyButton {
                CopyButton(
                    isCopied: copiedState,
                    compact: compactMode,
                    action: copyContent
                )
            }

            // Divider between copy and apps
            if showCopyButton && !quickOpenService.enabledTargets.isEmpty {
                Divider()
                    .frame(height: compactMode ? 14 : 18)
            }

            // App target buttons
            ForEach(quickOpenService.enabledTargets) { target in
                QuickOpenButton(
                    target: target,
                    isActive: activeTarget == target.id,
                    compact: compactMode,
                    action: { openInTarget(target) }
                )
            }

            // Feedback message
            if let message = feedbackMessage {
                Text(message)
                    .font(.system(size: compactMode ? 9 : 10, weight: .medium))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, compactMode ? 6 : 8)
        .padding(.vertical, compactMode ? 3 : 5)
        .background(
            RoundedRectangle(cornerRadius: compactMode ? 6 : 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .animation(.easeInOut(duration: 0.15), value: feedbackMessage)
    }

    // MARK: - Actions

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        withAnimation {
            copiedState = true
            feedbackMessage = "Copied"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                copiedState = false
                feedbackMessage = nil
            }
        }

        logger.info("Copied content to clipboard")
    }

    private func openInTarget(_ target: QuickOpenTarget) {
        // Visual feedback
        withAnimation {
            activeTarget = target.id
            feedbackMessage = "Opening \(target.name)..."
        }

        // Execute the open
        quickOpenService.open(content: content, in: target)

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                activeTarget = nil
                feedbackMessage = nil
            }
        }

        logger.info("Opened content in \(target.name)")
    }
}

// MARK: - Copy Button

private struct CopyButton: View {
    let isCopied: Bool
    let compact: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundColor(isCopied ? .green : (isHovered ? .primary : .secondary))
                .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Copy to clipboard")
    }
}

// MARK: - Quick Open Button

private struct QuickOpenButton: View {
    let target: QuickOpenTarget
    let isActive: Bool
    let compact: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isActive {
                    // Active state - checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    // Normal state - real app icon
                    if let bundleId = target.bundleId {
                        AppIconView(bundleIdentifier: bundleId, size: compact ? 16 : 20)
                            .opacity(target.isInstalled ? 1.0 : 0.4)
                    } else {
                        // Fallback to generic icon
                        Image(systemName: "app")
                            .font(.system(size: compact ? 11 : 13))
                            .foregroundColor(isHovered ? .primary : .secondary)
                    }
                }
            }
            .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
        .overlay(alignment: .bottomTrailing) {
            // Keyboard shortcut hint
            if let shortcut = target.keyboardShortcut, !compact {
                Text("⌘\(shortcut)")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(x: 2, y: 2)
            }
        }
        // Dim if app not installed
        .opacity(target.isInstalled ? 1.0 : 0.5)
    }

    private var helpText: String {
        var text = "Open in \(target.name)"
        if let shortcut = target.keyboardShortcut {
            text += " (⌘\(shortcut))"
        }
        if !target.isInstalled {
            text += " (not installed)"
        }
        return text
    }
}

// MARK: - Keyboard Shortcuts Handler

/// View modifier to handle quick open keyboard shortcuts
struct QuickOpenKeyboardShortcuts: ViewModifier {
    let content: String
    let isEnabled: Bool

    @State private var quickOpenService = QuickOpenService.shared

    func body(content view: Content) -> some View {
        view
            .background {
                // Hidden buttons to capture keyboard shortcuts
                if isEnabled {
                    ForEach(1...9, id: \.self) { number in
                        Button("") {
                            quickOpenService.open(content: content, shortcut: number)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                    }
                }
            }
    }
}

extension View {
    /// Adds quick open keyboard shortcuts (⌘1-⌘9) to open content in configured apps
    func quickOpenShortcuts(content: String, enabled: Bool = true) -> some View {
        modifier(QuickOpenKeyboardShortcuts(content: content, isEnabled: enabled))
    }
}

// MARK: - Inline Quick Open (for transcript view)

/// Compact inline toolbar for transcript quick actions
struct InlineQuickOpenBar: View {
    let transcript: String

    var body: some View {
        QuickOpenBar(content: transcript, showCopyButton: true, compactMode: true)
    }
}

// MARK: - Preview

#Preview("Quick Open Bar") {
    VStack(spacing: 20) {
        QuickOpenBar(content: "Sample transcript content for testing quick open functionality.")

        QuickOpenBar(content: "Compact mode", compactMode: true)
    }
    .padding()
    .frame(width: 400)
}
