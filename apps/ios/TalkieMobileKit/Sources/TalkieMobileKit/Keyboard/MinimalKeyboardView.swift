#if canImport(UIKit) && !os(watchOS)
//
//  MinimalKeyboardView.swift
//  TalkieMobileKit
//
//  Shared ultra-minimal single-row keyboard.
//

import UIKit
import ObjectiveC

private let log = Log(.ui)

private enum AssociatedKeys {
    static var borderGradient = 0
}

@available(iOS 17.0, *)
public final class MinimalKeyboardView: UIView {

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

    public static let totalHeight: CGFloat = Design.buttonHeight + Design.topPadding + Design.bottomPadding

    public var slotConfigs: [Int: SlotConfig] = KeyboardMode.minimal.slots {
        didSet { rebuildSlotButtons() }
    }
    public var showsDictateButton = true {
        didSet { rebuildSlotButtons() }
    }

    public var onDictateTapped: (() -> Void)?
    public var onSlotAction: ((Int, SlotConfig) -> Void)?
    public var onSwipeUp: (() -> Void)?

    public private(set) var dictateButton: UIButton!

    private weak var dictateIconView: UIImageView?
    private weak var dictateContentStack: UIStackView?
    private var stackView: UIStackView!
    private var slotButtons: [Int: UIButton] = [:]
    private var borderTraceLayer: CAShapeLayer?
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private var recordingDotView: UIView?
    private var recordingTimerLabel: UILabel?
    private var recordingStartTime: Date?
    private var recordingDisplayLink: CADisplayLink?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .clear
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

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        swipeUp.direction = .up
        addGestureRecognizer(swipeUp)

        rebuildSlotButtons()
    }

    private var orderedSlots: [Int] {
        let maxSlot = max(slotConfigs.keys.max() ?? 4, 4)
        return Array(1...maxSlot)
    }

    private func rebuildSlotButtons() {
        stackView.arrangedSubviews.forEach { arrangedSubview in
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        slotButtons.removeAll()

        guard orderedSlots.count >= 4 else { return }

        let allButtons: [UIButton]
        if showsDictateButton {
            let leftButtons = orderedSlots.prefix(2).map { makeSlotButton(slot: $0, config: slotConfigs[$0] ?? .empty) }
            let rightButtons = orderedSlots.dropFirst(2).map { makeSlotButton(slot: $0, config: slotConfigs[$0] ?? .empty) }
            let dictateButton = makeDictateButton()
            self.dictateButton = dictateButton

            allButtons = leftButtons + [dictateButton] + rightButtons
            for button in leftButtons {
                stackView.addArrangedSubview(button)
            }
            stackView.addArrangedSubview(dictateButton)
            for button in rightButtons {
                stackView.addArrangedSubview(button)
            }
        } else {
            dictateButton = nil
            dictateIconView = nil
            dictateContentStack = nil
            allButtons = orderedSlots.map { makeSlotButton(slot: $0, config: slotConfigs[$0] ?? .empty) }
            for button in allButtons {
                stackView.addArrangedSubview(button)
            }
        }

        guard let referenceButton = allButtons.first else { return }
        for button in allButtons.dropFirst() {
            button.widthAnchor.constraint(equalTo: referenceButton.widthAnchor).isActive = true
        }
        for button in allButtons {
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
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
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
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

    private func makeSlotButton(slot: Int, config: SlotConfig) -> UIButton {
        let button = UIButton(type: .system)
        button.layer.cornerRadius = Design.cornerRadius
        button.tag = slot
        applyKeyRestingStyle(to: button)
        attachPressHandlers(to: button)
        button.addTarget(self, action: #selector(slotTapped(_:)), for: .touchUpInside)

        slotButtons[slot] = button
        configureSlotButtonContent(button, config: config)
        return button
    }

    private func configureSlotButtonContent(_ button: UIButton, config: SlotConfig) {
        button.subviews.forEach { $0.removeFromSuperview() }
        button.setTitle(nil, for: .normal)

        switch config.type {
        case .action:
            if config.label == "SHIFT" {
                let label = UILabel()
                label.text = "⇧"
                label.font = .systemFont(ofSize: 16, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            } else if config.label == "CONTROL" {
                let label = UILabel()
                label.text = "⌃"
                label.font = .systemFont(ofSize: 16, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            } else if config.label == "COPY" || config.label == "PASTE" {
                let label = UILabel()
                label.text = config.label == "COPY" ? "⌘C" : "⌘V"
                label.font = .systemFont(ofSize: 13, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            } else if let iconName = config.icon, !iconName.isEmpty {
                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let iconView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: symbolConfig))
                iconView.tintColor = Design.textPrimary
                iconView.contentMode = .scaleAspectFit
                iconView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(iconView)
                NSLayoutConstraint.activate([
                    iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            } else {
                let label = UILabel()
                label.text = config.label
                label.font = .systemFont(ofSize: 11, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            }

        case .text, .snippet:
            let label = UILabel()
            label.text = config.label
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = Design.textPrimary
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])

        case .space:
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let iconView = UIImageView(image: UIImage(systemName: "space", withConfiguration: symbolConfig))
            iconView.tintColor = Design.textPrimary
            iconView.contentMode = .scaleAspectFit
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])

        case .empty:
            break
        }
    }

    private func makeDictateButton() -> UIButton {
        let button = UIButton(type: .system)
        button.layer.cornerRadius = Design.cornerRadius
        button.clipsToBounds = false
        applyKeyRestingStyle(to: button)
        attachPressHandlers(to: button)
        button.addTarget(self, action: #selector(dictateTapped), for: .touchUpInside)

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
        dictateIconView = iconView

        stack.addArrangedSubview(iconView)
        dictateContentStack = stack

        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        return button
    }

    public func updateReadyState(_ isReady: Bool, modelWarm: Bool = true) {
        _ = modelWarm
        guard showsDictateButton else { return }
        dictateIconView?.tintColor = isReady ? Design.textPrimary : Design.textMuted
    }

    public func startRecordingFeedback() {
        guard showsDictateButton, let dictateButton else { return }
        guard recordingTimerLabel == nil else { return }

        recordingStartTime = Date()
        dictateContentStack?.alpha = 0

        let timerLabel = UILabel()
        timerLabel.text = "0:00"
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timerLabel.textColor = Design.textSecondary
        timerLabel.textAlignment = .center
        timerLabel.isUserInteractionEnabled = false
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingTimerLabel = timerLabel

        let container = UIView()
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(timerLabel)
        dictateButton.addSubview(container)
        recordingDotView = container

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: dictateButton.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: dictateButton.centerYAnchor),
            timerLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            timerLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let link = CADisplayLink(target: self, selector: #selector(updateRecordingTimer))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 15, preferred: 10)
        link.add(to: .main, forMode: .common)
        recordingDisplayLink = link
    }

    public func stopRecordingFeedback() {
        guard showsDictateButton, let dictateButton else { return }
        recordingDisplayLink?.invalidate()
        recordingDisplayLink = nil
        cleanupRecordingLayers()
        dictateButton.layer.removeAnimation(forKey: "recordingPulse")
        dictateContentStack?.alpha = 1
    }

    @objc private func updateRecordingTimer() {
        guard let start = recordingStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        recordingTimerLabel?.text = "\(minutes):\(String(format: "%02d", seconds))"
    }

    public func startProcessingAnimation() {
        guard showsDictateButton, let dictateButton else { return }
        guard borderTraceLayer == nil else { return }

        dictateButton.layoutIfNeeded()
        let bounds = dictateButton.bounds
        guard bounds.width > 0 else {
            DispatchQueue.main.async { [weak self] in self?.startProcessingAnimation() }
            return
        }

        dictateContentStack?.alpha = 0

        let processingLabel = UILabel()
        processingLabel.text = "PROCESSING"
        processingLabel.font = .systemFont(ofSize: 8, weight: .medium)
        processingLabel.textColor = Design.textMuted
        processingLabel.textAlignment = .center
        processingLabel.isUserInteractionEnabled = false
        processingLabel.translatesAutoresizingMaskIntoConstraints = false
        processingLabel.tag = 999

        dictateButton.addSubview(processingLabel)
        NSLayoutConstraint.activate([
            processingLabel.centerXAnchor.constraint(equalTo: dictateButton.centerXAnchor),
            processingLabel.centerYAnchor.constraint(equalTo: dictateButton.centerYAnchor),
        ])

        let borderPath = UIBezierPath(roundedRect: bounds, cornerRadius: Design.cornerRadius)

        let baseBorder = CAShapeLayer()
        baseBorder.path = borderPath.cgPath
        baseBorder.fillColor = nil
        baseBorder.strokeColor = Design.keyBorder.cgColor
        baseBorder.lineWidth = 0.5
        dictateButton.layer.addSublayer(baseBorder)

        let trace = CAShapeLayer()
        trace.path = borderPath.cgPath
        trace.fillColor = nil
        trace.strokeColor = Design.keyBorderPressed.cgColor
        trace.lineWidth = 0.5
        trace.lineCap = .round
        trace.strokeStart = 0
        trace.strokeEnd = 0.15
        dictateButton.layer.addSublayer(trace)
        borderTraceLayer = trace

        objc_setAssociatedObject(self, &AssociatedKeys.borderGradient, baseBorder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

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

        log.info("Processing animation started (minimal keyboard)")
    }

    public func stopProcessingAnimation() {
        guard showsDictateButton else { return }
        cleanupProcessingLayers()
        dictateContentStack?.alpha = 1
    }

    public func showSuccessFlash() {
        guard showsDictateButton, let dictateButton else { return }
        recordingDisplayLink?.invalidate()
        recordingDisplayLink = nil

        let checkIcon = UIImageView(image: UIImage(systemName: "checkmark"))
        checkIcon.tintColor = UIColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1.0)
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

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) { [weak self] in
            self?.recordingDotView?.alpha = 0
            self?.borderTraceLayer?.opacity = 0
            checkIcon.alpha = 1
        } completion: { [weak self] _ in
            self?.cleanupProcessingLayers()
            self?.cleanupRecordingLayers()
            dictateButton.layer.removeAnimation(forKey: "recordingPulse")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                    checkIcon.alpha = 0
                } completion: { _ in
                    checkIcon.removeFromSuperview()
                    self?.dictateContentStack?.alpha = 0
                    UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
                        self?.dictateContentStack?.alpha = 1
                    }
                }
            }
        }
    }

    private func cleanupProcessingLayers() {
        borderTraceLayer?.removeAllAnimations()
        borderTraceLayer?.removeFromSuperlayer()
        borderTraceLayer = nil

        if let baseBorder = objc_getAssociatedObject(self, &AssociatedKeys.borderGradient) as? CALayer {
            baseBorder.removeAllAnimations()
            baseBorder.removeFromSuperlayer()
            objc_setAssociatedObject(self, &AssociatedKeys.borderGradient, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        dictateButton?.viewWithTag(999)?.removeFromSuperview()
    }

    private func cleanupRecordingLayers() {
        recordingDotView?.removeFromSuperview()
        recordingDotView = nil
        recordingTimerLabel = nil
        recordingStartTime = nil
    }

    @objc private func dictateTapped() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
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
#endif
