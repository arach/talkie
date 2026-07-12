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
                activeModelId: compose.activeDirectModelId,
                // Mac Bridge is a route, not a model — only offer it when the
                // bridge is actually connected (a "known good state"). The
                // picker is otherwise purely about the direct models you can run.
                macBridgeConnected: BridgeManager.shared.status == .connected,
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
                runningModelLabel: compose.runningModelLabel,
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

            ActionTray(
                state: compose.state,
                onAccept: { compose.acceptDiff() },
                onDiscard: { compose.discardDiff() },
                onRefine: { compose.discardDiff() },
                onKeyboard: {
                    NotificationCenter.default.post(name: .composeNextEditorToggleKeyboard, object: nil)
                }
            )

            // Keep the contextual action rail below the center Talkie pivot.
            // In review, ActionTray itself is the bottom rail; while writing,
            // the cursor/keyboard lane holds the pivot and quick transforms
            // become the final row beneath it.
            if compose.state != .diff {
                QuickTransforms(
                    state: compose.state,
                    onTap: { compose.applyTransform($0) },
                    onCommand: { compose.toggleVoiceCommand() }
                )
            }
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
    /// Insert a space / newline at the caret (replacing any selection). Posted
    /// by the editor tool row so quick edits don't need the full keyboard.
    static let composeNextEditorInsertSpace = Notification.Name("composeNextEditorInsertSpace")
    static let composeNextEditorInsertNewline = Notification.Name("composeNextEditorInsertNewline")
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
        keyboard.overrideUserInterfaceStyle = Self.keyboardStyle()
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
        keyboard.overrideUserInterfaceStyle = Self.keyboardStyle()
    }

    /// The keyboard's keycap palette is UIKit trait-driven (light/dark).
    /// Pin it to the *Talkie theme's* luminance, not the device's system
    /// appearance — otherwise a dark Talkie theme on a light-mode phone
    /// paints pale keycaps on the dark editor (and vice-versa).
    private static func keyboardStyle() -> UIUserInterfaceStyle {
        let bg = UIColor(ThemeManager.shared.colors.background)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard bg.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .dark }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5 ? .dark : .light
    }
}

/// Full-document editor backed by UITextView so the system caret,
/// double-tap word selection, and drag handles behave natively.
/// The Talkie keyboard is presented separately (see `TalkieKeyboardHost`);
/// the system keyboard is suppressed with an empty `inputView`.
private struct ComposeNextDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isKeyboardFocused: Bool
    @Binding var isMicVisible: Bool
    let keyboardController: ComposeKeyboardController
    let isEditable: Bool
    let textColor: UIColor
    let accentColor: UIColor
    let contentBottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isKeyboardFocused: $isKeyboardFocused,
            isMicVisible: $isMicVisible,
            keyboardController: keyboardController
        )
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
        context.coordinator.isMicVisible = $isMicVisible
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
        var isMicVisible: Binding<Bool>
        let keyboardController: ComposeKeyboardController
        var isUpdatingFromTextView = false
        weak var textView: UITextView?
        private var lastScrollOffset: CGFloat = 0

        init(
            text: Binding<String>,
            isKeyboardFocused: Binding<Bool>,
            isMicVisible: Binding<Bool>,
            keyboardController: ComposeKeyboardController
        ) {
            self.text = text
            self.isKeyboardFocused = isKeyboardFocused
            self.isMicVisible = isMicVisible
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
                selector: #selector(handleInsertSpaceRequest),
                name: .composeNextEditorInsertSpace,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertNewlineRequest),
                name: .composeNextEditorInsertNewline,
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

        @objc private func handleInsertSpaceRequest() {
            guard let textView else { return }
            if !textView.isFirstResponder { requestFocus(for: textView) }
            replaceSelection(with: " ")
        }

        @objc private func handleInsertNewlineRequest() {
            guard let textView else { return }
            if !textView.isFirstResponder { requestFocus(for: textView) }
            replaceSelection(with: "\n")
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

        // Scroll-aware inline mic: it sinks away as you scroll down into
        // the text (so it stops sitting over what you're reading) and
        // glides back when you scroll up or reach the top.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offset = scrollView.contentOffset.y
            defer { lastScrollOffset = offset }
            // Always show near the very top — nothing to get out of the way of.
            if offset <= 12 {
                setMicVisible(true)
                return
            }
            let delta = offset - lastScrollOffset
            if delta > 4 {
                setMicVisible(false)        // scrolling down → tuck away
            } else if delta < -4 {
                setMicVisible(true)         // scrolling up → bring back
            }
        }

        private func setMicVisible(_ visible: Bool) {
            guard isMicVisible.wrappedValue != visible else { return }
            isMicVisible.wrappedValue = visible
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
            // Comfortable reading size (17pt), Dynamic-Type aware. Clean sans —
            // a writing canvas, not a dense form field.
            UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .systemFont(ofSize: 17, weight: .regular))
        }

        private static func typingAttributes(textColor: UIColor, font: UIFont) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 5          // ~1.35 line-height for readability
            style.paragraphSpacing = 1.5
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
    let activeModelId: String
    let macBridgeConnected: Bool
    let state: ComposeState
    let onBack: () -> Void
    let onSelectRevisionPath: (ComposeStore.RevisionPath) -> Void
    let onSelectModel: (ComposeStore.ModelOption) -> Void
    let onShowNotes: () -> Void

    private func isActiveModel(_ option: ComposeStore.ModelOption) -> Bool {
        revisionPath == .direct
            && option.providerId == activeProviderId
            && option.modelId == activeModelId
    }

    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var onDeviceAI = OnDeviceAIService.shared

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
                        // configured API key becomes a pickable model. The
                        // Mac Bridge is a *route*, not a model, so it only
                        // appears when the bridge is actually connected (a
                        // known-good state). The picker stays independent of
                        // bridge/encryption config — it lists the models that
                        // should just work. With nothing configured it
                        // collapses to a single get-started CTA.
                        if modelOptions.isEmpty && !macBridgeConnected && !onDeviceAI.isAvailable {
                            Button {
                                AppShellRouter.shared.openAICredentials()
                            } label: {
                                Label("Pick a provider to get started…", systemImage: "sparkles")
                            }
                        } else {
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

                                if macBridgeConnected {
                                    Button {
                                        onSelectRevisionPath(.mac)
                                    } label: {
                                        Label(
                                            "Mac Bridge",
                                            systemImage: revisionPath == .mac ? "checkmark" : "desktopcomputer"
                                        )
                                    }
                                }

                                if onDeviceAI.isAvailable {
                                    Button {
                                        onSelectRevisionPath(.apple)
                                    } label: {
                                        Label(
                                            "Apple Intelligence",
                                            systemImage: revisionPath == .apple ? "checkmark" : "sparkles"
                                        )
                                    }
                                }
                            }

                            Divider()

                            Button {
                                AppShellRouter.shared.openAICredentials()
                            } label: {
                                Label("Manage AI keys…", systemImage: "key.fill")
                            }
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
    let runningModelLabel: String
    @Binding var documentText: String
    @Binding var isKeyboardFocused: Bool
    let keyboardController: ComposeKeyboardController
    let onMic: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var isMicVisible = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardSurface

            VStack(alignment: .leading, spacing: 12) {
                if state == .diff, let diff {
                    if let voiceCommand {
                        RequestedStrip(commandText: voiceCommand)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                    }
                    ScrollView {
                        DiffInline(diff: diff)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                } else {
                    ComposeNextDocumentEditor(
                        text: $documentText,
                        isKeyboardFocused: $isKeyboardFocused,
                        isMicVisible: $isMicVisible,
                        keyboardController: keyboardController,
                        isEditable: state == .idle || state == .dictating,
                        textColor: UIColor(theme.colors.textPrimary),
                        accentColor: UIColor(theme.currentTheme.chrome.accent),
                        contentBottomInset: 72
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Win the card's full height ahead of the trailing
                    // Spacer — otherwise the two flexible views split it
                    // ~50/50 and the editor only ever shows the top half,
                    // clipping (and stranding) everything below the fold.
                    .layoutPriority(1)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    if state == .dictating, let dictationPreview {
                        DictationPreviewStrip(preview: dictationPreview)
                            .padding(.horizontal, 16)
                    }

                    if state == .listening, let voiceCommand {
                        ListeningStrip(commandText: voiceCommand)
                            .padding(.horizontal, 16)
                    }
                    if state == .generating {
                        GeneratingStrip(modelLabel: runningModelLabel, eta: generatingETA ?? "~3s")
                            .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Inline mic — floats over the bottom of the card; only
            // active outside of the AI loop (idle/diff states). Sinks
            // out of the way while scrolling down so it stops covering
            // the text you're reading, glides back on scroll-up.
            if state == .idle || state == .dictating {
                EditorBottomChromeFade()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                ComposeFloatingTools(state: state, onMic: onMic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14)
                    .opacity(isMicVisible ? 1 : 0)
                    .scaleEffect(isMicVisible ? 1 : 0.85, anchor: .bottom)
                    .offset(y: isMicVisible ? 0 : 16)
                    .allowsHitTesting(isMicVisible)
                    .animation(.easeOut(duration: 0.2), value: isMicVisible)
            }
        }
        .padding(.top, 6)
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

private struct EditorBottomChromeFade: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    theme.colors.cardBackground.opacity(0),
                    theme.colors.cardBackground.opacity(0.14),
                    theme.colors.cardBackground.opacity(0.24),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)

            Rectangle()
                .fill(theme.colors.cardBackground.opacity(0.18))
                .frame(height: 18)
        }
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
    let modelLabel: String
    let eta: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GeneratingActivityGlyph()
                    .frame(width: 34, height: 16)

                Text("\(modelLabel) · iterating")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer()

                Text(eta)
                    .talkieType(.timestamp)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            GeneratingVelocityRail()
                .frame(height: 3)
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

private struct GeneratingActivityGlyph: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: TalkieMotion.isReduced)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let pulse = 0.5 + 0.5 * sin(time * 9.5 + Double(index) * 0.72)
                    Capsule()
                        .fill(index == 2 ? theme.currentTheme.chrome.accent : theme.currentTheme.chrome.accent.opacity(0.58))
                        .frame(width: 3, height: CGFloat(5.5 + pulse * 9.5))
                        .shadow(color: theme.currentTheme.chrome.accentGlow.opacity(0.35), radius: CGFloat(pulse * 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GeneratingVelocityRail: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: TalkieMotion.isReduced)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            GeometryReader { proxy in
                let width = proxy.size.width
                let travel = max(width + 48, 1)
                let phase = CGFloat(time * 210).truncatingRemainder(dividingBy: travel)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.55))

                    ForEach(0..<3, id: \.self) { index in
                        let x = (phase + CGFloat(index) * 52).truncatingRemainder(dividingBy: travel) - 24
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        theme.currentTheme.chrome.accent.opacity(0.0),
                                        theme.currentTheme.chrome.accent.opacity(0.95),
                                        theme.currentTheme.chrome.accent.opacity(0.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 44, height: 3)
                            .offset(x: x)
                    }
                }
            }
        }
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
        Button(action: {
            // Light "go" when starting dictation, firm "caught it" when stopping.
            Haptics.play(state == .dictating ? .transition : .confirm)
            action()
        }) {
            ZStack {
                Image(systemName: state == .dictating ? "stop.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }
            .frame(width: 31, height: 30)
            .background(commandKeyBackground(isActive: state == .dictating))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(state == .dictating ? "Stop dictation" : "Start dictation")
    }

    private func commandKeyBackground(isActive: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
            .fill(theme.currentTheme.chrome.accentTint)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .strokeBorder(
                        isActive ? theme.currentTheme.chrome.accent.opacity(0.52) : theme.currentTheme.chrome.accentStrong,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
    }
}

/// Floating editing toolbar that hovers over the bottom of the document
/// card — the "bottom row of the composer". The dictation mic is the
/// centerpiece; clipboard tools (select · cut · copy) sit to its left and
/// insert tools (space · paste · new line) to its right. Summon, cursor pad,
/// and keyboard live on the lower chrome row (ActionTray), not here.
private struct ComposeFloatingTools: View {
    let state: ComposeState
    let onMic: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        // Quick-actions rail: one paper-and-hairline bed with tight command groups. The mic is
        // pinned to the true center so it lines up with the cursor pad below.
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    iconButton("selection.pin.in.out", "Select all") {
                        NotificationCenter.default.post(name: .composeNextEditorSelectAll, object: nil)
                    }
                    iconButton("scissors", "Cut") {
                        NotificationCenter.default.post(name: .composeNextEditorCut, object: nil)
                    }
                    iconButton("doc.on.doc", "Copy") {
                        NotificationCenter.default.post(name: .composeNextEditorCopy, object: nil)
                    }
                }

                Spacer(minLength: 54)

                HStack(spacing: 5) {
                    spaceButton
                    iconButton("doc.on.clipboard", "Paste") {
                        NotificationCenter.default.post(name: .composeNextEditorPaste, object: nil)
                    }
                    iconButton("arrow.turn.down.left", "New line") {
                        NotificationCenter.default.post(name: .composeNextEditorInsertNewline, object: nil)
                    }
                }
            }

            InlineMicButton(state: state, action: onMic)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(railBackground)
        .padding(.horizontal, 30)
    }

    private func iconButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.action)
                .frame(width: 31, height: 30)
                .background(commandKeyBackground)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(label)
    }

    // Wider "space" key — same deck-key treatment, just roomier.
    private var spaceButton: some View {
        Button {
            NotificationCenter.default.post(name: .composeNextEditorInsertSpace, object: nil)
        } label: {
            Text("space")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.currentTheme.chrome.action)
                .frame(width: 54, height: 30)
                .background(commandKeyBackground)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("Space")
    }

    private var commandKeyBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
    }

    private var railBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm + 4, style: .continuous)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm + 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), theme.currentTheme.chrome.actionTint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm + 4, style: .continuous)
                    .strokeBorder(theme.currentTheme.chrome.edge,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Inline diff (vertical stacked: v1 above, v2 below)

struct DiffInline: View {
    let diff: ComposeStore.Diff
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let review = ComposeInlineDiff.review(
            original: diff.original,
            proposed: diff.proposed,
            fallbackRemoved: diff.removedCount,
            fallbackAdded: diff.addedCount,
            fallbackUnchanged: diff.unchangedCount,
            baseColor: theme.colors.textPrimary,
            secondaryColor: theme.colors.textSecondary,
            deleteColor: Color.red.opacity(0.82),
            insertColor: theme.currentTheme.chrome.accent
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(review.isBroadRewrite ? "FORMATTED REWRITE" : "WORD REVIEW")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                Spacer(minLength: 12)

                Text("\(review.unchangedCount) shared")
                    .talkieType(.timestamp)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            DiffTextPane(
                title: "BEFORE",
                subtitle: "v1",
                systemImage: "minus.circle",
                accent: Color.red.opacity(0.78),
                background: Color.red.opacity(0.055),
                content: review.original
            )

            DiffTextPane(
                title: "AFTER",
                subtitle: "v2",
                systemImage: "sparkles",
                accent: theme.currentTheme.chrome.accent,
                background: theme.currentTheme.chrome.accentTint,
                content: review.proposed
            )

            HStack(spacing: 8) {
                DiffCountPill(label: "removed", value: review.removedCount, color: Color.red.opacity(0.82))
                DiffCountPill(label: "added", value: review.addedCount, color: theme.currentTheme.chrome.accent)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct DiffTextPane: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let background: Color
    let content: AttributedString

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                Text(title)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(accent)
                Text(subtitle)
                    .talkieType(.timestamp)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 0)
            }

            Text(content)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct DiffCountPill: View {
    let label: String
    let value: Int
    let color: Color

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Text(value.formatted())
                .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
            Text(label)
                .talkieType(.channelLabelTiny)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(color.opacity(0.16), lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct ComposeInlineDiffReview {
    let original: AttributedString
    let proposed: AttributedString
    let removedCount: Int
    let addedCount: Int
    let unchangedCount: Int
    let isBroadRewrite: Bool
}

private enum ComposeInlineDiff {
    private struct WordToken {
        let range: Range<String.Index>
        let normalized: String
    }

    private struct Matches {
        let original: Set<Int>
        let proposed: Set<Int>
    }

    private static let maxMatrixCells = 1_500_000
    private static let trimCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    static func review(
        original: String,
        proposed: String,
        fallbackRemoved: Int,
        fallbackAdded: Int,
        fallbackUnchanged: Int,
        baseColor: Color,
        secondaryColor: Color,
        deleteColor: Color,
        insertColor: Color
    ) -> ComposeInlineDiffReview {
        let originalTokens = tokens(in: original)
        let proposedTokens = tokens(in: proposed)
        let matrixCells = originalTokens.count * proposedTokens.count
        let matches = matrixCells <= maxMatrixCells
            ? matchedTokenIndices(original: originalTokens, proposed: proposedTokens)
            : nil

        let unchangedCount = matches?.original.count ?? fallbackUnchanged
        let removedCount = matches.map { max(0, originalTokens.count - $0.original.count) } ?? fallbackRemoved
        let addedCount = matches.map { max(0, proposedTokens.count - $0.proposed.count) } ?? fallbackAdded
        let largestSide = max(originalTokens.count, proposedTokens.count)
        let overlap = largestSide == 0 ? 1 : Double(unchangedCount) / Double(largestSide)
        let hasStructureChange = original.contains("\n") != proposed.contains("\n")
            || proposed.contains("- ")
            || proposed.contains("•")
            || proposed.contains("#")
        let isBroadRewrite = largestSide > 80 && overlap < 0.18 || matches == nil
        let shouldMarkWords = !isBroadRewrite

        return ComposeInlineDiffReview(
            original: attributedText(
                original,
                tokens: originalTokens,
                changedIndices: shouldMarkWords ? originalTokens.indicesSet.subtracting(matches?.original ?? Set<Int>()) : [],
                baseColor: secondaryColor,
                changedColor: deleteColor,
                style: .removed
            ),
            proposed: attributedText(
                proposed,
                tokens: proposedTokens,
                changedIndices: shouldMarkWords ? proposedTokens.indicesSet.subtracting(matches?.proposed ?? Set<Int>()) : [],
                baseColor: baseColor,
                changedColor: insertColor,
                style: .added
            ),
            removedCount: removedCount,
            addedCount: addedCount,
            unchangedCount: unchangedCount,
            isBroadRewrite: isBroadRewrite || hasStructureChange && overlap < 0.35
        )
    }

    private static func tokens(in text: String) -> [WordToken] {
        var result: [WordToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }

            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }

            let raw = String(text[start..<index])
            let normalized = raw
                .trimmingCharacters(in: trimCharacters)
                .lowercased()
            if !normalized.isEmpty {
                result.append(WordToken(range: start..<index, normalized: normalized))
            }
        }

        return result
    }

    private static func matchedTokenIndices(original: [WordToken], proposed: [WordToken]) -> Matches {
        let originalCount = original.count
        let proposedCount = proposed.count
        guard originalCount > 0, proposedCount > 0 else {
            return Matches(original: [], proposed: [])
        }

        var table = Array(
            repeating: Array(repeating: 0, count: proposedCount + 1),
            count: originalCount + 1
        )

        for originalIndex in 0..<originalCount {
            for proposedIndex in 0..<proposedCount {
                if original[originalIndex].normalized == proposed[proposedIndex].normalized {
                    table[originalIndex + 1][proposedIndex + 1] = table[originalIndex][proposedIndex] + 1
                } else {
                    table[originalIndex + 1][proposedIndex + 1] = max(
                        table[originalIndex][proposedIndex + 1],
                        table[originalIndex + 1][proposedIndex]
                    )
                }
            }
        }

        var matchedOriginal = Set<Int>()
        var matchedProposed = Set<Int>()
        var originalIndex = originalCount
        var proposedIndex = proposedCount

        while originalIndex > 0, proposedIndex > 0 {
            if original[originalIndex - 1].normalized == proposed[proposedIndex - 1].normalized {
                matchedOriginal.insert(originalIndex - 1)
                matchedProposed.insert(proposedIndex - 1)
                originalIndex -= 1
                proposedIndex -= 1
            } else if table[originalIndex - 1][proposedIndex] >= table[originalIndex][proposedIndex - 1] {
                originalIndex -= 1
            } else {
                proposedIndex -= 1
            }
        }

        return Matches(original: matchedOriginal, proposed: matchedProposed)
    }

    private enum ChangeStyle {
        case added
        case removed
    }

    private static func attributedText(
        _ text: String,
        tokens: [WordToken],
        changedIndices: Set<Int>,
        baseColor: Color,
        changedColor: Color,
        style: ChangeStyle
    ) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex

        for (tokenIndex, token) in tokens.enumerated() {
            if cursor < token.range.lowerBound {
                var separator = AttributedString(String(text[cursor..<token.range.lowerBound]))
                separator.foregroundColor = baseColor
                result.append(separator)
            }

            var fragment = AttributedString(String(text[token.range]))
            if changedIndices.contains(tokenIndex) {
                fragment.foregroundColor = changedColor
                switch style {
                case .added:
                    fragment.underlineStyle = .single
                case .removed:
                    fragment.strikethroughStyle = .single
                }
            } else {
                fragment.foregroundColor = baseColor
            }
            result.append(fragment)
            cursor = token.range.upperBound
        }

        if cursor < text.endIndex {
            var trailing = AttributedString(String(text[cursor..<text.endIndex]))
            trailing.foregroundColor = baseColor
            result.append(trailing)
        }

        if result.characters.isEmpty {
            var empty = AttributedString("")
            empty.foregroundColor = baseColor
            return empty
        }

        return result
    }
}

private extension Collection where Index == Int {
    var indicesSet: Set<Int> { Set(indices) }
}

// MARK: - Quick transforms row (thin)

private struct QuickTransforms: View {
    let state: ComposeState
    let onTap: (ComposeStore.QuickTransform) -> Void
    let onCommand: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private var muted: Bool { state == .generating || state == .listening }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Command key — one pretty keycap: a mic, the word, and a sparkle
            // for the "AI is happening" signal. Rounded-rect (not a capsule) so
            // it reads as a real button / keyboard key rather than just another
            // quick-action chip. Tap to invoke a voice command — speak an
            // instruction and the model returns a diff.
            Button(action: onCommand) {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Command")
                        .talkieType(.fieldLabel)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(theme.chrome.action)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.chrome.actionTint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.chrome.action.opacity(0.4),
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                )
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel("Voice command")

            // Separator — the command key is its own thing, not a quick action.
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(width: theme.currentTheme.chrome.hairlineWidth, height: 22)

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
            .opacity(muted ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Revision strip

private enum RevisionPreviewMode: String, CaseIterable, Identifiable {
    case minimized
    case compact
    case expanded

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .minimized: return "minus"
        case .compact: return "line.3.horizontal"
        case .expanded: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .minimized: return "Minimize revision preview"
        case .compact: return "Compact revision preview"
        case .expanded: return "Expand revision preview"
        }
    }

    var lineLimit: Int {
        switch self {
        case .minimized: return 1
        case .compact: return 2
        case .expanded: return 8
        }
    }
}

private struct RevisionHistoryRollup: View {
    let revisions: [ComposeNoteStore.RevisionRecord]
    let onRestore: (ComposeNoteStore.RevisionRecord) -> Void

    @State private var selectedRevisionID: UUID?
    @State private var previewMode: RevisionPreviewMode = .minimized
    @ObservedObject private var theme = ThemeManager.shared

    private var selectedIndex: Int? {
        guard let selectedRevisionID else { return nil }
        return revisions.firstIndex { $0.id == selectedRevisionID }
    }

    private var selectedRevision: ComposeNoteStore.RevisionRecord? {
        guard let selectedIndex else { return nil }
        return revisions[selectedIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· REVISIONS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer(minLength: 4)
                Text("CURRENT v\(revisions.count + 1)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                if selectedRevision != nil {
                    RevisionPreviewModeControl(mode: $previewMode)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(revisions.prefix(10).enumerated(), id: \.element.id) { index, revision in
                        let version = versionNumber(for: index)
                        let isSelected = selectedRevisionID == revision.id
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if selectedRevisionID == revision.id {
                                    selectedRevisionID = nil
                                    previewMode = .minimized
                                } else {
                                    selectedRevisionID = revision.id
                                    previewMode = .compact
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("v\(version)")
                                    .talkieType(.channelLabelTiny)
                                    .foregroundStyle(isSelected ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(revision.instruction)
                                        .talkieType(.fieldLabel)
                                        .foregroundStyle(theme.colors.textPrimary)
                                        .lineLimit(1)
                                    Text("\(revision.scope) · \(revision.providerName)")
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
                                                isSelected ? theme.currentTheme.chrome.accentStrong : theme.currentTheme.chrome.edgeFaint,
                                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(isSelected ? "Hide" : "Show") revision \(version), \(revision.instruction)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            if let selectedIndex, let selectedRevision {
                if previewMode == .minimized {
                    RevisionMiniPreview(
                        revision: selectedRevision,
                        version: versionNumber(for: selectedIndex),
                        onRestore: { onRestore(selectedRevision) }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    RevisionDiffPreview(
                        revision: selectedRevision,
                        version: versionNumber(for: selectedIndex),
                        beforeText: beforeText(for: selectedIndex, revision: selectedRevision),
                        mode: previewMode,
                        onRestore: { onRestore(selectedRevision) }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: previewMode)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: selectedRevisionID)
    }

    private func versionNumber(for index: Int) -> Int {
        revisions.count - index + 1
    }

    private func beforeText(for index: Int, revision: ComposeNoteStore.RevisionRecord) -> String? {
        if let original = revision.originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty {
            return original
        }

        if let documentBefore = revision.documentTextBefore?.trimmingCharacters(in: .whitespacesAndNewlines),
           !documentBefore.isEmpty {
            return documentBefore
        }

        let olderIndex = index + 1
        guard revisions.indices.contains(olderIndex) else { return nil }
        let previousSnapshot = revisions[olderIndex].documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return previousSnapshot.isEmpty ? nil : previousSnapshot
    }
}

private struct RevisionPreviewModeControl: View {
    @Binding var mode: RevisionPreviewMode
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RevisionPreviewMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(mode == option ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                        .frame(width: 23, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(mode == option ? theme.currentTheme.chrome.accentTint : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.colors.cardBackground.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct RevisionMiniPreview: View {
    let revision: ComposeNoteStore.RevisionRecord
    let version: Int
    let onRestore: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("v\(max(1, version - 1)) → v\(version)")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text(revision.instruction)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.chrome.action)
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.chrome.actionTint)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(theme.chrome.action.opacity(0.34),
                                                  lineWidth: theme.chrome.hairlineWidth)
                            )
                    )
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel("Restore revision")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct RevisionDiffPreview: View {
    let revision: ComposeNoteStore.RevisionRecord
    let version: Int
    let beforeText: String?
    let mode: RevisionPreviewMode
    let onRestore: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("v\(max(1, version - 1)) → v\(version)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)

                Text(revision.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .talkieType(.timestamp)
                    .foregroundStyle(theme.colors.textTertiary)

                Spacer(minLength: 0)

                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.chrome.action)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.chrome.actionTint)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(theme.chrome.action.opacity(0.4),
                                                      lineWidth: theme.chrome.hairlineWidth)
                                )
                        )
                }
                .buttonStyle(CardPressStyle())
            }

            RevisionTextPane(
                title: "BEFORE",
                text: beforeText ?? "Earlier text was not stored for this revision.",
                isMissing: beforeText == nil,
                lineLimit: mode.lineLimit,
                tint: Color.red.opacity(0.75)
            )

            RevisionTextPane(
                title: "AFTER",
                text: revision.revisedText,
                isMissing: false,
                lineLimit: mode.lineLimit,
                tint: theme.currentTheme.chrome.accent
            )

            Text("\(revision.providerName) · \(revision.modelId)")
                .talkieType(.timestamp)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}

private struct RevisionTextPane: View {
    let title: String
    let text: String
    let isMissing: Bool
    let lineLimit: Int
    let tint: Color

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(tint)
            Text(text)
                .talkieType(.preview)
                .lineSpacing(3)
                .foregroundStyle(isMissing ? theme.colors.textTertiary : theme.colors.textPrimary)
                .italic(isMissing)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isMissing ? theme.colors.background : tint.opacity(0.08))
                )
        }
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
            // The global Talkie pivot occupies the center of this lane. Keep
            // the cursor and keyboard controls on its flanks so all three
            // remain visible and tappable.
            HStack {
                joystickButton
                Spacer()
                trayButton(
                    size: 48,
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
                .frame(width: 48, height: 48)
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
        size: CGFloat = 40,
        systemImage: String,
        accessibilityLabel: String,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: size, height: size)
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
