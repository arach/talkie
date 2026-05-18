//
//  ComposeNextView.swift
//  Talkie iOS
//
//  M2 — text-editing turns on an existing document. Five states:
//  idle / dictating / listening / generating / diff. Voice command
//  arrives via shell long-press; model returns a transformation
//  rendered as inline diff. Accept/discard applies it.
//
//  Spec: design/studio/app/compose/SWIFT_PORT.md
//  Visual reference: http://localhost:3000/compose
//

import SwiftUI

enum ComposeState: Equatable {
    case idle           // doc shown, caret blinking, ready
    case dictating      // mic hot, new text appearing at cursor
    case listening      // voice command being captured
    case generating     // model running; subtle spinner
    case diff           // model returned a transformation; review
}

struct ComposeNextView: View {
    let documentID: String

    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome
    @StateObject private var compose: ComposeStore
    @FocusState private var keyboardFieldFocused: Bool
    @State private var keyboardBridgeText: String = ""

    init(documentID: String = "mock", store: ComposeStore? = nil) {
        self.documentID = documentID
        _compose = StateObject(wrappedValue: store ?? ComposeStore(documentID: documentID))
    }

    /// Header back-label: short version of the document title, with
    /// a sensible fallback for the empty case.
    private var backTitle: String {
        let title = compose.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.lowercased() == "untitled note" { return "Home" }
        return String(title.prefix(20))
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposeHeader(
                backLabel: backTitle,
                modelLabel: compose.modelLabel,
                state: compose.state,
                onBack: { AppShellRouter.shared.openHome() }
            )

            DocumentBody(
                document: compose.document,
                state: compose.state,
                dictationPreview: compose.livePartialTranscript,
                voiceCommand: compose.lastCommandTranscript,
                generatingETA: compose.generatingETA,
                diff: compose.pendingDiff,
                onMic: { compose.toggleDictation() }
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if compose.state != .diff {
                QuickTransforms(
                    muted: compose.state == .generating || compose.state == .listening,
                    onTap: { compose.applyTransform($0) }
                )
            }

            ActionTray(
                state: compose.state,
                onAccept: { compose.acceptDiff() },
                onDiscard: { compose.discardDiff() },
                onRefine: { compose.discardDiff() },
                onVoice: { compose.toggleVoiceCommand() },
                onKeyboard: { compose.toggleKeyboard() }
            )

            TextField("", text: $keyboardBridgeText)
                .focused($keyboardFieldFocused)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
        .onChange(of: compose.keyboardFocusRequested) { _, _ in
            keyboardFieldFocused = true
        }
    }
}

// MARK: - Header

private struct ComposeHeader: View {
    let backLabel: String
    let modelLabel: String
    let state: ComposeState
    let onBack: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text(backLabel)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(state == .diff ? "· COMPOSE WITH · v1 → v2" : "· COMPOSE WITH")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.92)
                    .foregroundStyle(theme.colors.textTertiary)

                Button(action: { /* TODO: model picker */ }) {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                        Text(modelLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.colors.textPrimary)
                            .tracking(-0.3)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.leading, 1)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }
}

// MARK: - Document body (state-driven)

private struct DocumentBody: View {
    let document: ComposeStore.Document
    let state: ComposeState
    let dictationPreview: String?
    let voiceCommand: String?
    let generatingETA: String?
    let diff: ComposeStore.Diff?
    let onMic: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardSurface

            VStack(alignment: .leading, spacing: 12) {
                if state == .diff, let diff {
                    DiffInline(diff: diff)
                } else {
                    ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { idx, para in
                        ParagraphView(
                            text: para,
                            isLast: idx == document.paragraphs.count - 1,
                            dictationPreview: idx == document.paragraphs.count - 1 ? dictationPreview : nil,
                            showCaret: state == .idle && idx == document.paragraphs.count - 1,
                            accent: theme.currentTheme.chrome.accent
                        )
                    }
                }

                if state == .listening, let voiceCommand {
                    ListeningStrip(commandText: voiceCommand)
                }
                if state == .generating {
                    GeneratingStrip(eta: generatingETA ?? "~3s")
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Inline mic — floats over the bottom of the card; only
            // active outside of the AI loop (idle/diff states).
            if state == .idle || state == .dictating {
                InlineMicButton(state: state, action: onMic)
            }
        }
        .padding(.top, 8)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: theme.currentTheme.chrome.chromeCorner + 6)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: theme.currentTheme.chrome.chromeCorner + 6)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
    }
}

private struct ParagraphView: View {
    let text: String
    let isLast: Bool
    let dictationPreview: String?
    let showCaret: Bool
    let accent: Color

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            (
                Text(text)
                    .foregroundStyle(theme.colors.textPrimary)
                + (dictationPreview.map { preview in
                    Text(" \(preview)")
                        .foregroundStyle(accent)
                        .italic()
                } ?? Text(""))
            )
            .font(.system(size: 15))
            .lineSpacing(4)
            .tracking(-0.07)

            if showCaret {
                BlinkingCaret(color: accent)
                    .padding(.leading, 1)
            }
        }
    }
}

private struct BlinkingCaret: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1.5, height: 14)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                       value: visible)
            .onAppear { visible = false }
    }
}

private struct ListeningStrip: View {
    let commandText: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(theme.currentTheme.chrome.accent)
                        .frame(width: 2, height: CGFloat(4 + (i % 3) * 4))
                }
            }
            .frame(width: 16, height: 12)

            Text("LISTENING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text("\u{201C}\(commandText)\u{2026}\u{201D}")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.currentTheme.chrome.accentTint)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.currentTheme.chrome.accentStrong,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct GeneratingStrip: View {
    let eta: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.6)
            Text("Sonnet 4.6 · iterating")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Text(eta)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

// MARK: - Inline mic (in-document dictation)

private struct InlineMicButton: View {
    let state: ComposeState
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state == .dictating ? theme.currentTheme.chrome.accent : theme.colors.cardBackground)
                    .overlay(Circle().strokeBorder(
                        state == .dictating
                            ? Color.clear
                            : theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    ))
                Image(systemName: state == .dictating ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        state == .dictating
                            ? theme.colors.cardBackground
                            : theme.colors.textSecondary
                    )
            }
            .frame(width: 38, height: 38)
            .shadow(
                color: state == .dictating
                    ? theme.currentTheme.chrome.accentGlow
                    : Color.black.opacity(0.14),
                radius: state == .dictating ? 8 : 5,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 14)
    }
}

// MARK: - Inline diff (vertical stacked: v1 above, v2 below)

struct DiffInline: View {
    let diff: ComposeStore.Diff
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // v1 — what's being replaced
            VStack(alignment: .leading, spacing: 6) {
                Text("v1")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.red.opacity(0.75))
                Text(diff.original)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .tracking(-0.07)
                    .foregroundStyle(theme.colors.textTertiary)
                    .strikethrough(true, color: Color.red.opacity(0.45))
            }

            // v2 — proposed
            VStack(alignment: .leading, spacing: 6) {
                Text("v2 · just now")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text(diff.proposed)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .tracking(-0.07)
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.currentTheme.chrome.accentTint)
                    )
            }

            HStack {
                Text("− \(diff.removedCount)")
                    .foregroundStyle(Color.red.opacity(0.85))
                Text("+ \(diff.addedCount)")
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .padding(.top, 2)
        }
    }
}

// MARK: - Quick transforms row (thin)

private struct QuickTransforms: View {
    let muted: Bool
    let onTap: (ComposeStore.QuickTransform) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Text("· QUICK")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(theme.colors.textTertiary)

            ForEach(ComposeStore.QuickTransform.allCases, id: \.self) { transform in
                Button(action: { onTap(transform) }) {
                    Text(transform.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(theme.colors.cardBackground)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .opacity(muted ? 0.5 : 1)
        .overlay(
            // Single top hairline separates QUICK from the document
            // card above. The action tray below flows visually as
            // the same footer cluster — no divider between them.
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .top
        )
    }
}

// MARK: - Action tray (or accept/discard during diff)

private struct ActionTray: View {
    let state: ComposeState
    let onAccept: () -> Void
    let onDiscard: () -> Void
    let onRefine: () -> Void
    let onVoice: () -> Void
    let onKeyboard: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if state == .diff {
            HStack(spacing: 8) {
                actionChip(label: "Discard", active: false, action: onDiscard)
                actionChip(label: "Refine command", active: false, action: onRefine)
                actionChip(label: "Accept", active: true, action: onAccept)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else {
            HStack {
                trayButton(systemImage: "dot.radiowaves.left.and.right", accessibilityLabel: "Voice command", action: onVoice)
                Spacer()
                trayButton(systemImage: "keyboard", accessibilityLabel: "Keyboard", action: onKeyboard)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func actionChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? theme.colors.cardBackground : theme.colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(active ? theme.currentTheme.chrome.accent : Color.clear)
                        .overlay(
                            Capsule().strokeBorder(
                                active ? Color.clear : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trayButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(theme.colors.cardBackground)
                        .overlay(Circle().strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                                       lineWidth: theme.currentTheme.chrome.hairlineWidth))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
