//
//  CaptureMarkupPanelChrome.swift
//  Talkie
//
//  Native chrome around the markup canvas. Canvas, layer rail, and
//  drawing toolbar live in the ephemeral WKWebView (visuals/content
//  only). The native side owns:
//
//    · Speak Strip  — bottom band · Identity line + Composer + Status.
//    · Pass Verdict — accept / cancel cluster floating top-right on
//                     the canvas itself (was a footer commit bar).
//
//  Redesign (2026-06) ports design/studio · /mac-capture-markup-strip:
//
//    ┌ IDENTITY LINE ─ agent ▸ GPT-5.4 · openai   scope ▸ whole image ┐
//    ├ COMPOSER ────── [ tell the agent what to mark up…  (mic) ] [▸] ┤
//    └ STATUS ──────── try  chip · chip · chip   /  attached  /  rec  ┘
//
//  Identity line is the coding-agent "where am I running" header. The
//  composer rides the mic INSIDE the field's trailing edge with the
//  amber paperplane send as a squared button outside. The status line
//  is one adaptive slot — try-examples / attachment / listening — never
//  stacked. Palette is canonical warm amber (was blue); matches the
//  studio mock the port leads from.
//

import AppKit
import TalkieKit

// MARK: - Delegate

@MainActor
protocol CaptureMarkupPanelChromeDelegate: AnyObject {
    func captureMarkupPanelDidAccept()
    func captureMarkupPanelDidCancel()
    func captureMarkupPanelDidRun(instruction: String, providerId: String?, modelId: String?)
    /// Explicit Save (⌘S / SAVE button) — persist the current document to
    /// the sidecar now. Distinct from Accept: does NOT close the panel.
    func captureMarkupPanelDidSave()
    func captureMarkupPanelDidClearSelection()
    func captureMarkupPanelDidRemoveAttachment(id: String)
    func captureMarkupPanelTryExampleSelected(_ text: String)
    func captureMarkupPanelDidReportError(_ message: String)
}

private struct CaptureMarkupAgentChoice: Equatable {
    let providerId: String
    let providerName: String
    let modelId: String
    let modelDisplayName: String

    /// Badge title — "GPT-5.4 · openai". The "agent ▸" prefix is drawn by
    /// the static label beside the picker, so it's omitted here.
    var menuTitle: String {
        "\(modelDisplayName) · \(providerName.lowercased())"
    }
}

// MARK: - Warm amber palette (shared)
//
// Canonical Scope warm amber (#C47D1C). Was blue (rgb 0.31,0.49,1.0) —
// that override is the "studio doesn't match the app" gap; the redesign
// brings the chrome back to canon.

private enum CaptureMarkupPalette {
    static let amber = NSColor(red: 0.769, green: 0.490, blue: 0.110, alpha: 1)
    static let amberDeep = NSColor(red: 0.478, green: 0.322, blue: 0.102, alpha: 1)
    static let amberFaint = NSColor(red: 0.965, green: 0.940, blue: 0.890, alpha: 1)
    static let amberSoft = NSColor(red: 0.769, green: 0.490, blue: 0.110, alpha: 0.30)
    static let alert = NSColor(red: 0.77, green: 0.227, blue: 0.110, alpha: 1)
}

// MARK: - Mic (in-field ghost icon · tap-to-toggle)

@MainActor
private final class CaptureMarkupMicButton: NSButton {
    var onToggle: (() -> Void)?

    private let side: CGFloat = 26

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        title = ""
        bezelStyle = .recessed
        imageScaling = .scaleNone
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        target = self
        action = #selector(handleClick)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: side, height: side)
    }

    @objc private func handleClick() {
        onToggle?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Send button (squared · amber · paperplane)

@MainActor
private final class CaptureMarkupSendButton: NSView {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private var enabledForClick = true

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleNone
        if let plane = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Run") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            icon.image = plane.withSymbolConfiguration(cfg)
        }
        addSubview(icon)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyEnabledAppearance()
        toolTip = "Run · ⌘↵"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setEnabledForClick(_ enabled: Bool) {
        enabledForClick = enabled
        applyEnabledAppearance()
    }

    private func applyEnabledAppearance() {
        if enabledForClick {
            layer?.backgroundColor = CaptureMarkupPalette.amber.cgColor
            layer?.borderColor = CaptureMarkupPalette.amber.cgColor
            icon.contentTintColor = .white
        } else {
            layer?.backgroundColor = NSColor(red: 0.945, green: 0.945, blue: 0.937, alpha: 1).cgColor
            layer?.borderColor = NSColor(white: 0.10, alpha: 0.16).cgColor
            icon.contentTintColor = .tertiaryLabelColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard enabledForClick else { return }
        onClick?()
    }

    override func resetCursorRects() {
        if enabledForClick { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

// MARK: - Example chip
//
// Dashed-pill action chip used in the "try" suggestions row. Built as an
// NSView (text field + custom layers) rather than NSButton so we get a
// clean dashed CAShapeLayer stroke and pill-pinned radius.

@MainActor
private final class CaptureMarkupExampleChip: NSView {
    var onClick: (() -> Void)?

    private let textField = NSTextField(labelWithString: "")
    private let dashLayer = CAShapeLayer()

    private static let pane = NSColor(red: 0.945, green: 0.945, blue: 0.937, alpha: 1)
    private static let strokeColor = NSColor(white: 0.10, alpha: 0.22).cgColor
    private static let hoverStrokeColor = NSColor(red: 0.769, green: 0.490, blue: 0.110, alpha: 0.55).cgColor

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Self.pane.cgColor
        layer?.masksToBounds = true

        textField.stringValue = text
        textField.font = NSFont.systemFont(ofSize: 11)
        textField.textColor = .secondaryLabelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.isBordered = false
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            heightAnchor.constraint(equalToConstant: 20),
        ])

        dashLayer.fillColor = NSColor.clear.cgColor
        dashLayer.strokeColor = Self.strokeColor
        dashLayer.lineWidth = 0.5
        dashLayer.lineDashPattern = [3, 2] as [NSNumber]
        layer?.addSublayer(dashLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        dashLayer.frame = bounds
        let inset: CGFloat = 0.25  // keeps the 0.5pt stroke inside the bounds
        dashLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: max(0, radius - inset),
            cornerHeight: max(0, radius - inset),
            transform: nil
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        dashLayer.strokeColor = Self.hoverStrokeColor
    }

    override func mouseExited(with event: NSEvent) {
        dashLayer.strokeColor = Self.strokeColor
    }
}

// MARK: - Prompt container
//
// NSView subclass for the prompt's pane so we can pin a 1pt white inset
// highlight at the top edge (clipped to the corner radius).

@MainActor
private final class CaptureMarkupPromptContainerView: NSView {
    private let topHighlight = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        topHighlight.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        topHighlight.zPosition = 10
        layer?.addSublayer(topHighlight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        topHighlight.frame = CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)
    }
}

@MainActor
private final class CaptureMarkupPromptTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var placeholderString = "" {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "\r" {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let padding = textContainer?.lineFragmentPadding ?? 0
        let point = NSPoint(
            x: textContainerInset.width + padding,
            y: textContainerInset.height
        )
        (placeholderString as NSString).draw(at: point, withAttributes: attrs)
    }
}

// MARK: - Root layout

@MainActor
private final class CaptureMarkupDragHandleView: NSView, NSDraggingSource {
    var isEnabledForDrag = false {
        didSet {
            alphaValue = isEnabledForDrag ? 1 : 0
            isHidden = !isEnabledForDrag
            needsDisplay = true
        }
    }
    var makeDragPayload: (() -> (fileURL: URL, dragImage: NSImage)?)?

    private let dragThreshold: CGFloat = 4
    private var dragStartLocation: NSPoint?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    private static let amber = CaptureMarkupPalette.amber
    private static let amberDeep = CaptureMarkupPalette.amberDeep
    private static let amberFaint = CaptureMarkupPalette.amberFaint
    private static let amberSoft = NSColor(red: 0.769, green: 0.490, blue: 0.110, alpha: 0.55)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        toolTip = "Drag a copy of the annotated PNG"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag Copy")
        setAccessibilityHelp("Drag a copy of the annotated screenshot to another app.")
        isEnabledForDrag = false
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(next)
        trackingArea = next
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: pill, yRadius: pill)
        let fill = isPressed
            ? Self.amberSoft.withAlphaComponent(0.98)
            : (isHovering ? NSColor.white.withAlphaComponent(0.98) : Self.amberFaint)
        fill.setFill()
        path.fill()
        let stroke = isHovering || isPressed ? Self.amber : Self.amberSoft
        stroke.setStroke()
        path.lineWidth = 0.75
        path.stroke()

        let text = "⧉ DRAG COPY"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: Self.amberDeep,
            .kern: 0.7,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabledForDrag else { return }
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabledForDrag else { return }
        isPressed = true
        dragStartLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabledForDrag, let startLocation = dragStartLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - startLocation.x, current.y - startLocation.y) >= dragThreshold else { return }
        dragStartLocation = nil

        guard let payload = makeDragPayload?() else { return }
        isPressed = false
        let item = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: payload.fileURL))
        item.setDraggingFrame(bounds, contents: payload.dragImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        dragStartLocation = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

@MainActor
final class CaptureMarkupPanelRootView: NSView {
    let webHost = NSView()
    let inputBar = CaptureMarkupInputBarView()
    private let dragHandle = CaptureMarkupDragHandleView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // webHost and inputBar fill the panel top-to-bottom. Canvas undo/redo
        // now lives inside the WKWebView toolbar with the rest of the tools.
        webHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        webHost.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        inputBar.setContentHuggingPriority(.required, for: .vertical)
        inputBar.setContentCompressionResistancePriority(.required, for: .vertical)

        [webHost, inputBar, dragHandle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            webHost.topAnchor.constraint(equalTo: topAnchor),
            webHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            webHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            webHost.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            // Native file drags must start in AppKit, not inside WKWebView.
            // Keep the centered affordance outside the normal layer hit-test
            // path so canvas layer-move drags continue to belong to markup.js.
            dragHandle.centerXAnchor.constraint(equalTo: centerXAnchor),
            dragHandle.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -12),
            dragHandle.widthAnchor.constraint(equalToConstant: 152),
            dragHandle.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setDragOutAvailable(_ available: Bool) {
        dragHandle.isEnabledForDrag = available
        dragHandle.needsDisplay = true
    }

    func setDragPayloadProvider(_ provider: @escaping () -> (fileURL: URL, dragImage: NSImage)?) {
        dragHandle.makeDragPayload = provider
    }
}

// MARK: - Input bar

@MainActor
final class CaptureMarkupInputBarView: NSView {
    weak var delegate: CaptureMarkupPanelChromeDelegate?

    private static let band = NSColor(red: 0.925, green: 0.925, blue: 0.922, alpha: 1)
    private static let amber = CaptureMarkupPalette.amber
    private static let amberDeep = CaptureMarkupPalette.amberDeep
    private static let amberFaint = CaptureMarkupPalette.amberFaint
    private static let amberSoft = CaptureMarkupPalette.amberSoft
    private static let alert = CaptureMarkupPalette.alert
    private static let fieldBorder = NSColor(white: 0.10, alpha: 0.16)
    private static let fieldBorderActive = NSColor(red: 0.77, green: 0.227, blue: 0.11, alpha: 0.45)

    // Identity line — left stack (suggestions / listening) + right stack
    // (scope-or-selected-item, then the agent picker pinned far right,
    // sitting directly above the send button).
    private let leftStack = NSStackView()
    private let rightStack = NSStackView()
    private let agentPrefix = NSTextField(labelWithString: "agent ▸")
    private let agentPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scopePrefix = NSTextField(labelWithString: "scope ▸")
    private let scopeValue = NSTextField(labelWithString: "whole image")

    // Composer
    private let promptContainer = CaptureMarkupPromptContainerView()
    private let promptTextView = CaptureMarkupPromptTextView()
    private let voiceButton = CaptureMarkupMicButton()
    private let sendButton = CaptureMarkupSendButton()

    // Status line (one adaptive slot)
    private let tryLabel = NSTextField(labelWithString: "try")
    private let examplesStack = NSStackView()
    private let attachmentsLabel = NSTextField(labelWithString: "attached")
    private let attachmentChipsStack = NSStackView()
    private let listeningLabel = NSTextField(labelWithString: "● listening · tap mic to stop")

    private var saveFeedbackResetWork: DispatchWorkItem?

    private var isVoiceRecording = false
    private var isVoiceTranscribing = false
    private var isRunning = false
    private var agentChoices: [CaptureMarkupAgentChoice] = []
    private var agentPreferencesObserver: NSObjectProtocol?
    private var attachmentsVisible = false

    private var askExamples = [
        "circle the error and label it",
        "blur the email address",
        "arrow to the failed line",
    ]
    private var touchUpExamples = [
        "move down 6 px",
        "make the ring red",
        "rename to 'API error'",
        "delete",
    ]
    private var isTouchUpMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.band.cgColor

        // ── Identity line ───────────────────────────────────────────────
        agentPrefix.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        agentPrefix.textColor = .tertiaryLabelColor

        agentPicker.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        agentPicker.controlSize = .small
        agentPicker.isBordered = false
        agentPicker.toolTip = "Choose markup agent"
        agentPicker.target = self
        agentPicker.action = #selector(agentPickerChanged)
        agentPicker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        agentPicker.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setAgentPickerLoading()

        scopePrefix.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        scopePrefix.textColor = .tertiaryLabelColor
        scopeValue.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        scopeValue.textColor = .secondaryLabelColor
        scopeValue.alignment = .right

        // ── Composer ────────────────────────────────────────────────────
        promptContainer.wantsLayer = true
        promptContainer.layer?.backgroundColor = NSColor.white.cgColor
        promptContainer.layer?.borderColor = Self.fieldBorder.cgColor
        promptContainer.layer?.borderWidth = 0.5
        promptContainer.layer?.cornerRadius = 10

        voiceButton.toolTip = "Tap to record · tap again to stop"
        voiceButton.onToggle = { [weak self] in self?.toggleVoiceCapture() }

        promptTextView.font = NSFont.systemFont(ofSize: 13)
        promptTextView.textColor = .labelColor
        promptTextView.drawsBackground = false
        promptTextView.isRichText = false
        promptTextView.importsGraphics = false
        promptTextView.allowsUndo = true
        promptTextView.textContainerInset = NSSize(width: 0, height: 6)
        promptTextView.textContainer?.lineFragmentPadding = 0
        promptTextView.textContainer?.widthTracksTextView = true
        promptTextView.textContainer?.heightTracksTextView = false
        promptTextView.isHorizontallyResizable = false
        promptTextView.isVerticallyResizable = false
        promptTextView.insertionPointColor = .labelColor
        promptTextView.placeholderString = "tell the agent what to mark up…"
        promptTextView.delegate = self
        promptTextView.onCommandReturn = { [weak self] in self?.runTapped() }

        sendButton.onClick = { [weak self] in self?.runTapped() }

        // ── Status line ─────────────────────────────────────────────────
        tryLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        tryLabel.textColor = .tertiaryLabelColor

        examplesStack.orientation = .horizontal
        examplesStack.spacing = 8
        examplesStack.alignment = .centerY

        attachmentsLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        attachmentsLabel.textColor = .tertiaryLabelColor
        attachmentsLabel.isHidden = true

        attachmentChipsStack.orientation = .horizontal
        attachmentChipsStack.spacing = 6
        attachmentChipsStack.alignment = .centerY
        attachmentChipsStack.isHidden = true

        listeningLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        listeningLabel.textColor = Self.alert
        listeningLabel.isHidden = true

        // ── Assembly ────────────────────────────────────────────────────
        // Identity line is two horizontal stacks. LEFT keeps the suggestions
        // visible at all times (so "speak on this item" — submit with the
        // selected items attached — still shows the touch-up prompts). RIGHT
        // carries the run target (scope text, OR the selected-item chips with
        // their × when items are attached for submission) and then the agent
        // picker pinned far right, directly above the send button.
        leftStack.orientation = .horizontal
        leftStack.spacing = 8
        leftStack.alignment = .centerY
        [tryLabel, examplesStack, listeningLabel].forEach { leftStack.addArrangedSubview($0) }
        leftStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .centerY
        [scopePrefix, scopeValue, attachmentsLabel, attachmentChipsStack, agentPrefix, agentPicker]
            .forEach { rightStack.addArrangedSubview($0) }
        rightStack.setCustomSpacing(16, after: scopeValue)
        rightStack.setCustomSpacing(16, after: attachmentChipsStack)
        rightStack.setContentHuggingPriority(.required, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        [leftStack, rightStack, promptContainer, sendButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        [promptTextView, voiceButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            promptContainer.addSubview($0)
        }

        // Two rows: identity (row 1) + composer (row 2).
        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: leftStack.centerYAnchor),
            rightStack.leadingAnchor.constraint(greaterThanOrEqualTo: leftStack.trailingAnchor, constant: 12),

            // Composer
            promptContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            promptContainer.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            promptContainer.topAnchor.constraint(equalTo: leftStack.bottomAnchor, constant: 9),
            promptContainer.heightAnchor.constraint(equalToConstant: 40),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            sendButton.centerYAnchor.constraint(equalTo: promptContainer.centerYAnchor),

            voiceButton.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -7),
            voiceButton.centerYAnchor.constraint(equalTo: promptContainer.centerYAnchor),

            promptTextView.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 12),
            promptTextView.trailingAnchor.constraint(equalTo: voiceButton.leadingAnchor, constant: -6),
            promptTextView.topAnchor.constraint(equalTo: promptContainer.topAnchor, constant: 4),
            promptTextView.bottomAnchor.constraint(equalTo: promptContainer.bottomAnchor, constant: -4),
        ])

        setTouchUpMode(false)
        updateVoiceButtonAppearance()
        updateStatusRow()
        agentPreferencesObserver = NotificationCenter.default.addObserver(
            forName: LLMAgentModelPreferences.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAgentChoices()
            }
        }
        refreshAgentChoices()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        // Two rows: 12 top + 20 identity (chip row) + 9 + 40 composer + 12 bottom
        NSSize(width: NSView.noIntrinsicMetric, height: 94)
    }

    override func layout() {
        super.layout()
        syncPromptTextGeometry()
    }

    deinit {
        if let agentPreferencesObserver {
            NotificationCenter.default.removeObserver(agentPreferencesObserver)
        }
    }

    var promptText: String {
        get { promptTextView.string }
        set {
            promptTextView.string = newValue
            promptTextView.needsDisplay = true
            updateSendButtonAppearance()
        }
    }

    private var selectedAgentSelection: (providerId: String, modelId: String)? {
        let index = agentPicker.indexOfSelectedItem
        guard agentChoices.indices.contains(index) else { return nil }
        let choice = agentChoices[index]
        return (choice.providerId, choice.modelId)
    }

    private func syncPromptTextGeometry() {
        let width = max(1, promptTextView.bounds.width)
        promptTextView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        promptTextView.textContainer?.widthTracksTextView = true
    }

    func clearPrompt() {
        promptTextView.string = ""
        promptTextView.needsDisplay = true
        updateSendButtonAppearance()
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        promptTextView.isEditable = !running
        promptTextView.isSelectable = !running
        voiceButton.isEnabled = !running
        agentPicker.isEnabled = !running && !agentChoices.isEmpty
        updateSendButtonAppearance()
    }

    /// Flash the composer outline after a top-toolbar or keyboard save.
    func flashSaved() {
        saveFeedbackResetWork?.cancel()
        promptContainer.layer?.borderColor = Self.amber.cgColor
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.promptContainer.layer?.borderColor = self.isVoiceRecording
                ? Self.fieldBorderActive.cgColor
                : Self.fieldBorder.cgColor
        }
        saveFeedbackResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func setTouchUpMode(_ touchUp: Bool) {
        isTouchUpMode = touchUp
        let examples = touchUp ? touchUpExamples : askExamples
        promptTextView.placeholderString = touchUp ? "speak or type another pass…" : "tell the agent what to mark up…"
        rebuildExampleChips(examples)
    }

    func setAttachments(_ selections: [CaptureMarkupLayerSelection]) {
        attachmentChipsStack.arrangedSubviews.forEach { view in
            attachmentChipsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for selection in selections.prefix(4) {
            let chip = CaptureMarkupSelectionChipView()
            chip.configure(id: selection.id, label: selection.label, kind: selection.kind)
            let id = selection.id
            chip.onDismiss = { [weak self] in
                self?.delegate?.captureMarkupPanelDidRemoveAttachment(id: id)
            }
            attachmentChipsStack.addArrangedSubview(chip)
        }

        if selections.count > 4 {
            let overflow = NSTextField(labelWithString: "+\(selections.count - 4)")
            overflow.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
            overflow.textColor = Self.amberDeep
            attachmentChipsStack.addArrangedSubview(overflow)
        }

        // Items attached here are submitted to the engine with the prompt.
        // The chips carry the names + a × to drop them; the scope text is
        // hidden while they show (see updateStatusRow).
        attachmentsVisible = !selections.isEmpty
        updateStatusRow()
    }

    /// Left stack: suggestions stay up so you can still "speak on this item"
    /// while items are attached — only recording swaps them for "listening".
    /// Right stack: the selected-item chips (submitted to the engine) replace
    /// the plain scope text when items are attached.
    private func updateStatusRow() {
        let recording = isVoiceRecording
        listeningLabel.isHidden = !recording
        tryLabel.isHidden = recording
        examplesStack.isHidden = recording

        attachmentsLabel.isHidden = !attachmentsVisible
        attachmentChipsStack.isHidden = !attachmentsVisible
        scopePrefix.isHidden = attachmentsVisible
        scopeValue.isHidden = attachmentsVisible
    }

    private func rebuildExampleChips(_ examples: [String]) {
        examplesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for text in examples {
            let chip = CaptureMarkupExampleChip(text: text)
            chip.onClick = { [weak self] in
                self?.promptText = text
                self?.delegate?.captureMarkupPanelTryExampleSelected(text)
            }
            examplesStack.addArrangedSubview(chip)
        }
    }

    private func setAgentPickerLoading() {
        agentChoices = []
        agentPicker.removeAllItems()
        agentPicker.addItem(withTitle: "loading…")
        agentPicker.isEnabled = false
    }

    private func refreshAgentChoices() {
        setAgentPickerLoading()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let registry = LLMProviderRegistry.shared
            await registry.refreshModels()

            var choices: [CaptureMarkupAgentChoice] = []
            var providerIds: [String] = []
            var seenProviderIds = Set<String>()
            for providerId in LLMConfig.shared.preferredProviderOrder + registry.providers.map(\.id) {
                guard LLMAgentModelPreferences.isCuratableProvider(providerId),
                      seenProviderIds.insert(providerId).inserted else { continue }
                providerIds.append(providerId)
            }

            for providerId in providerIds {
                guard let provider = registry.provider(for: providerId) else { continue }
                guard await provider.isAvailable else { continue }
                let models = LLMAgentModelPreferences.curatedModels(
                    for: provider.id,
                    from: registry.allModels
                )
                for model in models {
                    choices.append(
                        CaptureMarkupAgentChoice(
                            providerId: provider.id,
                            providerName: provider.name,
                            modelId: model.id,
                            modelDisplayName: model.displayName
                        )
                    )
                }
            }

            var selected = choices.first {
                $0.providerId == registry.selectedProviderId && $0.modelId == registry.selectedModelId
            }
            if selected == nil {
                // No prior pick — prefer OpenAI's default model (GPT-5.5) whenever
                // an OpenAI agent is enabled, then fall back to any OpenAI model,
                // then to the first available choice.
                let openAIDefaultModel = LLMConfig.shared.defaultModel(for: "openai") ?? "gpt-5.5"
                selected = choices.first { $0.providerId == "openai" && $0.modelId == openAIDefaultModel }
                    ?? choices.first { $0.providerId == "openai" }
                    ?? choices.first
            }
            if let selected {
                registry.selectedProviderId = selected.providerId
                registry.selectedModelId = selected.modelId
            }

            applyAgentChoices(choices, selected: selected)
        }
    }

    private func applyAgentChoices(_ choices: [CaptureMarkupAgentChoice], selected: CaptureMarkupAgentChoice?) {
        agentChoices = choices
        agentPicker.removeAllItems()

        guard !choices.isEmpty else {
            agentPicker.addItem(withTitle: "no agent enabled")
            agentPicker.isEnabled = false
            agentPicker.toolTip = "Enable a markup agent in Settings → Models → LLM"
            updateSendButtonAppearance()
            return
        }

        choices.forEach { agentPicker.addItem(withTitle: $0.menuTitle) }
        let index = selected.flatMap { choices.firstIndex(of: $0) } ?? 0
        agentPicker.selectItem(at: index)
        agentPicker.isEnabled = !isRunning
        updateAgentPickerToolTip()
        updateSendButtonAppearance()
    }

    private func updateAgentPickerToolTip() {
        guard let selection = selectedAgentSelection else {
            agentPicker.toolTip = "Choose markup agent"
            return
        }
        agentPicker.toolTip = "Agent: \(selection.providerId) / \(selection.modelId)"
    }

    @objc private func agentPickerChanged() {
        guard let selection = selectedAgentSelection else { return }
        let registry = LLMProviderRegistry.shared
        registry.selectedProviderId = selection.providerId
        registry.selectedModelId = selection.modelId
        updateAgentPickerToolTip()
    }

    /// Mic is tap-to-toggle. First tap starts capture, second tap stops
    /// and transcribes. Tapping while transcribing is a no-op.
    private func toggleVoiceCapture() {
        if isVoiceRecording {
            stopVoiceCapture()
        } else if !isVoiceTranscribing && !isRunning {
            startVoiceCapture()
        }
    }

    private func startVoiceCapture() {
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .captureMarkupDictation)
            isVoiceRecording = true
            updateVoiceButtonAppearance()
        } catch {
            delegate?.captureMarkupPanelDidReportError(error.localizedDescription)
        }
    }

    private func stopVoiceCapture() {
        guard isVoiceRecording else { return }
        isVoiceRecording = false
        isVoiceTranscribing = true
        updateVoiceButtonAppearance()

        Task {
            defer {
                isVoiceTranscribing = false
                updateVoiceButtonAppearance()
            }
            do {
                let text = try await EphemeralTranscriber.shared.stopAndTranscribe()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                appendTranscriptToPrompt(text)
            } catch {
                delegate?.captureMarkupPanelDidReportError(error.localizedDescription)
            }
        }
    }

    private func appendTranscriptToPrompt(_ text: String) {
        let existing = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            promptTextView.string = text
        } else {
            let needsSpace = !existing.hasSuffix(" ") && !existing.hasSuffix("\n")
            promptTextView.string = existing + (needsSpace ? " " : "") + text
        }
        promptTextView.needsDisplay = true
        updateSendButtonAppearance()
        window?.makeFirstResponder(promptTextView)
    }

    private func updateVoiceButtonAppearance() {
        let symbolName: String
        let glyphColor: NSColor
        let bg: NSColor
        let tip: String

        if isVoiceTranscribing {
            symbolName = "ellipsis"
            glyphColor = .secondaryLabelColor
            bg = .clear
            tip = "Transcribing…"
        } else if isVoiceRecording {
            symbolName = "stop.fill"
            glyphColor = Self.alert
            bg = NSColor(red: 0.77, green: 0.227, blue: 0.11, alpha: 0.12)
            tip = "Tap to stop"
        } else {
            symbolName = "mic.fill"
            glyphColor = .tertiaryLabelColor
            bg = .clear
            tip = "Tap to record"
        }

        voiceButton.title = ""
        voiceButton.attributedTitle = NSAttributedString(string: "")
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: tip) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            voiceButton.image = symbol.withSymbolConfiguration(config)
        }
        voiceButton.imageScaling = .scaleNone
        voiceButton.contentTintColor = glyphColor
        voiceButton.layer?.backgroundColor = bg.cgColor
        voiceButton.toolTip = tip
        updateComposerRecordingState()
        updateStatusRow()
        updateSendButtonAppearance()
    }

    /// While the mic is hot the field reads "listening…" and the outline
    /// flushes alert-red. No VU transport — the status line carries the
    /// recording state (openscout-simple).
    private func updateComposerRecordingState() {
        let recording = isVoiceRecording
        promptTextView.placeholderString = recording
            ? "listening…"
            : (isTouchUpMode ? "speak or type another pass…" : "tell the agent what to mark up…")
        promptTextView.needsDisplay = true
        promptContainer.layer?.borderColor = (recording ? Self.fieldBorderActive : Self.fieldBorder).cgColor
    }

    private func updateSendButtonAppearance() {
        let hasText = !promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let enabled = !isRunning && !isVoiceRecording && !isVoiceTranscribing && !agentChoices.isEmpty && hasText
        sendButton.setEnabledForClick(enabled)
        sendButton.toolTip = isRunning ? "Running…" : (agentChoices.isEmpty ? "No agent enabled" : "Run · ⌘↵")
    }

    /// ⌘↵ runs, ⌘S saves — works whether the prompt field or the bar has
    /// key focus. (The webview canvas handles its own ⌘S via the bridge.)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "\r": runTapped(); return true
        case "s": saveTapped(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    @objc private func saveTapped() {
        guard !isRunning else { return }
        delegate?.captureMarkupPanelDidSave()
    }

    @objc private func runTapped() {
        guard !isRunning else { return }
        let instruction = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        guard let agent = selectedAgentSelection else { return }
        delegate?.captureMarkupPanelDidRun(
            instruction: instruction,
            providerId: agent.providerId,
            modelId: agent.modelId
        )
    }
}

extension CaptureMarkupInputBarView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        syncPromptTextGeometry()
        promptTextView.needsDisplay = true
        updateSendButtonAppearance()
    }
}

// MARK: - Selection chip

@MainActor
final class CaptureMarkupSelectionChipView: NSView {
    var onDismiss: (() -> Void)?

    private let idLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let dismissButton = NSButton(title: "×", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CaptureMarkupPalette.amberFaint.cgColor
        layer?.borderColor = NSColor(red: 0.769, green: 0.490, blue: 0.110, alpha: 0.30).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 999

        idLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        idLabel.textColor = CaptureMarkupPalette.amberDeep
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = CaptureMarkupPalette.amberDeep

        dismissButton.isBordered = false
        dismissButton.bezelStyle = .inline
        dismissButton.font = NSFont.systemFont(ofSize: 10)
        dismissButton.contentTintColor = CaptureMarkupPalette.amberDeep
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)

        [idLabel, nameLabel, dismissButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            idLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            idLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: idLabel.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func configure(id: String, label: String, kind: String) {
        idLabel.stringValue = "↳ \(id.uppercased())"
        nameLabel.stringValue = label.isEmpty ? kind : label
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
