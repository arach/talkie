//
//  CaptureMarkupPanelChrome.swift
//  Talkie
//
//  Native chrome around the markup canvas. Canvas, layer rail, and
//  drawing toolbar live in the ephemeral WKWebView (visuals/content
//  only). The native side owns:
//
//    · Speak Strip  — bottom band · Mic + Prompt + Run
//    · Pass Verdict — accept / cancel cluster floating top-right on
//                     the canvas itself (was a footer commit bar).
//
//  Vocabulary mirrors design/studio/components/studies/MacCaptureMarkup
//  (the "names · marginalia" block on section 1c).
//

import AppKit

// MARK: - Delegate

@MainActor
protocol CaptureMarkupPanelChromeDelegate: AnyObject {
    func captureMarkupPanelDidAccept()
    func captureMarkupPanelDidCancel()
    func captureMarkupPanelDidRun(instruction: String)
    /// Explicit Save (⌘S / SAVE button) — persist the current document to
    /// the sidecar now. Distinct from Accept: does NOT close the panel.
    func captureMarkupPanelDidSave()
    func captureMarkupPanelDidClearSelection()
    func captureMarkupPanelTryExampleSelected(_ text: String)
    func captureMarkupPanelDidReportError(_ message: String)
}

// MARK: - Mic (narrow circular tap-to-toggle control)

@MainActor
private final class CaptureMarkupMicButton: NSButton {
    var onToggle: (() -> Void)?

    private let diameter: CGFloat = 32
    /// Thin white sliver at the top edge — clipped to the circular bounds
    /// by `masksToBounds`, so only the curved arc shows. Matches the
    /// studio's `box-shadow: inset 0 1px 0 rgba(255,255,255,0.55)` cap.
    private let topHighlight = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        title = ""
        bezelStyle = .recessed
        layer?.cornerRadius = diameter / 2
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true

        topHighlight.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        topHighlight.zPosition = 10  // above bg fill / border, below glyph
        layer?.addSublayer(topHighlight)

        target = self
        action = #selector(handleClick)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }

    override func layout() {
        super.layout()
        // y = bounds.maxY - 1 places the sliver at the visible top edge
        // for a non-flipped NSButton layer. The rounded corner clip turns
        // a flat 1pt strip into a centered top arc.
        topHighlight.frame = CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)
    }

    @objc private func handleClick() {
        onToggle?()
    }
}

// MARK: - Mag-tape waveform (recording state of the prompt lane)
//
// While the mic is hot the prompt lane becomes a magnetic-tape transport —
// VU bars riding an accent centerline, newest sample at the right under a
// tape-head marker, an elapsed readout on the left. Bars are sampled from
// EphemeralTranscriber.shared.audioLevel (live RMS) on a ~24fps timer.

@MainActor
private final class CaptureMarkupWaveformView: NSView {
    private var levels: [CGFloat] = []
    private var timer: Timer?
    private var startedAt: Date?
    private let maxBars = 56

    private static let amber = NSColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1)
    private static let amberDeep = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 1)
    private static let ink = NSColor(white: 0.14, alpha: 0.55)
    private static let alert = NSColor(red: 0.82, green: 0.23, blue: 0.11, alpha: 1)

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    func start() {
        levels.removeAll()
        startedAt = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        needsDisplay = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        levels.removeAll()
        startedAt = nil
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    private func tick() {
        let raw = CGFloat(EphemeralTranscriber.shared.audioLevel)
        // RMS is small; sqrt-shape it for liveliness and keep a faint floor
        // so the tape always reads as "running," not flatlined.
        let norm = min(1, max(0.07, sqrt(max(0, raw)) * 1.9))
        levels.append(norm)
        if levels.count > maxBars { levels.removeFirst(levels.count - maxBars) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let timeStr = String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Self.amberDeep,
        ]
        let timeSize = (timeStr as NSString).size(withAttributes: timeAttrs)
        (timeStr as NSString).draw(at: NSPoint(x: 10, y: b.midY - timeSize.height / 2), withAttributes: timeAttrs)

        let leftInset: CGFloat = 44
        let rightInset: CGFloat = 36 // room for the REC tag
        let track = NSRect(x: b.minX + leftInset, y: b.minY + 4, width: b.width - leftInset - rightInset, height: b.height - 8)
        guard track.width > 8 else { return }

        // accent centerline
        Self.amber.withAlphaComponent(0.5).setStroke()
        let center = NSBezierPath()
        center.move(to: NSPoint(x: track.minX, y: track.midY))
        center.line(to: NSPoint(x: track.maxX, y: track.midY))
        center.lineWidth = 1
        center.stroke()

        // VU bars — newest sample nearest the tape head (right)
        let barW: CGFloat = 2
        let stride = barW + 2
        let count = levels.count
        for i in 0..<count {
            let level = levels[count - 1 - i]
            let x = track.maxX - CGFloat(i + 1) * stride
            if x < track.minX { break }
            let h = max(2, level * (track.height - 2))
            let rect = NSRect(x: x, y: track.midY - h / 2, width: barW, height: h)
            (i < 3 ? Self.amber : Self.ink).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }

        // tape head marker at the write point (right edge of the track)
        Self.amberDeep.setStroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: track.maxX, y: track.minY))
        head.line(to: NSPoint(x: track.maxX, y: track.maxY))
        head.lineWidth = 1.5
        head.stroke()

        let recAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: Self.alert,
        ]
        let recSize = ("REC" as NSString).size(withAttributes: recAttrs)
        ("REC" as NSString).draw(at: NSPoint(x: b.maxX - recSize.width - 12, y: b.midY - recSize.height / 2), withAttributes: recAttrs)
    }
}

// MARK: - Example chip
//
// Dashed-pill action chip used in the "· TRY" suggestions row. Replaces
// the previous NSButton(.recessed) bezel — that style read as a system
// control and broke the documentary feel of the surrounding chrome.
// Built as an NSView (text field + custom layers) rather than NSButton
// so we get a clean dashed CAShapeLayer stroke and pill-pinned radius.

@MainActor
private final class CaptureMarkupExampleChip: NSView {
    var onClick: (() -> Void)?

    private let textField = NSTextField(labelWithString: "")
    private let dashLayer = CAShapeLayer()

    private static let pane = NSColor(red: 0.945, green: 0.945, blue: 0.937, alpha: 1)
    private static let strokeColor = NSColor(white: 0.10, alpha: 0.22).cgColor
    private static let hoverStrokeColor = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 0.55).cgColor

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
// highlight at the top edge (clipped to the 5pt corner radius). Same
// `box-shadow: inset 0 1px 0` treatment as the mic and the studio mock.

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

    private static let amber = NSColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1)
    private static let amberDeep = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 1)
    private static let amberFaint = NSColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 0.98)
    private static let amberSoft = NSColor(red: 0.72, green: 0.80, blue: 1.0, alpha: 1)

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

// MARK: - Pill button (Save / Run)
//
// Custom-drawn pills so the fills, radius, and keycaps are fully under our
// control. The keycap (⌘S / ⌘↵ / ✓) is rendered in the SYSTEM font — the
// monospaced font tofus those glyphs, which was the garbled "X" in the
// shipped bar. Label stays mono uppercase to match the chrome.

@MainActor
private final class CaptureMarkupPillButton: NSView {
    enum Kind { case primary, faint }

    var onClick: (() -> Void)?

    private let kind: Kind
    private let labelField = NSTextField(labelWithString: "")
    private let keycapField = NSTextField(labelWithString: "")
    private var enabledForClick = true

    private static let amber = NSColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1)
    private static let amberDeep = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 1)
    private static let amberFaint = NSColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)
    private static let amberSoft = NSColor(red: 0.72, green: 0.80, blue: 1.0, alpha: 1)

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5

        labelField.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        keycapField.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        for field in [labelField, keycapField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = false
            field.isSelectable = false
            field.drawsBackground = false
            field.isBordered = false
            addSubview(field)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            keycapField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 6),
            keycapField.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingAnchor.constraint(equalTo: keycapField.trailingAnchor, constant: 12),
        ])
        applyDefaultColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(label: String, keycap: String?) {
        labelField.stringValue = label
        keycapField.stringValue = keycap ?? ""
        keycapField.isHidden = (keycap == nil)
        applyDefaultColors()
    }

    func setEnabledForClick(_ enabled: Bool) {
        enabledForClick = enabled
        alphaValue = enabled ? 1 : 0.45
    }

    func applyDefaultColors() {
        switch kind {
        case .primary:
            layer?.backgroundColor = Self.amber.cgColor
            layer?.borderColor = Self.amber.cgColor
            labelField.textColor = .white
            keycapField.textColor = NSColor.white.withAlphaComponent(0.85)
        case .faint:
            layer?.backgroundColor = Self.amberFaint.cgColor
            layer?.borderColor = Self.amberSoft.cgColor
            labelField.textColor = Self.amberDeep
            keycapField.textColor = Self.amberDeep.withAlphaComponent(0.7)
        }
    }

    /// Override the palette for transient states (e.g. the "SAVED ✓" flash).
    func setColors(background: NSColor, border: NSColor, label: NSColor, keycap: NSColor) {
        layer?.backgroundColor = background.cgColor
        layer?.borderColor = border.cgColor
        labelField.textColor = label
        keycapField.textColor = keycap
    }

    override func mouseDown(with event: NSEvent) {
        guard enabledForClick else { return }
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Input bar

@MainActor
final class CaptureMarkupInputBarView: NSView {
    weak var delegate: CaptureMarkupPanelChromeDelegate?

    private static let chrome = NSColor(red: 0.945, green: 0.945, blue: 0.941, alpha: 1)
    private static let pane = NSColor(red: 0.945, green: 0.945, blue: 0.937, alpha: 1)
    private static let amber = NSColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1)
    private static let amberDeep = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 1)
    private static let amberFaint = NSColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)
    private static let amberSoft = NSColor(red: 0.72, green: 0.80, blue: 1.0, alpha: 1)
    private static let fieldBorder = NSColor(white: 0.10, alpha: 0.20)
    private static let fieldBorderActive = NSColor(red: 0.82, green: 0.23, blue: 0.11, alpha: 0.45)

    private let examplesStack = NSStackView()
    private let tryLabel = NSTextField(labelWithString: "· TRY")
    private let scopeBadge = NSTextField(labelWithString: "GLOBAL · WHOLE IMAGE")
    private let voiceButton = CaptureMarkupMicButton()
    private let selectionChip = CaptureMarkupSelectionChipView()
    private let promptField = NSTextField()
    private let waveform = CaptureMarkupWaveformView()
    private let saveButton = CaptureMarkupPillButton(kind: .faint)
    private let runButton = CaptureMarkupPillButton(kind: .primary)
    private let promptContainer = CaptureMarkupPromptContainerView()
    /// Resets the Save button out of its transient "SAVED ✓" state.
    private var saveFeedbackResetWork: DispatchWorkItem?

    // Attachments row. Hidden when empty; shows the selection chip(s)
    // between the TRY row and the composer row, so things you've pulled
    // into the message don't pollute the prompt's text area.
    private let attachmentsRow = NSStackView()
    private let attachmentsLabel = NSTextField(labelWithString: "· ATTACHED")
    private var attachmentsRowHeightConstraint: NSLayoutConstraint?
    private var attachmentsRowTopConstraint: NSLayoutConstraint?

    private var isVoiceRecording = false
    private var isVoiceTranscribing = false
    private var isRunning = false
    private var isSaveConfirming = false

    private var askExamples = [
        "circle the error and label it",
        "draw a horizontal guide from the first word",
        "blur the email address",
        "arrow from the title to the failed line",
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
        layer?.backgroundColor = Self.chrome.cgColor

        tryLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        tryLabel.textColor = .tertiaryLabelColor

        scopeBadge.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        scopeBadge.textColor = .tertiaryLabelColor
        scopeBadge.alignment = .right

        examplesStack.orientation = .horizontal
        examplesStack.spacing = 8
        examplesStack.alignment = .centerY

        promptContainer.wantsLayer = true
        promptContainer.layer?.backgroundColor = NSColor.white.cgColor
        promptContainer.layer?.borderColor = Self.fieldBorder.cgColor
        promptContainer.layer?.borderWidth = 0.5
        // Rounder field harmonizes with the circular mic sitting beside it —
        // a boxy r7 lane read square next to the round tap-target.
        promptContainer.layer?.cornerRadius = 12

        // Mic affordance is the shape. Glyph + colors swap with state.
        voiceButton.toolTip = "Tap to record · tap again to stop"
        voiceButton.onToggle = { [weak self] in self?.toggleVoiceCapture() }

        promptField.placeholderString = "tell the agent what to mark up…"
        promptField.font = NSFont.systemFont(ofSize: 13)
        promptField.isBordered = false
        promptField.isBezeled = false
        promptField.drawsBackground = false
        promptField.focusRingType = .none
        promptField.target = self
        promptField.action = #selector(runTapped)

        // Save / Run — custom pill buttons. Save is the quieter accent-faint
        // pill; Run the filled accent primary. Keyboard shortcuts (⌘S / ⌘↵)
        // are handled in performKeyEquivalent below; the pills carry the
        // keycaps as visible hints.
        saveButton.onClick = { [weak self] in self?.saveTapped() }
        runButton.onClick = { [weak self] in self?.runTapped() }

        selectionChip.onDismiss = { [weak self] in
            self?.delegate?.captureMarkupPanelDidClearSelection()
        }
        selectionChip.isHidden = false  // visibility is now driven by the row

        attachmentsLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        attachmentsLabel.textColor = .tertiaryLabelColor

        attachmentsRow.orientation = .horizontal
        attachmentsRow.spacing = 8
        attachmentsRow.alignment = .centerY
        attachmentsRow.addArrangedSubview(attachmentsLabel)
        attachmentsRow.addArrangedSubview(selectionChip)
        attachmentsRow.isHidden = true

        // Speak Strip composition:
        //   · TRY  [chips…]                     GLOBAL · WHOLE IMAGE
        //   · ATTACHED  ↳ LAYER chip          ← hidden when empty
        //   [🎤]   [────── prompt ──────]   [ RUN ⌘↵ ]
        //
        // Mic and Run sit OUTSIDE the prompt container — three distinct
        // elements with gaps, not one merged composer row. Attachments
        // live in their own row; nothing is ever crammed inside the
        // prompt's text area.
        [tryLabel, examplesStack, scopeBadge, attachmentsRow, voiceButton, promptContainer, saveButton, runButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        promptContainer.addSubview(promptField)
        promptField.translatesAutoresizingMaskIntoConstraints = false

        // Waveform overlays the prompt lane and only shows while recording —
        // the lane is the prompt at rest, the tape transport when hot.
        waveform.translatesAutoresizingMaskIntoConstraints = false
        waveform.isHidden = true
        promptContainer.addSubview(waveform)

        let attachmentsTop = attachmentsRow.topAnchor.constraint(equalTo: tryLabel.bottomAnchor, constant: 8)
        let attachmentsHeight = attachmentsRow.heightAnchor.constraint(equalToConstant: 0)
        attachmentsHeight.priority = .defaultHigh
        attachmentsHeight.isActive = false  // active only when row is hidden
        attachmentsRowTopConstraint = attachmentsTop
        attachmentsRowHeightConstraint = attachmentsHeight

        // Strip padding matches the studio mock: 8pt top, 14pt sides,
        // 10pt bottom. Was 10/12/10 — felt cramped at the leading edge
        // and a touch tall at the top.
        NSLayoutConstraint.activate([
            tryLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            tryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            examplesStack.centerYAnchor.constraint(equalTo: tryLabel.centerYAnchor),
            examplesStack.leadingAnchor.constraint(equalTo: tryLabel.trailingAnchor, constant: 8),

            scopeBadge.centerYAnchor.constraint(equalTo: tryLabel.centerYAnchor),
            scopeBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scopeBadge.leadingAnchor.constraint(greaterThanOrEqualTo: examplesStack.trailingAnchor, constant: 12),

            attachmentsTop,
            attachmentsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            attachmentsRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            voiceButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            voiceButton.topAnchor.constraint(equalTo: attachmentsRow.bottomAnchor, constant: 7),
            voiceButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            promptContainer.leadingAnchor.constraint(equalTo: voiceButton.trailingAnchor, constant: 10),
            promptContainer.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            promptContainer.centerYAnchor.constraint(equalTo: voiceButton.centerYAnchor),
            promptContainer.heightAnchor.constraint(equalToConstant: 34),

            promptField.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor, constant: 12),
            promptField.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor, constant: -12),
            promptField.centerYAnchor.constraint(equalTo: promptContainer.centerYAnchor),

            waveform.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor),
            waveform.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor),
            waveform.topAnchor.constraint(equalTo: promptContainer.topAnchor),
            waveform.bottomAnchor.constraint(equalTo: promptContainer.bottomAnchor),

            saveButton.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: voiceButton.centerYAnchor),

            runButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            runButton.centerYAnchor.constraint(equalTo: voiceButton.centerYAnchor),
        ])

        setAttachmentsRowVisible(false)
        setTouchUpMode(false)
        updateVoiceButtonAppearance()
        updateSaveButtonAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var promptText: String {
        get { promptField.stringValue }
        set { promptField.stringValue = newValue }
    }

    func clearPrompt() {
        promptField.stringValue = ""
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        promptField.isEnabled = !running
        voiceButton.isEnabled = !running
        updateRunButtonAppearance()
        updateSaveButtonAppearance()
    }

    /// Flash the Save button into a confirmed "SAVED ✓" state, then settle
    /// back to the idle "⌘S SAVE" label after a short beat. Called by the
    /// coordinator once the document is persisted to the sidecar.
    func flashSaved() {
        saveFeedbackResetWork?.cancel()
        isSaveConfirming = true
        updateSaveButtonAppearance()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isSaveConfirming = false
            self.updateSaveButtonAppearance()
        }
        saveFeedbackResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    func setTouchUpMode(_ touchUp: Bool) {
        isTouchUpMode = touchUp
        let examples = touchUp ? touchUpExamples : askExamples
        promptField.placeholderString = touchUp
            ? "speak or type another pass…"
            : "tell the agent what to mark up…"
        if !touchUp || attachmentsRow.isHidden {
            scopeBadge.stringValue = "GLOBAL · WHOLE IMAGE"
        }
        rebuildExampleChips(examples)
    }

    func setSelection(id: String?, label: String?, kind: String?) {
        if let id, let label, let kind {
            selectionChip.configure(id: id, label: label, kind: kind)
            setAttachmentsRowVisible(true)
            scopeBadge.stringValue = "SCOPED · \(id.uppercased()) SELECTED"
        } else {
            setAttachmentsRowVisible(false)
            if isTouchUpMode {
                scopeBadge.stringValue = "GLOBAL · WHOLE IMAGE"
            }
        }
    }

    private func setAttachmentsRowVisible(_ visible: Bool) {
        attachmentsRow.isHidden = !visible
        // When hidden, collapse the row to 0pt + drop the top gap so the
        // strip shrinks back to its idle height.
        attachmentsRowHeightConstraint?.isActive = !visible
        attachmentsRowTopConstraint?.constant = visible ? 8 : 0
    }

    private func rebuildExampleChips(_ examples: [String]) {
        examplesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for text in examples {
            let chip = CaptureMarkupExampleChip(text: text)
            chip.onClick = { [weak self] in
                self?.promptField.stringValue = text
                self?.delegate?.captureMarkupPanelTryExampleSelected(text)
            }
            examplesStack.addArrangedSubview(chip)
        }
    }

    /// Mic is tap-to-toggle. First tap starts capture, second tap stops
    /// and transcribes. Tapping while transcribing is a no-op (next tap
    /// available once the transcript lands).
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
        let existing = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            promptField.stringValue = text
        } else {
            let needsSpace = !existing.hasSuffix(" ") && !existing.hasSuffix("\n")
            promptField.stringValue = existing + (needsSpace ? " " : "") + text
        }
        promptField.becomeFirstResponder()
    }

    private func updateVoiceButtonAppearance() {
        let symbolName: String
        let glyphColor: NSColor
        let bg: NSColor
        let border: NSColor
        let tip: String

        if isVoiceTranscribing {
            symbolName = "ellipsis"
            glyphColor = .secondaryLabelColor
            bg = NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
            border = NSColor.separatorColor
            tip = "Transcribing…"
        } else if isVoiceRecording {
            symbolName = "stop.fill"
            glyphColor = NSColor.systemRed.withAlphaComponent(0.92)
            bg = NSColor.systemRed.withAlphaComponent(0.14)
            border = NSColor.systemRed.withAlphaComponent(0.45)
            tip = "Tap to stop"
        } else {
            symbolName = "mic.fill"
            glyphColor = Self.amberDeep
            bg = Self.amberFaint
            border = Self.amberSoft
            tip = "Tap to record"
        }

        voiceButton.title = ""
        voiceButton.attributedTitle = NSAttributedString(string: "")
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: tip) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            voiceButton.image = symbol.withSymbolConfiguration(config)
        }
        voiceButton.imageScaling = .scaleNone
        voiceButton.contentTintColor = glyphColor
        voiceButton.layer?.backgroundColor = bg.cgColor
        voiceButton.layer?.borderColor = border.cgColor
        voiceButton.toolTip = tip
        updateRunButtonAppearance()
        updateComposerRecordingState()
    }

    /// While the mic is hot, the prompt lane becomes the tape transport:
    /// hide the text field, reveal + run the waveform, flush the lane border
    /// to alert-red. At rest it's the prompt again.
    private func updateComposerRecordingState() {
        let recording = isVoiceRecording
        waveform.isHidden = !recording
        promptField.isHidden = recording
        if recording {
            waveform.start()
        } else {
            waveform.stop()
        }
        let border = recording ? Self.fieldBorderActive : Self.fieldBorder
        promptContainer.layer?.borderColor = border.cgColor
    }

    private func updateRunButtonAppearance() {
        let enabled = !isRunning && !isVoiceRecording && !isVoiceTranscribing
        if isRunning {
            runButton.configure(label: "RUNNING", keycap: nil)
        } else {
            runButton.configure(label: "RUN", keycap: "⌘↵")
        }
        runButton.setEnabledForClick(enabled)
    }

    private func updateSaveButtonAppearance() {
        // Quieter than Run: accent-faint pill. While a run is in flight it's
        // disabled; when a save just landed it flashes a confirmed check.
        if isSaveConfirming {
            saveButton.configure(label: "SAVED", keycap: "✓")
            saveButton.setColors(
                background: Self.amberFaint,
                border: Self.amber,
                label: Self.amber,
                keycap: Self.amber
            )
        } else {
            saveButton.configure(label: "SAVE", keycap: "⌘S")
        }
        saveButton.setEnabledForClick(!isRunning)
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
        let instruction = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        delegate?.captureMarkupPanelDidRun(instruction: instruction)
    }
}

// MARK: - Selection chip

@MainActor
final class CaptureMarkupSelectionChipView: NSView {
    var onDismiss: (() -> Void)?

    private let idLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let dismissButton = NSButton(title: "×", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1).cgColor
        layer?.borderColor = NSColor(red: 0.72, green: 0.80, blue: 1.0, alpha: 1).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 3

        idLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        idLabel.textColor = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 1)
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = NSColor(red: 0.14, green: 0.29, blue: 0.65, alpha: 1)

        dismissButton.isBordered = false
        dismissButton.bezelStyle = .inline
        dismissButton.font = NSFont.systemFont(ofSize: 10)
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)

        [idLabel, nameLabel, dismissButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            idLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            idLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: idLabel.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(id: String, label: String, kind: String) {
        idLabel.stringValue = "↳ \(id.uppercased())"
        nameLabel.stringValue = label.isEmpty ? kind : label
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
