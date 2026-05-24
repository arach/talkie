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
import TalkieMobileKit
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var compose: ComposeStore
    @State private var isTalkieKeyboardFocused = false
    @State private var showingNotesList = false

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
                modelDisplay: compose.modelDisplay,
                revisionPath: compose.revisionPath,
                state: compose.state,
                onBack: { AppShellRouter.shared.openHome() },
                onSelectRevisionPath: { compose.selectRevisionPath($0) },
                onShowNotes: { showingNotesList = true }
            )

            DocumentBody(
                document: compose.document,
                state: compose.state,
                dictationPreview: compose.livePartialTranscript,
                voiceCommand: compose.lastCommandTranscript,
                generatingETA: compose.generatingETA,
                diff: compose.pendingDiff,
                cursorParagraphIndex: compose.cursorParagraphIndex,
                onMic: { compose.toggleDictation() }
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !compose.appliedRevisions.isEmpty {
                RevisionHistoryRollup(
                    revisions: compose.appliedRevisions,
                    onRestore: { compose.restoreRevision($0) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

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
                onKeyboard: { compose.toggleKeyboard() },
                cursorParagraphIndex: Binding(
                    get: { compose.cursorParagraphIndex },
                    set: { compose.cursorParagraphIndex = $0 }
                ),
                paragraphCount: compose.document.paragraphs.count
            )
        }
        .overlay(alignment: .bottomTrailing) {
            // Bridge that hosts the in-app Talkie keyboard
            // (HostedTalkieKeyboardView). Keep UIKit's responder view
            // non-zero sized and fully opaque at the UIView level; a
            // nearly-transparent SwiftUI wrapper can make UITextField
            // first-responder activation flaky, so the field itself hides
            // its visuals with clear colors instead.
            TalkieKeyboardBridge(
                isFocused: $isTalkieKeyboardFocused,
                onInsert: { fragment in
                    compose.applyKeyboardInsert(fragment)
                },
                onDeleteBackward: {
                    compose.applyKeyboardDelete()
                }
            )
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: compose.keyboardFocusRequested) { _, _ in
            isTalkieKeyboardFocused = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            compose.autosave()
        }
        .sheet(isPresented: $showingNotesList) {
            ComposeNotesListSheet(activeID: documentID)
        }
    }
}

// MARK: - Talkie keyboard bridge

/// Hidden UITextField whose `inputView` is `HostedTalkieKeyboardView`.
/// When `isFocused` flips true the field becomes first responder, which
/// slides the in-app Talkie keyboard up. The keyboard's own collapse
/// button calls `resignFirstResponder` to slide it back down; we mirror
/// that back into the binding via the editing-did-end target so the
/// next button tap re-opens cleanly.
///
/// Text input doesn't accumulate in the field — every keystroke fans
/// out through `onInsert` / `onDeleteBackward` so the owning store can
/// drop the fragment at the document's tail. Keeping the field's own
/// `text` empty avoids the system "selection moved" notifications that
/// would otherwise spam the host.
private struct TalkieKeyboardBridge: UIViewRepresentable {
    @Binding var isFocused: Bool
    let onInsert: (String) -> Void
    let onDeleteBackward: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInsert: onInsert, onDeleteBackward: onDeleteBackward)
    }

    func makeUIView(context: Context) -> _TalkieKeyboardBridgeField {
        let field = _TalkieKeyboardBridgeField(frame: .zero)
        field.isAccessibilityElement = false
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = .clear
        field.tintColor = .clear   // hide caret on the invisible bridge
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []

        let keyboard = HostedTalkieKeyboardView()
        keyboard.preferredInitialLayout = .compact
        keyboard.inputHost = context.coordinator
        keyboard.onRequestCollapse = { [weak field] in
            field?.resignFirstResponder()
        }
        keyboard.onLayoutHeightChange = { [weak field] in
            field?.reloadInputViews()
        }

        field.inputView = keyboard
        context.coordinator.field = field
        context.coordinator.keyboard = keyboard

        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingDidEnd),
            for: .editingDidEnd
        )

        return field
    }

    func updateUIView(_ uiView: _TalkieKeyboardBridgeField, context: Context) {
        context.coordinator.onInsert = onInsert
        context.coordinator.onDeleteBackward = onDeleteBackward
        context.coordinator.onResign = {
            // Bounce the binding flip out of UIKit's responder callback
            // so SwiftUI's update pass picks it up cleanly.
            DispatchQueue.main.async { isFocused = false }
        }

        if isFocused {
            context.coordinator.requestFocus(for: uiView)
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: _TalkieKeyboardBridgeField, coordinator: Coordinator) {
        uiView.inputView = nil
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        coordinator.field = nil
        coordinator.keyboard?.inputHost = nil
        coordinator.keyboard?.onRequestCollapse = nil
        coordinator.keyboard?.onLayoutHeightChange = nil
        coordinator.keyboard = nil
    }

    @MainActor
    final class Coordinator: NSObject, KeyboardInputHost {
        var onInsert: (String) -> Void
        var onDeleteBackward: () -> Void
        var onResign: (() -> Void)?
        weak var field: _TalkieKeyboardBridgeField?
        weak var keyboard: HostedTalkieKeyboardView?

        init(onInsert: @escaping (String) -> Void, onDeleteBackward: @escaping () -> Void) {
            self.onInsert = onInsert
            self.onDeleteBackward = onDeleteBackward
        }

        @objc func editingDidEnd() {
            onResign?()
        }

        func requestFocus(for field: _TalkieKeyboardBridgeField) {
            guard !field.isFirstResponder else { return }
            guard field.window != nil else {
                Task { @MainActor [weak field] in
                    guard let field, !field.isFirstResponder else { return }
                    _ = field.becomeFirstResponder()
                }
                return
            }

            if !field.becomeFirstResponder() {
                Task { @MainActor [weak field] in
                    guard let field, !field.isFirstResponder else { return }
                    _ = field.becomeFirstResponder()
                }
            }
        }

        func performKeyboardAction(_ action: KeyboardAction) {
            switch action {
            case .insert(let fragment):
                guard !fragment.isEmpty else { return }
                onInsert(fragment)
            case .deleteBackward:
                onDeleteBackward()
            case .enter:
                onInsert("\n")
            case .tab:
                onInsert("\t")
            case .escape, .dismissKeyboard:
                field?.resignFirstResponder()
            case .paste:
                if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                    onInsert(clipboard)
                }
            case .copy, .toggleShift, .toggleControl, .interrupt, .moveCursor:
                break
            }
        }
    }
}

/// Custom UITextField subclass that suppresses the iOS edit menu and
/// keeps its own text buffer empty — input is routed through
/// `KeyboardInputHost` rather than accumulated locally.
fileprivate final class _TalkieKeyboardBridgeField: UITextField {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override var canBecomeFirstResponder: Bool { true }
}

// MARK: - Header

private struct ComposeHeader: View {
    let backLabel: String
    let modelDisplay: ComposeStore.ModelDisplay
    let revisionPath: ComposeStore.RevisionPath
    let state: ComposeState
    let onBack: () -> Void
    let onSelectRevisionPath: (ComposeStore.RevisionPath) -> Void
    let onShowNotes: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private var accessibilityLabel: String {
        if let standalone = modelDisplay.standaloneLabel { return standalone }
        if let provider = modelDisplay.providerName, let model = modelDisplay.modelId {
            return "\(provider) \(model)"
        }
        return "Choose model"
    }

    var body: some View {
        // ZStack-anchored layout: the centered title is positioned by
        // the ZStack's default .center alignment so it stays on the
        // screen's horizontal center regardless of how long the back
        // button's label is. Back button + ellipsis are pinned to the
        // leading/trailing edges via an overlaid HStack; the back
        // text truncates instead of pushing the title around.
        ZStack {
            // Centered title (always at screen horizontal center).
            // In .diff state the model picker is suppressed — the
            // decision view should focus on the diff itself, not on
            // which API is wired up. Model selection still reachable
            // via the ⋯ menu.
            VStack(spacing: 2) {
                Text(state == .diff ? "· COMPOSE WITH · v1 → v2" : "· COMPOSE WITH")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                if state != .diff {
                    Menu {
                        Section("Revision path") {
                            ForEach(ComposeStore.RevisionPath.allCases) { path in
                                Button {
                                    onSelectRevisionPath(path)
                                } label: {
                                    Label(path.title, systemImage: path.systemImage)
                                }
                            }
                        }

                        Section("Provider") {
                            Button {
                                AppShellRouter.shared.openAICredentials()
                            } label: {
                                Label("Manage AI keys", systemImage: "key.fill")
                            }
                        }

                        Button {
                            onShowNotes()
                        } label: {
                            Label("Open notes", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: revisionPath.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                            ComposeModelGlyph(display: modelDisplay)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.colors.textTertiary)
                                .padding(.leading, 1)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose revision path · \(accessibilityLabel)")
                }
            }

            // Edge-anchored controls
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                        Text(backLabel)
                            .talkieType(.preview)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)
                // Cap back-button width so a long memo title can't
                // grow into the centered title's territory. ~28% of
                // screen leaves the center comfortably visible on
                // 13 mini.
                .frame(maxWidth: 120, alignment: .leading)
                .yieldsToChromeZone(.topLeading)

                Spacer()

                Button(action: onShowNotes) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open notes")
                .yieldsToChromeZone(.topTrailing)
            }
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

// MARK: - Model glyph

/// Renders the active model as Family (serif) + Version (mono) + optional
/// Variant tag — e.g. "GPT 5.5", "Llama 3.3 70B", "Sonnet 4.6". Replaces
/// the flat "OpenAI · gpt-5.5" line so the header reads as a typographied
/// model signature instead of a settings string.
private struct ComposeModelGlyph: View {
    let display: ComposeStore.ModelDisplay

    @ObservedObject private var theme = ThemeManager.shared

    private struct Parsed {
        let family: String
        let version: String?
        let variant: String?
    }

    var body: some View {
        if let standalone = display.standaloneLabel {
            // "Mac Bridge" et al — render as a single serif headline,
            // no version split.
            Text(standalone)
                .talkieType(.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
        } else if let modelId = display.modelId {
            let parsed = Self.parse(modelId)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parsed.family)
                    .talkieType(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                if let version = parsed.version {
                    Text(version)
                        .font(Font.system(size: 12, weight: .regular, design: .monospaced).monospacedDigit())
                        .tracking(0.4)
                        .foregroundStyle(theme.colors.textSecondary)
                        .baselineOffset(2)
                }

                if let variant = parsed.variant {
                    Text(variant)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                        .baselineOffset(2)
                }
            }
        } else {
            // No credentials → quiet sans fallback. Avoids the loud
            // "Direct API" string and invites the menu tap.
            Text("Choose model")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
        }
    }

    /// Parse a provider model id ("gpt-5.5", "llama-3.3-70b-versatile",
    /// "claude-sonnet-4-6") into a renderable family / version / variant
    /// trio. Heuristic — not exhaustive; falls back to capitalized id.
    private static func parse(_ modelId: String) -> Parsed {
        let cleaned = modelId.lowercased()
        // Drop noise tokens that read as marketing strings, not specs.
        let noise: Set<String> = [
            "chat", "latest", "instruct", "preview", "versatile", "turbo",
        ]
        let pieces = cleaned
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !noise.contains($0) }

        guard let head = pieces.first else {
            return Parsed(family: modelId, version: nil, variant: nil)
        }

        // Claude's id puts the size tier ("sonnet") after "claude" — pull
        // it forward so the headline reads as "Sonnet 4.6" rather than
        // "Claude · sonnet · 4 · 6".
        if head == "claude" {
            let rest = Array(pieces.dropFirst())
            let sizeToken = rest.first(where: { ["sonnet", "opus", "haiku"].contains($0) })
            let numeric = rest.filter { $0.first?.isNumber == true }
            let family = sizeToken.map { $0.capitalized } ?? "Claude"
            let version = numeric.isEmpty ? nil : numeric.joined(separator: ".")
            let variantTokens = rest.filter {
                $0 != sizeToken
                    && $0.first?.isNumber != true
            }
            let variant = variantTokens.isEmpty
                ? nil
                : variantTokens.map { $0.uppercased() }.joined(separator: " ")
            return Parsed(family: family, version: version, variant: variant)
        }

        let family = familyName(head)

        var version: String?
        var variantTokens: [String] = []
        for piece in pieces.dropFirst() {
            if version == nil, piece.first?.isNumber == true {
                version = piece
            } else {
                variantTokens.append(piece)
            }
        }
        let variant = variantTokens.isEmpty
            ? nil
            : variantTokens.map { $0.uppercased() }.joined(separator: " ")
        return Parsed(family: family, version: version, variant: variant)
    }

    private static func familyName(_ token: String) -> String {
        switch token {
        case "gpt": return "GPT"
        case "llama": return "Llama"
        case "mistral": return "Mistral"
        case "mixtral": return "Mixtral"
        case "gemini": return "Gemini"
        case "qwen": return "Qwen"
        case "sonnet": return "Sonnet"
        case "opus": return "Opus"
        case "haiku": return "Haiku"
        case "claude": return "Claude"
        default: return token.capitalized
        }
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
    let cursorParagraphIndex: Int
    let onMic: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardSurface

            VStack(alignment: .leading, spacing: 12) {
                if state == .diff, let diff {
                    if let voiceCommand {
                        RequestedStrip(commandText: voiceCommand)
                    }
                    DiffInline(diff: diff)
                } else {
                    ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { idx, para in
                        ParagraphView(
                            text: para,
                            isLast: idx == document.paragraphs.count - 1,
                            dictationPreview: idx == cursorParagraphIndex ? dictationPreview : nil,
                            showCaret: state == .idle && idx == cursorParagraphIndex,
                            accent: theme.currentTheme.chrome.accent
                        )
                    }

                    if state == .listening, let voiceCommand {
                        ListeningStrip(commandText: voiceCommand)
                    }
                    if state == .generating {
                        GeneratingStrip(eta: generatingETA ?? "~3s")
                    }
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
            .talkieType(.listTitle)
            .lineSpacing(4)

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
                .talkieType(.channelLabel)
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text("\u{201C}\(commandText)\u{2026}\u{201D}")
                .talkieType(.fieldLabel)
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
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Text(eta)
                .talkieType(.timestamp)
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

private struct RequestedStrip: View {
    let commandText: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text("REQUESTED")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text("\u{201C}\(commandText)\u{201D}")
                .talkieType(.fieldLabel)
                .italic()
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(Color.red.opacity(0.75))
                Text(diff.original)
                    .talkieType(.listTitle)
                    .lineSpacing(4)
                    .foregroundStyle(theme.colors.textTertiary)
                    .strikethrough(true, color: Color.red.opacity(0.45))
            }

            // v2 — proposed
            VStack(alignment: .leading, spacing: 6) {
                Text("v2 · just now")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text(diff.proposed)
                    .talkieType(.listTitle)
                    .lineSpacing(4)
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
            .talkieType(.channelLabel)
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
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)

            ForEach(ComposeStore.QuickTransform.allCases, id: \.self) { transform in
                Button(action: { onTap(transform) }) {
                    Text(transform.label)
                        .talkieType(.fieldLabel)
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

// MARK: - Revision strip

private struct RevisionHistoryRollup: View {
    let revisions: [ComposeNoteStore.RevisionRecord]
    let onRestore: (ComposeNoteStore.RevisionRecord) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("· VERSIONS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 4)
                Text("\(revisions.count) APPLIED")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(revisions.prefix(8).enumerated(), id: \.element.id) { index, revision in
                        Button {
                            onRestore(revision)
                        } label: {
                            HStack(spacing: 6) {
                                Text("R\((index + 1), format: .number.precision(.integerLength(2)))")
                                    .talkieType(.channelLabelTiny)
                                    .foregroundStyle(index == 0 ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(revision.instruction)
                                        .talkieType(.fieldLabel)
                                        .foregroundStyle(theme.colors.textPrimary)
                                        .lineLimit(1)
                                    Text("\(revision.providerName) · \(revision.scope)")
                                        .talkieType(.timestamp)
                                        .foregroundStyle(theme.colors.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.colors.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                index == 0 ? theme.currentTheme.chrome.accentStrong : theme.currentTheme.chrome.edgeFaint,
                                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Restore revision \(index + 1), \(revision.instruction)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Notes list

private struct ComposeNotesListSheet: View {
    let activeID: String

    @Environment(\.dismiss) private var dismiss
    @State private var notes: [ComposeNoteStore.NoteSummary] = []
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        openNewNote()
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                    }
                }

                Section("Notes") {
                    if notes.isEmpty {
                        Text("No saved notes yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(notes) { note in
                            Button {
                                open(note)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: note.id == activeID ? "checkmark.circle.fill" : "doc.text")
                                        .foregroundStyle(note.id == activeID ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(note.title)
                                            .foregroundStyle(theme.colors.textPrimary)
                                            .lineLimit(1)
                                        Text(note.preview)
                                            .foregroundStyle(theme.colors.textTertiary)
                                            .lineLimit(2)
                                        Text(note.modifiedLabel)
                                            .font(.caption2)
                                            .foregroundStyle(theme.colors.textTertiary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Compose notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: .composeNotesDidChange)) { _ in
                reload()
            }
        }
    }

    private func reload() {
        notes = ComposeNoteStore.all()
    }

    private func open(_ note: ComposeNoteStore.NoteSummary) {
        dismiss()
        AppShellRouter.shared.openCompose(documentID: note.id)
    }

    private func openNewNote() {
        let note = ComposeNoteStore.create()
        guard let id = note.id?.uuidString else { return }
        dismiss()
        AppShellRouter.shared.openCompose(documentID: id)
    }

    private func delete(_ offsets: IndexSet) {
        let ids = offsets.map { notes[$0].id }
        ids.forEach { _ = ComposeNoteStore.delete(id: $0) }
        reload()
    }
}

// MARK: - Cursor joystick

private struct CursorJoystickPopover: View {
    @Binding var cursorParagraphIndex: Int
    let paragraphCount: Int

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Button(action: moveUp) {
                joystickGlyph("chevron.up")
            }
            .disabled(cursorParagraphIndex <= 0)

            HStack(spacing: 8) {
                joystickGlyph("chevron.left")
                    .opacity(0.35)

                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.currentTheme.chrome.accentTint))

                joystickGlyph("chevron.right")
                    .opacity(0.35)
            }

            Button(action: moveDown) {
                joystickGlyph("chevron.down")
            }
            .disabled(cursorParagraphIndex >= max(0, paragraphCount - 1))

            Text("Paragraph \(min(cursorParagraphIndex + 1, max(1, paragraphCount))) of \(max(1, paragraphCount))")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 140, height: 140)
        .background(
            RoundedRectangle(cornerRadius: theme.currentTheme.chrome.chromeCorner + 4)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.currentTheme.chrome.chromeCorner + 4)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
        .presentationCompactAdaptation(.popover)
    }

    private func moveUp() {
        cursorParagraphIndex = max(0, cursorParagraphIndex - 1)
    }

    private func moveDown() {
        cursorParagraphIndex = min(max(0, paragraphCount - 1), cursorParagraphIndex + 1)
    }

    private func joystickGlyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: 34, height: 28)
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

// MARK: - Action tray (or accept/discard during diff)

private struct ActionTray: View {
    let state: ComposeState
    let onAccept: () -> Void
    let onDiscard: () -> Void
    let onRefine: () -> Void
    let onVoice: () -> Void
    let onKeyboard: () -> Void
    @Binding var cursorParagraphIndex: Int
    let paragraphCount: Int

    @State private var showJoystick = false
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
                // Edit cluster — cut · cursor · paste. Cursor button
                // still useful for jumping around the doc; cut/paste
                // are the real wins on mobile edits.
                HStack(spacing: 14) {
                    trayButton(systemImage: "scissors", accessibilityLabel: "Cut") { /* TODO M3: cut */ }
                    trayButton(systemImage: "arrow.up.and.down.and.arrow.left.and.right", accessibilityLabel: "Cursor") {
                        showJoystick = true
                    }
                    .popover(isPresented: $showJoystick) {
                        CursorJoystickPopover(
                            cursorParagraphIndex: $cursorParagraphIndex,
                            paragraphCount: paragraphCount
                        )
                    }
                    trayButton(systemImage: "doc.on.clipboard", accessibilityLabel: "Paste") { /* TODO M3: paste */ }
                }
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
                .talkieType(.fieldLabel)
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
