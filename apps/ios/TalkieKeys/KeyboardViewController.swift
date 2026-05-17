import UIKit
import TalkieMobileKit
#if canImport(FoundationModels)
import FoundationModels
#endif

private let log = Log(.keyboard)

// MARK: - Performance Instrumentation

/// Lightweight performance tracker.
private final class PerfTrace {
    private var startTime: UInt64 = 0
    private let name: StaticString

    init(_ name: StaticString) {
        self.name = name
    }

    func begin() {
        startTime = mach_absolute_time()
    }

    func event(_ message: StaticString) {
        log.debug("⏱ \(name) event: \(String(describing: message))")
    }

    func end() {
        let elapsed = elapsedMs()
        log.info("⏱ \(name): \(elapsed.formatted(.number.precision(.fractionLength(1))))ms")
    }

    func end(message: String) {
        let elapsed = elapsedMs()
        log.info("⏱ \(name): \(elapsed.formatted(.number.precision(.fractionLength(1))))ms - \(message)")
    }

    private func elapsedMs() -> Double {
        let end = mach_absolute_time()
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let elapsedNano = (end - startTime) * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        return Double(elapsedNano) / 1_000_000.0
    }
}

// MARK: - Constraint Priority Helper

extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

@available(iOS 17.0, *)
final class KeyboardViewController: UIInputViewController, KeyboardInputHost {

    // MARK: - Design Constants (Talkie Branded - Adaptive)

    private enum Design {
        // MARK: Adaptive Colors - Talkie branded with light/dark support

        /// Main keyboard background - fully transparent to match iOS
        static let background = UIColor.clear

        /// Key/button background (lightly tinted so texture remains visible)
        static let surfaceDark = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.02)
                : UIColor(white: 1.0, alpha: 0.72)
        }

        /// Pressed state
        static let surfaceLight = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.90)
        }

        /// Special key background (shift, delete, etc.)
        static let surfaceSpecial = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.04)
                : UIColor(white: 1.0, alpha: 0.78)
        }

        /// Subtle key border to define keys without heavy fills.
        static let keyBorder = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.16)
                : UIColor(white: 0.0, alpha: 0.08)
        }

        /// Slightly stronger border during press.
        static let keyBorderPressed = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.24)
                : UIColor(white: 0.0, alpha: 0.16)
        }

        // Brand colors - consistent across modes
        static let vermillion = UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1.0)  // #E84D3D
        static let vermillionDisabled = UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 0.4)

        /// Primary text color
        static let textPrimary = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 1.0)    // Dark: white
                : UIColor(white: 0.0, alpha: 1.0)    // Light: black
        }

        /// Secondary text color
        static let textSecondary = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.6, alpha: 1.0)
                : UIColor(white: 0.4, alpha: 1.0)
        }

        /// Muted text color
        static let textMuted = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.4, alpha: 1.0)
                : UIColor(white: 0.55, alpha: 1.0)
        }

        // Status accent color for transient text hints.
        static let ledReady = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)  // Green

        /// LED bar background
        static let ledBarBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)   // Dark: very dark
                : UIColor(red: 0.75, green: 0.75, blue: 0.77, alpha: 1.0)   // Light: darker than bg
        }

        // Layout
        static let rowSpacing: CGFloat = 6      // Vertical space between rows
        static let gridSpacing: CGFloat = 5     // Horizontal space between buttons
        static let sidePadding: CGFloat = 3     // Side margins for grid
        static let buttonHeight: CGFloat = 48   // Row height for slot grid
        static let cornerRadius: CGFloat = 4    // Button corner radius
        static let ledBarHeight: CGFloat = 40   // Status bar height
        static let ledSize: CGFloat = 7         // Status LED dot size
        static let activityBarHeight: CGFloat = 2

        // Liquid glass effect colors - adaptive (matte style, subtle)
        static let glassHighlight = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.03)
                : UIColor(white: 1.0, alpha: 0.25)
        }
        static let glassShadow = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.0, alpha: 0.2)
                : UIColor(white: 0.0, alpha: 0.1)
        }
        static let glassInnerShadow = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.0, alpha: 0.25)
                : UIColor(white: 0.0, alpha: 0.15)
        }
        static let glassGlow = UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 0.4)  // Recording glow
        static let modeKnobCornerRadius: CGFloat = 11
        static let modeTileCornerRadius: CGFloat = 9
    }

    // MARK: - Haptic Generators (pre-prepared for reliable feedback)

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let aiKeyboardResidentMemorySoftLimitBytes: UInt64 = 38 * 1_024 * 1_024
    private let aiMemoryWarningCooldown: TimeInterval = 30
    private var lastAIMemoryWarningAt: Date?
    private let localClipboardMaxCharacters = 4_096

    // MARK: - Keyboard Configuration

    /// Keyboard config (layout + modes) - loaded from App Group
    private var keyboardConfig = KeyboardConfig()
    private let modePersistenceMaxAge: TimeInterval = 60 * 60 * 24  // 24 hours

    /// Convenience: current active mode
    private var currentMode: TalkieMobileKit.KeyboardMode {
        keyboardConfig.activeMode
    }

    private func restorePersistedModeSelectionIfAvailable() {
        guard let savedModeId = bridge.getLastSelectedModeId(maxAge: modePersistenceMaxAge) else { return }
        guard keyboardConfig.modeOrder.contains(savedModeId) else { return }
        keyboardConfig.activeModeId = savedModeId
        selectedCategory = ModeCategory.category(for: savedModeId)
    }

    private func persistActiveModeSelection() {
        bridge.setLastSelectedModeId(currentMode.id)
    }

    /// Cycle to next mode
    private func cycleToNextMode() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        refreshModeKnobAttention()

        // Show status message with next mode name
        let nextModeName = nextModeLabel
        showModeTransition(to: nextModeName)

        // Update state
        keyboardConfig.cycleToNextMode()
        persistActiveModeSelection()
        updateGridForMode()
        updateModeKnobSelection()

        log.info("Mode switched to: \(currentMode.name)")
    }

    /// Cycle to previous mode
    private func cycleToPreviousMode() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        refreshModeKnobAttention()

        // Get previous mode name before switching
        let modes = keyboardConfig.orderedModes
        guard let currentIndex = modes.firstIndex(where: { $0.id == currentMode.id }) else { return }
        let prevIndex = (currentIndex - 1 + modes.count) % modes.count
        let prevModeName = getModeLabel(for: modes[prevIndex])
        showModeTransition(to: prevModeName)

        // Update state
        keyboardConfig.cycleToPreviousMode()
        persistActiveModeSelection()
        updateGridForMode()
        updateModeKnobSelection()

        log.info("Mode switched to: \(currentMode.name)")
    }

    private func storeLocalClipboardText(_ text: String) {
        localClipboardText = String(text.prefix(localClipboardMaxCharacters))
    }

    /// Show brief status message during mode transition
    private func setStatusMessage(_ message: String, color: UIColor? = nil) {
        statusMessage = message
        guard let statusLabel else { return }
        applyStatusPillStyle(isIdle: false)
        let foreground = (color ?? Design.textSecondary).withAlphaComponent(0.88)
        statusLabel.text = message
        statusLabel.textColor = foreground
        statusPillView?.layer.borderColor = foreground.withAlphaComponent(0.28).cgColor
        statusLabel.alpha = message.isEmpty ? 0 : 1
        selectionStatusOverlayLabel?.text = message
        selectionStatusOverlayLabel?.textColor = foreground
        selectionStatusOverlayView?.layer.borderColor = foreground.withAlphaComponent(0.28).cgColor
        statusActionOverlayView?.layer.borderColor = foreground.withAlphaComponent(0.28).cgColor
        updateActionOverlayHeader()
        statusActionPreviewLabel?.text = actionModePreviewText()
    }

    private var idleStatusForegroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.84)
                : UIColor(white: 0.15, alpha: 0.62)
        }
    }

    private func applyStatusPillStyle(isIdle: Bool) {
        guard let statusPillView else { return }

        if isIdle {
            statusPillView.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.08)
                    : UIColor(white: 1.0, alpha: 0.80)
            }
            statusPillView.layer.borderColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.18)
                    : UIColor(white: 1.0, alpha: 0.56)
            }.cgColor
        } else {
            statusPillView.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.12)
                    : UIColor(white: 1.0, alpha: 0.88)
            }
            statusPillView.layer.borderColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.24)
                    : UIColor(white: 1.0, alpha: 0.64)
            }.cgColor
        }
    }

    private func clearStatusMessage(color: UIColor? = nil) {
        statusMessage = ""
        guard let statusLabel else { return }
        applyStatusPillStyle(isIdle: true)
        statusLabel.text = "Ready"
        if let color {
            statusLabel.textColor = color
        } else {
            statusLabel.textColor = idleStatusForegroundColor
        }
        statusLabel.alpha = 1
        selectionStatusOverlayLabel?.text = "Ready"
        selectionStatusOverlayLabel?.textColor = statusLabel.textColor
        selectionStatusOverlayView?.layer.borderColor = statusPillView?.layer.borderColor
        statusActionOverlayView?.layer.borderColor = statusPillView?.layer.borderColor
        updateActionOverlayHeader()
        statusActionPreviewLabel?.text = actionModePreviewText()
    }

    private func showModeTransition(to modeName: String) {
        refreshModeKnobAttention()
        animateModeKnobGlassPulse()
        // Flash the status label with mode name
        setStatusMessage(modeName, color: Design.textPrimary)

        // Clear status after brief display (unless in an active state)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .arming]
            if !activePhases.contains(self.currentPhase) {
                UIView.animate(withDuration: 0.2) {
                    self.clearStatusMessage()
                }
            }
        }
    }

    private func animateModeKnobGlassPulse() {
        guard let target = modeShortcutContainer ?? modeKnobSelectionPill ?? modeKnob else { return }

        let pulseOverlay = UIView()
        pulseOverlay.translatesAutoresizingMaskIntoConstraints = false
        pulseOverlay.isUserInteractionEnabled = false
        pulseOverlay.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 1.0, alpha: 0.22)
        }
        pulseOverlay.layer.cornerRadius = target.layer.cornerRadius
        pulseOverlay.layer.cornerCurve = .continuous
        pulseOverlay.alpha = 0

        target.addSubview(pulseOverlay)
        NSLayoutConstraint.activate([
            pulseOverlay.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            pulseOverlay.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            pulseOverlay.topAnchor.constraint(equalTo: target.topAnchor),
            pulseOverlay.bottomAnchor.constraint(equalTo: target.bottomAnchor)
        ])

        // Subtle shimmer sweep on mode switcher.
        let shimmerWidth: CGFloat = 42
        let shimmerLayer = CAGradientLayer()
        shimmerLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.22).cgColor,
            UIColor.clear.cgColor
        ]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.frame = CGRect(
            x: -shimmerWidth,
            y: 0,
            width: shimmerWidth,
            height: max(1, target.bounds.height)
        )
        pulseOverlay.layer.addSublayer(shimmerLayer)

        UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: {
            pulseOverlay.alpha = 1
            shimmerLayer.frame.origin.x = target.bounds.width + shimmerWidth
        }) { _ in
            UIView.animate(withDuration: 0.24, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: {
                pulseOverlay.alpha = 0
            }) { _ in
                pulseOverlay.removeFromSuperview()
            }
        }
    }

    /// Get display label for a mode
    private func getModeLabel(for mode: TalkieMobileKit.KeyboardMode) -> String {
        switch mode.id {
        case "abc": return "ABC"
        case "fn", "shortcuts": return "Shortcuts"
        case "numbers": return "123"
        case "symbols": return "#$&"
        case "emoji": return "Emoji"
        default: return String(mode.name.prefix(3)).uppercased()
        }
    }

    /// Get the next mode in the cycle (for mode button label)
    private var nextMode: TalkieMobileKit.KeyboardMode {
        let modes = keyboardConfig.orderedModes
        guard let currentIndex = modes.firstIndex(where: { $0.id == currentMode.id }) else {
            return modes.first ?? .abc
        }
        let nextIndex = (currentIndex + 1) % modes.count
        return modes[nextIndex]
    }

    /// Get the icon for the next mode
    private var nextModeIcon: String {
        switch nextMode.id {
        case "abc": return "keyboard"
        case "fn", "shortcuts": return "rectangle.grid.2x2"
        case "numbers": return "textformat.123"
        case "symbols": return "numbersign"
        case "emoji": return "face.smiling"
        default: return nextMode.icon
        }
    }

    /// Get the label for the next mode
    private var nextModeLabel: String {
        switch nextMode.id {
        case "abc": return "ABC"
        case "fn", "shortcuts": return "Shortcuts"
        case "numbers": return "123"
        case "symbols": return "#$&"
        case "emoji": return "Emoji"
        default: return nextMode.name.prefix(3).uppercased()
        }
    }

    // MARK: - Text Capitalization Styles

    /// Styles for the capitalize button cycle
    enum CapitalizeStyle: CaseIterable {
        case lowercase      // all lowercase
        case capitalize     // First Letter Of Each Word
        case uppercase      // ALL UPPERCASE
        case camelCase      // camelCase (first word lower, rest capitalized, no spaces)
        case snakeCase      // snake_case (lowercase with underscores)

        var next: CapitalizeStyle {
            let all = Self.allCases
            let idx = all.firstIndex(of: self)!
            return all[(idx + 1) % all.count]
        }

        var label: String {
            switch self {
            case .lowercase: return "aa"
            case .capitalize: return "Aa"
            case .uppercase: return "AA"
            case .camelCase: return "aA"
            case .snakeCase: return "a_a"
            }
        }
    }

    private var currentCapitalizeStyle: CapitalizeStyle = .capitalize

    // MARK: - Ready State

    private var isRecordReady = false {
        didSet {
            updateRecordButtonState()
        }
    }

    // MARK: - UI Elements

    private lazy var mainStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private weak var recordButton: UIButton?
    private weak var statusLabel: UILabel?
    private var statusMessage: String = ""
    private var localClipboardText: String?
    private weak var activityBar: UIView?
    private var shimmerLayer: CAGradientLayer?
    private var diagnosticsEvents: [String] = []
    private let maxDiagnosticsEvents = 12

    /// When true, transcription result will be routed through EmojiRecognizer
    private var isVoiceEmojiMode = false
    /// When true, dictation results are interpreted as commands instead of inserted text.
    private var isVoiceCommandMode = false
    /// When true, command mode should auto-start listening once recorder becomes idle.
    private var pendingVoiceCommandStart = false
    private enum CaptureMode {
        case dictation
        case voiceCommand
    }
    private var activeCaptureMode: CaptureMode = .dictation

    /// Voice emoji overlay for cosmic search experience
    private var voiceEmojiOverlay: VoiceEmojiOverlayView?
    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?

    /// Compact keyboard for ABC mode (full QWERTY with long-press accents)
    private var compactKeyboardView: CompactKeyboardView?
    private var isABCModeActive = false

    /// Minimal layout state
    private var isMinimalLayoutActive = false
    private var minimalKeyboardView: MinimalKeyboardView?
    private var pillTrayView: PillTrayView?
    private var puncOverlayView: PuncOverlayView?
    private var puncLongPressTimer: Timer?
    private var puncDidFireLongPress = false
    private weak var compactRecordButton: UIButton?
    private let minimalKeyboardHeight: CGFloat = MinimalKeyboardView.totalHeight

    /// Slot grid container (hidden when ABC keyboard is shown)
    private var slotGridContainer: UIView?

    /// Surface shell that gives the keyboard slight padding from host edges.
    private var keyboardSurfaceView: UIView?

    /// Height constraint for keyboard - consistent across all modes
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var slotGridHeightConstraint: NSLayoutConstraint?

    /// Standard keyboard base height (without bottom safe-area inset).
    private let standardKeyboardBaseHeight: CGFloat = 224
    private var gridPreset: KeyboardGridPreset = .sixteen
    private var slotGridHeight: CGFloat {
        let rowCount = gridPreset.slotRows.count + 1 // + dictate row
        return (Design.buttonHeight * CGFloat(rowCount)) + (Design.rowSpacing * CGFloat(max(rowCount - 1, 0)))
    }
    private let keyboardSurfaceInsets = NSDirectionalEdgeInsets(top: 2, leading: 4, bottom: 0, trailing: 4)
    private let keyboardSurfaceCornerRadius: CGFloat = 22
    private let keyboardSurfaceTopPadding: CGFloat = 8
    private var minimumStandardKeyboardHeight: CGFloat {
        keyboardSurfaceInsets.top
        + keyboardSurfaceInsets.bottom
        + keyboardSurfaceTopPadding
        + Design.ledBarHeight
        + mainStack.spacing
        + slotGridHeight
    }

    /// Slot buttons indexed by slot number (1-12) for efficient mode switching
    private var slotButtons: [Int: UIButton] = [:]
    private var modeKnobFadeWorkItem: DispatchWorkItem?
    private var isModeKnobExpanded = true
    private let modeKnobIdleDelay: TimeInterval = 2.2
    private let modeKnobIdleAlpha: CGFloat = 0.72
    private let modeKnobActiveAlpha: CGFloat = 1.0
    private weak var modeKnobSelectionPill: UIView?
    private var modeKnobSelectionLeadingConstraint: NSLayoutConstraint?
    private var modeKnobSelectionTrailingConstraint: NSLayoutConstraint?

    private let bridge = KeyboardBridge.shared
    private let sharedStore = DictationSharedStore.shared
    private var currentSessionId: UUID?
    private var lastHeartbeatSentAt: TimeInterval = 0

    /// Tracks retry attempts for text insertion when textDocumentProxy is disconnected.
    /// Reset to 0 on successful insertion or after max retries.
    private var resultInsertionRetryCount = 0
    private let maxResultInsertionRetries = 3

    // Performance instrumentation
    private let loadTrace = PerfTrace("keyboard.load")
    private let stateTrace = PerfTrace("keyboard.state")
    private var dictationTrace: PerfTrace?

    // Liquid glass layers for record button
    private var glassHighlightLayer: CAGradientLayer?
    private var glassInnerShadowLayer: CALayer?
    private var glassGlowLayer: CALayer?
    private var pulseAnimation: CABasicAnimation?
    private var didAttemptDeepLinkFallback = false
    private var stateChangedToken: DictationNotificationCenter.Token?
    private var keyboardDebugEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var currentPhase: DictationSharedState.Phase {
        sharedStore.phase
    }

    private var phaseAge: TimeInterval {
        sharedStore.phaseAge
    }

    private var instantStartAvailable: Bool {
        let heartbeatFresh = isAppHeartbeatFresh()
        let warmReady = sharedStore.capability == .warm && heartbeatFresh
        let bridgeReady = bridge.isAppReady() && heartbeatFresh
        return warmReady || bridgeReady
    }

    private func isAppHeartbeatFresh(maxAge: TimeInterval = 6.0) -> Bool {
        let heartbeat = sharedStore.appHeartbeat
        guard heartbeat > 0 else { return false }
        return (Date().timeIntervalSince1970 - heartbeat) <= maxAge
    }

    // MARK: - Emoji Library

    private static let fullEmojiLibrary: [String] = {
        let ranges: [ClosedRange<UInt32>] = [
            0x1F300...0x1FAFF, // Symbols & pictographs, supplemental symbols
            0x2600...0x26FF,   // Misc symbols
            0x2700...0x27BF    // Dingbats
        ]

        var output: [String] = []
        var seen = Set<String>()

        for range in ranges {
            for value in range {
                guard let scalar = UnicodeScalar(value) else { continue }
                let props = scalar.properties
                guard props.isEmoji else { continue }
                guard props.isEmojiPresentation || props.generalCategory == .otherSymbol else { continue }
                let emoji = String(scalar)
                if seen.insert(emoji).inserted {
                    output.append(emoji)
                }
            }
        }

        // Merge in known multi-scalar mappings from recognizer
        for category in EmojiCategory.allCases {
            for emoji in EmojiRecognizer.shared.emojis(for: category) {
                if seen.insert(emoji).inserted {
                    output.append(emoji)
                }
            }
        }

        return output
    }()

    private static let defaultPopularEmojis: [String] = [
        "😂", "❤️", "😍", "😭", "😊", "🙏", "🥺", "🤣",
        "👍", "🔥", "💕", "😘", "😁", "😅", "✨", "🎉",
        "😎", "🤔", "😮", "😢", "😡", "👏", "🙌", "💯",
        "🤩", "🥳", "😉", "😴", "😱", "🤝", "👌", "🤗"
    ]

    private static func popularEmojiList(maxCount: Int = 60) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        let recents = RecentEmojis.shared.all
        for emoji in recents + defaultPopularEmojis {
            guard seen.insert(emoji).inserted else { continue }
            output.append(emoji)
            if output.count >= maxCount { break }
        }

        return output
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // ⏱ Start load timing
        loadTrace.begin()

        // Read user-selected slot-grid density from shared settings.
        gridPreset = bridge.getGridPreset()

        // Set up keyboard height constraint
        setupKeyboardHeight()

        // FAST PATH: Setup UI immediately, defer everything else
        setupUI()

        // Restore last mode selection so we don't reset to Shortcuts on every reload
        restorePersistedModeSelectionIfAvailable()
        updateGridForMode()

        // ⏱ Mark first paint ready
        loadTrace.event("ui_setup_complete")

        // Defer logging configuration to not block first paint
        Task { @MainActor in
            await Task.yield()
            TalkieLogger.configure(source: .talkieKeys)
        }

        // Warm up Taptic Engine for reliable first-tap haptics
        lightImpact.prepare()
        mediumImpact.prepare()

        stateChangedToken = DictationNotificationCenter.shared.addObserver(.stateChanged) { [weak self] in
            self?.handleStateSignal()
        }

        registerColorAppearanceObservation()
    }

    /// Set up the keyboard height constraint for proper sizing
    /// Checks persisted layout to avoid flashing the wrong height on cold start
    private func setupKeyboardHeight() {
        keyboardHeightConstraint?.isActive = false
        let savedLayout = bridge.getActiveLayout()
        let initialHeight = (savedLayout == "minimal") ? minimalKeyboardHeight : resolvedStandardKeyboardHeight()
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: initialHeight)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
        self.keyboardHeightConstraint = heightConstraint
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // ⏱ Mark visible
        loadTrace.event("view_did_appear")
        loadTrace.end(message: "first_paint")
        refreshModeKnobAttention(animated: false)

        // Show subtle "connecting" shimmer while we load state (skip in minimal — no LED bar)
        if !isMinimalLayoutActive {
            startLoadingShimmer()
        }

        // Defer ALL state loading to after first paint
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.loadState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        localClipboardText = nil

        // Run stale-state hygiene on every keyboard entry, not just initial load.
        cleanupStaleState()
        resetTransientTouchState(animated: false)

        // Respect the host app's keyboardAppearance request.
        // If the text field asks for .dark, override our interface style.
        if textDocumentProxy.keyboardAppearance == .dark {
            overrideUserInterfaceStyle = .dark
        } else {
            overrideUserInterfaceStyle = .unspecified
        }

        if !isABCModeActive {
            refreshGridPresetIfNeeded()
        }

        synchronizeLayoutWithPersistedPreference()

        startHeartbeat()

        // Quick check for results (user returning to keyboard)
        // Defer to not block appearance
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.checkForDictationResult()
            self?.checkRecordingState()
        }
    }

    private func synchronizeLayoutWithPersistedPreference() {
        let savedLayout = bridge.getActiveLayout() ?? "compact"
        if savedLayout == "minimal" {
            if !isMinimalLayoutActive {
                showMinimalLayout(animated: false)
            }
        } else if isMinimalLayoutActive {
            hideMinimalLayout(animated: false)
        }
        synchronizeKeyboardHeightForCurrentLayout()
    }

    private func registerColorAppearanceObservation() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            self.handleColorAppearanceChange(previousTraitCollection: previousTraitCollection)
        }
    }

    private func handleColorAppearanceChange(previousTraitCollection: UITraitCollection?) {
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        // Update key borders/shadows for adaptive key styling.
        for btn in slotButtons.values {
            applyGridKeyRestingStyle(to: btn)
        }
        if let recordButton {
            applyGridKeyRestingStyle(to: recordButton)
        }

        // Update LED bar border if visible
        ledDisplayBar?.layer.borderColor = Design.textMuted.cgColor

        log.debug("Appearance changed to: \(traitCollection.userInterfaceStyle == .dark ? "dark" : "light")")
    }

    /// Deferred state loading - called after first paint
    private func loadState() {
        // ⏱ Start state loading timing
        stateTrace.begin()

        log.info("viewDidAppear - keyboard visible")

        // Clean up stale state from previous sessions
        cleanupStaleState()
        stateTrace.event("stale_cleanup_done")

        sharedStore.updateKeyboardHeartbeat()

        // Check for dictation results from main app
        checkForDictationResult()
        stateTrace.event("result_check_done")

        // Check if recording is in progress (user returned from main app)
        checkRecordingState()
        stateTrace.event("recording_check_done")

        // Check ready state and update LED/record button
        checkReadyState()
        stateTrace.event("ready_check_done")

        // Stop loading shimmer once state is loaded
        stopLoadingShimmer()

        // Layout already restored in setupUI() — no deferred switch needed

        // ⏱ End state loading
        stateTrace.end(message: "fully_ready")

        // Defer non-critical logging
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.logExhaustiveContext()

            // Log diagnostics in background
            let diagnosis = self.bridge.diagnose()
            log.info("App Group Diagnostics:\n\(diagnosis)")
        }

        updateDebugView()
    }

    /// Subtle shimmer to indicate keyboard is connecting/loading
    private func startLoadingShimmer() {
        guard activityBar != nil else { return }

        // Very subtle gray shimmer while loading
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let bar = self.activityBar else { return }

            let screenWidth = self.view.window?.windowScene?.screen.bounds.width ?? 400
            let barWidth = bar.bounds.width > 0 ? bar.bounds.width : screenWidth

            let gradient = CAGradientLayer()
            gradient.frame = CGRect(x: 0, y: 0, width: barWidth * 2, height: Design.activityBarHeight)

            // Very subtle off-black shimmer
            let shimmerColor = UIColor(white: 0.2, alpha: 1.0)
            gradient.colors = [
                UIColor.clear.cgColor,
                shimmerColor.withAlphaComponent(0.4).cgColor,
                shimmerColor.cgColor,
                shimmerColor.withAlphaComponent(0.4).cgColor,
                UIColor.clear.cgColor
            ]
            gradient.locations = [0.0, 0.35, 0.5, 0.65, 1.0]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)

            bar.layer.addSublayer(gradient)
            self.shimmerLayer = gradient

            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = -barWidth / 2
            animation.toValue = barWidth * 1.5
            animation.duration = 1.5
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            gradient.add(animation, forKey: "shimmer")
        }
    }

    private func stopLoadingShimmer() {
        // Only stop if we're not in an active state that needs shimmer
        let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .arming]
        if !activePhases.contains(currentPhase) {
            stopActivityShimmer()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resetTransientTouchState(animated: false)
        modeKnobFadeWorkItem?.cancel()
        modeKnobFadeWorkItem = nil
        dismissCursorPadOverlay()
        stopHeartbeat()
        stopPolling()
        stopActivityShimmer()
        if let token = stateChangedToken {
            DictationNotificationCenter.shared.removeObserver(token)
            stateChangedToken = nil
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update shimmer frame if active
        if let shimmer = shimmerLayer, let bar = activityBar {
            shimmer.frame = CGRect(x: 0, y: 0, width: bar.bounds.width * 2, height: Design.activityBarHeight)
        }
        // Update glass effect frames
        updateGlassFrames()
        synchronizeKeyboardHeightForCurrentLayout()
        synchronizeCompactSpaceAlignmentReference()
        // Mode sync (compact show/hide) handled by updateGridForMode() at mode-change sites.
        // Do NOT sync here — layout passes during dictation could trigger hideCompactKeyboard()
        // which auto-stops recording.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        lastAIMemoryWarningAt = Date()
        log.warning("Keyboard received memory warning; pausing in-keyboard AI transforms temporarily")
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        log.debug("textWillChange")
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        log.debug("textDidChange")
        updateDebugView()
    }

    // MARK: - Setup UI

    private func setupUI() {
        // Transparent host; keyboard content sits inside a slightly inset shell.
        view.backgroundColor = .clear

        let surface = UIView(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.layer.cornerCurve = .continuous
        surface.layer.cornerRadius = keyboardSurfaceCornerRadius
        surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        surface.backgroundColor = .clear
        surface.clipsToBounds = true
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: view.topAnchor, constant: keyboardSurfaceInsets.top),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -keyboardSurfaceInsets.bottom),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: keyboardSurfaceInsets.leading),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -keyboardSurfaceInsets.trailing)
        ])
        keyboardSurfaceView = surface

        surface.addSubview(mainStack)
        NSLayoutConstraint.activate([
            // Main stack fills surface shell with a small top inset.
            mainStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: keyboardSurfaceTopPadding),
            mainStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: 0),
            mainStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor)
        ])

        // LED Display Bar at top (compact status + mode selector)
        let ledBar = createLEDDisplayBar()
        mainStack.addArrangedSubview(ledBar)
        let ledHeight = ledBar.heightAnchor.constraint(equalToConstant: Design.ledBarHeight)
        ledHeight.priority = .required
        ledHeight.isActive = true

        // Slot Grid with integrated DICTATE button
        // Row 1 (bottom): [SELECT][DICTATE 2x][ENTER]
        // Row 2: [slot][slot][slot][slot]
        // Row 3: [ESC][slot][slot][DEL]
        // Row 4 (top): [slot][slot][slot][slot]
        let slotGrid = createSlotGridWithDictate()
        slotGridContainer = slotGrid
        mainStack.addArrangedSubview(slotGrid)
        let slotHeight = slotGrid.heightAnchor.constraint(equalToConstant: slotGridHeight)
        slotHeight.isActive = true
        slotGridHeightConstraint = slotHeight

        // Start with record ENABLED - user can tap immediately
        // State will be verified async after first paint
        isRecordReady = true

        // Add swipe gestures for mode switching
        setupModeSwipeGestures()

        // If minimal layout was persisted, show it immediately (no flash of compact UI)
        if bridge.getActiveLayout() == "minimal" {
            showMinimalLayout(animated: false)
        }
    }

    /// Setup swipe gestures for mode cycling and layout switching
    private func setupModeSwipeGestures() {
        // Swipe left to go to previous mode (pill moves left)
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        // Swipe right to go to next mode (pill moves right)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        // Swipe down to switch to minimal layout
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)
    }

    @objc private func handleSwipeLeft() {
        if isMinimalLayoutActive {
            switchToLayout("compact")
        } else {
            cycleToPreviousMode()
        }
    }

    @objc private func handleSwipeRight() {
        if isMinimalLayoutActive {
            switchToLayout("compact")
        } else {
            cycleToNextMode()
        }
    }

    @objc private func handleSwipeDown() {
        if !isMinimalLayoutActive {
            switchToLayout("minimal")
        }
    }

    private func refreshGridPresetIfNeeded() {
        let persistedPreset = bridge.getGridPreset()
        guard persistedPreset != gridPreset else { return }
        guard !isABCModeActive else { return }

        gridPreset = persistedPreset
        rebuildSlotGridForCurrentPreset()
        synchronizeKeyboardHeightForCurrentLayout()

        log.info("Applied grid preset: \(gridPreset.rawValue)")
    }

    private func rebuildSlotGridForCurrentPreset() {
        guard let existingGrid = slotGridContainer else { return }

        mainStack.removeArrangedSubview(existingGrid)
        existingGrid.removeFromSuperview()

        slotButtons.removeAll()
        compactRecordButton = nil

        let newGrid = createSlotGridWithDictate()
        slotGridContainer = newGrid

        if mainStack.arrangedSubviews.isEmpty {
            mainStack.addArrangedSubview(newGrid)
        } else {
            mainStack.insertArrangedSubview(newGrid, at: min(1, mainStack.arrangedSubviews.count))
        }

        slotGridHeightConstraint?.isActive = false
        let heightConstraint = newGrid.heightAnchor.constraint(equalToConstant: slotGridHeight)
        heightConstraint.isActive = true
        slotGridHeightConstraint = heightConstraint
    }

    // MARK: - Slot Configuration

    /// Slot content types for the configurable slot grid
    enum SlotContent {
        case text(String)           // Simple text button - inserts text
        case icon(String, String)   // SF Symbol + label (display only)
        case action(String, String, Selector)  // icon, label, action (built-in)
        case space                  // Space bar (can span multiple slots)
        case empty                  // Empty/placeholder

        /// Create from user configuration
        static func fromConfig(_ config: SlotConfig) -> SlotContent {
            switch config.type {
            case .text:
                return .text(config.label)
            case .snippet:
                return .text(config.label)  // Snippet shows label, inserts content
            case .action:
                // Built-in actions are handled separately
                return .text(config.label)
            case .space:
                return .space
            case .empty:
                return .empty
            }
        }
    }

    /// User-configurable slot definition (stored in App Group)
    struct SlotConfig: Codable {
        let type: SlotType
        let label: String       // What's shown on button
        let content: String     // What gets inserted (for text/snippet)
        let icon: String?       // SF Symbol name (optional)

        enum SlotType: String, Codable {
            case text       // Simple text insertion
            case snippet    // Multi-line or complex text
            case action     // Built-in action (copy, paste, etc)
            case space      // Space bar
            case empty      // Placeholder
        }

        static func text(_ label: String, inserts content: String? = nil) -> SlotConfig {
            SlotConfig(type: .text, label: label, content: content ?? label, icon: nil)
        }

        static func snippet(_ label: String, content: String, icon: String? = nil) -> SlotConfig {
            SlotConfig(type: .snippet, label: label, content: content, icon: icon)
        }

        static func action(_ label: String, icon: String) -> SlotConfig {
            SlotConfig(type: .action, label: label, content: label, icon: icon)
        }

        static let space = SlotConfig(type: .space, label: "SPACE", content: " ", icon: nil)
        static let empty = SlotConfig(type: .empty, label: "", content: "", icon: nil)
    }

    /// Default slot configurations for SHORTCUTS mode (user-customizable)
    /// Row A: TAB (1), DICTATE (2-3 integrated), ENTER (4)
    /// Row B: ESC (5), slots 6-7, DEL (8)
    /// Row C: slots 9-12
    private static let defaultSlotConfigs: [Int: SlotConfig] = [
        // Row A (1, 4): TAB and ENTER flank DICTATE
        1: .action("TAB", icon: "arrow.right.to.line"),
        // Slots 2-3 are replaced by DICTATE button
        4: .action("ENTER", icon: "return"),
        // Row B (5-8): ESC, utility actions, DEL
        5: .action("ESC", icon: "escape"),
        6: .action("Aa", icon: "textformat"),
        7: .space,
        8: .action("DEL", icon: "delete.left"),
        // Row C (9-12): Quick text shortcuts
        9: .text("Best", inserts: "Best regards,\n"),
        10: .text("@"),
        11: .text("Re:", inserts: "Re: "),
        12: .text("FYI", inserts: "FYI - "),
    ]

    /// Slot configurations for NUMBERS mode
    /// Matches numeric keypad flow:
    /// Top row (slots 9-12): 7 8 9 DEL
    /// Middle row (slots 5-8): 4 5 6 +
    /// Bottom row (slots 1-4): 1 2 3 ENTER
    /// Dictate flanks: 0 (slot 13), . (slot 14)
    private static let numberSlotConfigs: [Int: SlotConfig] = [
        // Row A (1-4): 1 2 3 ENTER
        1: .text("1"),
        2: .text("2"),
        3: .text("3"),
        4: .action("ENTER", icon: "return"),
        // Row B (5-8): 4 5 6 +
        5: .text("4"),
        6: .text("5"),
        7: .text("6"),
        8: .text("+"),
        // Row C (9-12): 7 8 9 DEL
        9: .text("7"),
        10: .text("8"),
        11: .text("9"),
        12: .action("DEL", icon: "delete.left"),
        // Dictate row flanks
        13: .text("0"),
        14: .text("."),
    ]

    /// Slot configurations for SYMBOLS mode
    /// DEL is now in the bottom row with DICTATE
    private static let symbolSlotConfigs: [Int: SlotConfig] = [
        // Row A (1-4): Common punctuation (closest to DICTATE)
        1: .text("."),
        2: .text(","),
        3: .text("?"),
        4: .text("!"),
        // Row B (5-8): Quotes and common
        5: .text("'"),
        6: .text("\""),
        7: .text("-"),
        8: .text("@"),
        // Row C (9-12): Brackets and special
        9: .text("("),
        10: .text(")"),
        11: .text("/"),
        12: .text("&"),
    ]

    /// Get the current host app's bundle ID (the app using the keyboard)
    private var hostAppBundleId: String? {
        // Try to get the host app bundle ID from the parent app
        return parent?.value(forKey: "_hostBundleID") as? String
    }

    /// Load user's custom slot configuration from App Group
    /// Priority: App-specific > User global > Defaults
    private func loadSlotConfig(_ slot: Int) -> SlotConfig {
        // 1. Try app-specific config first
        if let appId = hostAppBundleId,
           let data = bridge.getSlotConfig(slot, forApp: appId),
           let config = try? JSONDecoder().decode(SlotConfig.self, from: data) {
            log.debug("Using app-specific config for slot \(slot) in \(appId)")
            return config
        }

        // 2. Try user's global custom config
        if let data = bridge.getSlotConfig(slot),
           let config = try? JSONDecoder().decode(SlotConfig.self, from: data) {
            return config
        }

        // 3. Fall back to built-in defaults
        return Self.defaultSlotConfigs[slot] ?? .empty
    }

    /// Pre-built app-specific suggestions (shown in Talkie settings UI)
    /// Customize slots 9-12 (top row) per app for quick inputs
    static let appConfigSuggestions: [String: [Int: SlotConfig]] = [
        // Mail app - email-focused quick inputs
        "com.apple.mobilemail": [
            9: .text("Best", inserts: "Best regards,\n"),
            10: .text("Thanks", inserts: "Thank you,\n"),
            11: .text("Re:", inserts: "Re: "),
            12: .text("Fwd:", inserts: "Fwd: "),
        ],
        // Messages - quick reactions and short responses
        "com.apple.MobileSMS": [
            9: .text("👍"),
            10: .text("OMW", inserts: "On my way!"),
            11: .text("BRB", inserts: "Be right back"),
            12: .text("OK"),
        ],
        // Notes - productivity helpers
        "com.apple.mobilenotes": [
            9: .text("TODO", inserts: "TODO: "),
            10: .text("•", inserts: "• "),
            11: .text("[ ]", inserts: "[ ] "),
            12: .text("---", inserts: "\n---\n"),
        ],
        // Slack - slash commands and reactions
        "com.tinyspeck.chatlyio": [
            9: .text("/status"),
            10: .text("/giphy"),
            11: .text("👀"),
            12: .text("✅"),
        ],
    ]

    /// Current slot configuration (1-12)
    /// Slots are numbered left-to-right, BOTTOM-to-TOP:
    /// [9 ][10][11][12]  ← Row C (top) - Quick inputs
    /// [5 ][6 ][7 ][8 ]  ← Row B (middle) - ESC, SPACE, 123, #$&
    /// [1 ][2 ][3 ][4 ]  ← Row A (bottom) - TAB, COPY, PASTE, ENTER
    /// [    DICTATE    ]
    private func getSlotContent(_ slot: Int) -> SlotContent {
        let config = getSlotConfigForCurrentMode(slot)

        // Built-in actions need special handling (selectors)
        if config.type == .action {
            // Map action labels to their handlers
            switch config.label {
            case "TAB": return .action("arrow.right.to.line", "TAB", #selector(tabTapped))
            case "COPY": return .action("doc.on.doc", "COPY", #selector(copyTapped))
            case "PASTE": return .action("doc.on.clipboard", "PASTE", #selector(pasteTapped))
            case "ENTER": return .action("return", "ENTER", #selector(enterTapped))
            case "DEL": return .action("delete.left", "DEL", #selector(deleteTapped))
            case "ESC": return .action("escape", "ESC", #selector(escapeTapped))
            case "SELECT": return .action("selection.pin.in.out", "SELECT", #selector(selectWordTapped))
            case "Aa": return .action("textformat", "Aa", #selector(capitalizeTapped))
            case "PUNC": return .action("circle.fill", "PUNC", #selector(punctTapped))
            case ".": return .action("circle.fill", ".", #selector(punctTapped))
            case "MODE", "123", "#$&", "ABC":
                // Dynamic mode button - shows next mode, cycles on tap
                return .action(nextModeIcon, nextModeLabel, #selector(modeCycleTapped))
            case "VOICE":
                // Voice emoji search - press and hold to search
                // We return a special marker, actual gesture is added in configureSlotButton
                return .action("magnifyingglass", "SRCH", #selector(voiceEmojiTapped))
            default:
                // Unknown action - treat as text
                return .text(config.label)
            }
        }

        // Space bar
        if config.type == .space {
            return .action("space", "SPACE", #selector(spaceTapped))
        }

        // Customizable text/snippet slots
        return .text(config.label)
    }

    /// Get slot config based on current keyboard mode
    /// Checks for user customizations from App Group first, then falls back to built-in defaults
    private func getSlotConfigForCurrentMode(_ slot: Int) -> SlotConfig {
        // Check for user's custom config for this mode+slot first
        if let customData = bridge.getSlotConfig(slot, forMode: currentMode.id),
           let customConfig = try? JSONDecoder().decode(TalkieMobileKit.SlotConfig.self, from: customData) {
            // Convert TalkieMobileKit.SlotConfig to local SlotConfig
            return convertToLocalSlotConfig(customConfig)
        }

        // Fall back to built-in mode default
        let tkConfig = currentMode.config(for: slot)
        return convertToLocalSlotConfig(tkConfig)
    }

    /// Convert TalkieMobileKit.SlotConfig to local KeyboardViewController.SlotConfig
    private func convertToLocalSlotConfig(_ tkConfig: TalkieMobileKit.SlotConfig) -> SlotConfig {
        switch tkConfig.type {
        case .text:
            return .text(tkConfig.label, inserts: tkConfig.content)
        case .snippet:
            return .snippet(tkConfig.label, content: tkConfig.content, icon: tkConfig.icon)
        case .action:
            return .action(tkConfig.label, icon: tkConfig.icon ?? "questionmark")
        case .space:
            return .space
        case .empty:
            return .empty
        }
    }

    /// Handle tap on customizable slot (inserts configured content)
    @objc private func customSlotTapped(_ sender: UIButton) {
        guard let slot = sender.tag as Int?,
              slot >= 1 && slot <= 14 else { return }

        let config = getSlotConfigForCurrentMode(slot)
        log.debug("Custom slot \(slot) tapped", detail: config.label)

        // Insert the configured content
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText(config.content)
        updateDebugView()
    }

    // MARK: - LED Display Bar

    private weak var ledDisplayBar: UIView?
    private weak var modeShortcutContainer: UIView?
    private weak var cursorNavigator: UIView?
    private weak var statusPillView: UIView?
    private weak var selectionStatusOverlayView: UIView?
    private weak var selectionStatusOverlayLabel: UILabel?
    private var selectionStatusOverlayPinned = false
    private weak var statusActionOverlayView: UIView?
    private weak var statusActionOverlayLabel: UILabel?
    private weak var statusActionOverlayStateLabel: UILabel?
    private weak var statusActionPreviewLabel: UILabel?
    private var isActionPanelInSmartMenu = false
    private weak var cursorPadOverlay: UIView?
    private weak var cursorPadThumb: UIView?
    private weak var modeKnob: UIView?
    private var cursorPadDirection: CursorPadDirection = .none
    private var cursorPadRepeatTimer: Timer?
    private var cursorPadDragOrigin: CGPoint?
    private var cursorPadHasCalibratedCenter = false
    private var cursorPadWasOutsideZone = false
    private var cursorPadRepeatInterval: TimeInterval = 0.12
    private var cursorPadSpeedLevel: Int = 0
    private var cursorPadStepCounter: Int = 0
    private var modeSegments: [String: UIButton] = [:]  // mode.id -> segment button

    private enum CursorPadDirection {
        case none
        case left
        case right
        case up
        case down
    }

    /// Create the LED display bar at top — sits directly on the matte surface
    private func createLEDDisplayBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = .clear

        let statusZone = UIView()
        statusZone.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusZone)

        let utilityZone = UIView()
        utilityZone.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(utilityZone)

        let modeZone = UIView()
        modeZone.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(modeZone)

        // Utility cluster: cursor navigator.
        let navigator = createCursorNavigator()
        utilityZone.addSubview(navigator)

        // Dedicated mode picker zone with all modes visible.
        let modePicker = createModeShortcutControl()
        modeZone.addSubview(modePicker)

        // Left status area (persistent reserved zone).
        let statusPill = UIView()
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        statusPill.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.0, alpha: 0.55)
                : UIColor(white: 1.0, alpha: 0.92)
        }
        statusPill.layer.cornerRadius = 15
        statusPill.layer.cornerCurve = .continuous
        statusPill.layer.borderWidth = 0.85
        statusPill.layer.borderColor = Design.keyBorder.cgColor
        statusPill.isUserInteractionEnabled = true
        statusPill.accessibilityLabel = "Talkie Status"
        statusPill.accessibilityHint = "Double tap to open Talkie."
        statusZone.addSubview(statusPill)

        let statusDoubleTap = UITapGestureRecognizer(target: self, action: #selector(statusPillDoubleTapped))
        statusDoubleTap.numberOfTapsRequired = 2
        statusPill.addGestureRecognizer(statusDoubleTap)

        let statusLongPress = UILongPressGestureRecognizer(target: self, action: #selector(statusPillLongPressed(_:)))
        statusLongPress.minimumPressDuration = 0.35
        statusLongPress.allowableMovement = 28
        statusPill.addGestureRecognizer(statusLongPress)

        let status = UILabel()
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        status.textAlignment = .left
        status.textColor = Design.textSecondary
        status.alpha = 0
        status.numberOfLines = 1
        statusPill.addSubview(status)

        self.statusLabel = status
        self.statusMessage = ""
        self.statusPillView = statusPill
        let statusPillHeight = statusPill.heightAnchor.constraint(equalToConstant: 34)

        NSLayoutConstraint.activate([
            statusZone.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 2),
            statusZone.topAnchor.constraint(equalTo: bar.topAnchor),
            statusZone.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            utilityZone.leadingAnchor.constraint(equalTo: statusZone.trailingAnchor, constant: 2),
            utilityZone.topAnchor.constraint(equalTo: bar.topAnchor),
            utilityZone.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            modeZone.leadingAnchor.constraint(equalTo: utilityZone.trailingAnchor, constant: 2),
            modeZone.topAnchor.constraint(equalTo: bar.topAnchor),
            modeZone.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            modeZone.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -2),

            // Symmetric side zones keep the joystick as the visual center piece.
            statusZone.widthAnchor.constraint(equalTo: utilityZone.widthAnchor, multiplier: 2.35),
            modeZone.widthAnchor.constraint(equalTo: utilityZone.widthAnchor, multiplier: 2.35),

            navigator.centerXAnchor.constraint(equalTo: utilityZone.centerXAnchor),
            navigator.centerYAnchor.constraint(equalTo: utilityZone.centerYAnchor),
            navigator.widthAnchor.constraint(equalToConstant: 40),
            navigator.heightAnchor.constraint(equalToConstant: 40),

            modePicker.leadingAnchor.constraint(equalTo: modeZone.leadingAnchor),
            modePicker.trailingAnchor.constraint(equalTo: modeZone.trailingAnchor),
            modePicker.centerYAnchor.constraint(equalTo: modeZone.centerYAnchor),
            modePicker.heightAnchor.constraint(equalToConstant: 36),

            statusPill.leadingAnchor.constraint(equalTo: statusZone.leadingAnchor),
            statusPill.trailingAnchor.constraint(equalTo: statusZone.trailingAnchor),
            statusPill.centerYAnchor.constraint(equalTo: statusZone.centerYAnchor),
            statusPillHeight,

            status.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 8),
            status.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -7),
            status.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 2),
            status.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -4)
        ])

        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        clearStatusMessage()

        self.ledDisplayBar = bar
        self.modeShortcutContainer = modePicker
        self.cursorNavigator = navigator
        return bar
    }

    @objc private func statusPillDoubleTapped() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        showStatus("Opening Talkie...")
        if let url = URL(string: "talkie://keyboard") {
            openURL(url)
        }
    }

    @objc private func statusPillLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        // Stable "all-text action mode": no voice-command capture in this path.
        isVoiceCommandMode = false
        pendingVoiceCommandStart = false
        activeCaptureMode = .dictation
        isActionPanelInSmartMenu = false
        selectAllText()
        presentStatusActionOverlay(animated: true)
    }

    private func createModeShortcutControl() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 15
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 0.85
        container.layer.borderColor = Design.keyBorder.cgColor
        container.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.07)
                : UIColor(white: 1.0, alpha: 0.78)
        }
        container.accessibilityLabel = "Keyboard Mode Picker"
        container.accessibilityHint = "Tap a mode to switch keyboard layout."

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 2
        container.addSubview(stack)

        modeSegments.removeAll()
        for mode in keyboardConfig.orderedModes {
            let segment = createModeSegment(for: mode)
            stack.addArrangedSubview(segment)
            modeSegments[mode.id] = segment
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])

        updateModeShortcutSegments(animated: false)
        return container
    }

    private func updateModeShortcutSegments(animated: Bool = true) {
        guard !modeSegments.isEmpty else { return }

        let activeSelectionColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.96)
                : UIColor(white: 0.08, alpha: 0.92)
        }
        let inactiveLabel = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.64)
                : UIColor(white: 0.12, alpha: 0.56)
        }

        for mode in keyboardConfig.orderedModes {
            guard let segment = modeSegments[mode.id] else { continue }
            guard
                let label = segment.viewWithTag(100) as? UILabel,
                let icon = segment.viewWithTag(102) as? UIImageView
            else { continue }

            let isActive = (mode.id == currentMode.id)
            let applyState = {
                segment.backgroundColor = .clear
                segment.layer.borderWidth = 0
                segment.layer.borderColor = nil
                segment.alpha = isActive ? 1.0 : 0.88
                segment.transform = .identity
                let hasIcon = icon.image != nil
                icon.tintColor = isActive ? activeSelectionColor : Design.textSecondary
                icon.alpha = isActive ? 1.0 : 0.74
                label.isHidden = hasIcon
                label.alpha = isActive ? 1.0 : 0.78
                label.textColor = isActive ? activeSelectionColor : inactiveLabel
            }

            if animated {
                UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: applyState)
            } else {
                applyState()
            }
        }
    }

    private func compactModeLabel(for mode: TalkieMobileKit.KeyboardMode) -> String {
        switch mode.id {
        case "abc":
            return "ABC"
        case "fn", "shortcuts":
            return "SC"
        case "numbers":
            return "123"
        case "symbols":
            return "#+="
        case "emoji":
            return ":-)"
        default:
            return String(mode.name.prefix(3)).uppercased()
        }
    }

    private func modeShortcutSymbolImage(for mode: TalkieMobileKit.KeyboardMode) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let names: [String] = {
            switch mode.id {
            case "abc":
                return ["textformat.abc", "keyboard"]
            case "fn", "shortcuts":
                return ["wand.and.stars", "sparkles", "function"]
            case "numbers":
                return ["number", "textformat.123"]
            case "symbols":
                return ["textformat.123", "at"]
            case "emoji":
                return ["face.smiling"]
            default:
                return [mode.icon]
            }
        }()

        for name in names {
            if let image = UIImage(systemName: name, withConfiguration: config) {
                return image
            }
        }
        return nil
    }

    @objc private func modeSegmentTapped(_ sender: UIButton) {
        guard let modeId = sender.accessibilityIdentifier else { return }
        lightImpact.impactOccurred()
        lightImpact.prepare()
        activateMode(modeId: modeId)
    }

    private func activateMode(modeId: String) {
        guard keyboardConfig.modeOrder.contains(modeId) else { return }
        guard keyboardConfig.activeModeId != modeId else { return }

        keyboardConfig.activeModeId = modeId
        selectedCategory = ModeCategory.category(for: modeId)
        persistActiveModeSelection()
        showModeTransition(to: modeId == "emoji" ? "Emoji" : getModeLabel(for: currentMode))
        updateGridForMode()
        updateModeKnobSelection()
    }

    private func createCursorNavigator() -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.95
        button.layer.borderColor = Design.keyBorder.cgColor
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.90)
        }
        button.tintColor = Design.textPrimary
        let joystickSymbol = UIImage(systemName: "dpad")
            ?? UIImage(systemName: "dpad.fill")
            ?? UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right.circle")
            ?? UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right.circle.fill")
            ?? UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold, scale: .medium),
            forImageIn: .normal
        )
        button.setImage(joystickSymbol, for: .normal)
        button.accessibilityLabel = "Cursor Joystick"
        button.accessibilityHint = "Long press and drag to move cursor by character or by word."
        button.addTarget(self, action: #selector(cursorNavigatorTapped), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(cursorNavigatorLongPressed(_:)))
        longPress.minimumPressDuration = 0.2
        longPress.allowableMovement = 180
        button.addGestureRecognizer(longPress)

        return button
    }

    @objc private func cursorNavigatorTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        showStatus("Hold + drag joystick")
    }

    @objc private func cursorNavigatorLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        let touchPoint = gesture.location(in: view)

        switch gesture.state {
        case .began:
            mediumImpact.impactOccurred()
            mediumImpact.prepare()
            presentCursorPadOverlay(anchor: button, initialTouchPoint: touchPoint)
        case .changed:
            updateCursorPad(with: touchPoint)
        case .cancelled, .ended, .failed:
            dismissCursorPadOverlay()
        default:
            break
        }
    }

    private func presentCursorPadOverlay(anchor: UIButton, initialTouchPoint: CGPoint) {
        dismissCursorPadOverlay()

        let diameter: CGFloat = 152
        let overlay = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.08, alpha: 0.94)
                : UIColor(white: 0.96, alpha: 0.96)
        }
        overlay.layer.cornerRadius = diameter / 2
        overlay.layer.cornerCurve = .continuous
        overlay.layer.borderWidth = 0.95
        overlay.layer.borderColor = Design.keyBorder.cgColor
        overlay.layer.shadowColor = UIColor.black.cgColor
        overlay.layer.shadowOffset = .zero
        overlay.layer.shadowRadius = 12
        overlay.layer.shadowOpacity = 0.18

        let cross = CAShapeLayer()
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let crossRadius: CGFloat = 44
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x - crossRadius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + crossRadius, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - crossRadius))
        path.addLine(to: CGPoint(x: center.x, y: center.y + crossRadius))
        cross.path = path.cgPath
        cross.strokeColor = Design.keyBorder.cgColor
        cross.lineWidth = 1.2
        overlay.layer.addSublayer(cross)

        let iconInset: CGFloat = 24
        let iconSpecs: [(String, CGPoint)] = [
            ("arrow.up", CGPoint(x: center.x, y: iconInset)),
            ("arrow.down", CGPoint(x: center.x, y: diameter - iconInset)),
            ("chevron.left", CGPoint(x: iconInset, y: center.y)),
            ("chevron.right", CGPoint(x: diameter - iconInset, y: center.y))
        ]
        for (symbol, point) in iconSpecs {
            let imageView = UIImageView(image: UIImage(systemName: symbol))
            imageView.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
            imageView.center = point
            imageView.tintColor = Design.textSecondary
            imageView.contentMode = .scaleAspectFit
            overlay.addSubview(imageView)
        }

        let thumb = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        thumb.center = center
        thumb.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.22)
                : UIColor(white: 1.0, alpha: 0.88)
        }
        thumb.layer.cornerRadius = 16
        thumb.layer.cornerCurve = .continuous
        thumb.layer.borderWidth = 0.95
        thumb.layer.borderColor = Design.keyBorderPressed.cgColor
        overlay.addSubview(thumb)

        view.addSubview(overlay)

        let anchorFrame = anchor.convert(anchor.bounds, to: view)
        let homeCenter = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        let margin = diameter / 2 + 4
        let targetCenter = CGPoint(
            x: min(max(initialTouchPoint.x, margin), view.bounds.width - margin),
            y: min(max(initialTouchPoint.y + 12, margin), view.bounds.height - margin)
        )

        overlay.center = homeCenter
        overlay.alpha = 0
        overlay.transform = CGAffineTransform(scaleX: 0.36, y: 0.36)

        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            overlay.alpha = 1
            overlay.transform = .identity
            overlay.center = targetCenter
        }

        // Keep first movement neutral so a press does not auto-trigger a direction.
        cursorPadDragOrigin = initialTouchPoint
        cursorPadWasOutsideZone = false
        cursorPadRepeatInterval = 0.12
        cursorPadSpeedLevel = 0
        cursorPadStepCounter = 0
        cursorPadHasCalibratedCenter = false
        cursorPadOverlay = overlay
        cursorPadThumb = thumb
        cursorPadDirection = .none
        showStatus("Center to start")
    }

    private func dismissCursorPadOverlay() {
        cursorPadDragOrigin = nil
        cursorPadWasOutsideZone = false
        cursorPadDirection = .none
        cursorPadRepeatInterval = 0.12
        cursorPadSpeedLevel = 0
        cursorPadStepCounter = 0
        cursorPadHasCalibratedCenter = false
        stopCursorPadRepeat()

        guard let overlay = cursorPadOverlay else { return }
        cursorPadOverlay = nil
        cursorPadThumb = nil

        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseIn]) {
            overlay.alpha = 0
            overlay.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        } completion: { _ in
            overlay.removeFromSuperview()
        }
    }

    private func updateCursorPad(with touchPoint: CGPoint) {
        guard let overlay = cursorPadOverlay else { return }
        let overlayCenter = overlay.center
        let fallbackOrigin = overlayCenter
        var origin = cursorPadDragOrigin ?? fallbackOrigin

        let thumbReach = (overlay.bounds.width * 0.5) - ((cursorPadThumb?.bounds.width ?? 32) * 0.5)
        let distanceFromCenter = hypot(touchPoint.x - overlayCenter.x, touchPoint.y - overlayCenter.y)
        let outsideZone = distanceFromCenter > (thumbReach + 6)

        // If the drag left the joystick area and then returns, re-anchor to the
        // circle center so thumb position matches the current finger location.
        if cursorPadWasOutsideZone && !outsideZone {
            origin = overlayCenter
            cursorPadDragOrigin = overlayCenter
        }
        cursorPadWasOutsideZone = outsideZone

        let centerDistance = hypot(touchPoint.x - overlayCenter.x, touchPoint.y - overlayCenter.y)
        if !cursorPadHasCalibratedCenter {
            let calibrationRadius: CGFloat = 14
            if centerDistance <= calibrationRadius {
                cursorPadHasCalibratedCenter = true
                showStatus("Calibrated")
                lightImpact.impactOccurred()
                lightImpact.prepare()
            } else {
                setCursorPadDirection(.none)
                guard let thumb = cursorPadThumb else { return }
                thumb.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
                return
            }
        }

        let dx = touchPoint.x - origin.x
        let dy = touchPoint.y - origin.y
        let distance = hypot(dx, dy)
        updateCursorPadRepeatRate(distance: distance)
        let direction = cursorPadDirection(for: CGVector(dx: dx, dy: dy))
        setCursorPadDirection(direction)

        guard let thumb = cursorPadThumb else { return }
        let maxTravel = (overlay.bounds.width * 0.5) - (thumb.bounds.width * 0.5)
        let scale = (distance > 0) ? min(maxTravel / distance, 1) : 0
        let offset = CGPoint(x: dx * scale, y: dy * scale)
        thumb.center = CGPoint(
            x: overlay.bounds.midX + offset.x,
            y: overlay.bounds.midY + offset.y
        )
    }

    private func cursorPadDirection(for vector: CGVector) -> CursorPadDirection {
        let deadZone: CGFloat = 8
        guard hypot(vector.dx, vector.dy) > deadZone else { return .none }

        if abs(vector.dx) > abs(vector.dy) {
            return vector.dx < 0 ? .left : .right
        }
        return vector.dy < 0 ? .up : .down
    }

    private func setCursorPadDirection(_ direction: CursorPadDirection) {
        guard direction != cursorPadDirection else { return }
        cursorPadDirection = direction
        cursorPadStepCounter = 0

        guard direction != .none else {
            stopCursorPadRepeat()
            return
        }

        if let status = cursorPadStatus(for: direction) {
            showStatus(status)
        }
        lightImpact.impactOccurred()
        lightImpact.prepare()
        performCursorPadStep(direction)
        startCursorPadRepeat()
    }

    private func startCursorPadRepeat() {
        guard cursorPadRepeatTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: cursorPadRepeatInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.cursorPadDirection != .none else { return }
            self.performCursorPadStep(self.cursorPadDirection)
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorPadRepeatTimer = timer
    }

    private func restartCursorPadRepeat() {
        stopCursorPadRepeat()
        startCursorPadRepeat()
    }

    private func updateCursorPadRepeatRate(distance: CGFloat) {
        let nextInterval = cursorPadInterval(forDistance: distance)
        let nextSpeedLevel = cursorPadSpeedLevel(forInterval: nextInterval)
        let levelChanged = nextSpeedLevel != cursorPadSpeedLevel

        cursorPadRepeatInterval = nextInterval
        cursorPadSpeedLevel = nextSpeedLevel

        if levelChanged && cursorPadDirection != .none {
            lightImpact.impactOccurred()
            lightImpact.prepare()
            if nextSpeedLevel == 0 {
                showStatus("Precision mode")
            } else if nextSpeedLevel >= 3 {
                showStatus("Go mode")
            }
        }

        if levelChanged && cursorPadDirection != .none && cursorPadRepeatTimer != nil {
            restartCursorPadRepeat()
        }
    }

    private func cursorPadInterval(forDistance distance: CGFloat) -> TimeInterval {
        let deadZone: CGFloat = 20
        let maxDistance: CGFloat = 140
        let usableDistance = max(0, min(distance, maxDistance) - deadZone)
        let normalized = usableDistance / (maxDistance - deadZone)
        // Keep center control stable. Acceleration ramps mostly near the far edge.
        let eased = pow(normalized, 3.1)
        let slowest: TimeInterval = 0.19
        let fastest: TimeInterval = 0.032
        return slowest - (slowest - fastest) * Double(eased)
    }

    private func cursorPadSpeedLevel(forInterval interval: TimeInterval) -> Int {
        if interval <= 0.045 { return 3 }
        if interval <= 0.080 { return 2 }
        if interval <= 0.120 { return 1 }
        return 0
    }

    private func stopCursorPadRepeat() {
        cursorPadRepeatTimer?.invalidate()
        cursorPadRepeatTimer = nil
    }

    private func performCursorPadStep(_ direction: CursorPadDirection) {
        cursorPadStepCounter += 1

        if cursorPadSpeedLevel == 0 {
            // Deliberate close-control mode with tactile tick on each step.
            lightImpact.impactOccurred()
            lightImpact.prepare()
        }

        switch direction {
        case .left:
            if cursorPadSpeedLevel >= 3 {
                moveCursorByWord(direction: -1)
            } else {
                let charSteps = cursorPadSpeedLevel >= 2 ? 2 : 1
                textDocumentProxy.adjustTextPosition(byCharacterOffset: -charSteps)
            }
        case .right:
            if cursorPadSpeedLevel >= 3 {
                moveCursorByWord(direction: 1)
            } else {
                let charSteps = cursorPadSpeedLevel >= 2 ? 2 : 1
                textDocumentProxy.adjustTextPosition(byCharacterOffset: charSteps)
            }
        case .up:
            let wordSteps = cursorPadSpeedLevel >= 3 ? 2 : 1
            for _ in 0..<wordSteps {
                moveCursorByWord(direction: -1)
            }
        case .down:
            let wordSteps = cursorPadSpeedLevel >= 3 ? 2 : 1
            for _ in 0..<wordSteps {
                moveCursorByWord(direction: 1)
            }
        case .none:
            break
        }
    }

    private func cursorPadStatus(for direction: CursorPadDirection) -> String? {
        switch direction {
        case .left:
            return "Cursor ←"
        case .right:
            return "Cursor →"
        case .up:
            return "Word ←"
        case .down:
            return "Word →"
        case .none:
            return nil
        }
    }

    private func moveCursorByWord(direction: Int) {
        if direction < 0 {
            guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return }
            let chars = Array(before)
            var index = chars.count - 1
            var offset = 0

            while index >= 0 && (chars[index].isWhitespace || chars[index].isPunctuation) {
                index -= 1
                offset += 1
            }
            while index >= 0 && !(chars[index].isWhitespace || chars[index].isPunctuation) {
                index -= 1
                offset += 1
            }

            if offset > 0 {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: -offset)
            }
            return
        }

        let after = textDocumentProxy.documentContextAfterInput ?? ""
        guard !after.isEmpty else { return }
        let chars = Array(after)
        var index = 0
        var offset = 0

        while index < chars.count && (chars[index].isWhitespace || chars[index].isPunctuation) {
            index += 1
            offset += 1
        }
        while index < chars.count && !(chars[index].isWhitespace || chars[index].isPunctuation) {
            index += 1
            offset += 1
        }

        if offset > 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }
    }

    // MARK: - Mode Category Tiles

    /// Mode categories for the tile selector
    private enum ModeCategory: String, CaseIterable {
        case abc = "ABC"       // Full QWERTY keyboard
        case fn = "Shortcuts"  // Keyboard shortcuts and actions
        case numbers = "123"
        case symbols = "#+="
        case emoji = "emoji"

        var displayLabel: String {
            switch self {
            case .abc: return "ABC"
            case .fn: return "Shortcuts"
            case .numbers: return "123"
            case .symbols: return "#+="
            case .emoji: return ""  // Uses icon
            }
        }

        var modeIds: [String] {
            switch self {
            case .abc: return ["abc"]
            case .fn: return ["fn", "shortcuts"]
            case .numbers: return ["numbers"]
            case .symbols: return ["symbols"]
            case .emoji: return ["emoji"]
            }
        }

        var primaryModeId: String {
            modeIds.first ?? "abc"
        }

        static func category(for modeId: String) -> ModeCategory {
            for cat in allCases {
                if cat.modeIds.contains(modeId) {
                    return cat
                }
            }
            return .abc
        }
    }

    private var selectedCategory: ModeCategory = .fn
    private var categoryTiles: [ModeCategory: UIButton] = [:]

    private func categorySymbolImage(for category: ModeCategory) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let symbolNames: [String] = {
            switch category {
            case .abc:
                return ["textformat.abc", "character.textbox"]
            case .fn:
                return ["wand.and.stars", "sparkles"]
            case .numbers:
                return []
            case .symbols:
                return []
            case .emoji:
                return ["face.smiling"]
            }
        }()

        for symbolName in symbolNames {
            if let image = UIImage(systemName: symbolName, withConfiguration: config) {
                return image
            }
        }

        return nil
    }

    private func cancelModeKnobFade() {
        modeKnobFadeWorkItem?.cancel()
        modeKnobFadeWorkItem = nil
    }

    private func setModeKnobExpanded(_ expanded: Bool, animated: Bool) {
        guard modeKnob != nil else { return }
        isModeKnobExpanded = expanded

        let applyVisibility = {
            for (category, tile) in self.categoryTiles {
                tile.isHidden = false
                tile.alpha = expanded ? 1.0 : (category == self.selectedCategory ? 1.0 : 0.82)
            }
            self.modeKnob?.superview?.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: applyVisibility)
        } else {
            applyVisibility()
        }

        updateModeKnobSelectionPill(animated: false)
    }

    private func wakeModeKnob(animated: Bool = true) {
        cancelModeKnobFade()
        guard let knob = modeKnob else { return }
        setModeKnobExpanded(true, animated: animated)

        let applyVisible = {
            knob.alpha = self.modeKnobActiveAlpha
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: applyVisible)
        } else {
            applyVisible()
        }
    }

    private func scheduleModeKnobFade() {
        cancelModeKnobFade()
        guard modeKnob != nil, !isMinimalLayoutActive else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let knob = self.modeKnob, !self.isMinimalLayoutActive else { return }
            // Keep geometry stable in idle; only settle opacity.
            self.isModeKnobExpanded = false
            self.updateCategoryTileSelection(animated: true)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
                knob.alpha = self.modeKnobIdleAlpha
            }
        }
        modeKnobFadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + modeKnobIdleDelay, execute: work)
    }

    private func refreshModeKnobAttention(animated: Bool = true) {
        wakeModeKnob(animated: animated)
        scheduleModeKnobFade()
    }

    private func updateModeKnobSelectionPill(animated: Bool) {
        guard
            let knob = modeKnob,
            let pill = modeKnobSelectionPill,
            let selectedTile = categoryTiles[selectedCategory]
        else { return }

        modeKnobSelectionLeadingConstraint?.isActive = false
        modeKnobSelectionTrailingConstraint?.isActive = false

        let leading = pill.leadingAnchor.constraint(equalTo: selectedTile.leadingAnchor)
        let trailing = pill.trailingAnchor.constraint(equalTo: selectedTile.trailingAnchor)
        modeKnobSelectionLeadingConstraint = leading
        modeKnobSelectionTrailingConstraint = trailing
        NSLayoutConstraint.activate([leading, trailing])

        let updates = {
            knob.layoutIfNeeded()
        }

        if animated {
            pill.transform = CGAffineTransform(scaleX: 0.94, y: 0.92)
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.16,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                animations: {
                    updates()
                    pill.transform = .identity
                }
            ) { _ in
                self.animateModeKnobSelectionSweep(on: pill)
            }
        } else {
            pill.transform = .identity
            updates()
        }
    }

    private func animateModeKnobSelectionSweep(on pill: UIView) {
        let width = max(pill.bounds.width, 1)
        let height = max(pill.bounds.height, 1)

        let sweep = CAGradientLayer()
        sweep.frame = CGRect(x: -width, y: 0, width: width * 2, height: height)
        sweep.cornerRadius = pill.layer.cornerRadius
        sweep.colors = [
            UIColor.clear.cgColor,
            UIColor(white: 1.0, alpha: 0.0).cgColor,
            UIColor(white: 1.0, alpha: traitCollection.userInterfaceStyle == .dark ? 0.18 : 0.30).cgColor,
            UIColor(white: 1.0, alpha: 0.0).cgColor,
            UIColor.clear.cgColor
        ]
        sweep.locations = [0.0, 0.33, 0.5, 0.67, 1.0]
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        pill.layer.addSublayer(sweep)

        let travel = CABasicAnimation(keyPath: "transform.translation.x")
        travel.fromValue = -width
        travel.toValue = width
        travel.duration = 0.34
        travel.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            sweep.removeFromSuperlayer()
        }
        sweep.add(travel, forKey: "modeKnobSweep")
        CATransaction.commit()
    }

    /// Create the tile-based mode selector
    private func createModeKnob() -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.layer.cornerRadius = Design.modeKnobCornerRadius
        container.layer.cornerCurve = .continuous
        container.layer.masksToBounds = true
        container.layer.borderWidth = 0.75
        container.layer.borderColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.20)
                : UIColor(white: 1.0, alpha: 0.60)
        }.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alpha = modeKnobActiveAlpha

        let blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blurView)

        let tintView = UIView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.isUserInteractionEnabled = false
        tintView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.10, alpha: 0.30)
                : UIColor(white: 1.0, alpha: 0.20)
        }
        blurView.contentView.addSubview(tintView)

        let topShine = UIView()
        topShine.translatesAutoresizingMaskIntoConstraints = false
        topShine.isUserInteractionEnabled = false
        topShine.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 1.0, alpha: 0.26)
        }
        container.addSubview(topShine)

        let selectionPill = UIView()
        selectionPill.translatesAutoresizingMaskIntoConstraints = false
        selectionPill.isUserInteractionEnabled = false
        selectionPill.layer.cornerRadius = Design.modeTileCornerRadius
        selectionPill.layer.cornerCurve = .continuous
        selectionPill.layer.masksToBounds = true
        selectionPill.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.16)
                : UIColor(white: 1.0, alpha: 0.58)
        }
        selectionPill.layer.borderWidth = 0.5
        selectionPill.layer.borderColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.28)
                : UIColor(white: 1.0, alpha: 0.72)
        }.cgColor

        let selectionShine = UIView()
        selectionShine.translatesAutoresizingMaskIntoConstraints = false
        selectionShine.isUserInteractionEnabled = false
        selectionShine.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.06)
                : UIColor(white: 1.0, alpha: 0.22)
        }
        selectionPill.addSubview(selectionShine)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 1
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        for category in ModeCategory.allCases {
            let tile = createCategoryTile(for: category)
            stack.addArrangedSubview(tile)
            categoryTiles[category] = tile
        }

        container.addSubview(selectionPill)
        container.addSubview(stack)
        container.bringSubviewToFront(stack)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tintView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),

            topShine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topShine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topShine.topAnchor.constraint(equalTo: container.topAnchor),
            topShine.heightAnchor.constraint(equalToConstant: 1),

            selectionPill.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            selectionPill.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),

            selectionShine.leadingAnchor.constraint(equalTo: selectionPill.leadingAnchor),
            selectionShine.trailingAnchor.constraint(equalTo: selectionPill.trailingAnchor),
            selectionShine.topAnchor.constraint(equalTo: selectionPill.topAnchor),
            selectionShine.heightAnchor.constraint(equalToConstant: 1),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1)
        ])
        container.heightAnchor.constraint(equalToConstant: Design.ledBarHeight).isActive = true

        self.modeKnob = container
        self.modeKnobSelectionPill = selectionPill

        // Set initial selection based on current mode
        selectedCategory = ModeCategory.category(for: currentMode.id)
        updateCategoryTileSelection(animated: false)
        setModeKnobExpanded(true, animated: false)
        scheduleModeKnobFade()

        return container
    }

    /// Create a single category tile button
    private func createCategoryTile(for category: ModeCategory) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = ModeCategory.allCases.firstIndex(of: category) ?? 0

        if let icon = categorySymbolImage(for: category) {
            button.setImage(icon, for: .normal)
            button.setTitle(nil, for: .normal)
        } else {
            button.setTitle(category.displayLabel, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 10, weight: .bold)
        }

        button.tintColor = Design.textSecondary
        button.setTitleColor(Design.textSecondary, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = Design.modeTileCornerRadius
        button.layer.cornerCurve = .continuous

        button.addTarget(self, action: #selector(categoryTileTapped(_:)), for: .touchUpInside)

        // Fixed size for consistent layout
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])

        return button
    }

    @objc private func categoryTileTapped(_ sender: UIButton) {
        refreshModeKnobAttention()
        guard let index = ModeCategory.allCases.firstIndex(where: { ModeCategory.allCases.firstIndex(of: $0) == sender.tag }) else { return }
        let category = ModeCategory.allCases[index]

        lightImpact.impactOccurred()
        lightImpact.prepare()

        // If same category, cycle through its modes (for QWERTY which has multiple)
        if category == selectedCategory && category.modeIds.count > 1 {
            // Find next mode within this category
            if let currentIndex = category.modeIds.firstIndex(of: currentMode.id) {
                let nextIndex = (currentIndex + 1) % category.modeIds.count
                let nextModeId = category.modeIds[nextIndex]
                if keyboardConfig.modeOrder.contains(nextModeId) {
                    keyboardConfig.activeModeId = nextModeId
                    persistActiveModeSelection()
                    showModeTransition(to: getModeLabel(for: currentMode))
                    updateGridForMode()
                }
            }
        } else {
            // Switch to new category
            selectedCategory = category
            keyboardConfig.activeModeId = category.primaryModeId
            persistActiveModeSelection()
            showModeTransition(to: category == .emoji ? "Emoji" : category.displayLabel)
            updateGridForMode()
        }

        updateCategoryTileSelection()
        log.info("Category selected: \(category.rawValue), mode: \(currentMode.id)")
    }

    /// Update the visual selection state of category tiles
    private func updateCategoryTileSelection(animated: Bool = true) {
        updateModeKnobSelectionPill(animated: animated)

        let selectedTextColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        }

        for (category, tile) in categoryTiles {
            let isSelected = category == selectedCategory

            let applyState = {
                tile.backgroundColor = .clear
                tile.layer.borderWidth = 0
                tile.layer.shadowOpacity = 0
                tile.layer.shadowRadius = 0
                tile.layer.shadowOffset = .zero
                tile.transform = .identity
                tile.alpha = isSelected ? 1.0 : (self.isModeKnobExpanded ? 0.84 : 0.74)

                // Emoji tile: switch between SF Symbol and actual emoji
                if category == .emoji {
                    if isSelected {
                        tile.setImage(nil, for: .normal)
                        tile.setTitle("😊", for: .normal)
                        tile.titleLabel?.font = .systemFont(ofSize: 12)
                    } else {
                        tile.setImage(self.categorySymbolImage(for: .emoji), for: .normal)
                        tile.setTitle(nil, for: .normal)
                        tile.tintColor = Design.textSecondary
                    }
                } else {
                    tile.tintColor = isSelected ? selectedTextColor : Design.textSecondary
                    tile.setTitleColor(isSelected ? selectedTextColor : Design.textSecondary, for: .normal)
                }
            }

            if animated {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: applyState)
            } else {
                applyState()
            }
        }
    }

    /// Create a single compact mode segment (icon-forward with fallback label).
    private func createModeSegment(for mode: TalkieMobileKit.KeyboardMode) -> UIButton {
        let segment = UIButton(type: .system)
        segment.layer.cornerRadius = 9
        segment.layer.cornerCurve = .continuous
        segment.backgroundColor = .clear
        segment.accessibilityLabel = mode.id == "emoji" ? "Emoji mode" : "\(getModeLabel(for: mode)) mode"
        segment.accessibilityIdentifier = mode.id
        segment.addTarget(self, action: #selector(modeSegmentTapped(_:)), for: .touchUpInside)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

        let iconView = UIImageView(image: modeShortcutSymbolImage(for: mode))
        iconView.tag = 102
        iconView.tintColor = Design.textSecondary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15)
        ])

        // Mode label (active/inactive styling applied in update pass)
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 7, weight: .semibold)
        label.textAlignment = .center
        label.tag = 100
        label.text = compactModeLabel(for: mode)
        label.isHidden = iconView.image != nil

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)

        segment.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: segment.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: segment.trailingAnchor, constant: -2),
            stack.centerXAnchor.constraint(equalTo: segment.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: segment.centerYAnchor)
        ])

        return segment
    }

    /// Update the mode knob to show current mode
    private func updateModeKnobSelection() {
        // Update selected category based on current mode
        selectedCategory = ModeCategory.category(for: currentMode.id)
        updateCategoryTileSelection()
        updateModeShortcutSegments()
        scheduleModeKnobFade()
    }

    // MARK: - UI Factory Methods

    private func createSlotGrid() -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = Design.rowSpacing
        grid.distribution = .fillEqually

        // Row C (top): Slots 9-12 - Quick inputs
        let rowC = createSlotRow(slots: [9, 10, 11, 12])
        grid.addArrangedSubview(rowC)

        // Row B (middle): Slots 5-8
        let rowB = createSlotRow(slots: [5, 6, 7, 8])
        grid.addArrangedSubview(rowB)

        // Row A (bottom): Slots 1-4
        let rowA = createSlotRow(slots: [1, 2, 3, 4])
        grid.addArrangedSubview(rowA)

        return grid
    }

    /// Create slot grid with integrated DICTATE row.
    /// Slot rows are driven by the user-selected grid preset.
    private func createSlotGridWithDictate() -> UIView {
        let container = UIView()

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = Design.rowSpacing
        grid.distribution = .fill  // Rows use their own height constraints
        grid.translatesAutoresizingMaskIntoConstraints = false

        for slots in gridPreset.slotRows {
            grid.addArrangedSubview(createSlotRow(slots: slots))
        }

        // Bottom row: left flank, DICTATE, right flank.
        grid.addArrangedSubview(createDictateRow(forColumnCount: gridPreset.columnCount))

        container.addSubview(grid)

        // Fill container exactly; container itself has fixed content height.
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Design.sidePadding),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Design.sidePadding)
        ])

        return container
    }

    /// Create the bottom row with DICTATE button and two flanking slots.
    private func createDictateRow(forColumnCount columnCount: Int) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Design.gridSpacing
        row.distribution = columnCount >= 4 ? .fill : .fillEqually
        row.alignment = .fill

        // Left flanking slot (slot 13) - config-driven
        let leftBtn = createSlotButton(slot: 13)

        // DICTATE button (spans 2 slots width) - same style as other buttons
        let dictateBtn = createDictateButton()

        // Right flanking slot (slot 14) - config-driven
        let rightBtn = createSlotButton(slot: 14)

        row.addArrangedSubview(leftBtn)
        row.addArrangedSubview(dictateBtn)
        row.addArrangedSubview(rightBtn)

        // 4-column presets use a 2-slot dictate width. 3-column presets keep equal segments.
        if columnCount >= 4 {
            leftBtn.widthAnchor.constraint(equalTo: rightBtn.widthAnchor).isActive = true
            dictateBtn.widthAnchor.constraint(equalTo: leftBtn.widthAnchor, multiplier: 2, constant: Design.gridSpacing).isActive = true
        }

        row.heightAnchor.constraint(equalToConstant: Design.buttonHeight).isActive = true

        return row
    }

    /// Create a button for the bottom row (matches slot button style: icon + label below)
    private func createBottomRowButton(icon: String, label: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = Design.cornerRadius
        applyGridKeyRestingStyle(to: btn)
        btn.addTarget(self, action: action, for: .touchUpInside)
        attachGridKeyPressHandlers(to: btn)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = Design.textPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let labelView = UILabel()
        labelView.text = label
        labelView.font = .systemFont(ofSize: 8, weight: .medium)
        labelView.textColor = Design.textSecondary

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(labelView)

        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])

        return btn
    }

    private func attachGridKeyPressHandlers(to button: UIButton) {
        button.addTarget(self, action: #selector(gridKeyTouchDown(_:)), for: .touchDown)
        button.addTarget(
            self,
            action: #selector(gridKeyTouchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit, .touchDragOutside]
        )
    }

    private func applyGridKeyRestingStyle(to button: UIButton) {
        button.backgroundColor = Design.surfaceDark
        button.layer.borderWidth = 0.45
        button.layer.borderColor = Design.keyBorder.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        button.layer.shadowRadius = 1.2
        button.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.05
    }

    private func gridKeyPressScale(for button: UIButton) -> CGFloat {
        let width = max(button.bounds.width, 1)
        let height = max(button.bounds.height, 1)
        let aspect = width / height
        if aspect >= 1.8 { return 0.988 }   // Wide keys like DICTATE
        if aspect >= 1.3 { return 0.982 }   // Medium-width keys
        return 0.975                         // Standard keys
    }

    @objc private func gridKeyTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.07, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            let scale = self.gridKeyPressScale(for: sender)
            sender.transform = CGAffineTransform(scaleX: scale, y: scale)
            sender.backgroundColor = Design.surfaceLight
            sender.layer.borderColor = Design.keyBorderPressed.cgColor
            sender.layer.shadowOpacity = 0.02
        }
    }

    @objc private func gridKeyTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = .identity
            self.applyGridKeyRestingStyle(to: sender)
        }
    }

    private func resetTransientTouchState(animated: Bool) {
        puncLongPressTimer?.invalidate()
        puncLongPressTimer = nil
        puncDidFireLongPress = false
        dismissPuncOverlay()

        compactKeyboardView?.resetTransientTouchState(animated: animated)
        minimalKeyboardView?.resetTransientTouchState(animated: animated)

        let buttons = Array(slotButtons.values) + [recordButton].compactMap { $0 }
        var seen = Set<ObjectIdentifier>()

        let reset = {
            for button in buttons {
                guard seen.insert(ObjectIdentifier(button)).inserted else { continue }
                button.transform = .identity
                self.applyGridKeyRestingStyle(to: button)
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                animations: reset
            )
        } else {
            UIView.performWithoutAnimation(reset)
        }
    }

    private func createSlotRow(slots: [Int]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Design.gridSpacing
        row.distribution = .fillEqually

        for slot in slots {
            let btn = createSlotButton(slot: slot)
            row.addArrangedSubview(btn)
        }

        row.heightAnchor.constraint(equalToConstant: Design.buttonHeight).isActive = true

        return row
    }


    private func createSlotButton(slot: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.tag = slot
        btn.layer.cornerRadius = Design.cornerRadius
        applyGridKeyRestingStyle(to: btn)
        attachGridKeyPressHandlers(to: btn)

        // Store reference for efficient mode switching
        slotButtons[slot] = btn

        // Configure button content
        configureSlotButton(btn, slot: slot)

        return btn
    }

    /// Configure a slot button's content based on current mode (used for initial setup and mode switching)
    private func configureSlotButton(_ btn: UIButton, slot: Int) {
        let content = getSlotContent(slot)

        // Remove existing content completely
        btn.subviews.forEach { $0.removeFromSuperview() }
        btn.removeTarget(nil, action: nil, for: .allEvents)
        btn.setTitle(nil, for: .normal)
        btn.setAttributedTitle(nil, for: .normal)
        btn.setImage(nil, for: .normal)
        btn.gestureRecognizers?.filter { $0 is UILongPressGestureRecognizer }.forEach {
            btn.removeGestureRecognizer($0)
        }
        applyGridKeyRestingStyle(to: btn)
        attachGridKeyPressHandlers(to: btn)

        switch content {
        case .text(let text):
            // Text slot - use a label subview for reliable styling
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = Design.textPrimary
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            btn.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
            ])

            // Number mode operator key: long-press '+' for quick operator variants.
            if text == "+" {
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(operatorLongPressed(_:)))
                longPress.minimumPressDuration = 0.3
                btn.addGestureRecognizer(longPress)
            }

            btn.addTarget(self, action: #selector(customSlotTapped(_:)), for: .touchUpInside)

        case .icon(let icon, let label), .action(let icon, let label, _):
            if case .action(_, _, let action) = content {
                // PUNC button: custom touch tracking for long-press overlay
                let isPunc = label == "PUNC" || (slot == 8 && action == #selector(punctTapped))
                if isPunc {
                    btn.addTarget(self, action: #selector(puncTouchDown(_:)), for: .touchDown)
                    btn.addTarget(self, action: #selector(puncTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
                } else {
                    btn.addTarget(self, action: action, for: .touchUpInside)
                }

                // Add long-press gesture for SELECT action (slot 13)
                if slot == 13 && label == "SELECT" {
                    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(selectLongPressed(_:)))
                    longPress.minimumPressDuration = 0.4
                    longPress.allowableMovement = 44
                    btn.addGestureRecognizer(longPress)
                    btn.menu = nil
                    btn.showsMenuAsPrimaryAction = false
                }

                // Quirky shortcut: long-press PASTE to force system/universal clipboard paste.
                if label == "PASTE" {
                    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(pasteLongPressed(_:)))
                    longPress.minimumPressDuration = 0.35
                    longPress.allowableMovement = 28
                    btn.addGestureRecognizer(longPress)
                }
            }

            let stack = UIStackView()
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 1
            stack.isUserInteractionEnabled = false
            stack.translatesAutoresizingMaskIntoConstraints = false

            // PUNC uses text characters instead of SF Symbol
            if label == "PUNC" || (slot == 8 && label == ".") {
                let textIcon = UILabel()
                textIcon.text = ".,?!"
                textIcon.font = .systemFont(ofSize: 12, weight: .bold)
                textIcon.textColor = Design.textPrimary
                textIcon.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(textIcon)
            } else {
                let iconView = UIImageView(image: UIImage(systemName: icon))
                iconView.tintColor = Design.textPrimary
                iconView.contentMode = .scaleAspectFit
                iconView.translatesAutoresizingMaskIntoConstraints = false
                iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
                iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
                stack.addArrangedSubview(iconView)
            }

            let labelView = UILabel()
            labelView.text = label
            labelView.font = .systemFont(ofSize: 8, weight: .medium)
            labelView.textColor = Design.textSecondary

            stack.addArrangedSubview(labelView)

            btn.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
            ])

        case .space, .empty:
            break
        }
    }

    /// Update all slot buttons for new keyboard mode (efficient - no view recreation)
    private func updateGridForMode() {
        log.info("Switching to mode: \(currentMode.name)")

        // Check if switching to/from ABC mode
        if currentMode.id == "abc" {
            showCompactKeyboard()
        } else {
            hideCompactKeyboard()
            refreshGridPresetIfNeeded()

            // Update all slot buttons (1-12 grid + 13-14 dictate row flanking)
            for slot in 1...14 {
                guard let btn = slotButtons[slot] else { continue }
                configureSlotButton(btn, slot: slot)
            }
        }

        // Update mode knob visual
        updateModeKnobSelection()
    }

    // MARK: - Compact Keyboard (ABC Mode)

    private func showCompactKeyboard() {
        guard compactKeyboardView == nil else { return }
        isABCModeActive = true

        // Height is now consistent across all modes - no change needed

        let keyboard = CompactKeyboardView()

        keyboard.onKeyTapped = { [weak self] key in
            self?.insertCompactText(key)
            self?.updateDebugView()
        }

        keyboard.onDeleteTapped = { [weak self] in
            if self?.consumeSelectionIfNeeded() != true {
                self?.textDocumentProxy.deleteBackward()
            }
            self?.updateDebugView()
        }

        keyboard.onSpaceTapped = { [weak self] in
            self?.insertCompactText(" ")
            self?.updateDebugView()
        }

        keyboard.onReturnTapped = { [weak self] in
            self?.insertCompactText("\n")
            self?.updateDebugView()
        }

        keyboard.onVoiceTapped = { [weak self] in
            self?.recordTapped()
        }

        keyboard.onEmojiTapped = { [weak self] in
            guard let self else { return }
            self.selectedCategory = .emoji
            self.keyboardConfig.activeModeId = "emoji"
            self.persistActiveModeSelection()
            self.updateGridForMode()
            self.updateCategoryTileSelection()
        }

        keyboard.onShiftDebugRequested = { [weak self] in
            self?.copyDebugSnapshotFromShift()
        }

        keyboard.onDismiss = { [weak self] in
            self?.compactKeyboardView = nil
            self?.isABCModeActive = false
        }

        // Position compact keyboard in the exact same frame as slot grid to avoid vertical jumps.
        if let surface = keyboardSurfaceView, let slotGrid = slotGridContainer {
            keyboard.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(keyboard)

            NSLayoutConstraint.activate([
                keyboard.topAnchor.constraint(equalTo: slotGrid.topAnchor),
                keyboard.leadingAnchor.constraint(equalTo: slotGrid.leadingAnchor),
                keyboard.trailingAnchor.constraint(equalTo: slotGrid.trailingAnchor),
                keyboard.bottomAnchor.constraint(equalTo: slotGrid.bottomAnchor)
            ])

            // Keep slot grid in layout (hidden) to preserve the frame geometry.
            slotGridContainer?.alpha = 0
        } else if let surface = keyboardSurfaceView {
            keyboard.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(keyboard)

            NSLayoutConstraint.activate([
                keyboard.topAnchor.constraint(
                    equalTo: surface.topAnchor,
                    constant: keyboardSurfaceTopPadding + Design.ledBarHeight + mainStack.spacing
                ),
                keyboard.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
                keyboard.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
                keyboard.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
            ])

            slotGridContainer?.alpha = 0
        }

        compactKeyboardView = keyboard
        synchronizeCompactSpaceAlignmentReference()
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeCompactSpaceAlignmentReference()
        }

        // Sync dictation state immediately — don't wait for deferred loadState()
        // Without this, the first spacebar tap after returning from Talkie app
        // is treated as a regular space instead of a stop command.
        let phase = currentPhase
        if phase == .recording {
            keyboard.setDictationState(.recording)
        } else if [.stopping, .transcribing, .arming].contains(phase) {
            keyboard.setDictationState(.processing)
        }

        // Recover session ID if we lost it during extension reload
        if currentSessionId == nil {
            currentSessionId = sharedStore.activeSessionId
        }

        log.info("ABC compact keyboard shown (phase: \(phase))")
    }

    private func hideCompactKeyboard() {
        guard isABCModeActive else { return }
        isABCModeActive = false

        // Stop any active dictation when leaving ABC mode
        let phase = currentPhase
        if [.recording, .stopping, .arming].contains(phase) {
            log.info("Auto-stopping dictation on ABC mode exit (phase: \(phase))")
            recordTapped()
        }

        compactKeyboardView?.removeFromSuperview()
        compactKeyboardView = nil

        // Restore slot grid visibility
        slotGridContainer?.alpha = 1
        compactKeyboardView?.setSpaceAlignmentReference(frame: nil, showGuide: false)

        log.info("ABC compact keyboard hidden")
    }

    private func synchronizeCompactSpaceAlignmentReference() {
        guard isABCModeActive,
              let compactKeyboard = compactKeyboardView,
              let referenceButton = compactRecordButton else {
            return
        }

        let referenceFrame = referenceButton.convert(referenceButton.bounds, to: compactKeyboard)
        compactKeyboard.setSpaceAlignmentReference(frame: referenceFrame, showGuide: false)
    }

    // MARK: - Minimal Layout

    /// Orchestrate transition between layouts (compact <-> minimal)
    private func switchToLayout(_ layoutId: String) {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()

        if layoutId == "minimal" {
            showMinimalLayout(animated: true)
        } else {
            hideMinimalLayout(animated: true)
        }

        // Persist layout choice
        bridge.setActiveLayout(layoutId)
        log.info("Switched to layout: \(layoutId)")
    }

    /// Show the minimal single-row keyboard
    private func showMinimalLayout(animated: Bool) {
        guard !isMinimalLayoutActive else { return }
        isMinimalLayoutActive = true

        // Hide ABC keyboard if active
        hideCompactKeyboard()

        // Defensive cleanup in case a previous minimal view survived an extension lifecycle edge-case.
        inputView?.subviews
            .compactMap { $0 as? MinimalKeyboardView }
            .forEach { $0.removeFromSuperview() }

        let minimal = MinimalKeyboardView()

        // Resolve slot configs: custom override from bridge, then built-in defaults
        var configs: [Int: TalkieMobileKit.SlotConfig] = [:]
        for slot in 1...4 {
            if let customData = bridge.getSlotConfig(slot, forMode: "minimal"),
               let customConfig = try? JSONDecoder().decode(TalkieMobileKit.SlotConfig.self, from: customData) {
                configs[slot] = customConfig
            } else {
                configs[slot] = KeyboardMode.minimal.config(for: slot)
            }
        }
        minimal.slotConfigs = configs

        minimal.onDictateTapped = { [weak self] in
            self?.recordTapped()
        }

        minimal.onSlotAction = { [weak self] slot, config in
            self?.handleMinimalSlotAction(slot: slot, config: config)
        }

        minimal.onSwipeUp = { [weak self] in
            self?.switchToLayout("compact")
        }

        minimal.translatesAutoresizingMaskIntoConstraints = false

        if let inputView = inputView {
            inputView.addSubview(minimal)
            NSLayoutConstraint.activate([
                minimal.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                minimal.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                minimal.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
                minimal.heightAnchor.constraint(equalToConstant: minimalKeyboardHeight),
            ])
        }

        minimalKeyboardView = minimal

        // Reassign record button so dictation state updates the minimal dictate button
        recordButton = minimal.dictateButton

        // Set initial ready state on the minimal dictate button
        minimal.updateReadyState(isRecordReady, modelWarm: bridge.isModelWarm())

        // Hide the main stack (LED bar + slot grid)
        mainStack.alpha = 0

        // Animate height
        animateHeightTransition(to: minimalKeyboardHeight, animated: animated)

        log.info("Minimal layout shown")
    }

    /// Hide the minimal keyboard and restore compact layout
    private func hideMinimalLayout(animated: Bool) {
        guard isMinimalLayoutActive else { return }
        isMinimalLayoutActive = false

        // Stop animations and dismiss overlays
        minimalKeyboardView?.stopProcessingAnimation()
        dismissPuncOverlay()
        dismissPillTray()

        minimalKeyboardView?.removeFromSuperview()
        minimalKeyboardView = nil

        // Remove any orphaned minimal rows left by lifecycle churn.
        inputView?.subviews
            .compactMap { $0 as? MinimalKeyboardView }
            .forEach { $0.removeFromSuperview() }

        // Restore record button to the compact one
        recordButton = compactRecordButton

        // Show main stack
        mainStack.alpha = 1

        // Animate height back to standard
        animateHeightTransition(to: resolvedStandardKeyboardHeight(), animated: animated)

        log.info("Minimal layout hidden")
    }

    /// Dispatch a slot action from the minimal keyboard based on its config
    private func handleMinimalSlotAction(slot: Int, config: TalkieMobileKit.SlotConfig) {
        _ = slot

        switch config.label {
        case "SELECT":
            selectWordTapped()
        case "Aa":
            capitalizeTapped()
        case ".,?!":
            punctTapped()
        case "PUNC":
            puncOverlayTapped()
        default:
            KeyboardActionResolver.perform(config, on: self)
        }
    }

    func performKeyboardAction(_ action: KeyboardAction) {
        switch action {
        case .insert(let text):
            _ = consumeSelectionIfNeeded()
            textDocumentProxy.insertText(text)
            updateDebugView()
        case .deleteBackward:
            deleteTapped()
        case .copy:
            copyTapped()
        case .paste:
            pasteTapped()
        case .toggleShift:
            capitalizeTapped()
        case .toggleControl:
            break
        case .tab:
            tabTapped()
        case .escape:
            escapeTapped()
        case .enter:
            enterTapped()
        case .interrupt:
            break
        case .dismissKeyboard:
            dismissKeyboard()
        case .moveCursor(let movement):
            switch movement {
            case .left:
                textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            case .right:
                textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
            case .up, .wordLeft:
                moveCursorByWord(direction: -1)
            case .down, .wordRight:
                moveCursorByWord(direction: 1)
            }
        }
    }

    /// Animate the keyboard height constraint
    private func animateHeightTransition(to height: CGFloat, animated: Bool) {
        keyboardHeightConstraint?.constant = height
        if animated {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: .curveEaseInOut
            ) {
                self.view.superview?.layoutIfNeeded()
            }
        } else {
            view.superview?.layoutIfNeeded()
        }
    }

    private func resolvedStandardKeyboardHeight() -> CGFloat {
        let inset = max(view.safeAreaInsets.bottom, view.window?.safeAreaInsets.bottom ?? 0)
        let adaptive = standardKeyboardBaseHeight + inset
        return max(minimumStandardKeyboardHeight, adaptive)
    }

    private func synchronizeKeyboardHeightForCurrentLayout() {
        guard let keyboardHeightConstraint else { return }
        let target = isMinimalLayoutActive ? minimalKeyboardHeight : resolvedStandardKeyboardHeight()
        guard abs(keyboardHeightConstraint.constant - target) > 0.5 else { return }
        keyboardHeightConstraint.constant = target
    }

    // MARK: - Pill Tray

    /// Show the pill tray overlay above the minimal keyboard
    private func showPillTray() {
        guard pillTrayView == nil, isMinimalLayoutActive else { return }

        let tray = PillTrayView()

        tray.onOpenTalkie = { [weak self] in
            if let url = URL(string: "talkie://") {
                self?.openURL(url)
            }
        }

        tray.onSwitchKeyboard = { [weak self] in
            self?.advanceToNextInputMode()
        }

        tray.onEngineStatus = { [weak self] in
            self?.showStatus("Engine: checking...")
            // Could expand to show detailed engine status
        }

        tray.onDismiss = { [weak self] in
            self?.pillTrayView = nil
        }

        if let inputView = inputView {
            tray.showAnimated(in: inputView, below: inputView.bounds.height - minimalKeyboardHeight)
        }

        pillTrayView = tray
    }

    /// Dismiss the pill tray if visible
    private func dismissPillTray() {
        pillTrayView?.dismissAnimated()
        pillTrayView = nil
    }

    @objc private func tabTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        log.debug("Tab tapped")
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText("\t")
        updateDebugView()
    }

    // MARK: - Smart Select
    //
    // iOS keyboard extensions can't programmatically select text (Apple limitation).
    // We identify text and show it in status bar, then offer Copy/Delete/Cut actions.
    // Text stays in place until user explicitly acts on it.

    private var selectedText: String?
    private var selectedRange: (before: Int, after: Int)?

    @objc private func selectWordTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        selectNearestWord()
    }

    private func selectNearestWord() {
        guard let beforeContext = textDocumentProxy.documentContextBeforeInput else {
            showSelectStatus("No text")
            return
        }

        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""

        // Find word boundaries
        var charsBefore = 0
        for char in beforeContext.reversed() {
            if char.isWhitespace || char.isPunctuation { break }
            charsBefore += 1
        }

        var charsAfter = 0
        for char in afterContext {
            if char.isWhitespace || char.isPunctuation { break }
            charsAfter += 1
        }

        guard charsBefore + charsAfter > 0 else {
            showSelectStatus("No word at cursor")
            return
        }

        // Extract word WITHOUT deleting
        let wordStart = beforeContext.index(beforeContext.endIndex, offsetBy: -charsBefore)
        let word = String(beforeContext[wordStart...]) + String(afterContext.prefix(charsAfter))

        log.info("Selected word: '\(word)'")

        // Store for later actions
        selectedText = word
        selectedRange = (before: charsBefore, after: charsAfter)

        showSelectedTextUI(word, scope: "Word")
    }

    private func selectSentenceText() {
        guard let beforeContext = textDocumentProxy.documentContextBeforeInput else {
            showSelectStatus("No text")
            return
        }

        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""
        let enders: Set<Character> = [".", "!", "?"]

        var charsBefore = 0
        for char in beforeContext.reversed() {
            if enders.contains(char) && charsBefore > 0 { break }
            charsBefore += 1
        }

        var charsAfter = 0
        for char in afterContext {
            charsAfter += 1
            if enders.contains(char) { break }
        }

        guard charsBefore + charsAfter > 0 else {
            showSelectStatus("No sentence")
            return
        }

        let start = beforeContext.index(beforeContext.endIndex, offsetBy: -charsBefore)
        let sentence = (String(beforeContext[start...]) + String(afterContext.prefix(charsAfter))).trimmingCharacters(in: .whitespaces)

        selectedText = sentence
        selectedRange = (before: charsBefore, after: charsAfter)
        showSelectedTextUI(sentence, scope: "Sentence")
    }

    private func selectParagraphText() {
        guard let beforeContext = textDocumentProxy.documentContextBeforeInput else {
            showSelectStatus("No text")
            return
        }

        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""

        var charsBefore = 0
        for char in beforeContext.reversed() {
            if char == "\n" { break }
            charsBefore += 1
        }

        var charsAfter = 0
        for char in afterContext {
            if char == "\n" { break }
            charsAfter += 1
        }

        guard charsBefore + charsAfter > 0 else {
            showSelectStatus("No paragraph")
            return
        }

        let start = beforeContext.index(beforeContext.endIndex, offsetBy: -charsBefore)
        let para = String(beforeContext[start...]) + String(afterContext.prefix(charsAfter))

        selectedText = para
        selectedRange = (before: charsBefore, after: charsAfter)
        showSelectedTextUI(para, scope: "Paragraph")
    }

    private func selectAllText() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let allText = before + after

        guard !allText.isEmpty else {
            showSelectStatus("No text")
            return
        }

        selectedText = allText
        selectedRange = (before: before.count, after: after.count)
        showSelectedTextUI(allText, scope: "All")
    }

    private func showSelectedTextUI(_ text: String, scope: String) {
        let display = formattedSelectionPreview(text, maxVisible: 150)
        setStatusMessage("Selected {\(display)}\nActions: COPY • CUT • DEL", color: Design.textPrimary)
        setStatusPillSelectionExpanded(true)
        pulseSelectionFeedback()

        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()

        // Auto-clear selection after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            if self?.selectedText != nil {
                self?.clearSelection()
            }
        }
    }

    private func formattedSelectionPreview(_ text: String, maxVisible: Int) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard compact.count > maxVisible else { return compact }

        let tail = lastAlphanumericToken(compact, count: 10)
        let separator = tail.isEmpty ? "" : " "
        let reserved = 3 + separator.count + tail.count // "..." + optional separator + tail token
        let prefixCount = max(0, maxVisible - reserved)
        let head = String(compact.prefix(prefixCount))
        return "\(head)...\(separator)\(tail)"
    }

    private func lastAlphanumericToken(_ text: String, count: Int) -> String {
        var chars: [Character] = []
        chars.reserveCapacity(count)

        for char in text.reversed() {
            guard char.isLetter || char.isNumber else { continue }
            chars.append(char)
            if chars.count == count { break }
        }
        return String(chars.reversed())
    }

    private func pulseSelectionFeedback() {
        guard let statusPillView else { return }
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            statusPillView.transform = CGAffineTransform(scaleX: 1.015, y: 1.015)
        } completion: { _ in
            UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
                statusPillView.transform = .identity
            }
        }
    }

    private func showSelectStatus(_ message: String) {
        setStatusMessage(message, color: Design.textSecondary)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.selectedText == nil {
                self?.clearStatusMessage()
            }
        }
    }

    private func clearSelection() {
        selectedText = nil
        selectedRange = nil
        setStatusPillSelectionExpanded(false)
        clearStatusMessage()
    }

    @discardableResult
    private func consumeSelectionIfNeeded() -> Bool {
        guard let range = selectedRange else { return false }

        // Move cursor to selection end, then delete captured span.
        if range.after != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: range.after)
        }
        for _ in 0..<(range.before + range.after) {
            textDocumentProxy.deleteBackward()
        }

        selectedText = nil
        selectedRange = nil
        setStatusPillSelectionExpanded(false)
        return true
    }

    private func setStatusPillSelectionExpanded(_ expanded: Bool, animated: Bool = true, forceCollapse: Bool = false) {
        guard let statusLabel else { return }
        if statusActionOverlayView != nil && !forceCollapse { return }
        statusLabel.numberOfLines = expanded ? 2 : 1
        if expanded {
            selectionStatusOverlayPinned = true
            presentSelectionStatusOverlay(animated: animated)
        } else {
            guard forceCollapse || !selectionStatusOverlayPinned else { return }
            dismissSelectionStatusOverlay(animated: animated)
        }
    }

    private func presentSelectionStatusOverlay(animated: Bool) {
        guard let statusPill = statusPillView else { return }
        guard selectionStatusOverlayView == nil else { return }
        view.layoutIfNeeded()

        let startFrame = statusPill.convert(statusPill.bounds, to: view)
        let overlay = UIView(frame: startFrame)
        overlay.isUserInteractionEnabled = true
        overlay.layer.cornerCurve = .continuous
        overlay.layer.cornerRadius = statusPill.layer.cornerRadius
        overlay.layer.borderWidth = statusPill.layer.borderWidth
        overlay.layer.borderColor = statusPill.layer.borderColor
        overlay.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.05, alpha: 0.98)
                : UIColor(white: 0.98, alpha: 0.98)
        }
        overlay.layer.shadowColor = UIColor.black.cgColor
        overlay.layer.shadowOpacity = 0.20
        overlay.layer.shadowRadius = 14
        overlay.layer.shadowOffset = CGSize(width: 0, height: 2)
        overlay.accessibilityLabel = "Selection Panel"
        overlay.accessibilityHint = "Swipe up to dismiss."

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(selectionStatusOverlaySwipedUp))
        swipeUp.direction = .up
        overlay.addGestureRecognizer(swipeUp)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textAlignment = .left
        label.numberOfLines = 4
        label.text = statusLabel?.text
        label.textColor = statusLabel?.textColor
        label.alpha = statusLabel?.alpha ?? 1
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -8)
        ])

        view.addSubview(overlay)
        view.bringSubviewToFront(overlay)
        selectionStatusOverlayView = overlay
        selectionStatusOverlayLabel = label

        let targetFrame = selectionStatusOverlayTargetFrame()

        statusPill.alpha = 0
        if !animated {
            overlay.frame = targetFrame
            overlay.layer.cornerRadius = 16
            return
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            overlay.frame = targetFrame
            overlay.layer.cornerRadius = 16
        }
    }

    private func selectionStatusOverlayTargetFrame() -> CGRect {
        let inset: CGFloat = 3
        let surfaceY = keyboardSurfaceView?.frame.minY ?? 0
        let topY = surfaceY + keyboardSurfaceTopPadding
        let width = max(120, view.bounds.width - (inset * 2))
        // Take over status row + stack gap + top key row (+ tiny buffer).
        let height = Design.ledBarHeight + mainStack.spacing + Design.buttonHeight + 3
        return CGRect(x: inset, y: topY, width: width, height: height)
    }

    private func dismissSelectionStatusOverlay(animated: Bool) {
        guard let overlay = selectionStatusOverlayView, let statusPill = statusPillView else { return }
        selectionStatusOverlayView = nil
        selectionStatusOverlayLabel = nil
        selectionStatusOverlayPinned = false
        let destination = statusPill.convert(statusPill.bounds, to: view)
        statusPill.alpha = 1

        let finish = {
            overlay.removeFromSuperview()
        }
        guard animated else {
            finish()
            return
        }

        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn]) {
            overlay.frame = destination
            overlay.alpha = 0
            overlay.layer.cornerRadius = statusPill.layer.cornerRadius
        } completion: { _ in
            finish()
        }
    }

    @objc private func selectionStatusOverlaySwipedUp() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        setStatusPillSelectionExpanded(false, animated: true, forceCollapse: true)
    }

    private func updateActionOverlayHeader() {
        statusActionOverlayLabel?.text = isActionPanelInSmartMenu ? "actions > smart" : "actions"
        statusActionOverlayLabel?.textColor = UIColor(white: 1.0, alpha: 0.80)
        statusActionOverlayStateLabel?.text = "STATE: \(currentPhase.rawValue.uppercased())"
    }

    private func presentStatusActionOverlay(animated: Bool) {
        guard let statusPill = statusPillView else { return }
        if statusActionOverlayView != nil { return }
        dismissSelectionStatusOverlay(animated: false)
        view.layoutIfNeeded()

        let startFrame = statusPill.convert(statusPill.bounds, to: view)
        let overlay = UIView(frame: startFrame)
        overlay.isUserInteractionEnabled = true
        overlay.layer.cornerCurve = .continuous
        overlay.layer.cornerRadius = statusPill.layer.cornerRadius
        overlay.layer.borderWidth = 0.45
        overlay.layer.borderColor = UIColor(white: 1.0, alpha: 0.08).cgColor
        overlay.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.0, alpha: 0.94)
                : UIColor(white: 0.03, alpha: 0.92)
        }
        overlay.layer.shadowColor = UIColor.black.cgColor
        overlay.layer.shadowOpacity = 0.28
        overlay.layer.shadowRadius = 12
        overlay.layer.shadowOffset = CGSize(width: 0, height: 2)
        overlay.accessibilityLabel = "Action Mode Panel"
        overlay.accessibilityHint = "Swipe up to dismiss."

        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        blurView.alpha = 0.18
        blurView.layer.cornerRadius = overlay.layer.cornerRadius
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        overlay.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: overlay.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor)
        ])

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(statusActionOverlayDismissRequested))
        swipeUp.direction = .up
        overlay.addGestureRecognizer(swipeUp)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        title.textAlignment = .left
        title.numberOfLines = 1
        title.text = isActionPanelInSmartMenu ? "actions > smart" : "actions"
        title.textColor = UIColor(white: 1.0, alpha: 0.80)
        overlay.addSubview(title)
        statusActionOverlayLabel = title

        let stateLabel = UILabel()
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.font = .monospacedSystemFont(ofSize: 8, weight: .semibold)
        stateLabel.textAlignment = .right
        stateLabel.numberOfLines = 1
        stateLabel.textColor = UIColor(white: 1.0, alpha: 0.72)
        stateLabel.text = "STATE: \(currentPhase.rawValue.uppercased())"
        overlay.addSubview(stateLabel)
        statusActionOverlayStateLabel = stateLabel

        let preview = UILabel()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.font = .monospacedSystemFont(ofSize: 8, weight: .light)
        preview.textAlignment = .left
        preview.numberOfLines = 11
        preview.textColor = UIColor(white: 1.0, alpha: 0.66)
        preview.text = actionModePreviewText()
        overlay.addSubview(preview)
        statusActionPreviewLabel = preview

        let grid = UIStackView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.axis = .vertical
        grid.spacing = 0
        grid.alignment = .fill
        overlay.addSubview(grid)

        let commands: [(Int, String, Selector)] = actionPanelCommands()

        let row1 = makeActionCommandRow(Array(commands.prefix(3)))
        let row2 = makeActionCommandRow(Array(commands.suffix(3)))
        grid.addArrangedSubview(row1)
        row1.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let horizontalSeparator = UIView()
        horizontalSeparator.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        horizontalSeparator.translatesAutoresizingMaskIntoConstraints = false
        grid.addArrangedSubview(horizontalSeparator)
        horizontalSeparator.heightAnchor.constraint(equalToConstant: 0.55).isActive = true

        grid.addArrangedSubview(row2)
        row2.heightAnchor.constraint(equalToConstant: 22).isActive = true

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: stateLabel.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 3),

            stateLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            stateLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            preview.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),

            grid.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            grid.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 3),
            grid.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -4)
        ])

        updateActionOverlayHeader()

        view.addSubview(overlay)
        view.bringSubviewToFront(overlay)
        statusActionOverlayView = overlay

        let target = statusActionOverlayTargetFrame()
        statusPill.alpha = 0
        if !animated {
            overlay.frame = target
            overlay.layer.cornerRadius = 12
            return
        }

        UIView.animate(
            withDuration: 0.30,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.72,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            overlay.frame = target
            overlay.layer.cornerRadius = 12
        }
    }

    private func statusActionOverlayTargetFrame() -> CGRect {
        let inset: CGFloat = 2
        let surfaceY = keyboardSurfaceView?.frame.minY ?? 0
        let topY = surfaceY + 1
        let width = max(120, view.bounds.width - (inset * 2))
        // Keep close to top while preserving activation-style debug lines + command rows.
        let height = Design.ledBarHeight + mainStack.spacing + Design.buttonHeight + 76
        return CGRect(x: inset, y: topY, width: width, height: height)
    }

    private func actionModePreviewText() -> String {
        let selectionCount = selectedText?.count ?? 0
        let selectionLine = selectionCount > 0
            ? "selection: \(selectionCount) chars"
            : "selection: none"
        let clipboardLine = localClipboardText?.isEmpty == false ? "clipboard: local ready" : "clipboard: empty"
        let aiLine = isAppleIntelligenceAvailable() ? "ai: ready" : "ai: unavailable"
        let modeLine = isActionPanelInSmartMenu ? "smart tools + selection" : "edit tools"
        return "\(modeLine)\n\(selectionLine)\n\(clipboardLine)\n\(aiLine)"
    }

    private func actionPanelCommands() -> [(Int, String, Selector)] {
        if isActionPanelInSmartMenu {
            return [
                (1, "BACK", #selector(actionPanelBackTapped)),
                (2, "SUMMARY", #selector(actionPanelSummarizeTapped)),
                (3, "BULLETS", #selector(actionPanelBulletsTapped)),
                (4, "TOPICS", #selector(actionPanelTopicsTapped)),
                (5, "SEL ALL", #selector(actionPanelSelectAllTapped)),
                (6, "SEL SENT", #selector(actionPanelSelectSentenceTapped))
            ]
        }

        return [
            (1, "COPY", #selector(actionPanelCopyTapped)),
            (2, "CUT", #selector(actionPanelCutTapped)),
            (3, "PASTE", #selector(actionPanelPasteTapped)),
            (4, "DEL", #selector(actionPanelDeleteTapped)),
            (5, "CLEAR", #selector(actionPanelClearSelectionTapped)),
            (6, "SMART", #selector(actionPanelSmartTapped))
        ]
    }

    private func refreshStatusActionOverlayMenu() {
        guard statusActionOverlayView != nil else { return }
        statusActionOverlayView?.removeFromSuperview()
        statusActionOverlayView = nil
        statusActionOverlayLabel = nil
        statusActionOverlayStateLabel = nil
        statusActionPreviewLabel = nil
        presentStatusActionOverlay(animated: false)
    }

    private func makeActionPanelCommandButton(number: Int, title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 1)

        let accent = UIColor(red: 0.42, green: 0.92, blue: 0.62, alpha: 1.0)
        let base = UIColor(white: 1.0, alpha: 0.74)
        let fullText = String(format: "%02d// %@", number, title)
        let attributed = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .light),
                .foregroundColor: base
            ]
        )
        attributed.addAttributes([.foregroundColor: accent], range: NSRange(location: 0, length: 4))
        button.setAttributedTitle(attributed, for: .normal)
        button.setAttributedTitle(attributed, for: .highlighted)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.isEnabled = true
        button.alpha = 1.0
        return button
    }

    private func makeActionCommandRow(_ commands: [(Int, String, Selector)]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        var commandButtons: [UIButton] = []

        for (index, command) in commands.enumerated() {
            let button = makeActionPanelCommandButton(number: command.0, title: command.1, action: command.2)
            commandButtons.append(button)
            row.addArrangedSubview(button)
            if index < commands.count - 1 {
                let separator = UIView()
                separator.backgroundColor = UIColor(white: 1.0, alpha: 0.10)
                separator.translatesAutoresizingMaskIntoConstraints = false
                row.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalToConstant: 0.55).isActive = true
            }
        }

        if let first = commandButtons.first {
            for button in commandButtons.dropFirst() {
                button.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
            }
        }

        return row
    }

    @objc private func statusActionOverlayDismissRequested() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        dismissStatusActionOverlay(animated: true)
    }

    private func dismissStatusActionOverlay(animated: Bool) {
        guard let overlay = statusActionOverlayView, let statusPill = statusPillView else { return }
        statusActionOverlayView = nil
        statusActionOverlayLabel = nil
        statusActionOverlayStateLabel = nil
        statusActionPreviewLabel = nil
        isActionPanelInSmartMenu = false
        let destination = statusPill.convert(statusPill.bounds, to: view)
        statusPill.alpha = 1

        let finish = {
            overlay.removeFromSuperview()
        }
        guard animated else {
            finish()
            return
        }

        UIView.animate(
            withDuration: 0.20,
            delay: 0,
            usingSpringWithDamping: 0.94,
            initialSpringVelocity: 0.42,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn]
        ) {
            overlay.frame = destination
            overlay.alpha = 0
            overlay.layer.cornerRadius = statusPill.layer.cornerRadius
        } completion: { _ in
            finish()
        }
    }

    @objc private func actionPanelVoiceCommandTapped() {
        isVoiceCommandMode.toggle()
        pendingVoiceCommandStart = isVoiceCommandMode
        if isVoiceCommandMode {
            activeCaptureMode = .voiceCommand
            setStatusMessage("Voice cmd: armed", color: Design.textPrimary)
        } else {
            activeCaptureMode = .dictation
            setStatusMessage("Voice cmd: off", color: Design.textPrimary)
        }
        lightImpact.impactOccurred()
        lightImpact.prepare()

        refreshStatusActionOverlayMenu()

        guard isVoiceCommandMode else { return }
        // If we're already recording, keep the current take and route its result to commands.
        // No stop/restart churn.
        let phase = sharedStore.phase
        if phase == .recording || phase == .stopping || phase == .arming || phase == .transcribing {
            pendingVoiceCommandStart = false
            showStatus("Voice cmd: using current take")
            return
        }
        startVoiceCommandListeningIfPossible()
    }

    private func startVoiceCommandListeningIfPossible() {
        guard isVoiceCommandMode else { return }
        let phase = sharedStore.phase
        if phase == .idle || phase == .ready || phase == .done || phase == .error {
            pendingVoiceCommandStart = false
            activeCaptureMode = .voiceCommand
            setStatusMessage("Voice cmd: listening", color: Design.textPrimary)
            recordTapped()
            return
        }

        // If a take is active, keep it and route result to command mode.
        if phase == .recording || phase == .stopping || phase == .arming || phase == .transcribing {
            pendingVoiceCommandStart = false
            activeCaptureMode = .voiceCommand
            showStatus("Voice cmd: using current take")
        }
    }

    @objc private func actionPanelCopyTapped() {
        copySelectedText()
    }

    @objc private func actionPanelCutTapped() {
        cutSelectedText()
    }

    @objc private func actionPanelDeleteTapped() {
        deleteSelectedText()
    }

    @objc private func actionPanelClearSelectionTapped() {
        clearSelection()
    }

    @objc private func actionPanelDictateTapped() {
        if isVoiceCommandMode {
            isVoiceCommandMode = false
            pendingVoiceCommandStart = false
        }
        activeCaptureMode = .dictation
        setStatusMessage("Dictating...", color: Design.textPrimary)
        recordTapped()
    }

    @objc private func actionPanelPasteTapped() {
        pasteTapped()
    }

    @objc private func actionPanelPasteSystemTapped() {
        if !pasteFromSystemClipboard() {
            showStatus("System clipboard empty")
        }
    }

    @objc private func actionPanelSmartTapped() {
        isActionPanelInSmartMenu = true
        lightImpact.impactOccurred()
        lightImpact.prepare()
        refreshStatusActionOverlayMenu()
    }

    @objc private func actionPanelBackTapped() {
        isActionPanelInSmartMenu = false
        lightImpact.impactOccurred()
        lightImpact.prepare()
        refreshStatusActionOverlayMenu()
    }

    @objc private func actionPanelSummarizeTapped() {
        guard isAppleIntelligenceAvailable() else {
            showStatus("AI unavailable: \(appleIntelligenceAvailabilityDescription())")
            return
        }
        lightImpact.impactOccurred()
        lightImpact.prepare()
        runSmartTransform(.summary)
    }

    @objc private func actionPanelBulletsTapped() {
        guard isAppleIntelligenceAvailable() else {
            showStatus("AI unavailable: \(appleIntelligenceAvailabilityDescription())")
            return
        }
        lightImpact.impactOccurred()
        lightImpact.prepare()
        runSmartTransform(.bullets)
    }

    @objc private func actionPanelSelectWordTapped() {
        selectNearestWord()
    }

    @objc private func actionPanelSelectSentenceTapped() {
        selectSentenceText()
    }

    @objc private func actionPanelSelectParagraphTapped() {
        selectParagraphText()
    }

    @objc private func actionPanelSelectAllTapped() {
        selectAllText()
    }

    @objc private func actionPanelTopicsTapped() {
        guard isAppleIntelligenceAvailable() else {
            showStatus("AI unavailable: \(appleIntelligenceAvailabilityDescription())")
            return
        }
        lightImpact.impactOccurred()
        lightImpact.prepare()
        runSmartTransform(.topics)
    }

    @objc private func actionPanelOpenActivationTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        guard let url = URL(string: "talkie://dictate") else {
            showStatus("Nudge: invalid URL")
            return
        }
        showStatus("Nudge: opening activation")
        openURL(url)
    }

    @objc private func actionPanelRetryTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        sharedStore.updateKeyboardHeartbeat()
        if pollTimer == nil {
            startPolling()
        }
        let phase = sharedStore.phase
        if phase == .idle || phase == .ready || phase == .done || phase == .error {
            showStatus("Nudge: retry start")
            recordTapped()
            return
        }
        pollForUpdates()
        showStatus("Nudge: refreshed state")
    }

    @objc private func actionPanelStopTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        let phase = sharedStore.phase
        let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .arming, .transcribing]
        guard activePhases.contains(phase) else {
            showStatus("Nudge: not recording")
            return
        }

        bridge.requestStopRecording()
        if let sessionId = currentSessionId ?? sharedStore.snapshot().activeSessionId {
            _ = sharedStore.keyboardRequestStop(sessionId: sessionId)
        }
        showStatus("Nudge: stop requested")
        startPolling()
    }

    @objc private func actionPanelResetTapped() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        sharedStore.forceReset(reason: "Action panel reset", preserveCapability: true, updatedBy: "keyboard")
        bridge.forceReset()
        currentSessionId = nil
        showNormalUI()
        showStatus("Nudge: reset complete")
    }

    @objc private func actionPanelSnapshotTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        copyDebugSnapshotFromShift()
    }

    @objc private func actionPanelSyncTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        sharedStore.updateKeyboardHeartbeat()
        publishKeyboardDebug("actionPanelSync")
        pollForUpdates()
        showStatus("Nudge: sync requested")
    }

    /// Copy selected text to clipboard (doesn't delete from document)
    private func copySelectedText() {
        guard let text = selectedText else { return }

        storeLocalClipboardText(text)
        UIPasteboard.general.string = text

        setStatusMessage("Copied!", color: Design.ledReady)

        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.clearSelection()
        }
    }

    /// Delete selected text from document
    private func deleteSelectedText() {
        guard consumeSelectionIfNeeded() else { return }

        setStatusMessage("Deleted", color: Design.textSecondary)

        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.clearSelection()
        }
    }

    /// Cut = Copy + Delete
    private func cutSelectedText() {
        guard let text = selectedText else { return }

        storeLocalClipboardText(text)
        UIPasteboard.general.string = text
        deleteSelectedText()

        setStatusMessage("Cut!", color: Design.ledReady)
    }

    @objc private func selectLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        mediumImpact.impactOccurred()
        mediumImpact.prepare()

        guard let button = gesture.view as? UIButton else {
            selectNearestWord()
            return
        }
        showSelectScopeMenu(button: button)
    }

    private func selectWordToLeft() {
        guard let beforeContext = textDocumentProxy.documentContextBeforeInput, !beforeContext.isEmpty else {
            showSelectStatus("No text on left")
            return
        }

        let characters = Array(beforeContext)
        var cursor = characters.count - 1

        while cursor >= 0 && (characters[cursor].isWhitespace || characters[cursor].isPunctuation) {
            cursor -= 1
        }

        guard cursor >= 0 else {
            showSelectStatus("No word on left")
            return
        }

        var start = cursor
        while start >= 0 && !(characters[start].isWhitespace || characters[start].isPunctuation) {
            start -= 1
        }

        let wordStart = start + 1
        let text = String(characters[wordStart...cursor])
        selectedText = text
        selectedRange = (before: cursor - wordStart + 1, after: 0)
        showSelectedTextUI(text, scope: "Word Left")
    }

    private func selectWordToRight() {
        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""
        guard !afterContext.isEmpty else {
            showSelectStatus("No text on right")
            return
        }

        let characters = Array(afterContext)

        var start = 0
        while start < characters.count && (characters[start].isWhitespace || characters[start].isPunctuation) {
            start += 1
        }

        guard start < characters.count else {
            showSelectStatus("No word on right")
            return
        }

        var end = start
        while end < characters.count && !(characters[end].isWhitespace || characters[end].isPunctuation) {
            end += 1
        }

        let text = String(characters[start..<end])
        selectedText = text
        selectedRange = (before: 0, after: end - start)
        showSelectedTextUI(text, scope: "Word Right")
    }

    private func selectAllBeforeCursor() {
        let beforeContext = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !beforeContext.isEmpty else {
            showSelectStatus("No text above")
            return
        }

        selectedText = beforeContext
        selectedRange = (before: beforeContext.count, after: 0)
        showSelectedTextUI(beforeContext, scope: "Above Cursor")
    }

    private func selectAllAfterCursor() {
        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""
        guard !afterContext.isEmpty else {
            showSelectStatus("No text below")
            return
        }

        selectedText = afterContext
        selectedRange = (before: 0, after: afterContext.count)
        showSelectedTextUI(afterContext, scope: "Below Cursor")
    }

    private func showSelectScopeMenu(button: UIButton) {
        // Selection scopes - ordered by user preference (All first, then granular)
        let all = UIAction(title: "Select All", image: UIImage(systemName: "selection.pin.in.out")) { [weak self] _ in
            self?.selectAllText()
        }
        let word = UIAction(title: "Word", image: UIImage(systemName: "text.cursor")) { [weak self] _ in
            self?.selectNearestWord()
        }
        let sentence = UIAction(title: "Sentence", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in
            self?.selectSentenceText()
        }
        let paragraph = UIAction(title: "Paragraph", image: UIImage(systemName: "text.justify")) { [weak self] _ in
            self?.selectParagraphText()
        }
        let toLeft = UIAction(title: "Word Left", image: UIImage(systemName: "arrow.left")) { [weak self] _ in
            self?.selectWordToLeft()
        }
        let toRight = UIAction(title: "Word Right", image: UIImage(systemName: "arrow.right")) { [weak self] _ in
            self?.selectWordToRight()
        }
        let allBefore = UIAction(title: "All Above Cursor", image: UIImage(systemName: "arrow.up.to.line")) { [weak self] _ in
            self?.selectAllBeforeCursor()
        }
        let allAfter = UIAction(title: "All Below Cursor", image: UIImage(systemName: "arrow.down.to.line")) { [weak self] _ in
            self?.selectAllAfterCursor()
        }
        let directional = UIMenu(
            title: "Directional",
            options: .displayInline,
            children: [toLeft, toRight, allBefore, allAfter]
        )

        button.menu = UIMenu(title: "Select Scope", children: [all, word, sentence, paragraph, directional])
        button.showsMenuAsPrimaryAction = false
    }

    // MARK: - Vim-style "to end of" selections

    private func selectToEndOfWord() {
        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""
        guard !afterContext.isEmpty else {
            showSelectStatus("No text ahead")
            return
        }

        var charsAfter = 0
        for char in afterContext {
            if char.isWhitespace || char.isPunctuation { break }
            charsAfter += 1
        }

        guard charsAfter > 0 else {
            showSelectStatus("At word end")
            return
        }

        let text = String(afterContext.prefix(charsAfter))
        selectedText = text
        selectedRange = (before: 0, after: charsAfter)
        showSelectedTextUI(text, scope: "To End Word")
    }

    private func selectToEndOfSentence() {
        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""
        guard !afterContext.isEmpty else {
            showSelectStatus("No text ahead")
            return
        }

        let enders: Set<Character> = [".", "!", "?"]
        var charsAfter = 0
        for char in afterContext {
            charsAfter += 1
            if enders.contains(char) { break }
        }

        let text = String(afterContext.prefix(charsAfter))
        selectedText = text
        selectedRange = (before: 0, after: charsAfter)
        showSelectedTextUI(text, scope: "To End Sentence")
    }

    private func selectToEndOfParagraph() {
        let afterContext = textDocumentProxy.documentContextAfterInput ?? ""
        guard !afterContext.isEmpty else {
            showSelectStatus("No text ahead")
            return
        }

        var charsAfter = 0
        for char in afterContext {
            if char == "\n" { break }
            charsAfter += 1
        }

        guard charsAfter > 0 else {
            showSelectStatus("At paragraph end")
            return
        }

        let text = String(afterContext.prefix(charsAfter))
        selectedText = text
        selectedRange = (before: 0, after: charsAfter)
        showSelectedTextUI(text, scope: "To End Paragraph")
    }

    private func selectSentence() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        selectSentenceText()
    }

    private func selectParagraph() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        selectParagraphText()
    }

    private func selectAll() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        selectAllText()
    }

    // Legacy compatibility aliases
    private var capturedText: String? {
        get { selectedText }
        set { selectedText = newValue }
    }
    private func restoreCapturedTextIfNeeded() { clearSelection() }
    func copyCapturedText() { copySelectedText() }
    func cancelCapture() { clearSelection() }
    private func showSelectOptionsMenu(from sourceView: UIView?) {
        if let button = sourceView as? UIButton { showSelectScopeMenu(button: button) }
    }
    private func showCapturedTextUI(_ text: String, type: String) {
        showSelectedTextUI(text, scope: "Captured")
    }

    // Keep for backward compatibility but unused
    private func captureNearestWord() { selectNearestWord() }
    private func captureSentence() { selectSentenceText() }
    private func captureParagraph() { selectParagraphText() }
    private func captureAll() { selectAllText() }

    @objc private func escapeTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        log.debug("Escape tapped")
        // Dismiss keyboard
        dismissKeyboard()
    }

    // MARK: - Punctuation Overlay

    @objc private func puncOverlayTapped() {
        // Toggle — dismiss if already showing
        if puncOverlayView != nil {
            dismissPuncOverlay()
            return
        }
        showPuncOverlay()
    }

    private func showPuncOverlay() {
        guard puncOverlayView == nil, let inputView = inputView else { return }

        let overlay = PuncOverlayView()

        overlay.onPuncInsert = { [weak self] char in
            _ = self?.consumeSelectionIfNeeded()
            self?.textDocumentProxy.insertText(char)
            self?.updateDebugView()
        }

        overlay.onSwitchToSymbols = { [weak self] in
            guard let self else { return }
            if self.isMinimalLayoutActive {
                self.keyboardConfig.activeModeId = "symbols"
                self.persistActiveModeSelection()
                self.switchToLayout("compact")
            } else {
                self.activateMode(modeId: "symbols")
            }
        }

        overlay.onDismiss = { [weak self] in
            self?.puncOverlayView = nil
        }

        // Position close to the PUNC button (slot 8) when in compact grid
        let anchorY: CGFloat
        if !isMinimalLayoutActive, let puncBtn = slotButtons[8] {
            // Convert button's top edge to inputView coordinates
            let btnFrame = puncBtn.convert(puncBtn.bounds, to: inputView)
            anchorY = btnFrame.minY
        } else if isMinimalLayoutActive {
            anchorY = inputView.bounds.height - minimalKeyboardHeight
        } else {
            anchorY = inputView.bounds.height - resolvedStandardKeyboardHeight()
        }

        overlay.showAnimated(in: inputView, above: anchorY)
        puncOverlayView = overlay
    }

    private func dismissPuncOverlay() {
        puncOverlayView?.dismissAnimated()
        puncOverlayView = nil
    }

    @objc private func puncTouchDown(_ sender: UIButton) {
        puncDidFireLongPress = false
        puncLongPressTimer?.invalidate()

        // Must use RunLoop .common mode — .default doesn't fire during touch tracking
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.puncDidFireLongPress = true
            self.mediumImpact.impactOccurred()
            self.mediumImpact.prepare()
            self.showPuncOverlay()
        }
        RunLoop.main.add(timer, forMode: .common)
        puncLongPressTimer = timer
    }

    @objc private func puncTouchUp(_ sender: UIButton) {
        puncLongPressTimer?.invalidate()
        puncLongPressTimer = nil

        if !puncDidFireLongPress {
            // Short tap → insert period
            lightImpact.impactOccurred()
            lightImpact.prepare()
            _ = consumeSelectionIfNeeded()
            textDocumentProxy.insertText(".")
            updateDebugView()
        }
        puncDidFireLongPress = false
    }

    // MARK: - Programmer Punctuation (slot 12)

    @objc private func punctTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        textDocumentProxy.insertText(".")
    }

    /// Long-press punctuation button for programmer symbols menu
    @objc private func punctLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        mediumImpact.impactOccurred()
        mediumImpact.prepare()

        if let button = gesture.view as? UIButton {
            showPunctMenu(button: button)
        }
    }

    private func showPunctMenu(button: UIButton) {
        // Programmer's quick punctuation menu
        let period = UIAction(title: ".", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText(".")
        }
        let colon = UIAction(title: ":", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText(":")
        }
        let semicolon = UIAction(title: ";", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText(";")
        }
        let equals = UIAction(title: "=", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("=")
        }
        let plus = UIAction(title: "+", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("+")
        }
        let minus = UIAction(title: "-", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("-")
        }
        let underscore = UIAction(title: "_", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("_")
        }
        let arrow = UIAction(title: "->", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("->")
        }

        button.menu = UIMenu(title: "", children: [period, colon, semicolon, equals, plus, minus, underscore, arrow])
        button.showsMenuAsPrimaryAction = false  // Tap still inserts period
    }

    @objc private func operatorLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        mediumImpact.impactOccurred()
        mediumImpact.prepare()

        if let button = gesture.view as? UIButton {
            showOperatorMenu(button: button)
        }
    }

    private func showOperatorMenu(button: UIButton) {
        let plus = UIAction(title: "+", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("+")
        }
        let minus = UIAction(title: "-", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("-")
        }
        let multiply = UIAction(title: "*", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("*")
        }
        let divide = UIAction(title: "/", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("/")
        }
        let equals = UIAction(title: "=", image: nil) { [weak self] _ in
            self?.textDocumentProxy.insertText("=")
        }

        button.menu = UIMenu(title: "", children: [plus, minus, multiply, divide, equals])
        button.showsMenuAsPrimaryAction = false
    }

    @objc private func modeCycleTapped() {
        let oldMode = currentMode.id
        cycleToNextMode()
        log.info("Mode cycle: \(oldMode) → \(currentMode.id)")
    }

    // Legacy handlers - redirect to cycle
    @objc private func numberModeTapped() { modeCycleTapped() }
    @objc private func symbolModeTapped() { modeCycleTapped() }
    @objc private func lettersModeTapped() { modeCycleTapped() }

    /// Long-press LED area to show debug status and force reset if stuck
    @objc private func ledLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        heavyImpact.impactOccurred()
        heavyImpact.prepare()

        let snap = sharedStore.snapshot()
        let phase = snap.phase
        let phaseAge = Int(snap.phaseAge)
        let bridgeReady = instantStartAvailable
        let bridgeRecording = bridge.isRecordingInProgress()

        // Check if stuck in an active state
        let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .arming]
        let isStuck = activePhases.contains(phase)

        if isStuck {
            // Force reset and show what we reset from
            log.warning("Long-press reset: was \(phase) for \(phaseAge)s")
            sharedStore.forceReset(reason: "User long-press reset", preserveCapability: true, updatedBy: "keyboard")
            bridge.forceReset()
            showNormalUI()
            setStatusMessage("Reset from \(phase)", color: Design.vermillion)

            // Clear status after showing what happened
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.clearStatusMessage()
            }
        }

        let snapshot = buildKeyboardDebugSnapshot()
        log.info("Keyboard debug snapshot:\n\(snapshot)")
        sharedStore.publishKeyboardDebug(message: "ledLongPress", snapshot: snapshot)

        if hasFullAccess {
            UIPasteboard.general.string = snapshot
            setStatusMessage("Debug copied", color: Design.textSecondary)
        } else {
            // Show abbreviated status if we can't copy
            let info = "\(phase) | app:\(bridgeReady ? "✓" : "✗") rec:\(bridgeRecording ? "●" : "○")"
            setStatusMessage(info, color: Design.textSecondary)
        }

        // Clear after a few seconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            if !activePhases.contains(self.currentPhase) {
                self.clearStatusMessage()
            }
        }
    }

    private func buildKeyboardDebugSnapshot() -> String {
        let state = sharedStore.snapshot()
        let now = Date().timeIntervalSince1970
        let appHeartbeatAge = state.appHeartbeat > 0 ? formatSeconds(now - state.appHeartbeat) : "nil"
        let keyboardHeartbeatAge = state.keyboardHeartbeat > 0 ? formatSeconds(now - state.keyboardHeartbeat) : "nil"
        let commandInfo: String
        if let command = state.command {
            commandInfo = "\(command.kind.rawValue) id=\(command.id) session=\(command.sessionId) age=\(formatSeconds(now - command.requestedAt)) epoch=\(command.epoch)"
        } else {
            commandInfo = "none"
        }
        let ackInfo = state.commandAck.map { "\($0.id) phase=\($0.phase.rawValue)" } ?? "none"
        let resultInfo = state.lastResult.map { "session=\($0.sessionId) chars=\($0.text.count)" } ?? "none"
        let errorInfo = state.lastError.map { "session=\($0.sessionId?.uuidString ?? "nil") msg=\($0.message)" } ?? "none"

        return """
        === TalkieKeys Debug ===
        phase=\(state.phase.rawValue) age=\(formatSeconds(state.phaseAge))
        capability=\(state.capability.rawValue)
        activeSession=\(state.activeSessionId?.uuidString ?? "nil")
        command=\(commandInfo)
        ack=\(ackInfo)
        result=\(resultInfo)
        error=\(errorInfo)
        appHeartbeatAge=\(appHeartbeatAge) keyboardHeartbeatAge=\(keyboardHeartbeatAge)
        bridgeReady=\(bridge.isAppReady()) bridgeRecording=\(bridge.isRecordingInProgress())
        fullAccess=\(hasFullAccess)
        """
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        "\(seconds.formatted(.number.precision(.fractionLength(1))))s"
    }

    private func publishKeyboardDebug(_ message: String) {
        guard keyboardDebugEnabled else { return }
        let snapshot = buildKeyboardDebugSnapshot()
        sharedStore.publishKeyboardDebug(message: message, snapshot: snapshot)
        log.info("Keyboard debug published: \(message)")
    }

    private func copyDebugSnapshotFromShift() {
        let snapshot = buildKeyboardDebugSnapshot()
        sharedStore.publishKeyboardDebug(message: "shiftDebugLongPress", snapshot: snapshot)
        if hasFullAccess {
            UIPasteboard.general.string = snapshot
            showStatus("Debug copied")
        } else {
            showStatus("Enable Full Access")
        }
    }

    /// Open Talkie app for keyboard mode control.
    /// - Disabled: activate
    /// - Enabled but not ready: reconnect/activate
    /// - Enabled and ready: deactivate
    @objc private func ledTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()

        let isModeEnabled = bridge.getKeyboardModeEnabled()
        let isReady = instantStartAvailable
        let urlString: String

        if !isModeEnabled {
            // Mode disabled - activate
            urlString = "talkie://keyboard/activate"
            log.info("LED tapped (mode disabled) - opening activate")
            showStatus("Connecting to Talkie...")
        } else if isReady {
            // Enabled and ready - deactivate
            urlString = "talkie://keyboard/deactivate"
            log.info("LED tapped (mode enabled + ready) - opening deactivate")
            showStatus("Disconnecting...")
        } else {
            // Enabled but not ready - reconnect
            urlString = "talkie://keyboard/activate"
            log.info("LED tapped (mode enabled + not ready) - opening activate")
            showStatus("Reconnecting...")
        }

        guard let url = URL(string: urlString) else { return }

        // Open Talkie app
        if let extensionContext = self.extensionContext {
            extensionContext.open(url) { [weak self] success in
                DispatchQueue.main.async {
                    if !success {
                        log.warning("Failed to open URL: \(urlString)")
                        self?.showStatus("Open Talkie to connect")
                    }
                }
            }
        }
    }

    @objc private func capitalizeTapped() {
        // Priority 1: Use our custom selection (from SELECT button)
        if let customText = selectedText, let range = selectedRange {
            transformAndReplaceSelection(customText, range: range)
            return
        }

        // Priority 2: Use native iOS selection (rare in keyboard extension)
        if let nativeSelected = textDocumentProxy.selectedText, !nativeSelected.isEmpty {
            let transformed = applyTransformStyle(to: nativeSelected)
            textDocumentProxy.insertText(transformed)
            log.info("Transformed native selection: '\(nativeSelected)' → '\(transformed)' (\(currentCapitalizeStyle.label))")
            currentCapitalizeStyle = currentCapitalizeStyle.next
            updateCapitalizeButtonLabel()
            return
        }

        // Priority 3: Transform word before cursor
        if let beforeText = textDocumentProxy.documentContextBeforeInput, !beforeText.isEmpty {
            let words = beforeText.components(separatedBy: .whitespacesAndNewlines)
            if let lastWord = words.last, !lastWord.isEmpty {
                for _ in 0..<lastWord.count {
                    textDocumentProxy.deleteBackward()
                }
                let transformed = applyTransformStyle(to: lastWord)
                textDocumentProxy.insertText(transformed)
                log.info("Transformed word: '\(lastWord)' → '\(transformed)' (\(currentCapitalizeStyle.label))")
            }
        }

        currentCapitalizeStyle = currentCapitalizeStyle.next
        updateCapitalizeButtonLabel()
    }

    /// Transform selected text and replace it in the document
    private func transformAndReplaceSelection(_ text: String, range: (before: Int, after: Int)) {
        let transformed = applyTransformStyle(to: text)

        // Move cursor forward past the "after" part, then delete all
        if range.after != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: range.after)
        }
        for _ in 0..<(range.before + range.after) {
            textDocumentProxy.deleteBackward()
        }

        // Insert transformed text
        textDocumentProxy.insertText(transformed)

        log.info("Transformed selection: '\(text)' → '\(transformed)' (\(currentCapitalizeStyle.label))")

        // Show feedback
        setStatusMessage(currentCapitalizeStyle.label.uppercased(), color: Design.ledReady)

        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()

        // Clear selection state and cycle style
        clearSelection()
        currentCapitalizeStyle = currentCapitalizeStyle.next
        updateCapitalizeButtonLabel()
    }

    /// Apply a specific transform style (can be called directly for menu actions)
    private func transformSelectionWith(style: CapitalizeStyle) {
        guard let text = selectedText, let range = selectedRange else {
            // No custom selection - transform word before cursor
            if let beforeText = textDocumentProxy.documentContextBeforeInput, !beforeText.isEmpty {
                let words = beforeText.components(separatedBy: .whitespacesAndNewlines)
                if let lastWord = words.last, !lastWord.isEmpty {
                    for _ in 0..<lastWord.count {
                        textDocumentProxy.deleteBackward()
                    }
                    let transformed = applyTransform(to: lastWord, style: style)
                    textDocumentProxy.insertText(transformed)
                    log.info("Quick transform word: '\(lastWord)' → '\(transformed)' (\(style.label))")
                }
            }
            return
        }

        let transformed = applyTransform(to: text, style: style)

        // Delete selected text
        if range.after != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: range.after)
        }
        for _ in 0..<(range.before + range.after) {
            textDocumentProxy.deleteBackward()
        }

        // Insert transformed text
        textDocumentProxy.insertText(transformed)

        log.info("Quick transform selection: '\(text)' → '\(transformed)' (\(style.label))")

        setStatusMessage(style.label.uppercased(), color: Design.ledReady)

        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()

        clearSelection()
    }

    /// Apply current transform style (used by cycle tap)
    private func applyTransformStyle(to text: String) -> String {
        applyTransform(to: text, style: currentCapitalizeStyle)
    }

    /// Apply a specific transform style
    private func applyTransform(to text: String, style: CapitalizeStyle) -> String {
        switch style {
        case .lowercase:
            return text.lowercased()

        case .capitalize:
            return text.capitalized

        case .uppercase:
            return text.uppercased()

        case .camelCase:
            let words = text.components(separatedBy: .whitespacesAndNewlines)
            var result = ""
            for (index, word) in words.enumerated() {
                if index == 0 {
                    result += word.lowercased()
                } else {
                    result += word.capitalized
                }
            }
            return result

        case .snakeCase:
            return text.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }

    private func updateCapitalizeButtonLabel() {
        // Find slot 6 button (Aa) and update its label
        guard let btn = slotButtons[6] else { return }

        // Update the label in the button's stack view
        for subview in btn.subviews {
            if let stack = subview as? UIStackView {
                for arranged in stack.arrangedSubviews {
                    if let label = arranged as? UILabel {
                        label.text = currentCapitalizeStyle.next.label
                    }
                }
            }
        }
    }

    // MARK: - DICTATE Button

    /// Create the DICTATE button (spans 2 slots in the grid, matches slot button style)
    private func createDictateButton() -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = Design.cornerRadius
        btn.clipsToBounds = false
        applyGridKeyRestingStyle(to: btn)
        attachGridKeyPressHandlers(to: btn)
        btn.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)

        self.recordButton = btn
        self.compactRecordButton = btn

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic.fill"))
        iconView.tintColor = Design.textPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let labelView = UILabel()
        labelView.text = "DICTATE"
        labelView.font = .systemFont(ofSize: 8, weight: .medium)
        labelView.textColor = Design.textSecondary

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(labelView)

        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])

        return btn
    }

    @objc private func deleteTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        if !consumeSelectionIfNeeded() {
            textDocumentProxy.deleteBackward()
        }
        updateDebugView()
    }

    @objc private func enterTapped() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText("\n")
        updateDebugView()
    }

    // Keep old createRecordButton for reference/updates
    private func createRecordButton() -> UIButton {
        let btn = UIButton(type: .system)
        btn.backgroundColor = Design.vermillion
        btn.layer.cornerRadius = Design.cornerRadius
        btn.clipsToBounds = false  // Allow glow to extend beyond bounds
        btn.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)

        // Store reference for later updates
        self.recordButton = btn

        // Horizontal layout for full-width button: icon + label
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic.fill"))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let labelView = UILabel()
        labelView.text = "DICTATE"
        labelView.font = .systemFont(ofSize: 14, weight: .bold)
        labelView.textColor = .white

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(labelView)

        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])

        // Apply raised glass effect after layout
        DispatchQueue.main.async { [weak self] in
            self?.applyGlassRaised(to: btn)
        }

        return btn
    }

    // MARK: - Actions

    @objc private func switchKeyboard() {
        log.info("Switching keyboard")
        advanceToNextInputMode()
    }

    @objc private func copyTapped() {
        log.info("Copy tapped")
        if selectedText != nil {
            copySelectedText()
        } else {
            showStatus("Select text first")
        }
    }

    @objc private func voiceEmojiTapped() {
        log.info("Voice emoji search tapped")

        // Set flag for emoji mode
        isVoiceEmojiMode = true

        // Tell the main app to hide its recording UI - we handle it
        bridge.setVoiceEmojiMode(true)

        // Show overlay (recording starts when user holds the button)
        showVoiceEmojiOverlay()

        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    private func showEmojiBrowserOverlay() {
        let categoryEntries = EmojiCategory.allCases.map { category in
            (title: category.displayName, emojis: EmojiRecognizer.shared.emojis(for: category))
        }

        let popular = Self.popularEmojiList()
        let recents = RecentEmojis.shared.all
        var featured: [(title: String, emojis: [String])] = []
        if !popular.isEmpty {
            featured.append(("Popular", popular))
        }
        if !recents.isEmpty {
            featured.append(("Recent", recents))
        }

        voiceEmojiOverlay?.showEmojiBrowser(
            allEmojis: Self.fullEmojiLibrary,
            categories: categoryEntries,
            featured: featured
        )
    }

    private func showVoiceEmojiOverlay() {
        // Remove any existing overlay
        voiceEmojiOverlay?.removeFromSuperview()

        // Create new overlay
        let overlay = VoiceEmojiOverlayView(frame: view.bounds)

        overlay.onDismiss = { [weak self] in
            self?.stopVoiceEmojiMode()
        }

        overlay.onEmojiSelected = { [weak self] emoji in
            self?.textDocumentProxy.insertText(emoji)
            self?.showStatus("Inserted \(emoji)")
            // Track as recent emoji
            RecentEmojis.shared.add(emoji)
        }

        overlay.onClearTranscript = { [weak self] in
            self?.voiceEmojiOverlay?.updateSuggestions([])
        }

        // Recording starts when user taps
        overlay.onRecordingStarted = { [weak self] in
            guard let self = self else { return }
            log.info("Voice emoji: user started recording (phase: \(self.currentPhase))")

            // Always force reset for clean slate - this ensures second recording works
            self.sharedStore.forceReset(reason: "Voice emoji new recording", preserveCapability: true, updatedBy: "keyboard")

            let sessionId = UUID()
            self.currentSessionId = sessionId
            _ = self.sharedStore.keyboardRequestStart(sessionId: sessionId)

            // Start recording through bridge
            self.bridge.requestStartRecording()

            // Start polling with small delay to let state settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startPolling()
            }
        }

        overlay.onRecordingStopped = { [weak self] in
            guard let self = self else { return }
            log.info("Voice emoji: recording stopped - requesting stop and waiting for result")
            self.bridge.requestStopRecording()
            if let sessionId = self.currentSessionId {
                _ = self.sharedStore.keyboardRequestStop(sessionId: sessionId)
            }

            // Directly poll for result since state machine may not be synced
            self.pollForVoiceEmojiResult()
        }

        overlay.onTimeout = { [weak self] in
            guard let self = self else { return }
            log.warning("Voice emoji: timeout - resetting state")
            self.bridge.requestStopRecording()
            self.sharedStore.forceReset(reason: "Voice emoji timeout", preserveCapability: true, updatedBy: "keyboard")
            self.currentSessionId = nil
        }

        overlay.onBrowse = { [weak self] in
            guard let self = self else { return }
            log.info("Voice emoji: browse tapped - showing in-overlay emoji browser")
            self.showEmojiBrowserOverlay()
        }

        // Show overlay - this auto-starts listening
        overlay.show(in: view)
        voiceEmojiOverlay = overlay
    }

    /// Directly poll bridge for voice emoji result, bypassing state machine
    private func pollForVoiceEmojiResult(attempts: Int = 0) {
        guard isVoiceEmojiMode, voiceEmojiOverlay != nil else {
            log.info("Voice emoji: poll cancelled - no longer in mode")
            return
        }

        // Check bridge directly for result
        if let result = bridge.getDictationResult(), !result.text.isEmpty {
            log.info("Voice emoji: got result from bridge: '\(result.text)'")
            // Clear the result so we don't re-process it
            bridge.clearDictationResult()
            // Update suggestions
            updateEmojiSuggestions(for: result.text)
            return
        }

        // Keep polling for up to 5 seconds (50 attempts * 100ms)
        if attempts < 50 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.pollForVoiceEmojiResult(attempts: attempts + 1)
            }
        } else {
            log.warning("Voice emoji: timeout waiting for result after 5s")
            voiceEmojiOverlay?.updateSuggestions([]) // Will show "No matches"
        }
    }

    private func stopVoiceEmojiMode() {
        log.info("Voice emoji: stopping mode")
        bridge.requestStopRecording()
        bridge.setVoiceEmojiMode(false)
        voiceEmojiOverlay = nil
        isVoiceEmojiMode = false
        stopPolling()

        // Force reset to clean slate
        sharedStore.forceReset(reason: "Voice emoji mode ended", preserveCapability: true, updatedBy: "keyboard")
        currentSessionId = nil
        showNormalUI()
    }

    /// Process transcription and update emoji suggestions
    private func updateEmojiSuggestions(for text: String) {
        guard !text.isEmpty else {
            log.info("Voice emoji: empty text, clearing suggestions")
            voiceEmojiOverlay?.updateSuggestions([])
            return
        }

        // Get top emoji matches (up to 16 for scrollable grid)
        let matches = EmojiRecognizer.shared.topMatches(text, limit: 16)
        log.info("Voice emoji: '\(text)' -> \(matches.count) matches: \(matches.prefix(8).map { $0.emoji }.joined())")

        voiceEmojiOverlay?.updateTranscript(text)
        voiceEmojiOverlay?.updateSuggestions(matches)
    }

    private func updateVoiceEmojiOverlayAudioLevel(_ level: Float) {
        voiceEmojiOverlay?.audioLevel = level
    }

    @objc private func recordTapped() {
        let snap = sharedStore.snapshot()
        let phase = snap.phase
        let phaseAge = snap.phaseAge
        let sessionId = snap.activeSessionId ?? currentSessionId

        publishKeyboardDebug("recordTapped phase=\(phase.rawValue)")

        if snap.isCoolingDown() {
            showStatus("Try again in a moment")
            return
        }

        switch phase {
        case .recording, .stopping:
            // If already stopping, tapping again sends cancel (abort transcription)
            if phase == .stopping {
                if phaseAge > 5.0 {
                    log.warning("Stop timeout - forcing reset")
                    sharedStore.forceReset(reason: "Stop timeout after 5s", preserveCapability: true, updatedBy: "keyboard")
                    bridge.forceReset()
                    currentSessionId = nil
                    showNormalUI()
                    showStatus("Reset - try again")
                    return
                }
                // Cancel the in-flight stop+transcribe
                publishKeyboardDebug("cancelRequested (from stopping) session=\(sessionId?.uuidString ?? "nil")")
                if let sessionId {
                    _ = sharedStore.keyboardRequestCancel(sessionId: sessionId)
                }
                showStatus("Cancelled")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.showNormalUI()
                }
                return
            }

            if phase == .recording && phaseAge > 15.0 {
                log.warning("Recording stuck for \(Int(phaseAge))s - forcing reset")
                sharedStore.forceReset(reason: "Recording stuck - user requested escape", preserveCapability: true, updatedBy: "keyboard")
                bridge.forceReset()
                currentSessionId = nil
                showNormalUI()
                showStatus("Reset - try again")
                return
            }

            publishKeyboardDebug("stopRequested session=\(sessionId?.uuidString ?? "nil")")
            if let sessionId {
                _ = sharedStore.keyboardRequestStop(sessionId: sessionId)
            }
            bridge.requestStopRecording()
            showStatus("Stopping...")
            return

        case .arming:
            // Waiting for app
            if bridge.isRecordingInProgress() && isAppHeartbeatFresh(maxAge: 1.5) && phaseAge < 3.0 {
                log.info("recordTapped: Bridge shows recording - treating as STOP request")
                if let sessionId {
                    _ = sharedStore.keyboardRequestStop(sessionId: sessionId)
                }
                bridge.requestStopRecording()
                showStatus("Stopping...")
                showRecordingUI()
                startPolling()
                return
            }

            if phaseAge > 10.0 {
                log.warning("App launch timeout - forcing reset")
                sharedStore.forceReset(reason: "App launch timeout after 10s", preserveCapability: true, updatedBy: "keyboard")
                currentSessionId = nil
                showNormalUI()
                showStatus("Timeout - try again")
            } else {
                showStatus("Opening Talkie...")
            }
            return

        case .transcribing:
            // Cancel transcription — user tapped record button while transcribing
            publishKeyboardDebug("cancelRequested session=\(sessionId?.uuidString ?? "nil")")
            if let sessionId {
                _ = sharedStore.keyboardRequestCancel(sessionId: sessionId)
            }
            showStatus("Cancelled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showNormalUI()
            }
            return

        case .done, .error:
            checkForDictationResult()
            return

        case .idle, .ready:
            if bridge.isRecordingInProgress() {
                log.warning("recordTapped: Ignoring stale bridge recording flag in idle state")
                bridge.setRecordingInProgress(false)
            }
            if !isVoiceCommandMode {
                activeCaptureMode = .dictation
            }
        }

        // START DICTATING
        dictationTrace = PerfTrace("dictation.flow")
        dictationTrace?.begin()

        let newSessionId = UUID()
        currentSessionId = newSessionId
        didAttemptDeepLinkFallback = false

        publishKeyboardDebug("startRequested session=\(newSessionId)")
        _ = sharedStore.keyboardRequestStart(sessionId: newSessionId)
        dictationTrace?.event("state_requested")

        if instantStartAvailable {
            log.info("Instant start - app ready, no URL needed")
            dictationTrace?.event("instant_start")
            bridge.requestStartRecording()
            dictationTrace?.event("recording_started")
            showRecordingUI()
            checkReadyState()
            startPolling()
        } else {
            log.info("App launch required")
            dictationTrace?.event("app_launch_required")
            showStatus("Opening Talkie...")
            checkReadyState()
            startPolling()

            guard let url = URL(string: "talkie://dictate") else {
                log.error("Failed to create dictate URL")
                sharedStore.forceReset(reason: "Invalid URL", preserveCapability: true, updatedBy: "keyboard")
                dictationTrace?.end(message: "error_invalid_url")
                dictationTrace = nil
                showNormalUI()
                return
            }
            dictationTrace?.event("opening_url")
            openURL(url)
        }
    }

    /// Open a URL from the keyboard extension
    /// Requires "Allow Full Access" to be enabled in Settings
    @objc private func openURL(_ url: URL) {
        guard hasFullAccess else {
            log.warning("Cannot open URL - Full Access not granted")
            showStatus("Enable Full Access")
            return
        }

        // Get UIApplication.shared via Objective-C runtime
        // This works in keyboard extensions when Full Access is enabled
        guard let app = Self.getSharedApplication() else {
            log.warning("Could not access UIApplication")
            showStatus("Could not open app")
            return
        }

        app.open(url, options: [:]) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    log.info("URL opened successfully")
                } else {
                    log.warning("URL open failed")
                    self?.showStatus("Could not open app")
                }
            }
        }
    }

    /// Access UIApplication.shared from keyboard extension context
    private static func getSharedApplication() -> UIApplication? {
        // Use Objective-C runtime to get UIApplication.sharedApplication
        // This works when the keyboard has Full Access enabled
        let sharedAppSelector = NSSelectorFromString("sharedApplication")

        // UIApplication class as an object that can receive selectors
        guard let uiApplicationClass = NSClassFromString("UIApplication") else {
            return nil
        }

        // Check if the class responds to sharedApplication
        let responds = (uiApplicationClass as AnyObject).responds(to: sharedAppSelector)
        guard responds else {
            return nil
        }

        // Call the class method
        let result = (uiApplicationClass as AnyObject).perform(sharedAppSelector)
        return result?.takeUnretainedValue() as? UIApplication
    }

    // MARK: - Dictation Result Handling

    private func checkForDictationResult() {
        if let result = sharedStore.lastResult {
            let text = result.text
            log.info("Found dictation result: \(text.count) chars (attempt \(resultInsertionRetryCount + 1))")
            publishKeyboardDebug("resultReceived session=\(result.sessionId) chars=\(text.count)")

            dictationTrace?.event("result_received")
            dictationTrace?.end(message: "text_\(text.count)_chars")

            if isVoiceEmojiMode, let overlay = voiceEmojiOverlay {
                overlay.didReceiveTranscription()
                updateEmojiSuggestions(for: text)
                sharedStore.keyboardConsumeResult(sessionId: result.sessionId)
                bridge.clearDictationResult()
                resultInsertionRetryCount = 0
                return
            }

            if activeCaptureMode == .voiceCommand {
                handleVoiceCommandResult(text, sessionId: result.sessionId)
                resultInsertionRetryCount = 0
                return
            }

            let textBefore = textDocumentProxy.documentContextBeforeInput ?? ""
            let needsSpace = !textBefore.isEmpty && !textBefore.hasSuffix(" ") && !textBefore.hasSuffix("\n")

            let textToInsert = needsSpace ? " \(text)" : text
            insertTextReliably(textToInsert)

            // Verify insertion succeeded — textDocumentProxy can silently fail
            // when the host app's text field is disconnected (e.g. right after app switch)
            let contextAfter = textDocumentProxy.documentContextBeforeInput
            let insertionLikelyFailed = contextAfter == nil && !text.isEmpty

            if insertionLikelyFailed && resultInsertionRetryCount < maxResultInsertionRetries {
                resultInsertionRetryCount += 1
                log.warning("Text insertion may have failed (attempt \(resultInsertionRetryCount)/\(maxResultInsertionRetries)) — deferring consumption")
                publishKeyboardDebug("insertRetry attempt=\(resultInsertionRetryCount) chars=\(text.count)")
                // Don't consume — let the next poll/check retry
                return
            }

            if insertionLikelyFailed {
                log.error("Text insertion failed after \(maxResultInsertionRetries) attempts — consuming result to avoid stall")
                publishKeyboardDebug("insertFailed chars=\(text.count)")
            } else {
                publishKeyboardDebug("insertOK chars=\(text.count)")
            }

            resultInsertionRetryCount = 0
            sharedStore.keyboardConsumeResult(sessionId: result.sessionId)
            bridge.clearDictationResult()
            currentSessionId = nil

            // Success flash on minimal keyboard, then restore normal UI
            if isMinimalLayoutActive {
                minimalKeyboardView?.showSuccessFlash()
            } else {
                showNormalUI()
            }
            updateDebugView()

            if !insertionLikelyFailed {
                let wordCount = text.split(separator: " ").count
                showStatus("Inserted \(wordCount) words")
            } else {
                showStatus("Text may not have inserted")
            }
            return
        }

        if let error = sharedStore.lastError {
            log.warning("Dictation error: \(error.message)")
            publishKeyboardDebug("errorReceived session=\(error.sessionId?.uuidString ?? "nil") msg=\(error.message)")
            showStatus(error.message)
            showNormalUI()
            isVoiceEmojiMode = false
            sharedStore.keyboardConsumeError(sessionId: error.sessionId)
            bridge.clearDictationResult()
            currentSessionId = nil
            return
        }

        // Phase is done/error but result/error not yet visible — cross-process race.
        // Bump retry counter so polling continues instead of stopping.
        let phase = sharedStore.phase
        if phase == .done || phase == .error {
            resultInsertionRetryCount += 1
            log.warning("Phase is \(phase.rawValue) but no result/error yet (race retry \(resultInsertionRetryCount))")
            publishKeyboardDebug("resultRaceRetry attempt=\(resultInsertionRetryCount)")
            if resultInsertionRetryCount >= maxResultInsertionRetries {
                log.error("Result never arrived after \(maxResultInsertionRetries) retries — resetting")
                publishKeyboardDebug("resultRaceGaveUp")
                resultInsertionRetryCount = 0
                sharedStore.forceReset(reason: "Result race timeout", preserveCapability: true, updatedBy: "keyboard")
                showStatus("Error - try again")
                showNormalUI()
            }
            return
        }

        log.info("No result available yet")
    }

    /// Handle voice emoji search result - update suggestions in overlay
    private func handleVoiceEmojiResult(_ text: String) {
        log.info("Voice emoji search for: '\(text)'")
        updateEmojiSuggestions(for: text)
    }

    private enum VoiceCommandIntent {
        case copy
        case cut
        case delete
        case summarize
        case bullets
        case topics
        case selectWord
        case selectSentence
        case selectParagraph
        case selectAll
        case pasteLocal
        case pasteSystem
        case clearSelection
        case dismissPanel
        case unknown
    }

    private static let voiceCommandPhraseMap: [(intent: VoiceCommandIntent, phrases: [String])] = [
        (.pasteSystem, ["paste system", "paste universal", "paste global", "paste from mac", "paste remote"]),
        (.pasteLocal, ["paste", "insert clipboard", "paste here"]),
        (.copy, ["copy", "copy this", "copy selected", "duplicate selection"]),
        (.cut, ["cut", "cut this", "cut selected"]),
        (.delete, ["delete", "remove", "erase", "backspace"]),
        (.summarize, ["summarize", "make summary", "tl dr", "short summary", "brief this"]),
        (.bullets, ["bullets", "make bullets", "bullet list", "list this", "make list"]),
        (.topics, ["topics", "extract topics", "key topics", "keywords", "tags"]),
        (.selectAll, ["select all", "highlight all", "grab all"]),
        (.selectParagraph, ["select paragraph", "highlight paragraph", "paragraph"]),
        (.selectSentence, ["select sentence", "highlight sentence", "sentence"]),
        (.selectWord, ["select word", "highlight word", "word"]),
        (.clearSelection, ["clear selection", "clear", "unselect", "cancel selection"]),
        (.dismissPanel, ["dismiss", "close", "escape", "hide panel"])
    ]

    private func handleVoiceCommandResult(_ text: String, sessionId: UUID) {
        let intent = parseVoiceCommand(text)
        executeVoiceCommand(intent)
        sharedStore.keyboardConsumeResult(sessionId: sessionId)
        bridge.clearDictationResult()
        currentSessionId = nil
        showNormalUI()

        // Keep command mode conversational: auto-arm next listen cycle.
        if isVoiceCommandMode {
            pendingVoiceCommandStart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                self?.startVoiceCommandListeningIfPossible()
            }
        } else {
            activeCaptureMode = .dictation
        }
    }

    private func parseVoiceCommand(_ raw: String) -> VoiceCommandIntent {
        let normalized = normalizeVoiceCommandText(raw)
        guard !normalized.isEmpty else { return .unknown }

        // 1) Exact phrase table hit.
        for entry in Self.voiceCommandPhraseMap {
            if entry.phrases.contains(normalized) {
                return entry.intent
            }
        }

        // 2) Contains phrase (strong signal for natural speech wrappers).
        for entry in Self.voiceCommandPhraseMap {
            if entry.phrases.contains(where: { containsPhraseAsWholeWords($0, in: normalized) }) {
                return entry.intent
            }
        }

        // 3) Token overlap scoring (emoji-style alias heuristics).
        let inputTokens = Set(normalized.split(separator: " ").map(String.init))
        var bestIntent: VoiceCommandIntent = .unknown
        var bestScore: Double = 0

        for entry in Self.voiceCommandPhraseMap {
            for phrase in entry.phrases {
                let phraseTokens = phrase.split(separator: " ").map(String.init)
                guard !phraseTokens.isEmpty else { continue }
                let phraseTokenSet = Set(phraseTokens)
                let overlap = inputTokens.intersection(phraseTokenSet).count
                guard overlap > 0 else { continue }

                var score = Double(overlap) / Double(phraseTokens.count)
                if let first = phraseTokens.first, inputTokens.contains(first) {
                    score += 0.12
                }
                if normalized.hasPrefix(phrase) {
                    score += 0.10
                }
                if score > bestScore {
                    bestScore = score
                    bestIntent = entry.intent
                }
            }
        }

        return bestScore >= 0.52 ? bestIntent : .unknown
    }

    private func normalizeVoiceCommandText(_ raw: String) -> String {
        let lowered = raw.lowercased().replacing("-", with: " ")
        let sanitized = lowered.map { char -> Character in
            (char.isLetter || char.isNumber || char.isWhitespace) ? char : " "
        }
        return String(sanitized)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsPhraseAsWholeWords(_ phrase: String, in normalizedInput: String) -> Bool {
        guard !phrase.isEmpty, !normalizedInput.isEmpty else { return false }
        let haystack = " \(normalizedInput) "
        let needle = " \(phrase) "
        return haystack.contains(needle)
    }

    private func executeVoiceCommand(_ intent: VoiceCommandIntent) {
        switch intent {
        case .copy:
            if selectedText == nil { selectNearestWord() }
            copySelectedText()
            showStatus("Cmd: copy")
        case .cut:
            if selectedText == nil { selectNearestWord() }
            cutSelectedText()
            showStatus("Cmd: cut")
        case .delete:
            if selectedText == nil { selectNearestWord() }
            deleteSelectedText()
            showStatus("Cmd: delete")
        case .summarize:
            runSmartTransform(.summary)
            showStatus("Cmd: summary")
        case .bullets:
            runSmartTransform(.bullets)
            showStatus("Cmd: bullets")
        case .topics:
            runSmartTransform(.topics)
            showStatus("Cmd: topics")
        case .selectWord:
            selectNearestWord()
            showStatus("Cmd: select word")
        case .selectSentence:
            selectSentenceText()
            showStatus("Cmd: select sentence")
        case .selectParagraph:
            selectParagraphText()
            showStatus("Cmd: select paragraph")
        case .selectAll:
            selectAllText()
            showStatus("Cmd: select all")
        case .pasteLocal:
            if pasteFromLocalClipboardIfAvailable() || pasteFromSystemClipboard() {
                showStatus("Cmd: paste")
            } else {
                showStatus("Cmd: clipboard empty")
            }
        case .pasteSystem:
            if pasteFromSystemClipboard() {
                showStatus("Cmd: paste system")
            } else {
                showStatus("Cmd: system clipboard empty")
            }
        case .clearSelection:
            clearSelection()
            showStatus("Cmd: clear")
        case .dismissPanel:
            dismissStatusActionOverlay(animated: true)
            showStatus("Cmd: dismiss")
        case .unknown:
            showStatus("Cmd: not recognized")
        }
    }

    private enum SmartTransformKind {
        case summary
        case bullets
        case topics
    }

    private func runSmartTransform(_ kind: SmartTransformKind) {
        guard ensureSelectionForSmartTransform() else { return }
        guard let source = selectedText, let range = selectedRange else {
            showStatus("No text selected")
            return
        }
        let normalized = normalizedSmartText(source)
        guard !normalized.isEmpty else {
            showStatus("No text selected")
            return
        }
        guard canRunSmartTransformInKeyboard(inputCharacterCount: normalized.count) else {
            setStatusMessage("AI moved to app (memory)", color: Design.textPrimary)
            showStatus("Open Talkie app for AI transform")
            return
        }

        guard isAppleIntelligenceAvailable() else {
            let reason = appleIntelligenceAvailabilityDescription()
            setStatusMessage("AI unavailable in keyboard", color: Design.textPrimary)
            showStatus("AI unavailable: \(reason)")
            return
        }

        setStatusMessage("AI: processing...", color: Design.textPrimary)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let transformed = try await self.generateAppleSmartTransform(kind: kind, source: normalized)
                let cleaned = transformed.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else {
                    self.showStatus("AI returned empty result")
                    return
                }

                self.replaceSelectedRange(range, with: cleaned)
                self.selectedText = cleaned
                self.selectedRange = (before: cleaned.count, after: 0)
                self.showSelectedTextUI(cleaned, scope: "Smart")
                self.showStatus("AI applied in place")
            } catch {
                log.warning("Apple AI transform failed: \(error)")
                self.showStatus("AI failed in keyboard")
            }
        }
    }

    private func ensureSelectionForSmartTransform() -> Bool {
        if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        selectSentenceText()
        if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        selectParagraphText()
        return selectedText != nil
    }

    private func replaceSelectedRange(_ range: (before: Int, after: Int), with transformed: String) {
        if range.after != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: range.after)
        }
        for _ in 0..<(range.before + range.after) {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(transformed)
    }

    private func canRunSmartTransformInKeyboard(inputCharacterCount: Int) -> Bool {
        if let lastWarning = lastAIMemoryWarningAt,
           Date().timeIntervalSince(lastWarning) < aiMemoryWarningCooldown {
            log.warning("Skipping AI transform: recent memory warning")
            return false
        }

        guard let residentBytes = currentResidentMemoryBytes() else {
            return true
        }
        if residentBytes >= aiKeyboardResidentMemorySoftLimitBytes {
            let residentMB = Double(residentBytes) / (1_024.0 * 1_024.0)
            log.warning("Skipping AI transform at resident memory \(residentMB.formatted(.number.precision(.fractionLength(1))))MB")
            return false
        }

        // Add extra guardrail for larger prompts near the soft limit.
        let nearLimitBytes = aiKeyboardResidentMemorySoftLimitBytes - (6 * 1_024 * 1_024)
        if inputCharacterCount > 2_000, residentBytes >= nearLimitBytes {
            log.warning("Skipping AI transform: large input under elevated memory pressure")
            return false
        }

        return true
    }

    private func currentResidentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }

    private func isAppleIntelligenceAvailable() -> Bool {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        case .unavailable:
            return false
        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }

    private func appleIntelligenceAvailabilityDescription() -> String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return String(describing: reason)
        @unknown default:
            return "unknown"
        }
        #else
        return "framework missing"
        #endif
    }

    private func appleAIEligibilityDescription() -> String {
        let raw = appleIntelligenceAvailabilityDescription().lowercased()
        if raw == "available" {
            return "eligible"
        }
        if raw.contains("device") || raw.contains("eligible") {
            return "device not eligible"
        }
        return "not eligible (\(appleIntelligenceAvailabilityDescription()))"
    }

    private func actionModeTitleText() -> String {
        let modeTitle = isActionPanelInSmartMenu ? "Action Mode > Smart" : "Action Mode"
        return isAppleIntelligenceAvailable() ? "\(modeTitle) • AI ready" : "\(modeTitle) • AI unavailable"
    }

    private func generateAppleSmartTransform(kind: SmartTransformKind, source: String) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt: String
        switch kind {
        case .summary:
            prompt = """
            Summarize the following text in 1-2 concise sentences.
            Keep key meaning and decisions.
            Return only the summary text.

            Text:
            \(source.prefix(5000))
            """
        case .bullets:
            prompt = """
            Convert the following text into a compact bullet list.
            Use one idea per bullet. Return only bullet points.

            Text:
            \(source.prefix(5000))
            """
        case .topics:
            prompt = """
            Extract the top topics from the following text.
            Return 3-6 hashtag-style tokens on one line (example: #design #release #testing).
            Return only the topics line.

            Text:
            \(source.prefix(5000))
            """
        }
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw NSError(domain: "TalkieKeys.AI", code: 2)
        #endif
    }

    private func normalizedSmartText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func showStatus(_ message: String) {
        setStatusMessage(message, color: Design.textSecondary)
        appendDiagnosticsEvent(message)

        // Reset after delay (unless we're in an active state)
        let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .arming]
        guard !activePhases.contains(currentPhase) else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            let stillActive = activePhases.contains(self.currentPhase)
            if !stillActive {
                self.clearStatusMessage()
            }
        }
    }

    private func appendDiagnosticsEvent(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stamp = Date().formatted(date: .omitted, time: .standard).replacingOccurrences(of: " ", with: "_")
        let sanitized = trimmed.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "=", with: ":")
        diagnosticsEvents.append("event_at: \(stamp), event: \(sanitized)")
        if diagnosticsEvents.count > maxDiagnosticsEvents {
            diagnosticsEvents.removeFirst(diagnosticsEvents.count - maxDiagnosticsEvents)
        }
        statusActionPreviewLabel?.text = actionModePreviewText()
    }

    // MARK: - State-Based UI Updates

    /// Clean up stale flags from previous sessions
    private func cleanupStaleState() {
        let state = sharedStore.snapshot()
        let phase = state.phase
        let phaseAge = state.phaseAge

        // If phase is idle/done/error but bridge has stale flags, clear them
        if phase == .idle || phase == .done || phase == .error {
            // Check for stale flags
            let hasStaleStop = bridge.isStopRequested()
            let hasStaleStart = bridge.isStartRequested()
            let hasStaleRecording = bridge.isRecordingInProgress()

            if hasStaleStop || hasStaleStart || hasStaleRecording {
                log.warning("Cleaning up stale bridge state: stop=\(hasStaleStop), start=\(hasStaleStart), recording=\(hasStaleRecording)")
                bridge.clearStopRequest()
                bridge.clearStartRequest()
                if hasStaleRecording {
                    bridge.setRecordingInProgress(false)
                }
            }
        }

        // Check for stuck states - more aggressive timeout (30s instead of 60s)
        // Users find it very frustrating when the keyboard appears stuck
        if phaseAge > 30 {
            let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .arming]
            if activePhases.contains(phase) {
                log.warning("Phase \(phase) stuck for \(Int(phaseAge))s - forcing reset")
                sharedStore.forceReset(reason: "Keyboard detected stale active phase", preserveCapability: true, updatedBy: "keyboard")
                bridge.forceReset()
                currentSessionId = nil
            }
        }

        // Extra aggressive: if bridge says recording but state machine is idle, clear it
        if phase == .idle && bridge.isRecordingInProgress() {
            log.warning("Bridge says recording but state is idle - clearing stale recording flag")
            bridge.setRecordingInProgress(false)
        }
    }

    private func checkRecordingState() {
        let state = sharedStore.snapshot()
        let phase = state.phase
        if currentSessionId == nil {
            currentSessionId = state.activeSessionId
        }
        log.info("Dictation phase: \(phase)")

        switch phase {
        case .recording:
            log.info("Recording in progress - showing STOP state")
            showRecordingUI()
            startPolling()

        case .stopping:
            log.info("Stopping recording...")
            showStatus("Stopping...")
            updateLEDState()
            startPolling()

        case .done, .error:
            log.info("Result/error ready - consuming")
            checkForDictationResult()

        case .transcribing:
            showStatus("Transcribing...")
            updateLEDState()
            startPolling()

        case .arming:
            if bridge.isRecordingInProgress() {
                log.info("checkRecordingState: Bridge shows recording started - syncing local state")
                showRecordingUI()
                startPolling()
            } else {
                showStatus("Opening Talkie...")
                updateLEDState()
                startPolling()
            }

        case .idle, .ready:
            if bridge.isRecordingInProgress() {
                log.info("checkRecordingState: Bridge shows recording in progress - syncing state")
                showRecordingUI()
                startPolling()
            } else {
                showNormalUI()
                if pendingVoiceCommandStart && isVoiceCommandMode {
                    startVoiceCommandListeningIfPossible()
                }
            }
        }

        // Always call checkReadyState to sync button/LED state
        checkReadyState()
    }

    private func showRecordingUI() {
        // Skip if voice emoji overlay is showing - it handles its own UI
        if isVoiceEmojiMode && voiceEmojiOverlay != nil {
            return
        }

        // Update status label
        if activeCaptureMode == .voiceCommand {
            setStatusMessage("● CMD LISTENING", color: Design.ledReady)
        } else {
            setStatusMessage("● DICTATING", color: Design.vermillion)
        }

        // Update record button to STOP
        updateRecordButtonToStop()

        // Update LED
        updateLEDState()

        // Stop processing animation if it was running (recording restarted)
        // Start recording feedback (timer + pulse) on minimal keyboard
        if isMinimalLayoutActive {
            minimalKeyboardView?.stopProcessingAnimation()
            minimalKeyboardView?.startRecordingFeedback()
        }
    }

    /// Show processing/transcribing state — waveform animation on minimal keyboard
    private func showProcessingUI() {
        let isModelWarm = bridge.isModelWarm()
        if activeCaptureMode == .voiceCommand {
            setStatusMessage(isModelWarm ? "Interpreting cmd..." : "Warming cmd...", color: Design.ledReady)
        } else {
            setStatusMessage(isModelWarm ? "Transcribing..." : "Warming up AI...", color: Design.vermillion)
        }

        if isMinimalLayoutActive {
            minimalKeyboardView?.stopRecordingFeedback()
            minimalKeyboardView?.startProcessingAnimation()
        }
    }

    private func showNormalUI() {
        // Skip if voice emoji overlay is showing - it handles its own UI
        if isVoiceEmojiMode && voiceEmojiOverlay != nil {
            return
        }

        clearStatusMessage()
        updateRecordButtonToRecord()
        checkReadyState()  // This will update LED and record button state

        // Stop all minimal keyboard animations
        if isMinimalLayoutActive {
            minimalKeyboardView?.stopProcessingAnimation()
            minimalKeyboardView?.stopRecordingFeedback()
        }
    }

    private func updateRecordButtonToStop() {
        guard let button = recordButton else { return }

        // Clear existing subviews
        button.subviews.forEach { $0.removeFromSuperview() }
        removeGlassEffects(from: button)
        applyGridKeyRestingStyle(to: button)

        // Vertical layout for integrated style (icon above label)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic.fill"))
        iconView.tintColor = Design.textPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let labelView = UILabel()
        labelView.text = "STOP"
        labelView.font = .systemFont(ofSize: 8, weight: .medium)  // Integrated style
        labelView.textColor = Design.textSecondary

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(labelView)

        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    private func updateRecordButtonToRecord() {
        guard let button = recordButton else { return }

        // Clear existing subviews
        button.subviews.forEach { $0.removeFromSuperview() }
        removeGlassEffects(from: button)
        applyGridKeyRestingStyle(to: button)

        // Vertical layout for integrated style (icon above label)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic.fill"))
        iconView.tintColor = Design.textPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let labelView = UILabel()
        labelView.text = "DICTATE"
        labelView.font = .systemFont(ofSize: 8, weight: .medium)  // Smaller, integrated style
        labelView.textColor = Design.textSecondary  // Secondary text color

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(labelView)

        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        // No glass effect for integrated style - keeps it subtle
    }

    private func updateRecordButtonState() {
        guard let button = recordButton else { return }

        if isMinimalLayoutActive {
            // Minimal layout: use mic color as status indicator (no alpha change)
            button.alpha = 1.0
            button.isUserInteractionEnabled = true
            minimalKeyboardView?.updateReadyState(isRecordReady, modelWarm: bridge.isModelWarm())
        } else {
            // Compact layout: dim button when not ready
            if isRecordReady {
                button.alpha = 1.0
                button.isUserInteractionEnabled = true
            } else {
                button.alpha = 0.5
                button.isUserInteractionEnabled = false
            }
        }
    }

    // MARK: - Liquid Glass Effects

    /// Apply raised "3D" glass effect to a button (default state)
    private func applyGlassRaised(to button: UIButton) {
        // Remove any existing effects
        removeGlassEffects(from: button)

        // Very subtle top highlight gradient - matte style
        let highlight = CAGradientLayer()
        highlight.colors = [
            Design.glassHighlight.cgColor,
            UIColor.clear.cgColor
        ]
        highlight.locations = [0.0, 0.2]  // Shorter gradient for matte look
        highlight.frame = button.bounds
        highlight.cornerRadius = Design.cornerRadius
        button.layer.insertSublayer(highlight, at: 0)
        glassHighlightLayer = highlight

        // Subtle bottom shadow (border effect)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 1
        button.layer.shadowOpacity = 0.12  // Reduced for matte look

        // Very subtle top border
        button.layer.borderWidth = 0.33
        button.layer.borderColor = Design.glassHighlight.cgColor
    }

    /// Apply pressed "recessed" glass effect (recording state)
    private func applyGlassPressed(to button: UIButton) {
        // Remove any existing effects
        removeGlassEffects(from: button)

        // Inner shadow effect (dark at top, fading down)
        let innerShadow = CAGradientLayer()
        innerShadow.colors = [
            Design.glassInnerShadow.cgColor,
            UIColor.clear.cgColor
        ]
        innerShadow.locations = [0.0, 0.4]
        innerShadow.frame = button.bounds
        innerShadow.cornerRadius = Design.cornerRadius
        button.layer.insertSublayer(innerShadow, at: 0)
        glassInnerShadowLayer = innerShadow

        // Remove outer shadow (pressed in)
        button.layer.shadowOpacity = 0

        // Darker border for pressed look
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(white: 0.0, alpha: 0.3).cgColor

        // Add pulsing glow around button
        addRecordingGlow(to: button)
    }

    /// Add pulsing glow effect for recording state
    private func addRecordingGlow(to button: UIButton) {
        // Create glow layer
        let glow = CALayer()
        glow.frame = button.bounds.insetBy(dx: -4, dy: -4)
        glow.cornerRadius = Design.cornerRadius + 2
        glow.backgroundColor = UIColor.clear.cgColor
        glow.shadowColor = Design.vermillion.cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = 8
        glow.shadowOpacity = 0.6

        // Insert behind button content
        button.layer.insertSublayer(glow, at: 0)
        glassGlowLayer = glow

        // Pulse animation
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = 0.6
        pulse.toValue = 0.2
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "pulse")
        pulseAnimation = pulse
    }

    /// Remove all glass effects from button
    private func removeGlassEffects(from button: UIButton) {
        glassHighlightLayer?.removeFromSuperlayer()
        glassHighlightLayer = nil

        glassInnerShadowLayer?.removeFromSuperlayer()
        glassInnerShadowLayer = nil

        glassGlowLayer?.removeAllAnimations()
        glassGlowLayer?.removeFromSuperlayer()
        glassGlowLayer = nil

        button.layer.shadowOpacity = 0
        button.layer.borderWidth = 0
    }

    /// Update glass effects when button bounds change
    private func updateGlassFrames() {
        guard let button = recordButton else { return }

        glassHighlightLayer?.frame = button.bounds
        glassInnerShadowLayer?.frame = button.bounds
        glassGlowLayer?.frame = button.bounds.insetBy(dx: -4, dy: -4)
    }

    private func updateLEDState() {
        let phase = currentPhase

        // Update activity bar shimmer based on state
        let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .arming]
        if activePhases.contains(phase) {
            startActivityShimmer(for: phase)
        } else {
            stopActivityShimmer()
        }

        // Update compact keyboard spacebar dictation indicator
        if phase == .recording {
            compactKeyboardView?.setDictationState(.recording)
        } else if [.stopping, .transcribing, .arming].contains(phase) {
            compactKeyboardView?.setDictationState(.processing)
        } else {
            compactKeyboardView?.setDictationState(.idle)
        }
    }

    // MARK: - Activity Bar Shimmer

    private func startActivityShimmer(for phase: DictationSharedState.Phase) {
        guard activityBar != nil else { return }

        // Remove existing shimmer
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil

        // Defer to next run loop to ensure bar has proper bounds
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let bar = self.activityBar else { return }

            // Use screen width as fallback if bar bounds not ready
            let screenWidth = self.view.window?.windowScene?.screen.bounds.width ?? 400
            let barWidth = bar.bounds.width > 0 ? bar.bounds.width : screenWidth

            // Create gradient layer for shimmer effect
            let gradient = CAGradientLayer()
            gradient.frame = CGRect(x: 0, y: 0, width: barWidth * 2, height: Design.activityBarHeight)

            // Color based on state - red only during recording, subtle gray otherwise
            let shimmerColor: UIColor
            switch phase {
            case .recording:
                shimmerColor = Design.vermillion
            case .arming, .stopping, .transcribing:
                // Subtle off-black gray for processing states
                shimmerColor = UIColor(white: 0.25, alpha: 1.0)
            default:
                shimmerColor = UIColor(white: 0.2, alpha: 1.0)
            }

            // Gradient: transparent -> color -> transparent
            gradient.colors = [
                UIColor.clear.cgColor,
                shimmerColor.withAlphaComponent(0.6).cgColor,
                shimmerColor.cgColor,
                shimmerColor.withAlphaComponent(0.6).cgColor,
                UIColor.clear.cgColor
            ]
            gradient.locations = [0.0, 0.35, 0.5, 0.65, 1.0]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)

            bar.layer.addSublayer(gradient)
            self.shimmerLayer = gradient

            // Animate the shimmer across the bar
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = -barWidth / 2
            animation.toValue = barWidth * 1.5
            animation.duration = phase == .recording ? 1.2 : 1.8  // Faster during recording
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            gradient.add(animation, forKey: "shimmer")
        }
    }

    private func stopActivityShimmer() {
        shimmerLayer?.removeAllAnimations()
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil
    }

    /// Check if app is ready and enable record button
    /// Record button is enabled in idle/ready/done states (can start recording)
    /// and in recording state (can stop). Disabled only during processing.
    private func checkReadyState() {
        let phase = currentPhase

        // Enable button in states where user can take action
        switch phase {
        case .idle, .ready, .done, .error, .recording:
            isRecordReady = true
        case .arming, .stopping, .transcribing:
            isRecordReady = false
        }

        // Log ready state for instant start
        let instantReady = instantStartAvailable
        if instantReady {
            log.info("Instant start available - app ready in background")
        }

        updateLEDState()
    }

    private var pollCount = 0

    private func shouldPoll(for state: DictationSnapshot) -> Bool {
        if state.command != nil {
            return true
        }
        switch state.phase {
        case .arming, .recording, .stopping, .transcribing, .done, .error:
            return true
        case .idle, .ready:
            return isVoiceEmojiMode
        }
    }

    private func handleStateSignal() {
        let state = sharedStore.snapshot()
        if pollTimer == nil, shouldPoll(for: state) {
            startPolling()
        } else {
            pollForUpdates()
        }
    }

    private func startPolling() {
        stopPolling()
        pollCount = 0
        // Start with fast polling for quick response
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.pollForUpdates()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        sharedStore.updateKeyboardHeartbeat()
        lastHeartbeatSentAt = Date().timeIntervalSince1970

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sharedStore.updateKeyboardHeartbeat()
            self?.lastHeartbeatSentAt = Date().timeIntervalSince1970
        }
        if let heartbeatTimer {
            RunLoop.current.add(heartbeatTimer, forMode: .common)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func pollForUpdates() {
        pollCount += 1
        let now = Date().timeIntervalSince1970
        if now - lastHeartbeatSentAt > 1.0 {
            sharedStore.updateKeyboardHeartbeat()
            lastHeartbeatSentAt = now
        }

        let state = sharedStore.snapshot()
        let phase = state.phase

        // Log state periodically — every 25 polls at info to track flow without spam
        if pollCount % 25 == 0 {
            log.info("Poll #\(pollCount) phase=\(phase) age=\(Int(state.phaseAge))s")
        }

        switch phase {
        case .done, .error:
            log.info("Poll: Result ready!")
            dictationTrace?.event("poll_detected_done")

            checkForDictationResult()

            // Keep polling if insertion is being retried (result not yet consumed)
            // In voice emoji mode, also keep polling for continuous listening
            if !isVoiceEmojiMode && resultInsertionRetryCount == 0 {
                stopPolling()
            }
            return

        case .recording:
            if pollCount == 1 {
                dictationTrace?.event("poll_detected_recording")
            }
            showRecordingUI()

            // Check if app is still alive - if recording for too long with no bridge signal
            // Give the app 60 seconds max before declaring it unresponsive
            if state.phaseAge > 60.0 && !bridge.isRecordingInProgress() {
                log.warning("Recording timeout - app may have died")
                dictationTrace?.end(message: "recording_timeout")
                dictationTrace = nil
                sharedStore.forceReset(reason: "Recording timeout - app unresponsive", preserveCapability: true, updatedBy: "keyboard")
                bridge.forceReset()
                currentSessionId = nil
                showStatus("Timeout - try again")
                stopPolling()
                showNormalUI()
                return
            }

        case .transcribing:
            if pollCount == 1 || statusMessage != "Transcribing..." {
                dictationTrace?.event("transcribing")
            }
            showProcessingUI()

        case .stopping:
            dictationTrace?.event("stopping")

            // Check if recording has actually stopped (bridge sync)
            // The app may have already finished while our local state is stale
            if !bridge.isRecordingInProgress() {
                // Recording stopped - check for result
                if bridge.getDictationResult() != nil {
                    log.info("Poll: Bridge has result while stopping - consuming")
                    checkForDictationResult()
                    return
                }
            }

            showProcessingUI()
            // Timeout check - if stopping for too long, app isn't responding
            if state.phaseAge > 15.0 {
                log.warning("Stop timeout - app not responding after 15s")
                dictationTrace?.end(message: "stop_timeout")
                dictationTrace = nil
                sharedStore.forceReset(reason: "Stop request timeout - app unresponsive", preserveCapability: true, updatedBy: "keyboard")
                bridge.forceReset()
                currentSessionId = nil
                showStatus("Timeout - try again")
                stopPolling()
                showNormalUI()
                return
            }

        case .idle, .ready:
            // In voice emoji mode, don't stop polling - state transitions are managed differently
            if isVoiceEmojiMode {
                // Just continue polling, waiting for recording to start
                return
            }
            // Unexpected - we should stop polling
            if state.lastError != nil {
                log.info("Poll: Error occurred")
                dictationTrace?.end(message: "error")
                dictationTrace = nil
                checkForDictationResult()
            }
            stopPolling()
            showNormalUI()
            return

        case .arming:
            // Check if app has actually started recording (bridge sync)
            // This handles the case where keyboard state is stale
            if bridge.isRecordingInProgress() && isAppHeartbeatFresh(maxAge: 1.5) {
                log.info("Poll: Bridge shows recording started - syncing local state")
                showRecordingUI()
                return
            }

            // If we thought instant-start was possible but app isn't responding,
            // fall back to deep link once to force foreground.
            if !didAttemptDeepLinkFallback && !isAppHeartbeatFresh(maxAge: 2.5) {
                didAttemptDeepLinkFallback = true
                log.warning("Poll: App heartbeat stale while arming - forcing deep link fallback")
                if let url = URL(string: "talkie://dictate") {
                    openURL(url)
                }
            }

            // Check if app finished with a result (maybe we missed the recording state)
            if bridge.getDictationResult() != nil {
                log.info("Poll: Bridge has result while waiting - consuming")
                checkForDictationResult()
                return
            }

            // Check if app signaled an error
            if let error = bridge.getDictationError() {
                log.warning("Poll: App signaled error: \(error)")
                sharedStore.forceReset(reason: "App error: \(error)", preserveCapability: true, updatedBy: "keyboard")
                bridge.clearDictationError()
                showStatus(error)
                stopPolling()
                showNormalUI()
                return
            }

            // Timeout check - if waiting too long, app probably failed silently
            if state.phaseAge > 8.0 {
                log.warning("Poll: Waiting for app timeout after \(Int(state.phaseAge))s")
                sharedStore.forceReset(reason: "App launch timeout", preserveCapability: true, updatedBy: "keyboard")
                bridge.forceReset()
                showStatus("Timeout - try again")
                stopPolling()
                showNormalUI()
                return
            }

            showStatus("Opening Talkie...")
        }

        // Update button/LED state based on current state
        checkReadyState()

        // Slow down polling after initial fast checks
        if pollCount == 20 {
            stopPolling()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                self?.pollForUpdates()
            }
            log.debug("Poll: Switched to slower polling")
        }
    }

    @objc private func pasteTapped() {
        log.info("Paste tapped")
        if !pasteFromLocalClipboardIfAvailable() && !pasteFromSystemClipboard() {
            showStatus("Clipboard empty")
        }
    }

    @objc private func pasteLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        log.info("Paste long-pressed (system clipboard)")

        if !pasteFromSystemClipboard() {
            showStatus("System clipboard empty")
        }
    }

    @discardableResult
    private func pasteFromLocalClipboardIfAvailable() -> Bool {
        guard let localClipboardText, !localClipboardText.isEmpty else { return false }
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText(localClipboardText)
        setStatusMessage("Pasted local", color: Design.textSecondary)
        updateDebugView()
        return true
    }

    @discardableResult
    private func pasteFromSystemClipboard() -> Bool {
        guard hasFullAccess, let content = UIPasteboard.general.string, !content.isEmpty else { return false }
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText(content)
        setStatusMessage("Pasted system", color: Design.textSecondary)
        updateDebugView()
        return true
    }

    @objc private func spaceTapped() {
        log.debug("Space tapped")
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText(" ")
        updateDebugView()
    }

    private func insertCompactText(_ text: String) {
        guard text.isEmpty == false else { return }
        _ = consumeSelectionIfNeeded()
        textDocumentProxy.insertText(text)
    }

    // MARK: - Reliable Text Insertion

    /// Insert text reliably, chunking long texts to avoid silent failures
    /// in keyboard extension textDocumentProxy.
    private func insertTextReliably(_ text: String) {
        let chunkSize = 500  // Characters per chunk — conservative limit for keyboard extensions

        guard text.count > chunkSize else {
            // Short text: insert directly
            textDocumentProxy.insertText(text)
            log.info("Inserted dictation text: \(text.count) chars (direct)")
            verifyInsertion(expected: text)
            return
        }

        // Long text: chunk to avoid silent truncation
        log.info("Chunking long text: \(text.count) chars into \((text.count + chunkSize - 1) / chunkSize) chunks")
        var remaining = text[text.startIndex...]
        var chunkIndex = 0

        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(chunkSize, remaining.count))
            let chunk = String(remaining[remaining.startIndex..<end])
            textDocumentProxy.insertText(chunk)
            remaining = remaining[end...]
            chunkIndex += 1
            log.debug("Inserted chunk \(chunkIndex): \(chunk.count) chars")
        }

        log.info("Inserted dictation text: \(text.count) chars (\(chunkIndex) chunks)")
        verifyInsertion(expected: text)
    }

    /// Best-effort verification that text was actually inserted
    private func verifyInsertion(expected: String) {
        let contextAfter = textDocumentProxy.documentContextBeforeInput ?? ""
        if contextAfter.isEmpty && !expected.isEmpty {
            log.warning("INSERTION MAY HAVE FAILED: documentContextBeforeInput is empty after inserting \(expected.count) chars")
            log.warning("Text proxy may have lost connection to host app text field")
        } else if !contextAfter.hasSuffix(String(expected.suffix(20))) && expected.count > 20 {
            log.warning("INSERTION VERIFICATION UNCERTAIN: last 20 chars don't match (expected suffix: '\(expected.suffix(20))', got: '\(contextAfter.suffix(20))')")
        }
    }

    // MARK: - Exhaustive Context Logging

    private func logExhaustiveContext() {
        let proxy = textDocumentProxy

        log.info("=== EXHAUSTIVE CONTEXT ===")

        // Text content
        log.info("TEXT", detail: """
            beforeInput: \(proxy.documentContextBeforeInput ?? "nil")
            afterInput: \(proxy.documentContextAfterInput ?? "nil")
            selectedText: \(proxy.selectedText ?? "nil")
            """)

        // Keyboard configuration
        log.info("KEYBOARD", detail: """
            keyboardType: \(keyboardTypeName(proxy.keyboardType ?? .default))
            keyboardAppearance: \(proxy.keyboardAppearance == .dark ? "dark" : "light")
            returnKeyType: \(returnKeyTypeName(proxy.returnKeyType ?? .default))
            """)

        // Text input traits
        let smartInsert = proxy.smartInsertDeleteType ?? .default
        log.info("TEXT TRAITS", detail: """
            textContentType: \(proxy.textContentType?.rawValue ?? "nil")
            isSecureTextEntry: \(proxy.isSecureTextEntry ?? false)
            autocapitalizationType: \(autocapName(proxy.autocapitalizationType ?? .none))
            autocorrectionType: \(autocorrectionName(proxy.autocorrectionType ?? .default))
            spellCheckingType: \(spellCheckName(proxy.spellCheckingType ?? .default))
            smartQuotesType: \(smartQuotesName(proxy.smartQuotesType ?? .default))
            smartDashesType: \(smartDashesName(proxy.smartDashesType ?? .default))
            smartInsertDeleteType: \(smartInsertDeleteName(smartInsert))
            """)

        // Document info - skip documentIdentifier as it can crash on bridging in some contexts
        log.info("DOCUMENT", detail: """
            documentInputMode: \(proxy.documentInputMode?.primaryLanguage ?? "nil")
            """)

        // Input view controller info
        log.info("INPUT CONTROLLER", detail: """
            needsInputModeSwitchKey: \(needsInputModeSwitchKey)
            hasFullAccess: \(hasFullAccess)
            primaryLanguage: \(primaryLanguage ?? "nil")
            """)
    }

    // MARK: - Type Name Helpers

    private func keyboardTypeName(_ type: UIKeyboardType) -> String {
        switch type {
        case .default: return "default"
        case .asciiCapable: return "asciiCapable"
        case .numbersAndPunctuation: return "numbersAndPunctuation"
        case .URL: return "URL"
        case .numberPad: return "numberPad"
        case .phonePad: return "phonePad"
        case .namePhonePad: return "namePhonePad"
        case .emailAddress: return "emailAddress"
        case .decimalPad: return "decimalPad"
        case .twitter: return "twitter"
        case .webSearch: return "webSearch"
        case .asciiCapableNumberPad: return "asciiCapableNumberPad"
        @unknown default: return "unknown(\(type.rawValue))"
        }
    }

    private func returnKeyTypeName(_ type: UIReturnKeyType) -> String {
        switch type {
        case .default: return "default"
        case .go: return "go"
        case .google: return "google"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .search: return "search"
        case .send: return "send"
        case .yahoo: return "yahoo"
        case .done: return "done"
        case .emergencyCall: return "emergencyCall"
        case .continue: return "continue"
        @unknown default: return "unknown(\(type.rawValue))"
        }
    }

    private func autocapName(_ type: UITextAutocapitalizationType) -> String {
        switch type {
        case .none: return "none"
        case .words: return "words"
        case .sentences: return "sentences"
        case .allCharacters: return "allCharacters"
        @unknown default: return "unknown"
        }
    }

    private func autocorrectionName(_ type: UITextAutocorrectionType) -> String {
        switch type {
        case .default: return "default"
        case .no: return "no"
        case .yes: return "yes"
        @unknown default: return "unknown"
        }
    }

    private func spellCheckName(_ type: UITextSpellCheckingType) -> String {
        switch type {
        case .default: return "default"
        case .no: return "no"
        case .yes: return "yes"
        @unknown default: return "unknown"
        }
    }

    private func smartQuotesName(_ type: UITextSmartQuotesType) -> String {
        switch type {
        case .default: return "default"
        case .no: return "no"
        case .yes: return "yes"
        @unknown default: return "unknown"
        }
    }

    private func smartDashesName(_ type: UITextSmartDashesType) -> String {
        switch type {
        case .default: return "default"
        case .no: return "no"
        case .yes: return "yes"
        @unknown default: return "unknown"
        }
    }

    private func smartInsertDeleteName(_ type: UITextSmartInsertDeleteType) -> String {
        switch type {
        case .default: return "default"
        case .no: return "no"
        case .yes: return "yes"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Debug (disabled)

    private func updateDebugView() {
        // Debug view removed - no-op for call sites
    }

}
