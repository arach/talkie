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
    // Reflects whether the embedded Talkie keyboard is up. Focus itself is driven
    // imperatively (button → notification → becomeFirstResponder on the real text
    // view); this flag is only updated *by* the editor's begin/end editing so the
    // rest of the SwiftUI tree can observe keyboard state without racing it.
    @State private var isTalkieKeyboardFocused = false
    @State private var showingNotesList = false
    // Owns presentation of the Talkie keyboard (our view, not iOS's inputView).
    @StateObject private var keyboardController = ComposeKeyboardController()

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
                modelOptions: compose.configuredModelOptions,
                activeProviderId: compose.activeDirectProviderId,
                state: compose.state,
                onBack: { AppShellRouter.shared.openHome() },
                onSelectRevisionPath: { compose.selectRevisionPath($0) },
                onSelectModel: { compose.selectDirectModel($0) },
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
                keyboardController: keyboardController,
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
                    NotificationCenter.default.post(name: .composeNextEditorToggleKeyboard, object: nil)
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if keyboardController.isVisible {
                TalkieKeyboardHost(controller: keyboardController)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom))
            }
        }
        .onChange(of: keyboardController.isVisible) { _, up in
            AppShellRouter.shared.isEditorKeyboardUp = up
        }
        .onDisappear {
            AppShellRouter.shared.isEditorKeyboardUp = false
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
                withAnimation(.easeOut(duration: 0.22)) { keyboardController.isVisible = true }
                NotificationCenter.default.post(name: .composeRequestEditorFocus, object: nil)
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
    static let composeNextEditorCopy = Notification.Name("composeNextEditorCopy")
    static let composeNextEditorSelectAll = Notification.Name("composeNextEditorSelectAll")
    /// Show/hide the embedded keyboard. The Coordinator decides which by
    /// reading the text view's real first-responder state, so the tray
    /// button can't desync into a dead toggle.
    static let composeNextEditorToggleKeyboard = Notification.Name("composeNextEditorToggleKeyboard")
    /// Move the text caret one step in a cardinal direction. `userInfo["direction"]`
    /// is "up" | "down" | "left" | "right". Posted repeatedly by the cursor joystick.
    static let composeNextEditorMoveCursor = Notification.Name("composeNextEditorMoveCursor")
}

// MARK: - Talkie keyboard presentation (NOT iOS inputView)

/// Shared bridge between the document editor and the Talkie keyboard. The
/// keyboard is OUR view — it is presented as an ordinary bottom-anchored
/// subview of the Compose layout, never handed to iOS as a `UITextView.inputView`.
/// Doing it this way sidesteps the entire system-keyboard presentation path
/// (and its hardware-keyboard suppression): when we want the keyboard, we just
/// put it on screen.
@MainActor
final class ComposeKeyboardController: ObservableObject {
    /// Drives the slide-in/out of the bottom keyboard.
    @Published var isVisible = false
    /// The editor coordinator — receives key taps via `performKeyboardAction`.
    weak var inputHost: KeyboardInputHost?
    /// Set by the editor so a swipe-down collapse can resign the caret too.
    var onCollapse: (() -> Void)?
}

/// Renders `HostedTalkieKeyboardView` as a normal SwiftUI-hosted view. This is
/// the in-app keyboard the user sees — it does not depend on first-responder
/// key routing; taps flow through `controller.inputHost`.
private struct TalkieKeyboardHost: UIViewRepresentable {
    @ObservedObject var controller: ComposeKeyboardController

    func makeUIView(context: Context) -> HostedTalkieKeyboardView {
        let keyboard = HostedTalkieKeyboardView()
        keyboard.allowsMinimalLayout = false
        keyboard.preferredInitialLayout = .compact
        keyboard.preferredInitialModeId = KeyboardMode.abc.id
        keyboard.resetToPreferredInitialLayout()
        keyboard.inputHost = controller.inputHost
        keyboard.onRequestCollapse = { [weak controller] in
            withAnimation(.easeOut(duration: 0.22)) { controller?.isVisible = false }
            controller?.onCollapse?()
        }
        return keyboard
    }

    func updateUIView(_ keyboard: HostedTalkieKeyboardView, context: Context) {
        // Keep the host pointer fresh if the editor coordinator was recreated.
        keyboard.inputHost = controller.inputHost
    }
}

/// Full-document editor backed by UITextView so the system caret,
/// double-tap word selection, and drag handles behave natively.
/// The Talkie keyboard is presented separately (see `TalkieKeyboardHost`);
/// the system keyboard is suppressed with an empty `inputView`.
private struct ComposeNextDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isKeyboardFocused: Bool
    let keyboardController: ComposeKeyboardController
    let isEditable: Bool
    let textColor: UIColor
    let accentColor: UIColor
    let contentBottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isKeyboardFocused: $isKeyboardFocused, keyboardController: keyboardController)
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
        // NOTE: focus is intentionally NOT driven from here. Auto-focusing /
        // resigning inside updateUIView raced on every SwiftUI render and
        // resigned the keyboard the instant the bound flag read false — the
        // bug behind the "dead" keyboard button. Focus is now purely imperative
        // (toggle/focus/blur notifications → becomeFirstResponder on the text view).
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
        let keyboardController: ComposeKeyboardController
        var isUpdatingFromTextView = false
        weak var textView: UITextView?

        init(text: Binding<String>, isKeyboardFocused: Binding<Bool>, keyboardController: ComposeKeyboardController) {
            self.text = text
            self.isKeyboardFocused = isKeyboardFocused
            self.keyboardController = keyboardController
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCopyRequest),
                name: .composeNextEditorCopy,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSelectAllRequest),
                name: .composeNextEditorSelectAll,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleToggleKeyboardRequest),
                name: .composeNextEditorToggleKeyboard,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMoveCursorRequest(_:)),
                name: .composeNextEditorMoveCursor,
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
            // Suppress the iOS system keyboard entirely. A non-nil empty
            // inputView keeps the caret/selection working while presenting
            // nothing — the Talkie keyboard is shown separately as a normal
            // view (see TalkieKeyboardHost), so iOS never gets a chance to
            // suppress, resize, or otherwise interfere with it.
            textView.inputView = UIView()
            // Route key taps from the Talkie keyboard back into this editor.
            keyboardController.inputHost = self
            keyboardController.onCollapse = { [weak textView] in
                textView?.resignFirstResponder()
            }

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
            // The system spellcheck squiggle is a hard red dotted underline
            // that fights the monochrome canvas — turn it off for a clean
            // writing surface (autocorrect stays on).
            textView.spellCheckingType = .no
            textView.smartDashesType = .yes
            textView.smartQuotesType = .yes
            textView.inputAssistantItem.leadingBarButtonGroups = []
            textView.inputAssistantItem.trailingBarButtonGroups = []
            textView.accessibilityIdentifier = "keyboard.compose"
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
            if keyboardController.inputHost === self {
                keyboardController.inputHost = nil
                keyboardController.onCollapse = nil
            }
            textView = nil
        }

        @objc private func handleFocusRequest() {
            guard let textView else { return }
            requestFocus(for: textView)
        }

        @objc private func handleBlurRequest() {
            withAnimation(.easeOut(duration: 0.22)) { keyboardController.isVisible = false }
            textView?.resignFirstResponder()
        }

        @objc private func handleToggleKeyboardRequest() {
            guard let textView else { return }
            // Show/hide OUR keyboard view — not iOS's. When showing, also take
            // first responder so the caret blinks (the system keyboard stays
            // suppressed via the empty inputView). When hiding, drop the caret.
            let willShow = !keyboardController.isVisible
            withAnimation(.easeOut(duration: 0.22)) { keyboardController.isVisible = willShow }
            if willShow {
                requestFocus(for: textView)
            } else {
                textView.resignFirstResponder()
            }
            isKeyboardFocused.wrappedValue = willShow
        }

        @objc private func handleMoveCursorRequest(_ note: Notification) {
            guard let textView,
                  let raw = note.userInfo?["direction"] as? String else { return }
            let movement: KeyboardCursorMovement
            switch raw {
            case "up": movement = .up
            case "down": movement = .down
            case "left": movement = .left
            case "right": movement = .right
            default: return
            }
            // The caret only moves visibly once the editor is first responder.
            if !textView.isFirstResponder { requestFocus(for: textView) }
            moveCursor(movement, in: textView)
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

        @objc private func handleCopyRequest() {
            guard let textView else { return }
            copySelection(from: textView)
        }

        @objc private func handleSelectAllRequest() {
            guard let textView else { return }
            if !textView.isFirstResponder { textView.becomeFirstResponder() }
            textView.selectAll(nil)
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
            case .selectAll:
                if !textView.isFirstResponder { textView.becomeFirstResponder() }
                textView.selectAll(nil)
            case .toggleShift, .toggleControl, .interrupt:
                break
            case .tab:
                replaceSelection(with: "\t")
            case .escape, .dismissKeyboard:
                withAnimation(.easeOut(duration: 0.22)) { keyboardController.isVisible = false }
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
            label.text = "Start writing, or tap the mic to dictate…"
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
            // Comfortable reading size (18pt), Dynamic-Type aware. Clean sans —
            // a writing canvas, not a dense form field.
            UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .systemFont(ofSize: 18, weight: .regular))
        }

        private static func typingAttributes(textColor: UIColor, font: UIFont) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6          // ~1.4 line-height for readability
            style.paragraphSpacing = 2
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
    let modelOptions: [ComposeStore.ModelOption]
    let activeProviderId: String
    let state: ComposeState
    let onBack: () -> Void
    let onSelectRevisionPath: (ComposeStore.RevisionPath) -> Void
    let onSelectModel: (ComposeStore.ModelOption) -> Void
    let onShowNotes: () -> Void

    private func isActiveModel(_ option: ComposeStore.ModelOption) -> Bool {
        revisionPath == .direct && option.providerId == activeProviderId
    }

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
                        // Model picker — "what can I actually run." Each
                        // configured API key becomes a pickable model; the
                        // Mac bridge sits alongside as another route. A
                        // checkmark marks the active model. When nothing is
                        // set up the section collapses to the setup CTA.
                        Section("Model") {
                            ForEach(modelOptions) { option in
                                Button {
                                    onSelectModel(option)
                                } label: {
                                    Label(
                                        option.menuLabel,
                                        systemImage: isActiveModel(option) ? "checkmark" : "sparkles"
                                    )
                                }
                            }

                            Button {
                                onSelectRevisionPath(.mac)
                            } label: {
                                Label(
                                    "Mac Bridge",
                                    systemImage: revisionPath == .mac ? "checkmark" : "desktopcomputer"
                                )
                            }
                        }

                        Divider()

                        Button {
                            AppShellRouter.shared.openAICredentials()
                        } label: {
                            Label(
                                modelOptions.isEmpty ? "Set up a model…" : "Manage AI keys…",
                                systemImage: "key.fill"
                            )
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
    let keyboardController: ComposeKeyboardController
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
                        keyboardController: keyboardController,
                        isEditable: state == .idle || state == .dictating,
                        textColor: UIColor(theme.colors.textPrimary),
                        accentColor: UIColor(theme.currentTheme.chrome.accent),
                        contentBottomInset: 56
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Win the card's full height ahead of the trailing
                    // Spacer — otherwise the two flexible views split it
                    // ~50/50 and the editor only ever shows the top half,
                    // clipping (and stranding) everything below the fold.
                    .layoutPriority(1)
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

private enum JoystickDirection: Equatable {
    case up, down, left, right

    /// userInfo value for `.composeNextEditorMoveCursor`.
    var value: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        }
    }
}

/// Drives repeated caret moves while the joystick is held. A steady tick + a
/// velocity accumulator gives smooth acceleration: the further the knob is
/// dragged from center, the faster the caret travels.
@MainActor
private final class CursorJoystickDriver: ObservableObject {
    /// Active cardinal direction (nil when centered) — published for the ring highlight.
    @Published private(set) var direction: JoystickDirection?

    private var norm: CGFloat = 0          // 0…1 drag extension past the deadzone
    private var accumulator: Double = 0    // fractional caret steps owed
    private var timer: Timer?

    private let tickInterval = 1.0 / 60.0
    private let deadzone: CGFloat = 8
    private let maxRadius: CGFloat = 64
    private let minSpeed = 3.0   // caret steps / sec just past the deadzone
    private let maxSpeed = 38.0  // caret steps / sec at full extension

    func update(translation: CGSize) {
        let dx = translation.width
        let dy = translation.height
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude > deadzone else { reset(); return }

        let newDirection: JoystickDirection = abs(dx) >= abs(dy)
            ? (dx >= 0 ? .right : .left)
            : (dy >= 0 ? .down : .up)
        norm = min(1, (magnitude - deadzone) / (maxRadius - deadzone))

        if newDirection != direction {
            direction = newDirection
            accumulator = 1  // emit one step immediately on engage / direction flip
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if timer == nil { startTimer() }
    }

    func reset() {
        direction = nil
        norm = 0
        accumulator = 0
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let direction else { return }
        let speed = minSpeed + (maxSpeed - minSpeed) * Double(norm)
        accumulator += speed * tickInterval
        while accumulator >= 1 {
            accumulator -= 1
            NotificationCenter.default.post(
                name: .composeNextEditorMoveCursor,
                object: nil,
                userInfo: ["direction": direction.value]
            )
        }
    }
}

/// Keeps the original popover presentation — a framed pad with the scope target
/// ringed by directional chevrons — but the target is now a live drag joystick:
/// drag it toward a cardinal edge to walk the caret that way, faster the further
/// you pull from center.
private struct CursorJoystickPopover: View {
    @StateObject private var driver = CursorJoystickDriver()
    @ObservedObject private var theme = ThemeManager.shared
    @State private var knobOffset: CGSize = .zero

    private let knobTravel: CGFloat = 16  // visual clamp; input range is larger

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                joystickGlyph("chevron.up", active: driver.direction == .up)
                    .offset(y: -38)
                joystickGlyph("chevron.down", active: driver.direction == .down)
                    .offset(y: 38)
                joystickGlyph("chevron.left", active: driver.direction == .left)
                    .offset(x: -38)
                joystickGlyph("chevron.right", active: driver.direction == .right)
                    .offset(x: 38)

                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.currentTheme.chrome.accentTint))
                    .overlay(Circle().strokeBorder(theme.currentTheme.chrome.accent.opacity(0.35),
                                                   lineWidth: theme.currentTheme.chrome.hairlineWidth))
                    .offset(knobOffset)
            }
            .frame(width: 96, height: 96)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        driver.update(translation: value.translation)
                        let dx = value.translation.width
                        let dy = value.translation.height
                        let magnitude = (dx * dx + dy * dy).squareRoot()
                        if magnitude > 0 {
                            let clamped = min(magnitude, knobTravel)
                            knobOffset = CGSize(width: dx / magnitude * clamped,
                                                height: dy / magnitude * clamped)
                        } else {
                            knobOffset = .zero
                        }
                    }
                    .onEnded { _ in
                        driver.reset()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            knobOffset = .zero
                        }
                    }
            )

            Text("Drag to move cursor")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
        }
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
        .accessibilityElement()
        .accessibilityLabel("Cursor joystick")
        .accessibilityHint("Drag up, down, left, or right to move the cursor")
    }

    private func joystickGlyph(_ systemImage: String, active: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active
                ? theme.currentTheme.chrome.accent
                : theme.colors.textSecondary.opacity(0.5))
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
            // Joystick is the centerpiece: the cursor pad sits dead-center
            // as the hero, flanked by the two clipboard pairs — select·cut
            // to its left, copy·paste to its right (copy/paste being the
            // everyday wins). Voice and keyboard bookend the row at the
            // extremes.
            HStack(spacing: 0) {
                trayButton(systemImage: "dot.radiowaves.left.and.right", accessibilityLabel: "Voice command", action: onVoice)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    trayButton(systemImage: "selection.pin.in.out", accessibilityLabel: "Select all") {
                        NotificationCenter.default.post(name: .composeNextEditorSelectAll, object: nil)
                    }
                    trayButton(systemImage: "scissors", accessibilityLabel: "Cut") {
                        NotificationCenter.default.post(name: .composeNextEditorCut, object: nil)
                    }

                    joystickButton

                    trayButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy") {
                        NotificationCenter.default.post(name: .composeNextEditorCopy, object: nil)
                    }
                    trayButton(systemImage: "doc.on.clipboard", accessibilityLabel: "Paste") {
                        NotificationCenter.default.post(name: .composeNextEditorPaste, object: nil)
                    }
                }
                Spacer(minLength: 8)
                trayButton(
                    systemImage: "keyboard",
                    accessibilityLabel: "Keyboard",
                    accessibilityID: "compose.keyboard.toggle",
                    action: onKeyboard
                )
            }
            .padding(.horizontal, 16)
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

    // The hero cursor pad — accent-tinted and a touch larger than the
    // flanking clipboard buttons so it reads as the row's centerpiece.
    private var joystickButton: some View {
        Button {
            showJoystick = true
        } label: {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(theme.currentTheme.chrome.accentTint)
                        .overlay(Circle().strokeBorder(theme.currentTheme.chrome.accent.opacity(0.35),
                                                       lineWidth: theme.currentTheme.chrome.hairlineWidth))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cursor")
        .popover(isPresented: $showJoystick) {
            CursorJoystickPopover()
        }
    }

    @ViewBuilder
    private func trayButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
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
        .accessibilityIdentifier(accessibilityID ?? "compose.tray.\(accessibilityLabel.lowercased().replacing(" ", with: "-"))")
    }
}
