#if canImport(UIKit) && !os(watchOS)
//
//  HostedTalkieKeyboardView.swift
//  TalkieMobileKit
//
//  In-app host for the Talkie keyboard runtime.
//  Reuses the same keyboard modes, layout persistence, and swipe behavior
//  as the extension while allowing the embedding app to inject its own
//  text host and dictation implementation.
//

import UIKit
import ObjectiveC

@available(iOS 17.0, *)
public final class HostedTalkieKeyboardView: UIView, UIGestureRecognizerDelegate {
    public enum InitialLayout: Equatable {
        case persisted
        case compact
        case minimal
    }

    public enum DictationState: Equatable {
        case idle
        case recording
        case processing
    }

    public weak var inputHost: KeyboardInputHost?
    public var onDictationToggle: (() -> Void)?
    public var onLayoutHeightChange: (() -> Void)?
    public var onRequestCollapse: (() -> Void)?
    public var preferredInitialLayout: InitialLayout = .persisted {
        didSet {
            guard oldValue != preferredInitialLayout else { return }
            applyPreferredInitialLayoutIfNeeded()
        }
    }
    public var preferredInitialModeId: String? {
        didSet {
            guard oldValue != preferredInitialModeId else { return }
            applyPreferredInitialModeIfNeeded()
        }
    }
    public var customMinimalSlotConfigs: [Int: SlotConfig]? {
        didSet {
            guard oldValue != customMinimalSlotConfigs else { return }
            if isMinimalLayoutActive {
                rebuildKeyboardContent()
            }
        }
    }
    public var showsMinimalDictateButton = true {
        didSet {
            guard oldValue != showsMinimalDictateButton else { return }
            if isMinimalLayoutActive {
                rebuildKeyboardContent()
            }
        }
    }
    public var allowsMinimalLayout = true {
        didSet {
            guard oldValue != allowsMinimalLayout else { return }
            if !allowsMinimalLayout && isMinimalLayoutActive {
                isMinimalLayoutActive = false
                rebuildKeyboardContent()
            }
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    private enum Design {
        static let standardHeight: CGFloat = 224
        static let topInset: CGFloat = 6
        static let sideInset: CGFloat = 6
        static let bottomInset: CGFloat = 8
        static let edgeGestureExclusion: CGFloat = 18
        static let rowSpacing: CGFloat = 6
        static let gridSpacing: CGFloat = 5
        static let buttonHeight: CGFloat = 48
        static let cornerRadius: CGFloat = 4

        static let background = UIColor.clear
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

        static let surfaceSpecial = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.05)
                : UIColor(white: 1.0, alpha: 0.80)
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
                : UIColor(white: 0.0, alpha: 0.30)
        }

        static let textPrimary = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }

        static let textSecondary = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.6, alpha: 1.0)
                : UIColor(white: 0.4, alpha: 1.0)
        }

        static let textMuted = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.45, alpha: 1.0)
                : UIColor(white: 0.55, alpha: 1.0)
        }

        static let dictationActive = UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1.0)
        static let processing = UIColor(red: 0.34, green: 0.68, blue: 1.0, alpha: 1.0)
        static let success = UIColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1.0)
    }

    private let bridge = KeyboardBridge.shared
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    private var keyboardConfig = KeyboardConfig()
    private var gridPreset: KeyboardGridPreset = .sixteen
    private var dictationState: DictationState = .idle
    private var isMinimalLayoutActive = false

    private let contentHostView = UIView()
    private var activeContentView: UIView?
    private weak var compactKeyboardView: CompactKeyboardView?
    private weak var minimalKeyboardView: MinimalKeyboardView?
    private weak var dictateButton: UIButton?
    private var slotButtons: [Int: UIButton] = [:]
    private var lastResolvedBottomSafeAreaInset: CGFloat = 0

    private var preferredHeight: CGFloat {
        let contentHeight = isMinimalLayoutActive
            ? MinimalKeyboardView.totalHeight + 6
            : Design.standardHeight + 6
        return contentHeight + resolvedBottomSafeAreaInset
    }

    private var resolvedBottomSafeAreaInset: CGFloat {
        max(safeAreaInsets.bottom, window?.safeAreaInsets.bottom ?? 0)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        restorePersistedState()
        rebuildKeyboardContent()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        restorePersistedState()
        rebuildKeyboardContent()
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateForBottomSafeAreaInsetChange()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateForBottomSafeAreaInsetChange()
    }

    public func setDictationState(_ state: DictationState) {
        guard dictationState != state else { return }
        dictationState = state
        applyDictationState()
    }

    public func resetToPreferredInitialLayout() {
        let nextIsMinimal = resolvedPreferredInitialLayoutIsMinimal
        let didChangeMode = updatePreferredInitialModeIfNeeded()
        guard isMinimalLayoutActive != nextIsMinimal || didChangeMode else { return }
        isMinimalLayoutActive = nextIsMinimal
        rebuildKeyboardContent()
    }

    public func showDictationSuccessFeedback() {
        minimalKeyboardView?.showSuccessFlash()
        flashDictateButtonSuccess()
    }

    private func setupUI() {
        backgroundColor = Design.background
        lightImpact.prepare()
        mediumImpact.prepare()

        contentHostView.backgroundColor = .clear
        contentHostView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentHostView)

        NSLayoutConstraint.activate([
            contentHostView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            contentHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])

        let directionalPan = UIPanGestureRecognizer(target: self, action: #selector(handleDirectionalPan(_:)))
        directionalPan.cancelsTouchesInView = false
        directionalPan.maximumNumberOfTouches = 1
        directionalPan.delegate = self
        addGestureRecognizer(directionalPan)
    }

    private func restorePersistedState() {
        gridPreset = bridge.getGridPreset()
        isMinimalLayoutActive = resolvedPreferredInitialLayoutIsMinimal
        if let modeId = bridge.getLastSelectedModeId(maxAge: 60 * 60 * 24),
           keyboardConfig.modeOrder.contains(modeId) {
            keyboardConfig.activeModeId = modeId
        }
    }

    private var resolvedPreferredInitialLayoutIsMinimal: Bool {
        switch preferredInitialLayout {
        case .persisted:
            return allowsMinimalLayout && bridge.getActiveLayout() == "minimal"
        case .compact:
            return false
        case .minimal:
            return allowsMinimalLayout
        }
    }

    private func applyPreferredInitialLayoutIfNeeded() {
        let nextIsMinimal = resolvedPreferredInitialLayoutIsMinimal
        guard isMinimalLayoutActive != nextIsMinimal else { return }
        isMinimalLayoutActive = nextIsMinimal
        rebuildKeyboardContent()
    }

    private func applyPreferredInitialModeIfNeeded() {
        guard updatePreferredInitialModeIfNeeded() else { return }
        rebuildKeyboardContent()
    }

    @discardableResult
    private func updatePreferredInitialModeIfNeeded() -> Bool {
        guard let preferredInitialModeId,
              keyboardConfig.modeOrder.contains(preferredInitialModeId),
              keyboardConfig.activeModeId != preferredInitialModeId else {
            return false
        }

        keyboardConfig.activeModeId = preferredInitialModeId
        return true
    }

    private func rebuildKeyboardContent() {
        activeContentView?.removeFromSuperview()
        compactKeyboardView = nil
        minimalKeyboardView = nil
        dictateButton = nil
        slotButtons.removeAll()

        let contentView: UIView
        if isMinimalLayoutActive {
            contentView = makeMinimalKeyboardView()
        } else if currentMode.id == KeyboardMode.abc.id {
            contentView = makeCompactKeyboardView()
        } else {
            contentView = makeModeGridView()
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),
        ])

        activeContentView = contentView
        applyDictationState()
        invalidateIntrinsicContentSize()
        onLayoutHeightChange?()
    }

    private func updateForBottomSafeAreaInsetChange() {
        let nextInset = resolvedBottomSafeAreaInset
        guard abs(nextInset - lastResolvedBottomSafeAreaInset) > 0.5 else { return }
        lastResolvedBottomSafeAreaInset = nextInset
        invalidateIntrinsicContentSize()
        onLayoutHeightChange?()
    }

    private var currentMode: KeyboardMode {
        keyboardConfig.activeMode
    }

    private func resolvedSlotConfig(slot: Int, for mode: KeyboardMode) -> SlotConfig {
        if let data = bridge.getSlotConfig(slot, forMode: mode.id),
           let config = try? JSONDecoder().decode(SlotConfig.self, from: data) {
            return config
        }

        return mode.config(for: slot)
    }

    private func makeCompactKeyboardView() -> UIView {
        let keyboard = CompactKeyboardView()
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.onKeyTapped = { [weak self] key in
            self?.inputHost?.performKeyboardAction(.insert(key))
        }
        keyboard.onDeleteTapped = { [weak self] in
            self?.inputHost?.performKeyboardAction(.deleteBackward)
        }
        keyboard.onSpaceTapped = { [weak self] in
            self?.inputHost?.performKeyboardAction(.insert(" "))
        }
        keyboard.onReturnTapped = { [weak self] in
            self?.inputHost?.performKeyboardAction(.enter)
        }
        keyboard.onVoiceTapped = { [weak self] in
            self?.onDictationToggle?()
        }
        keyboard.onEmojiTapped = { [weak self] in
            self?.activateMode(KeyboardMode.emoji.id)
        }
        compactKeyboardView = keyboard
        return keyboard
    }

    private func makeMinimalKeyboardView() -> UIView {
        let minimal = MinimalKeyboardView()
        minimal.showsDictateButton = showsMinimalDictateButton
        var configs: [Int: SlotConfig] = [:]
        let slotCount = max(customMinimalSlotConfigs?.keys.max() ?? 4, 4)
        for slot in 1...slotCount {
            if let customMinimalSlotConfigs, let config = customMinimalSlotConfigs[slot] {
                configs[slot] = config
            } else if let data = bridge.getSlotConfig(slot, forMode: KeyboardMode.minimal.id),
               let config = try? JSONDecoder().decode(SlotConfig.self, from: data) {
                configs[slot] = config
            } else {
                configs[slot] = KeyboardMode.minimal.config(for: slot)
            }
        }
        minimal.slotConfigs = configs
        minimal.onDictateTapped = { [weak self] in
            self?.onDictationToggle?()
        }
        minimal.onSlotAction = { [weak self] _, config in
            self?.perform(config)
        }
        minimal.onSwipeUp = { [weak self] in
            self?.switchToLayout(isMinimal: false)
        }
        minimal.updateReadyState(true, modelWarm: bridge.isModelWarm())
        minimalKeyboardView = minimal
        return minimal
    }

    private func makeModeGridView() -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = Design.rowSpacing
        grid.distribution = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        for rowSlots in gridPreset.slotRows {
            grid.addArrangedSubview(makeSlotRow(slots: rowSlots))
        }
        grid.addArrangedSubview(makeDictateRow(forColumnCount: gridPreset.columnCount))

        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: Design.topInset),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Design.sideInset),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Design.sideInset),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Design.bottomInset),
        ])

        return container
    }

    private func makeSlotRow(slots: [Int]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Design.gridSpacing
        row.distribution = .fillEqually

        for slot in slots {
            row.addArrangedSubview(makeSlotButton(slot: slot, config: resolvedSlotConfig(slot: slot, for: currentMode)))
        }

        row.heightAnchor.constraint(equalToConstant: Design.buttonHeight).isActive = true
        return row
    }

    private func makeDictateRow(forColumnCount columnCount: Int) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Design.gridSpacing
        row.distribution = columnCount >= 4 ? .fill : .fillEqually

        let leftButton = makeSlotButton(slot: 13, config: resolvedSlotConfig(slot: 13, for: currentMode))
        let dictate = makeDictateButton()
        let rightButton = makeSlotButton(slot: 14, config: resolvedSlotConfig(slot: 14, for: currentMode))

        row.addArrangedSubview(leftButton)
        row.addArrangedSubview(dictate)
        row.addArrangedSubview(rightButton)

        if columnCount >= 4 {
            leftButton.widthAnchor.constraint(equalTo: rightButton.widthAnchor).isActive = true
            dictate.widthAnchor.constraint(equalTo: leftButton.widthAnchor, multiplier: 2, constant: Design.gridSpacing).isActive = true
        }

        row.heightAnchor.constraint(equalToConstant: Design.buttonHeight).isActive = true
        return row
    }

    private func makeSlotButton(slot: Int, config: SlotConfig) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = slot
        button.layer.cornerRadius = Design.cornerRadius
        applyKeyRestingStyle(to: button)
        attachPressHandlers(to: button)
        button.addTarget(self, action: #selector(slotButtonTapped(_:)), for: .touchUpInside)
        slotButtons[slot] = button
        configureSlotButton(button, config: config)
        return button
    }

    private func makeDictateButton() -> UIButton {
        let button = UIButton(type: .system)
        button.layer.cornerRadius = Design.cornerRadius
        applyKeyRestingStyle(to: button)
        attachPressHandlers(to: button)
        button.addTarget(self, action: #selector(dictateButtonTapped), for: .touchUpInside)
        dictateButton = button
        updateDictateButton(button)
        return button
    }

    private func configureSlotButton(_ button: UIButton, config: SlotConfig) {
        button.subviews.forEach { $0.removeFromSuperview() }
        button.setTitle(nil, for: .normal)
        button.setImage(nil, for: .normal)
        objc_setAssociatedObject(button, &AssociatedSlotConfigKey.key, config, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        switch config.type {
        case .action:
            if config.label == "SHIFT" {
                let label = UILabel()
                label.text = "⇧"
                label.font = .systemFont(ofSize: 18, weight: .semibold)
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
                label.font = .systemFont(ofSize: 14, weight: .semibold)
                label.textColor = Design.textPrimary
                label.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            } else {
                let stack = makeActionStack(iconName: config.icon, label: config.label)
                button.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            }

        case .text, .snippet:
            let label = UILabel()
            label.text = config.label
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = Design.textPrimary
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])

        case .space:
            let label = UILabel()
            label.text = "SPACE"
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = Design.textSecondary
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])

        case .empty:
            break
        }
    }

    private func makeActionStack(iconName: String?, label: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        if label == "PUNC" {
            let iconLabel = UILabel()
            iconLabel.text = ".,?!"
            iconLabel.font = .systemFont(ofSize: 12, weight: .bold)
            iconLabel.textColor = Design.textPrimary
            stack.addArrangedSubview(iconLabel)
        } else if let iconName, !iconName.isEmpty {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            let imageView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: config))
            imageView.tintColor = Design.textPrimary
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
            stack.addArrangedSubview(imageView)
        }

        let labelView = UILabel()
        labelView.text = label
        labelView.font = .systemFont(ofSize: 8, weight: .medium)
        labelView.textColor = Design.textSecondary
        stack.addArrangedSubview(labelView)
        return stack
    }

    private func updateDictateButton(_ button: UIButton) {
        button.subviews.forEach { $0.removeFromSuperview() }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

        let imageName: String
        let labelText: String
        let tintColor: UIColor

        switch dictationState {
        case .idle:
            imageName = "mic.fill"
            labelText = "DICTATE"
            tintColor = Design.textPrimary
            button.backgroundColor = Design.surfaceSpecial
            button.layer.borderColor = Design.keyBorder.cgColor
        case .recording:
            imageName = "stop.fill"
            labelText = "STOP"
            tintColor = .white
            button.backgroundColor = Design.dictationActive
            button.layer.borderColor = Design.dictationActive.cgColor
        case .processing:
            imageName = "ellipsis"
            labelText = "PROCESS"
            tintColor = .white
            button.backgroundColor = Design.processing
            button.layer.borderColor = Design.processing.cgColor
        }

        let imageView = UIImageView(image: UIImage(systemName: imageName))
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = UILabel()
        label.text = labelText
        label.font = .systemFont(ofSize: 8, weight: .medium)
        label.textColor = tintColor.withAlphaComponent(0.92)

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(label)
        button.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
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

    private func applyDictationState() {
        switch dictationState {
        case .idle:
            compactKeyboardView?.setDictationState(.idle)
            minimalKeyboardView?.stopRecordingFeedback()
            minimalKeyboardView?.stopProcessingAnimation()
            minimalKeyboardView?.updateReadyState(true, modelWarm: bridge.isModelWarm())
        case .recording:
            compactKeyboardView?.setDictationState(.recording)
            minimalKeyboardView?.stopProcessingAnimation()
            minimalKeyboardView?.startRecordingFeedback()
        case .processing:
            compactKeyboardView?.setDictationState(.processing)
            minimalKeyboardView?.stopRecordingFeedback()
            minimalKeyboardView?.startProcessingAnimation()
        }

        if let dictateButton {
            updateDictateButton(dictateButton)
        }
    }

    private func flashDictateButtonSuccess() {
        guard let dictateButton else { return }
        let previousColor = dictateButton.backgroundColor
        UIView.animate(withDuration: 0.16, animations: {
            dictateButton.backgroundColor = Design.success
        }) { _ in
            UIView.animate(withDuration: 0.18, delay: 0.25) {
                dictateButton.backgroundColor = previousColor
            }
        }
    }

    private func perform(_ config: SlotConfig) {
        switch config.label {
        case "Aa":
            activateMode(KeyboardMode.abc.id)
        case "PUNC":
            activateMode(KeyboardMode.symbols.id)
        case "VOICE":
            onDictationToggle?()
        default:
            guard let inputHost else { return }
            KeyboardActionResolver.perform(config, on: inputHost)
        }
    }

    private func activateMode(_ modeId: String) {
        guard keyboardConfig.modeOrder.contains(modeId) else { return }
        mediumImpact.impactOccurred()
        keyboardConfig.activeModeId = modeId
        bridge.setLastSelectedModeId(modeId)
        rebuildKeyboardContent()
    }

    private func cycleMode(forward: Bool) {
        let modes = keyboardConfig.modeOrder
        guard let index = modes.firstIndex(of: keyboardConfig.activeModeId) else { return }
        let nextIndex: Int
        if forward {
            nextIndex = (index + 1) % modes.count
        } else {
            nextIndex = (index - 1 + modes.count) % modes.count
        }
        activateMode(modes[nextIndex])
    }

    private func switchToLayout(isMinimal: Bool) {
        guard allowsMinimalLayout || !isMinimal else { return }
        guard isMinimalLayoutActive != isMinimal else { return }
        mediumImpact.impactOccurred()
        isMinimalLayoutActive = isMinimal
        if allowsMinimalLayout {
            bridge.setActiveLayout(isMinimal ? "minimal" : "compact")
        }
        rebuildKeyboardContent()
    }

    @objc
    private func handleDirectionalPan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        let isVertical = abs(translation.y) > abs(translation.x)

        if isVertical {
            if !allowsMinimalLayout {
                if translation.y > 30 || velocity.y > 480 {
                    onRequestCollapse?()
                }
                return
            }
            if translation.y > 30 || velocity.y > 480 {
                if !isMinimalLayoutActive {
                    switchToLayout(isMinimal: true)
                }
            } else if translation.y < -30 || velocity.y < -480 {
                if isMinimalLayoutActive {
                    switchToLayout(isMinimal: false)
                }
            }
            return
        }

        if translation.x < -28 || velocity.x < -420 {
            if isMinimalLayoutActive {
                switchToLayout(isMinimal: false)
            } else {
                cycleMode(forward: false)
            }
        } else if translation.x > 28 || velocity.x > 420 {
            if isMinimalLayoutActive {
                switchToLayout(isMinimal: false)
            } else {
                cycleMode(forward: true)
            }
        }
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self)
        return point.x > Design.edgeGestureExclusion && point.x < bounds.width - Design.edgeGestureExclusion
    }

    @objc
    private func keyTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.07, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = CGAffineTransform(scaleX: 0.982, y: 0.982)
            self.applyKeyPressedStyle(to: sender)
        }
    }

    @objc
    private func keyTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = .identity
            self.applyKeyRestingStyle(to: sender)
            if sender === self.dictateButton {
                self.updateDictateButton(sender)
            }
        }
    }

    @objc
    private func slotButtonTapped(_ sender: UIButton) {
        guard let config = objc_getAssociatedObject(sender, &AssociatedSlotConfigKey.key) as? SlotConfig else {
            return
        }
        perform(config)
    }

    @objc
    private func dictateButtonTapped() {
        mediumImpact.impactOccurred()
        onDictationToggle?()
    }
}

private enum AssociatedSlotConfigKey {
    static var key = 0
}
#endif
