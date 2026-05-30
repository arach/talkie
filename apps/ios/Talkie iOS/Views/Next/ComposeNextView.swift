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
                state: compose.state,
                dictationPreview: compose.livePartialTranscript,
                voiceCommand: compose.lastCommandTranscript,
                generatingETA: compose.generatingETA,
                diff: compose.pendingDiff,
                documentText: Binding(
                    get: { compose.documentBodyText },
                    set: { compose.updateDocumentBodyText($0) }
                ),
                isKeyboardFocused: $isTalkieKeyboardFocused,
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
                onKeyboard: {
                    if isTalkieKeyboardFocused {
                        NotificationCenter.default.post(name: .composeRequestEditorBlur, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .composeRequestEditorFocus, object: nil)
                    }
                },
                cursorParagraphIndex: Binding(
                    get: { compose.cursorParagraphIndex },
                    set: { compose.cursorParagraphIndex = $0 }
                ),
                paragraphCount: compose.document.paragraphs.count
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            compose.autosave()
        }
        .onAppear {
            // Bottom-right keyboard complication routes here with this
            // flag set — give the editor first-responder so the embedded
            // Talkie keyboard slides up immediately.
            if AppShellRouter.shared.pendingComposeFocus {
                AppShellRouter.shared.pendingComposeFocus = false
                isTalkieKeyboardFocused = true
            }
        }
        .sheet(isPresented: $showingNotesList) {
            ComposeNotesListSheet(activeID: documentID)
        }
    }
}

// MARK: - Document editor (UITextView + Talkie keyboard)

extension Notification.Name {
    static let composeNextEditorPaste = Notification.Name("composeNextEditorPaste")
    static let composeNextEditorCut = Notification.Name("composeNextEditorCut")
}

/// Full-document editor backed by UITextView so the system caret,
/// double-tap word selection, and drag handles behave natively.
/// The in-app Talkie keyboard mounts as `inputView`.
private struct ComposeNextDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isKeyboardFocused: Bool
    let isEditable: Bool
    let textColor: UIColor
    let accentColor: UIColor
    let contentBottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isKeyboardFocused: $isKeyboardFocused)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        context.coordinator.configure(
            textView,
            textColor: textColor,
            accentColor: accentColor,
            bottomInset: contentBottomInset
        )
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isKeyboardFocused = $isKeyboardFocused
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.tintColor = accentColor
        textView.textColor = textColor

        if !context.coordinator.isUpdatingFromTextView, textView.text != text {
            let selectedRange = textView.selectedRange
            context.coordinator.setDocumentText(text, on: textView)
            let maxLocation = (text as NSString).length
            let clampedLocation = min(selectedRange.location, maxLocation)
            let clampedLength = min(selectedRange.length, maxLocation - clampedLocation)
            textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
            context.coordinator.updatePlaceholderVisibility(in: textView)
        }

        if isKeyboardFocused {
            context.coordinator.requestFocus(for: textView)
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        coordinator.teardown()
        uiView.delegate = nil
        uiView.inputView = nil
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, KeyboardInputHost {
        private enum Constants {
            static let placeholderTag = 7_002
        }

        var text: Binding<String>
        var isKeyboardFocused: Binding<Bool>
        var isUpdatingFromTextView = false
        weak var textView: UITextView?
        weak var keyboard: HostedTalkieKeyboardView?

        init(text: Binding<String>, isKeyboardFocused: Binding<Bool>) {
            self.text = text
            self.isKeyboardFocused = isKeyboardFocused
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusRequest),
                name: .composeRequestEditorFocus,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBlurRequest),
                name: .composeRequestEditorBlur,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePasteRequest),
                name: .composeNextEditorPaste,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCutRequest),
                name: .composeNextEditorCut,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func configure(
            _ textView: UITextView,
            textColor: UIColor,
            accentColor: UIColor,
            bottomInset: CGFloat
        ) {
            let keyboard = HostedTalkieKeyboardView()
            keyboard.preferredInitialLayout = .compact
            keyboard.preferredInitialModeId = KeyboardMode.abc.id
            keyboard.inputHost = self
            keyboard.onLayoutHeightChange = { [weak textView] in
                textView?.reloadInputViews()
            }
            keyboard.onRequestCollapse = { [weak textView] in
                textView?.resignFirstResponder()
            }

            textView.inputView = keyboard
            self.keyboard = keyboard

            textView.delegate = self
            textView.backgroundColor = .clear
            textView.textColor = textColor
            textView.tintColor = accentColor
            textView.font = Self.bodyFont
            textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            textView.textContainer.lineFragmentPadding = 0
            textView.isEditable = true
            textView.isSelectable = true
            textView.isScrollEnabled = true
            textView.alwaysBounceVertical = false
            textView.keyboardDismissMode = .none
            textView.autocapitalizationType = .sentences
            textView.autocorrectionType = .yes
            textView.spellCheckingType = .yes
            textView.smartDashesType = .yes
            textView.smartQuotesType = .yes
            textView.inputAssistantItem.leadingBarButtonGroups = []
            textView.inputAssistantItem.trailingBarButtonGroups = []
            applyTypingAttributes(to: textView)
            setDocumentText(text.wrappedValue, on: textView)

            self.textView = textView
            updatePlaceholder(in: textView)
        }

        func setDocumentText(_ value: String, on textView: UITextView) {
            textView.attributedText = NSAttributedString(
                string: value,
                attributes: Self.typingAttributes(
                    textColor: textView.textColor ?? .label,
                    font: Self.bodyFont
                )
            )
            applyTypingAttributes(to: textView)
        }

        func teardown() {
            keyboard?.inputHost = nil
            keyboard?.onRequestCollapse = nil
            keyboard?.onLayoutHeightChange = nil
            keyboard = nil
            textView = nil
        }

        @objc private func handleFocusRequest() {
            guard let textView else { return }
            requestFocus(for: textView)
        }

        @objc private func handleBlurRequest() {
            textView?.resignFirstResponder()
        }

        @objc private func handlePasteRequest() {
            performKeyboardAction(.paste)
        }

        @objc private func handleCutRequest() {
            guard let textView else { return }
            guard textView.selectedRange.length > 0 else { return }
            UIPasteboard.general.string = (textView.text as NSString).substring(with: textView.selectedRange)
            replaceSelection(with: "")
        }

        func requestFocus(for textView: UITextView) {
            guard !textView.isFirstResponder else { return }
            guard textView.window != nil else {
                Task { @MainActor [weak textView] in
                    guard let textView, !textView.isFirstResponder else { return }
                    _ = textView.becomeFirstResponder()
                }
                return
            }
            if !textView.becomeFirstResponder() {
                Task { @MainActor [weak textView] in
                    guard let textView, !textView.isFirstResponder else { return }
                    _ = textView.becomeFirstResponder()
                }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            keyboard?.resetToPreferredInitialLayout()
            isKeyboardFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isKeyboardFocused.wrappedValue = false
        }

        func textViewDidChange(_ textView: UITextView) {
            isUpdatingFromTextView = true
            text.wrappedValue = textView.text
            isUpdatingFromTextView = false
            updatePlaceholderVisibility(in: textView)
        }

        func performKeyboardAction(_ action: KeyboardAction) {
            guard let textView else { return }

            switch action {
            case .insert(let insertedText):
                replaceSelection(with: insertedText)
            case .deleteBackward:
                textView.deleteBackward()
                isUpdatingFromTextView = true
                text.wrappedValue = textView.text
                isUpdatingFromTextView = false
                updatePlaceholderVisibility(in: textView)
            case .copy:
                copySelection(from: textView)
            case .paste:
                guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else { return }
                replaceSelection(with: clipboardText)
            case .toggleShift, .toggleControl, .interrupt:
                break
            case .tab:
                replaceSelection(with: "\t")
            case .escape, .dismissKeyboard:
                textView.resignFirstResponder()
            case .enter:
                replaceSelection(with: "\n")
            case .moveCursor(let movement):
                moveCursor(movement, in: textView)
            }
        }

        private func replaceSelection(with replacement: String) {
            guard let textView else { return }
            let selectedRange = textView.selectedRange
            let current = textView.text ?? ""
            let next = (current as NSString).replacingCharacters(in: selectedRange, with: replacement)
            setDocumentText(next, on: textView)
            textView.selectedRange = NSRange(
                location: selectedRange.location + (replacement as NSString).length,
                length: 0
            )
            isUpdatingFromTextView = true
            text.wrappedValue = next
            isUpdatingFromTextView = false
            updatePlaceholderVisibility(in: textView)
        }

        private func copySelection(from textView: UITextView) {
            guard textView.selectedRange.length > 0 else { return }
            UIPasteboard.general.string = (textView.text as NSString).substring(with: textView.selectedRange)
        }

        private func moveCursor(_ movement: KeyboardCursorMovement, in textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else { return }
            let anchor = selectedRange.start

            let nextPosition: UITextPosition?
            switch movement {
            case .left:
                nextPosition = textView.position(from: anchor, offset: -1)
            case .right:
                nextPosition = textView.position(from: anchor, offset: 1)
            case .up:
                nextPosition = textView.position(from: anchor, in: .up, offset: 1)
            case .down:
                nextPosition = textView.position(from: anchor, in: .down, offset: 1)
            case .wordLeft:
                nextPosition = textView.position(from: anchor, offset: -5)
            case .wordRight:
                nextPosition = textView.position(from: anchor, offset: 5)
            }

            guard let nextPosition,
                  let collapsedRange = textView.textRange(from: nextPosition, to: nextPosition) else {
                return
            }

            textView.selectedTextRange = collapsedRange
        }

        func applyTypingAttributes(to textView: UITextView) {
            textView.typingAttributes = Self.typingAttributes(
                textColor: textView.textColor ?? .label,
                font: Self.bodyFont
            )
        }

        func updatePlaceholder(in textView: UITextView) {
            if let existing = textView.viewWithTag(Constants.placeholderTag) {
                existing.removeFromSuperview()
            }

            let label = UILabel()
            label.tag = Constants.placeholderTag
            label.text = "Tap to write…"
            label.font = Self.bodyFont
            label.textColor = textView.textColor?.withAlphaComponent(0.35)
            label.numberOfLines = 0
            label.isUserInteractionEnabled = false
            label.translatesAutoresizingMaskIntoConstraints = false
            textView.addSubview(label)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: textView.topAnchor),
                label.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            ])

            updatePlaceholderVisibility(in: textView)
        }

        func updatePlaceholderVisibility(in textView: UITextView) {
            textView.viewWithTag(Constants.placeholderTag)?.isHidden = !(textView.text ?? "").isEmpty
        }

        private static var bodyFont: UIFont {
            UIFont.preferredFont(forTextStyle: .body)
        }

        private static func typingAttributes(textColor: UIColor, font: UIFont) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            return [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: style,
            ]
        }
    }
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
    let state: ComposeState
    let dictationPreview: String?
    let voiceCommand: String?
    let generatingETA: String?
    let diff: ComposeStore.Diff?
    @Binding var documentText: String
    @Binding var isKeyboardFocused: Bool
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
                    ComposeNextDocumentEditor(
                        text: $documentText,
                        isKeyboardFocused: $isKeyboardFocused,
                        isEditable: state == .idle || state == .dictating,
                        textColor: UIColor(theme.colors.textPrimary),
                        accentColor: UIColor(theme.currentTheme.chrome.accent),
                        contentBottomInset: 56
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)

                    if state == .dictating, let dictationPreview {
                        DictationPreviewStrip(preview: dictationPreview)
                            .padding(.horizontal, 16)
                    }

                    if state == .listening, let voiceCommand {
                        ListeningStrip(commandText: voiceCommand)
                            .padding(.horizontal, 16)
                    }
                    if state == .generating {
                        GeneratingStrip(eta: generatingETA ?? "~3s")
                            .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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

private struct DictationPreviewStrip: View {
    let preview: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text(preview)
                .talkieType(.preview)
                .italic()
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.currentTheme.chrome.accentTint)
        )
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
        HStack(alignment: .center, spacing: 8) {
            Text("· QUICK")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ComposeStore.QuickTransform.allCases, id: \.self) { transform in
                        Button(action: { onTap(transform) }) {
                            Text(transform.label)
                                .talkieType(.fieldLabel)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
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
                }
            }
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
                    trayButton(systemImage: "scissors", accessibilityLabel: "Cut") {
                        NotificationCenter.default.post(name: .composeNextEditorCut, object: nil)
                    }
                    trayButton(systemImage: "arrow.up.and.down.and.arrow.left.and.right", accessibilityLabel: "Cursor") {
                        showJoystick = true
                    }
                    .popover(isPresented: $showJoystick) {
                        CursorJoystickPopover(
                            cursorParagraphIndex: $cursorParagraphIndex,
                            paragraphCount: paragraphCount
                        )
                    }
                    trayButton(systemImage: "doc.on.clipboard", accessibilityLabel: "Paste") {
                        NotificationCenter.default.post(name: .composeNextEditorPaste, object: nil)
                    }
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
