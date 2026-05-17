//
//  MinimalKeyboardView.swift
//  TalkieKeys
//
//  Ultra-minimal single-row keyboard for terminal-focused use.
//  Layout: [slot1][slot2][ —— DICTATE —— ][slot3][slot4]
//  Dictate button fills remaining space, doubles as status indicator.
//  Slot contents are configurable via SlotConfig from TalkieMobileKit.
//

import UIKit
import ObjectiveC
import TalkieMobileKit

private let log = Log(.ui)

private enum AssociatedKeys {
    static var borderGradient = 0
}

@available(iOS 17.0, *)
final class MinimalKeyboardView: UIView {

    // MARK: - Design Constants

    private enum Design {
        static let buttonHeight: CGFloat = 36
        static let topPadding: CGFloat = 3
        static let bottomPadding: CGFloat = 3
        static let sidePadding: CGFloat = 5
        static let gridSpacing: CGFloat = 5
        static let cornerRadius: CGFloat = 4

        static let surfaceDark = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.03)
                : UIColor(white: 1.0, alpha: 0.74)
        }

        static let surfaceLight = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.92)
        }

        static let keyBorder = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.16)
                : UIColor(white: 0.0, alpha: 0.08)
        }

        static let keyBorderPressed = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.24)
                : UIColor(white: 0.0, alpha: 0.16)
        }

        static let keyShadow = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black
                : UIColor(white: 0.0, alpha: 0.3)
        }

        static let textPrimary = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 1.0)
                : UIColor(white: 0.0, alpha: 1.0)
        }

        static let textSecondary = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.6, alpha: 1.0)
                : UIColor(white: 0.4, alpha: 1.0)
        }

        static let textMuted = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.4, alpha: 1.0)
                : UIColor(white: 0.55, alpha: 1.0)
        }
    }

    /// Total height: button + top/bottom padding
    static let totalHeight: CGFloat = Design.buttonHeight + Design.topPadding + Design.bottomPadding

    // MARK: - Slot Configuration

    /// Slot configs for slots 1-4. Set before adding to view hierarchy.
    /// Layout: [1][2][ DICTATE ][3][4]
    var slotConfigs: [Int: SlotConfig] = KeyboardMode.minimal.slots {
        didSet { rebuildSlots() }
    }

    // MARK: - Callbacks

    var onDictateTapped: (() -> Void)?
    /// Called when any slot button is tapped. Params: (slot number, config for that slot)
    var onSlotAction: ((Int, SlotConfig) -> Void)?
    var onSwipeUp: (() -> Void)?

    // MARK: - UI

    /// The dictate button, exposed so the parent can reassign recordButton
    private(set) var dictateButton: UIButton!

    /// The mic icon inside the dictate button, for color updates
    private weak var dictateIconView: UIImageView?
    /// The content stack (icon + label) inside dictate button
    private weak var dictateContentStack: UIStackView?

    private var stackView: UIStackView!

    /// References to slot buttons for updates
    private var slotButtons: [Int: UIButton] = [:]

    // MARK: - Processing Animation

    private var borderTraceLayer: CAShapeLayer?

    // MARK: - Haptic Generators (pre-prepared for reliable feedback)

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Recording State

    private var recordingDotView: UIView?
    private var recordingTimerLabel: UILabel?
    private var recordingStartTime: Date?
    private var recordingDisplayLink: CADisplayLink?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear

        // Warm up the Taptic Engine so first haptic fires reliably
        lightImpact.prepare()
        mediumImpact.prepare()

        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Design.gridSpacing
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Design.topPadding),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Design.bottomPadding),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Design.sidePadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Design.sidePadding),
        ])

        // Build: [slot1][slot2][ —— DICTATE —— ][slot3][slot4]
        let slot1Btn = makeSlotButton(slot: 1, config: slotConfigs[1] ?? .empty)
        let slot2Btn = makeSlotButton(slot: 2, config: slotConfigs[2] ?? .empty)
        dictateButton = makeDictateButton()
        let slot3Btn = makeSlotButton(slot: 3, config: slotConfigs[3] ?? .empty)
        let slot4Btn = makeSlotButton(slot: 4, config: slotConfigs[4] ?? .empty)

        stackView.addArrangedSubview(slot1Btn)
        stackView.addArrangedSubview(slot2Btn)
        stackView.addArrangedSubview(dictateButton)
        stackView.addArrangedSubview(slot3Btn)
        stackView.addArrangedSubview(slot4Btn)

        // Width constraints: slot buttons equal width, dictate fills remaining space
        let smallButtons = [slot1Btn, slot2Btn, slot3Btn, slot4Btn]
        for btn in smallButtons.dropFirst() {
            btn.widthAnchor.constraint(equalTo: slot1Btn.widthAnchor).isActive = true
        }
        dictateButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for btn in smallButtons {
            btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        }

        // Swipe up to return to previous keyboard layout
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        swipeUp.direction = .up
        addGestureRecognizer(swipeUp)
    }

    /// Rebuild slot button contents after slotConfigs changes (without recreating the view hierarchy)
    private func rebuildSlots() {
        for slot in 1...4 {
            guard let btn = slotButtons[slot] else { continue }
            let config = slotConfigs[slot] ?? .empty
            configureSlotButtonContent(btn, config: config)
        }
    }

    private func applyKeyRestingStyle(to button: UIButton) {
        button.backgroundColor = Design.surfaceDark
        button.layer.borderWidth = 0.45
        button.layer.borderColor = Design.keyBorder.cgColor
        button.layer.shadowColor = Design.keyShadow.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        button.layer.shadowRadius = 1.2
        button.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.05
    }

    private func applyKeyPressedStyle(to button: UIButton) {
        button.backgroundColor = Design.surfaceLight
        button.layer.borderColor = Design.keyBorderPressed.cgColor
        button.layer.shadowOpacity = 0.02
    }

    private func attachPressHandlers(to button: UIButton) {
        button.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
        button.addTarget(
            self,
            action: #selector(keyTouchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit, .touchDragOutside]
        )
    }

    @objc private func keyTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.06, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = CGAffineTransform(scaleX: 0.982, y: 0.982)
            self.applyKeyPressedStyle(to: sender)
        }
    }

    @objc private func keyTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = .identity
            self.applyKeyRestingStyle(to: sender)
        }
    }

    func resetTransientTouchState(animated: Bool) {
        let buttons = Array(slotButtons.values) + [dictateButton].compactMap { $0 }
        var seen = Set<ObjectIdentifier>()

        let reset = {
            for button in buttons {
                guard seen.insert(ObjectIdentifier(button)).inserted else { continue }
                button.transform = .identity
                self.applyKeyRestingStyle(to: button)
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            resetTransientTouchState(animated: false)
        }
    }

    // MARK: - Button Factories

    private func makeSlotButton(slot: Int, config: SlotConfig) -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = Design.cornerRadius
        btn.tag = slot
        applyKeyRestingStyle(to: btn)
        attachPressHandlers(to: btn)
        btn.addTarget(self, action: #selector(slotTapped(_:)), for: .touchUpInside)

        slotButtons[slot] = btn
        configureSlotButtonContent(btn, config: config)
        return btn
    }

    /// Configure a slot button's visual content based on its config
    private func configureSlotButtonContent(_ btn: UIButton, config: SlotConfig) {
        // Remove existing content
        btn.subviews.forEach { $0.removeFromSuperview() }
        btn.setTitle(nil, for: .normal)

        switch config.type {
        case .action:
            if config.label == "COPY" || config.label == "PASTE" {
                let label = UILabel()
                label.text = config.label == "COPY" ? "⌘C" : "⌘V"
                label.font = .systemFont(ofSize: 13, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                btn.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                ])
            } else if let iconName = config.icon, !iconName.isEmpty {
                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let iconView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: symbolConfig))
                iconView.tintColor = Design.textPrimary
                iconView.contentMode = .scaleAspectFit
                iconView.translatesAutoresizingMaskIntoConstraints = false
                btn.addSubview(iconView)
                NSLayoutConstraint.activate([
                    iconView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                    iconView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                ])
            } else {
                let label = UILabel()
                label.text = config.label
                label.font = .systemFont(ofSize: 11, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                btn.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                ])
            }

        case .text, .snippet:
            let label = UILabel()
            label.text = config.label
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = Design.textPrimary
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            btn.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
            ])

        case .space:
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let iconView = UIImageView(image: UIImage(systemName: "space", withConfiguration: symbolConfig))
            iconView.tintColor = Design.textPrimary
            iconView.contentMode = .scaleAspectFit
            iconView.translatesAutoresizingMaskIntoConstraints = false
            btn.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
            ])

        case .empty:
            break
        }
    }

    private func makeDictateButton() -> UIButton {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = Design.cornerRadius
        btn.clipsToBounds = false
        applyKeyRestingStyle(to: btn)
        attachPressHandlers(to: btn)
        btn.addTarget(self, action: #selector(dictateTapped), for: .touchUpInside)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic.fill"))
        iconView.tintColor = Design.textMuted
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        self.dictateIconView = iconView

        stack.addArrangedSubview(iconView)
        self.dictateContentStack = stack

        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
        ])

        return btn
    }

    // MARK: - Status Indicator

    /// Update the dictate button appearance based on ready state and model warmth.
    /// Minimal layout uses icon-only affordance.
    func updateReadyState(_ isReady: Bool, modelWarm: Bool = true) {
        _ = modelWarm
        dictateIconView?.tintColor = isReady ? Design.textPrimary : Design.textMuted
    }

    // MARK: - Recording State Feedback

    /// Show recording state: clean timer only, no background effects.
    /// The button itself is still tappable to stop.
    func startRecordingFeedback() {
        guard recordingTimerLabel == nil else { return }

        recordingStartTime = Date()

        // Hide mic icon/label
        dictateContentStack?.alpha = 0

        // Timer label — centered, clean
        let timerLabel = UILabel()
        timerLabel.text = "0:00"
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timerLabel.textColor = Design.textSecondary
        timerLabel.textAlignment = .center
        timerLabel.isUserInteractionEnabled = false
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingTimerLabel = timerLabel

        // Use a container for consistent cleanup
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(timerLabel)
        dictateButton.addSubview(container)
        recordingDotView = container // reuse slot for cleanup tracking

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: dictateButton.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: dictateButton.centerYAnchor),
            timerLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            timerLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        // Timer update via display link
        let link = CADisplayLink(target: self, selector: #selector(updateRecordingTimer))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 15, preferred: 10)
        link.add(to: .main, forMode: .common)
        recordingDisplayLink = link
    }

    /// Stop recording feedback and restore button content
    func stopRecordingFeedback() {
        recordingDisplayLink?.invalidate()
        recordingDisplayLink = nil
        cleanupRecordingLayers()
        dictateButton.layer.removeAnimation(forKey: "recordingPulse")

        // Restore content stack visibility
        dictateContentStack?.alpha = 1
    }

    @objc private func updateRecordingTimer() {
        guard let start = recordingStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        recordingTimerLabel?.text = "\(minutes):\(String(format: "%02d", seconds))"
    }

    // MARK: - Processing Animation (Border Trace)

    /// Start processing animation: slim border trace traveling around the dictate button
    func startProcessingAnimation() {
        guard borderTraceLayer == nil else { return }

        dictateButton.layoutIfNeeded()
        let bounds = dictateButton.bounds
        guard bounds.width > 0 else {
            DispatchQueue.main.async { [weak self] in self?.startProcessingAnimation() }
            return
        }

        // Show a subtle "PROCESSING" label instead of mic/DICTATE
        dictateContentStack?.alpha = 0

        let processingLabel = UILabel()
        processingLabel.text = "PROCESSING"
        processingLabel.font = .systemFont(ofSize: 8, weight: .medium)
        processingLabel.textColor = Design.textMuted
        processingLabel.textAlignment = .center
        processingLabel.isUserInteractionEnabled = false
        processingLabel.translatesAutoresizingMaskIntoConstraints = false
        processingLabel.tag = 999  // For cleanup

        dictateButton.addSubview(processingLabel)
        NSLayoutConstraint.activate([
            processingLabel.centerXAnchor.constraint(equalTo: dictateButton.centerXAnchor),
            processingLabel.centerYAnchor.constraint(equalTo: dictateButton.centerYAnchor),
        ])

        // -- Border trace: a slim highlight that travels around the border --
        let borderPath = UIBezierPath(roundedRect: bounds, cornerRadius: Design.cornerRadius)

        // Faint static border (always visible, very subtle)
        let baseBorder = CAShapeLayer()
        baseBorder.path = borderPath.cgPath
        baseBorder.fillColor = nil
        baseBorder.strokeColor = Design.keyBorder.cgColor
        baseBorder.lineWidth = 0.5
        dictateButton.layer.addSublayer(baseBorder)

        // Moving highlight stroke — slim and subtle
        let trace = CAShapeLayer()
        trace.path = borderPath.cgPath
        trace.fillColor = nil
        trace.strokeColor = Design.keyBorderPressed.cgColor
        trace.lineWidth = 0.5
        trace.lineCap = .round
        trace.strokeStart = 0.0
        trace.strokeEnd = 0.15  // Short tail — 15% of the perimeter
        dictateButton.layer.addSublayer(trace)
        borderTraceLayer = trace

        // Store base border for cleanup
        objc_setAssociatedObject(self, &AssociatedKeys.borderGradient, baseBorder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Keyframe animation: travel around the path smoothly
        let duration: CFTimeInterval = 2.0

        let startKeyframe = CAKeyframeAnimation(keyPath: "strokeStart")
        startKeyframe.values = [0.0, 0.85, 1.0]
        startKeyframe.keyTimes = [0.0, 0.85, 1.0]

        let endKeyframe = CAKeyframeAnimation(keyPath: "strokeEnd")
        endKeyframe.values = [0.15, 1.0, 1.0]
        endKeyframe.keyTimes = [0.0, 0.85, 1.0]

        let group = CAAnimationGroup()
        group.animations = [startKeyframe, endKeyframe]
        group.duration = duration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        trace.add(group, forKey: "borderTrace")

        log.info("Processing animation started (border trace only)")
    }

    /// Stop processing animation and restore content
    func stopProcessingAnimation() {
        cleanupProcessingLayers()

        // Restore content
        dictateContentStack?.alpha = 1

        log.info("Processing animation stopped")
    }

    // MARK: - Success Transition

    private static let successGreen = UIColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1.0)

    /// Smooth transition: processing eases out -> checkmark eases in -> checkmark eases out -> DICTATE eases in.
    /// No background flash, no overlapping elements — one thing at a time.
    func showSuccessFlash() {
        // Stop recording display link
        recordingDisplayLink?.invalidate()
        recordingDisplayLink = nil

        // Prepare checkmark (hidden initially)
        let checkIcon = UIImageView(image: UIImage(systemName: "checkmark"))
        checkIcon.tintColor = Self.successGreen
        checkIcon.contentMode = .scaleAspectFit
        checkIcon.alpha = 0
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        dictateButton.addSubview(checkIcon)
        NSLayoutConstraint.activate([
            checkIcon.centerXAnchor.constraint(equalTo: dictateButton.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: dictateButton.centerYAnchor),
            checkIcon.widthAnchor.constraint(equalToConstant: 16),
            checkIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Phase 1: Fade out recording/processing -> fade in checkmark
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) { [weak self] in
            self?.recordingDotView?.alpha = 0
            self?.borderTraceLayer?.opacity = 0
            checkIcon.alpha = 1
        } completion: { [weak self] _ in
            // Clean up processing/recording layers
            self?.cleanupProcessingLayers()
            self?.cleanupRecordingLayers()
            self?.dictateButton.layer.removeAnimation(forKey: "recordingPulse")

            // Phase 2: Hold checkmark, then fade to DICTATE
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                    checkIcon.alpha = 0
                } completion: { _ in
                    checkIcon.removeFromSuperview()
                    // Phase 3: Fade in DICTATE content
                    self?.dictateContentStack?.alpha = 0
                    UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
                        self?.dictateContentStack?.alpha = 1
                    }
                }
            }
        }

        log.info("Success transition started")
    }

    /// Remove border trace, base border, and processing label
    private func cleanupProcessingLayers() {
        borderTraceLayer?.removeAllAnimations()
        borderTraceLayer?.removeFromSuperlayer()
        borderTraceLayer = nil

        if let baseBorder = objc_getAssociatedObject(self, &AssociatedKeys.borderGradient) as? CALayer {
            baseBorder.removeAllAnimations()
            baseBorder.removeFromSuperlayer()
            objc_setAssociatedObject(self, &AssociatedKeys.borderGradient, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        // Remove processing label
        dictateButton?.viewWithTag(999)?.removeFromSuperview()
    }

    /// Remove recording dot, timer, and display link
    private func cleanupRecordingLayers() {
        recordingDotView?.removeFromSuperview()
        recordingDotView = nil
        recordingTimerLabel = nil
        recordingStartTime = nil
    }

    // MARK: - Actions

    @objc private func dictateTapped() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()  // Pre-warm for next tap
        onDictateTapped?()
    }

    @objc private func slotTapped(_ sender: UIButton) {
        lightImpact.impactOccurred()
        lightImpact.prepare()
        let slot = sender.tag
        guard let config = slotConfigs[slot] else { return }
        onSlotAction?(slot, config)
    }

    @objc private func handleSwipeUp() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        onSwipeUp?()
    }
}
