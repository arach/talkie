//
//  CompactKeyboardView.swift
//  TalkieMobileKit
//
//  Shared compact full QWERTY keyboard with long-press for accents.
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

private let log = Log(.ui)

// MARK: - Accent Mappings

private let accentMappings: [String: [String]] = [
    // Vowels with accents
    "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
    "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
    "i": ["ì", "í", "î", "ï", "ī", "į"],
    "o": ["ò", "ó", "ô", "ö", "õ", "ø", "ō", "œ"],
    "u": ["ù", "ú", "û", "ü", "ū"],
    "y": ["ÿ", "ý"],
    // Consonants with accents
    "c": ["ç", "ć", "č"],
    "n": ["ñ", "ń"],
    "s": ["ß", "ś", "š"],
    "z": ["ž", "ź", "ż"],
    "l": ["ł"],
    "d": ["ð"],
    // Numbers with symbols (for number row)
    "1": ["!", "¡", "¹"],
    "2": ["@", "²"],
    "3": ["#", "³"],
    "4": ["$", "¢", "£", "€"],
    "5": ["%", "‰"],
    "6": ["^", "¨"],
    "7": ["&"],
    "8": ["*"],
    "9": ["("],
    "0": [")", "°"],
    // Punctuation
    ".": ["…", ",", "?", "!", "'", "\"", "-", ":", ";"],
    ",": ["‚", "„"],
    "?": ["¿"],
    "!": ["¡"],
    "'": ["'", "'", "‚", "‛", "\""],
    "-": ["–", "—", "−"],
]

// MARK: - Key Button

private class KeyButton: UIButton {
    var keyValue: String = ""
    var isShiftKey = false
    var isDeleteKey = false
    var isSpaceKey = false
    var isReturnKey = false
    var isSymbolKey = false
    var isModeKey = false
    var isEmojiKey = false

    // For accent popup
    var hasAccents: Bool {
        return accentMappings[keyValue.lowercased()] != nil
    }

    // Slightly forgiving hit slop helps capture fast repeated taps on narrow keys.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -6, dy: -8)
        return expandedBounds.contains(point)
    }
}

// MARK: - Compact Keyboard View

public final class CompactKeyboardView: UIView {

    // MARK: - Adaptive Colors (Talkie Branded)

    private enum Colors {
        /// Keyboard background - fully transparent to match iOS
        static let background = UIColor.clear

        /// Regular key background
        static let keyBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.03)
                : UIColor(white: 1.0, alpha: 0.74)
        }

        /// Key pressed/hover state
        static let keyPressed = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.92)
        }

        /// Special key background (shift, delete, etc.)
        static let specialKey = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.05)
                : UIColor(white: 1.0, alpha: 0.80)
        }

        /// Special key active state (shift enabled)
        static let specialKeyActive = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.14)
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

        /// Key text color
        static let keyText = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        }

        /// Vermillion brand color
        static let vermillion = UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1.0)

        /// Return key blue
        static let returnBlue = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)

        /// Accent popup background
        static let popupBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 0.98)
                : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 0.98)
        }

        /// Key shadow color
        static let keyShadow = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black
                : UIColor(white: 0.0, alpha: 0.3)
        }
    }

    // MARK: - Callbacks

    public var onKeyTapped: ((String) -> Void)?
    public var onDeleteTapped: (() -> Void)?
    public var onReturnTapped: (() -> Void)?
    public var onSpaceTapped: (() -> Void)?
    public var onVoiceTapped: (() -> Void)?
    public var onEmojiTapped: (() -> Void)?
    public var onShiftDebugRequested: (() -> Void)?
    public var onDismiss: (() -> Void)?

    // MARK: - Haptic Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let bridge = KeyboardBridge.shared
    private var hapticFeedbackEnabled = true

    // MARK: - State

    private var isShifted = false
    private var isCapsLock = false
    private var isShowingNumbers = false
    private var isShowingSymbols = false
    private var isDictationActive = false

    // MARK: - UI

    private var keyButtons: [KeyButton] = []
    private var accentPopup: UIView?
    private var punctuationPopup: UIView?
    private var accentButtons: [UIButton] = []
    private var activeKeyForAccent: KeyButton?
    private var keyRestingShadowOpacity: Float {
        traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.05
    }

    // Layout constants - comfortable spacing for better usability
    private let keyHeight: CGFloat = 44
    private let keySpacing: CGFloat = 6
    private let rowSpacing: CGFloat = 8
    private let sidePadding: CGFloat = 3
    private let topPadding: CGFloat = 8
    private let bottomPadding: CGFloat = 6
    private let row4ModePreferredWidth: CGFloat = 40
    private let row4EmojiPreferredWidth: CGFloat = 40
    private let row4PeriodPreferredWidth: CGFloat = 38
    private let row4ReturnPreferredWidth: CGFloat = 64
    private let homeRowReferenceSpacing: CGFloat = 5
    private var spaceWidthReference: CGFloat?
    private var spaceFrameReference: CGRect?
    private let spaceStateHintStackTag = 992

    // Key rows — letters
    private let letterRow1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let letterRow2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private let letterRow3 = ["z", "x", "c", "v", "b", "n", "m"]

    // Key rows — numbers
    private let numberRow1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let numberRow2 = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
    private let numberRow3 = [".", ",", "?", "!", "'"]

    // Key rows — symbols
    private let symbolRow1 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
    private let symbolRow2 = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
    private let symbolRow3 = [".", ",", "?", "!", "'"]  // same as numberRow3

    private var suppressShiftTapUntil: CFTimeInterval = 0
    private let spaceIdleHintStackTag = 991

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Trait Changes (Light/Dark Mode)

    private func registerColorAppearanceObservation() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            self.handleColorAppearanceChange(previousTraitCollection: previousTraitCollection)
        }
    }

    private func handleColorAppearanceChange(previousTraitCollection: UITraitCollection?) {
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        // Update shadow colors (CGColor doesn't auto-update)
        for btn in keyButtons {
            btn.layer.shadowColor = Colors.keyShadow.cgColor
            btn.layer.borderColor = Colors.keyBorder.cgColor
            btn.layer.shadowOpacity = keyRestingShadowOpacity
        }
        accentPopup?.layer.shadowColor = Colors.keyShadow.cgColor
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = Colors.background
        lightImpact.prepare()
        mediumImpact.prepare()
        registerColorAppearanceObservation()
        buildKeyboard()
    }

    private func buildKeyboard() {
        // Clear existing
        keyButtons.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()
        dismissAccentPopup()
        dismissPunctuationPopup()
        hapticFeedbackEnabled = bridge.getHapticFeedbackEnabled()

        if isShowingSymbols {
            buildSymbolKeyboard()
        } else if isShowingNumbers {
            buildNumberKeyboard()
        } else {
            buildLetterKeyboard()
        }

        // Keep dictation affordance stable if the keyboard is rebuilt mid-session.
        applyDictationState(currentDictationState, animated: false)
    }

    // MARK: - Build Letter Keyboard

    private func buildLetterKeyboard() {
        // Row 1: Q W E R T Y U I O P
        for (index, key) in letterRow1.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 100 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        // Row 2: A S D F G H J K L
        for (index, key) in letterRow2.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 200 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        // Row 3: Shift + Z X C V B N M + Delete
        let shiftBtn = createSpecialButton("⇧", isShift: true)
        shiftBtn.tag = 300
        keyButtons.append(shiftBtn)
        addSubview(shiftBtn)

        for (index, key) in letterRow3.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 301 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        let deleteBtn = createSpecialButton("⌫", isDelete: true)
        deleteBtn.tag = 308
        keyButtons.append(deleteBtn)
        addSubview(deleteBtn)

        // Row 4: [123][emoji][space][voice][.][return]
        buildRow4Buttons()
    }

    // MARK: - Build Number Keyboard

    private func buildNumberKeyboard() {
        // Row 1: 1 2 3 4 5 6 7 8 9 0
        for (index, key) in numberRow1.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 100 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        // Row 2: - / : ; ( ) $ & @ "
        for (index, key) in numberRow2.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 200 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        // Row 3: #+= + . , ? ! ' + Delete
        let moreBtn = createSpecialButton("#+=", isSymbol: true)
        moreBtn.tag = 300
        keyButtons.append(moreBtn)
        addSubview(moreBtn)

        for (index, key) in numberRow3.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 301 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        let deleteBtn = createSpecialButton("⌫", isDelete: true)
        deleteBtn.tag = 306
        keyButtons.append(deleteBtn)
        addSubview(deleteBtn)

        // Row 4: [ABC][emoji][space][voice][.][return]
        buildRow4Buttons()
    }

    // MARK: - Build Symbol Keyboard

    private func buildSymbolKeyboard() {
        // Row 1: [ ] { } # % ^ * + =
        for (index, key) in symbolRow1.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 100 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        // Row 2: _ \ | ~ < > € £ ¥ •
        for (index, key) in symbolRow2.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 200 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        // Row 3: 123 + . , ? ! ' + Delete
        let numBtn = createSpecialButton("123", isSymbol: true)
        numBtn.tag = 300
        keyButtons.append(numBtn)
        addSubview(numBtn)

        for (index, key) in symbolRow3.enumerated() {
            let btn = createKeyButton(key)
            btn.tag = 301 + index
            keyButtons.append(btn)
            addSubview(btn)
        }

        let deleteBtn = createSpecialButton("⌫", isDelete: true)
        deleteBtn.tag = 306
        keyButtons.append(deleteBtn)
        addSubview(deleteBtn)

        // Row 4: [ABC][emoji][space][voice][.][return]
        buildRow4Buttons()
    }

    // MARK: - Build Row 4 (shared across all modes)

    private func buildRow4Buttons() {
        // Mode toggle: 123 (from letters) or ABC (from numbers/symbols)
        let modeLabel = (isShowingNumbers || isShowingSymbols) ? "ABC" : "123"
        let modeBtn = createSpecialButton(modeLabel, isMode: true)
        modeBtn.tag = 410
        keyButtons.append(modeBtn)
        addSubview(modeBtn)

        // Emoji button
        let emojiBtn = createSpecialButton("", isEmoji: true)
        emojiBtn.tag = 411
        keyButtons.append(emojiBtn)
        addSubview(emojiBtn)

        // Space bar (long-press triggers dictation)
        let spaceBtn = createSpecialButton("space", isSpace: true)
        spaceBtn.tag = 412
        let spaceLongPress = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPressed(_:)))
        spaceLongPress.minimumPressDuration = 0.4
        spaceBtn.addGestureRecognizer(spaceLongPress)
        keyButtons.append(spaceBtn)
        addSubview(spaceBtn)

        // Period
        let periodBtn = createKeyButton(".")
        periodBtn.tag = 413
        let periodLongPress = UILongPressGestureRecognizer(target: self, action: #selector(periodLongPressed(_:)))
        periodLongPress.minimumPressDuration = 0.3
        periodLongPress.delaysTouchesBegan = false
        periodBtn.addGestureRecognizer(periodLongPress)
        keyButtons.append(periodBtn)
        addSubview(periodBtn)

        // Return
        let returnBtn = createSpecialButton("return", isReturn: true)
        returnBtn.tag = 414
        keyButtons.append(returnBtn)
        addSubview(returnBtn)
    }

    // MARK: - Button Creators

    private func createKeyButton(_ key: String) -> KeyButton {
        let btn = KeyButton(type: .system)
        btn.keyValue = key

        let displayKey = (isShifted || isCapsLock) ? key.uppercased() : key
        btn.setTitle(displayKey, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 23, weight: .light)
        btn.setTitleColor(Colors.keyText, for: .normal)
        btn.backgroundColor = Colors.keyBackground
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 0.45
        btn.layer.borderColor = Colors.keyBorder.cgColor
        btn.layer.shadowColor = Colors.keyShadow.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        btn.layer.shadowRadius = 1.2
        btn.layer.shadowOpacity = keyRestingShadowOpacity

        btn.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        btn.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
        btn.addTarget(self, action: #selector(keyTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        // Add long press for accents
        if btn.hasAccents {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(keyLongPressed(_:)))
            longPress.minimumPressDuration = 0.3
            longPress.delaysTouchesBegan = false
            btn.addGestureRecognizer(longPress)
        }

        return btn
    }

    private func createSpecialButton(_ label: String, isShift: Bool = false, isDelete: Bool = false,
                                      isSpace: Bool = false, isReturn: Bool = false,
                                      isSymbol: Bool = false,
                                      isMode: Bool = false, isEmoji: Bool = false) -> KeyButton {
        let btn = KeyButton(type: .system)
        btn.isShiftKey = isShift
        btn.isDeleteKey = isDelete
        btn.isSpaceKey = isSpace
        btn.isReturnKey = isReturn
        btn.isSymbolKey = isSymbol
        btn.isModeKey = isMode
        btn.isEmojiKey = isEmoji

        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let shiftConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        if isSpace {
            btn.setTitle("", for: .normal)
            btn.backgroundColor = Colors.keyBackground  // Space bar like regular keys
        } else if isEmoji {
            // Emoji globe button
            btn.setImage(UIImage(systemName: "face.smiling", withConfiguration: config), for: .normal)
            btn.tintColor = Colors.keyText
            btn.setTitle(nil, for: .normal)
            btn.backgroundColor = Colors.specialKey
        } else if isDelete {
            // Use SF Symbol for delete
            btn.setImage(UIImage(systemName: "delete.left.fill", withConfiguration: config), for: .normal)
            btn.tintColor = Colors.keyText
            btn.setTitle(nil, for: .normal)
            btn.backgroundColor = Colors.specialKey
        } else if isReturn {
            // Return key - same style as other special keys
            btn.setImage(UIImage(systemName: "return", withConfiguration: config), for: .normal)
            btn.tintColor = Colors.keyText
            btn.setTitle(nil, for: .normal)
            btn.backgroundColor = Colors.specialKey
        } else if isShift {
            // Shift key with icon
            btn.setImage(UIImage(systemName: "shift", withConfiguration: shiftConfig), for: .normal)
            btn.tintColor = Colors.keyText
            btn.setTitle(nil, for: .normal)
            btn.backgroundColor = Colors.specialKey
        } else {
            // Text-labeled special keys: mode (123/ABC), symbol (#+=), etc.
            btn.setTitle(label, for: .normal)
            btn.backgroundColor = Colors.specialKey
        }

        btn.titleLabel?.font = .systemFont(ofSize: (isSymbol || isMode) ? 15 : 16, weight: .medium)
        btn.setTitleColor(Colors.keyText, for: .normal)
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 0.45
        btn.layer.borderColor = Colors.keyBorder.cgColor
        btn.layer.shadowColor = Colors.keyShadow.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        btn.layer.shadowRadius = 1.2
        btn.layer.shadowOpacity = keyRestingShadowOpacity

        if isShift && (isShifted || isCapsLock) {
            btn.backgroundColor = Colors.specialKeyActive
        }

        btn.addTarget(self, action: #selector(specialKeyTapped(_:)), for: .touchUpInside)
        btn.addTarget(self, action: #selector(specialKeyTouchDown(_:)), for: .touchDown)
        btn.addTarget(
            self,
            action: #selector(specialKeyTouchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )

        // Delete key repeats on hold
        if isDelete {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPressed(_:)))
            longPress.minimumPressDuration = 0.3
            longPress.delaysTouchesBegan = false
            btn.addGestureRecognizer(longPress)
        }

        if isShift {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(shiftLongPressed(_:)))
            longPress.minimumPressDuration = 0.45
            longPress.delaysTouchesBegan = false
            btn.addGestureRecognizer(longPress)

            // Deep long-press on shift exports debug state (used for troubleshooting).
            let debugPress = UILongPressGestureRecognizer(target: self, action: #selector(shiftDebugLongPressed(_:)))
            debugPress.minimumPressDuration = 1.15
            debugPress.delaysTouchesBegan = false
            btn.addGestureRecognizer(debugPress)
        }

        return btn
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Calculate available height from full bounds.
        // Keep bottomPadding in the spacing equation only once to avoid an upward bias.
        let availableHeight = bounds.height

        // Calculate dynamic key height to fit in available space.
        // Total: 4 rows + 3 row spacings + top + bottom padding.
        let totalVerticalSpacing = rowSpacing * 3 + topPadding + bottomPadding
        let dynamicKeyHeight = min(keyHeight, (availableHeight - totalVerticalSpacing) / 4)

        // Start from top with a tight, stable inset.
        let startY: CGFloat = topPadding
        let row1Y = startY
        let row2Y = row1Y + dynamicKeyHeight + rowSpacing
        let row3Y = row2Y + dynamicKeyHeight + rowSpacing
        let row4Y = row3Y + dynamicKeyHeight + rowSpacing

        let isNonLetterMode = isShowingNumbers || isShowingSymbols

        // Row 1: 10 keys
        layoutRow(startTag: 100, count: 10, y: row1Y, fullWidth: true, keyHeight: dynamicKeyHeight)

        // Row 2: 9 keys (letters, centered) or 10 keys (numbers/symbols, full width)
        layoutRow(startTag: 200, count: isNonLetterMode ? 10 : 9, y: row2Y, fullWidth: isNonLetterMode, keyHeight: dynamicKeyHeight)

        // Row 3: Shift/Symbol + keys + Delete
        layoutRow3(y: row3Y, keyHeight: dynamicKeyHeight)

        // Row 4: [mode][emoji][space][voice][.][return]
        layoutRow4(y: row4Y, keyHeight: dynamicKeyHeight)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let resolved = super.hitTest(point, with: event)
        if let resolved, resolved !== self {
            return resolved
        }
        return nearestLetterKeyHitTarget(for: point) ?? resolved
    }

    private func nearestLetterKeyHitTarget(for point: CGPoint) -> UIView? {
        guard !isShowingNumbers, !isShowingSymbols else { return nil }

        var bestButton: KeyButton?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for button in keyButtons {
            guard button.keyValue.isEmpty == false else { continue }
            // Letter rows only; avoids stealing taps meant for function row/special keys.
            guard (100...109).contains(button.tag) || (200...208).contains(button.tag) || (301...307).contains(button.tag) else {
                continue
            }

            let permissiveFrame = button.frame.insetBy(dx: -7, dy: -10)
            guard permissiveFrame.contains(point) else { continue }

            let distance = hypot(point.x - button.frame.midX, point.y - button.frame.midY)
            if distance < bestDistance {
                bestDistance = distance
                bestButton = button
            }
        }

        return bestButton
    }

    private func layoutRow(startTag: Int, count: Int, y: CGFloat, fullWidth: Bool, keyHeight: CGFloat) {
        let availableWidth = bounds.width - sidePadding * 2
        let totalSpacing = keySpacing * CGFloat(count - 1)
        let keyWidth = (availableWidth - totalSpacing) / CGFloat(count)

        let inset: CGFloat = fullWidth ? 0 : keyWidth * 0.5
        let startX = sidePadding + inset
        let adjustedWidth = fullWidth ? keyWidth : (availableWidth - totalSpacing - inset * 2) / CGFloat(count)

        for i in 0..<count {
            if let btn = keyButtons.first(where: { $0.tag == startTag + i }) {
                let x = startX + CGFloat(i) * (adjustedWidth + keySpacing)
                btn.frame = CGRect(x: x, y: y, width: adjustedWidth, height: keyHeight)
            }
        }
    }

    private func layoutRow3(y: CGFloat, keyHeight: CGFloat) {
        let availableWidth = bounds.width - sidePadding * 2
        let isNonLetterMode = isShowingNumbers || isShowingSymbols

        // Shift/Symbol and Delete are fixed width
        let letterCount = isNonLetterMode ? numberRow3.count : letterRow3.count
        let specialWidth: CGFloat = 42
        let totalSpacing = keySpacing * CGFloat(letterCount + 1)
        let letterWidth = (availableWidth - specialWidth * 2 - totalSpacing) / CGFloat(letterCount)

        // Left special button (Shift / #+= / 123)
        if let leftBtn = keyButtons.first(where: { $0.tag == 300 }) {
            leftBtn.frame = CGRect(x: sidePadding, y: y, width: specialWidth, height: keyHeight)
        }

        // Middle keys
        var x = sidePadding + specialWidth + keySpacing
        for i in 0..<letterCount {
            if let btn = keyButtons.first(where: { $0.tag == 301 + i }) {
                btn.frame = CGRect(x: x, y: y, width: letterWidth, height: keyHeight)
                x += letterWidth + keySpacing
            }
        }

        // Delete button
        let deleteTag = isNonLetterMode ? 306 : 308
        if let deleteBtn = keyButtons.first(where: { $0.tag == deleteTag }) {
            deleteBtn.frame = CGRect(x: bounds.width - sidePadding - specialWidth, y: y, width: specialWidth, height: keyHeight)
        }
    }

    private func layoutRow4(y: CGFloat, keyHeight: CGFloat) {
        let availableWidth = bounds.width - sidePadding * 2
        let spacing = keySpacing
        let rowStartX = sidePadding
        let rowEndX = sidePadding + availableWidth

        var modeWidth: CGFloat
        var emojiWidth: CGFloat
        var periodWidth: CGFloat
        var returnWidth: CGFloat
        var resolvedSpaceFrame: CGRect

        if let reference = spaceFrameReference, reference.width > 0, reference.height > 0 {
            // Exact imprint mode: lock compact spacebar to the slot-grid dictate frame.
            let clampedX = min(max(reference.minX, rowStartX), rowEndX - reference.width)
            resolvedSpaceFrame = CGRect(
                x: clampedX,
                y: reference.minY,
                width: reference.width,
                height: reference.height
            )

            let leftAvailable = max(resolvedSpaceFrame.minX - rowStartX - spacing * 2, 0)
            let leftPreferred = row4ModePreferredWidth + row4EmojiPreferredWidth
            let leftScale = leftPreferred > 0 ? leftAvailable / leftPreferred : 1
            modeWidth = max(row4ModePreferredWidth * leftScale, 0)
            emojiWidth = max(leftAvailable - modeWidth, 0)

            let rightAvailable = max(rowEndX - resolvedSpaceFrame.maxX - spacing * 2, 0)
            let rightPreferred = row4PeriodPreferredWidth + row4ReturnPreferredWidth
            let rightScale = rightPreferred > 0 ? rightAvailable / rightPreferred : 1
            periodWidth = max(row4PeriodPreferredWidth * rightScale, 0)
            returnWidth = max(rightAvailable - periodWidth, 0)
        } else {
            // Fallback geometry: derive from compact home-row center pair.
            let singleHomeSlotWidth = (availableWidth - (homeRowReferenceSpacing * 3)) / 4
            let derivedSpaceWidth = (singleHomeSlotWidth * 2) + homeRowReferenceSpacing
            let targetSpaceWidth = max(spaceWidthReference ?? derivedSpaceWidth, 60)

            let surroundingAvailable = max(availableWidth - targetSpaceWidth - spacing * 4, 0)
            let preferredSurroundingTotal = row4ModePreferredWidth
                + row4EmojiPreferredWidth
                + row4PeriodPreferredWidth
                + row4ReturnPreferredWidth
            let surroundingScale = preferredSurroundingTotal > 0 ? surroundingAvailable / preferredSurroundingTotal : 1

            modeWidth = row4ModePreferredWidth * surroundingScale
            emojiWidth = row4EmojiPreferredWidth * surroundingScale
            periodWidth = row4PeriodPreferredWidth * surroundingScale
            returnWidth = max(surroundingAvailable - modeWidth - emojiWidth - periodWidth, 0)

            let spaceX = rowStartX + modeWidth + spacing + emojiWidth + spacing
            resolvedSpaceFrame = CGRect(x: spaceX, y: y, width: targetSpaceWidth, height: keyHeight)
        }

        // Mode (123 / ABC)
        if let modeBtn = keyButtons.first(where: { $0.tag == 410 }) {
            let modeX = resolvedSpaceFrame.minX - spacing - emojiWidth - spacing - modeWidth
            modeBtn.frame = CGRect(x: modeX, y: resolvedSpaceFrame.minY, width: modeWidth, height: resolvedSpaceFrame.height)
        }

        // Emoji
        if let emojiBtn = keyButtons.first(where: { $0.tag == 411 }) {
            let emojiX = resolvedSpaceFrame.minX - spacing - emojiWidth
            emojiBtn.frame = CGRect(x: emojiX, y: resolvedSpaceFrame.minY, width: emojiWidth, height: resolvedSpaceFrame.height)
        }

        // Space bar (long-press for dictation)
        if let spaceBtn = keyButtons.first(where: { $0.tag == 412 }) {
            spaceBtn.frame = resolvedSpaceFrame
        }

        // Period
        if let periodBtn = keyButtons.first(where: { $0.tag == 413 }) {
            let periodX = resolvedSpaceFrame.maxX + spacing
            periodBtn.frame = CGRect(x: periodX, y: resolvedSpaceFrame.minY, width: periodWidth, height: resolvedSpaceFrame.height)
        }

        // Return
        if let returnBtn = keyButtons.first(where: { $0.tag == 414 }) {
            let returnX = resolvedSpaceFrame.maxX + spacing + periodWidth + spacing
            returnBtn.frame = CGRect(x: returnX, y: resolvedSpaceFrame.minY, width: returnWidth, height: resolvedSpaceFrame.height)
        }
    }

    // MARK: - Actions

    private func pressScale(for button: UIButton) -> CGFloat {
        let width = max(button.bounds.width, 1)
        let height = max(button.bounds.height, 1)
        let aspect = width / height
        if aspect >= 1.8 { return 0.988 }   // Wide keys like space bar / return
        if aspect >= 1.3 { return 0.982 }   // Medium keys
        return 0.975                         // Standard letter keys
    }

    private func pressTransform(for button: UIButton) -> CGAffineTransform {
        let scale = pressScale(for: button)
        let translation = CGAffineTransform(translationX: 0, y: 0.6)
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        return translation.concatenating(scaleTransform)
    }

    private func applySpecialKeyRestingStyle(_ button: KeyButton) {
        button.layer.borderColor = Colors.keyBorder.cgColor
        button.layer.shadowOpacity = keyRestingShadowOpacity

        if button.isShiftKey {
            if isCapsLock || isShifted {
                button.backgroundColor = Colors.specialKeyActive
            } else {
                button.backgroundColor = Colors.specialKey
            }
            return
        }

        if button.isSpaceKey {
            if isDictationActive {
                return
            }
            button.backgroundColor = Colors.keyBackground
            return
        }

        button.backgroundColor = Colors.specialKey
    }

    @objc private func keyTapped(_ sender: KeyButton) {
        dismissPunctuationPopup()

        let key = (isShifted || isCapsLock) ? sender.keyValue.uppercased() : sender.keyValue
        onKeyTapped?(key)

        // Auto-unshift after typing (unless caps lock)
        if isShifted && !isCapsLock {
            isShifted = false
            updateKeyLabels()
        }
    }

    @objc private func keyTouchDown(_ sender: KeyButton) {
        if hapticFeedbackEnabled {
            lightImpact.impactOccurred(intensity: 0.5)
            lightImpact.prepare()
        }
        UIView.animate(withDuration: 0.05, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = self.pressTransform(for: sender)
            sender.backgroundColor = Colors.keyPressed
            sender.layer.borderColor = Colors.keyBorderPressed.cgColor
            sender.layer.shadowOpacity = 0.02
        }
    }

    @objc private func keyTouchUp(_ sender: KeyButton) {
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            usingSpringWithDamping: 0.76,
            initialSpringVelocity: 0.45,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            sender.transform = .identity
            sender.backgroundColor = Colors.keyBackground
            sender.layer.borderColor = Colors.keyBorder.cgColor
            sender.layer.shadowOpacity = self.keyRestingShadowOpacity
        }
    }

    @objc private func specialKeyTouchDown(_ sender: KeyButton) {
        if hapticFeedbackEnabled {
            lightImpact.impactOccurred(intensity: 0.45)
            lightImpact.prepare()
        }
        UIView.animate(withDuration: 0.05, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            sender.transform = self.pressTransform(for: sender)
            sender.backgroundColor = Colors.keyPressed
            sender.layer.borderColor = Colors.keyBorderPressed.cgColor
            sender.layer.shadowOpacity = 0.02
        }
    }

    @objc private func specialKeyTouchUp(_ sender: KeyButton) {
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            usingSpringWithDamping: 0.76,
            initialSpringVelocity: 0.45,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            sender.transform = .identity
            self.applySpecialKeyRestingStyle(sender)
        }
    }

    @objc private func specialKeyTapped(_ sender: KeyButton) {
        dismissPunctuationPopup()

        if sender.isShiftKey {
            if CACurrentMediaTime() < suppressShiftTapUntil {
                return
            }
            // Double tap for caps lock
            if isShifted && !isCapsLock {
                isCapsLock = true
            } else if isCapsLock {
                isCapsLock = false
                isShifted = false
            } else {
                isShifted = true
            }
            updateKeyLabels()
            updateShiftButton()
        } else if sender.isDeleteKey {
            onDeleteTapped?()
        } else if sender.isSpaceKey {
            if isDictationActive {
                onVoiceTapped?()  // Tap spacebar to stop dictation
            } else {
                onSpaceTapped?()
            }
        } else if sender.isReturnKey {
            onReturnTapped?()
        } else if sender.isEmojiKey {
            onEmojiTapped?()
        } else if sender.isModeKey {
            // Row 4 mode toggle: letters ↔ numbers
            if isShowingNumbers || isShowingSymbols {
                isShowingNumbers = false
                isShowingSymbols = false
            } else {
                isShowingNumbers = true
            }
            buildKeyboard()
            setNeedsLayout()
        } else if sender.isSymbolKey {
            // Row 3 toggle: numbers ↔ symbols
            isShowingSymbols.toggle()
            buildKeyboard()
            setNeedsLayout()
        }
    }

    @objc private func keyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let btn = gesture.view as? KeyButton else { return }

        switch gesture.state {
        case .began:
            showAccentPopup(for: btn)
        case .changed:
            updateAccentSelection(for: gesture)
        case .ended, .cancelled:
            selectAccentAndDismiss(for: gesture)
        default:
            break
        }
    }

    @objc private func deleteLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            startDeleteRepeat()
        case .ended, .cancelled:
            stopDeleteRepeat()
        default:
            break
        }
    }

    @objc private func shiftLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        suppressShiftTapUntil = CACurrentMediaTime() + 0.4

        // Caps lock on long press
        isCapsLock = true
        isShifted = true
        updateKeyLabels()
        updateShiftButton()
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    @objc private func shiftDebugLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        onShiftDebugRequested?()
    }

    private var deleteRepeatTimer: Timer?

    private func startDeleteRepeat() {
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.onDeleteTapped?()
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    @objc private func spaceLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        mediumImpact.impactOccurred()
        onVoiceTapped?()
    }

    @objc private func periodLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? KeyButton else { return }
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
        showPunctuationPopup(for: button)
    }



    // MARK: - Accent Popup

    private func showAccentPopup(for key: KeyButton) {
        dismissPunctuationPopup()
        guard let accents = accentMappings[key.keyValue.lowercased()] else { return }

        activeKeyForAccent = key

        // Remove existing popup
        accentPopup?.removeFromSuperview()
        accentButtons.removeAll()

        let popup = UIView()
        popup.backgroundColor = Colors.popupBackground
        popup.layer.cornerRadius = 8
        popup.layer.shadowColor = Colors.keyShadow.cgColor
        popup.layer.shadowOffset = CGSize(width: 0, height: 4)
        popup.layer.shadowRadius = 12
        popup.layer.shadowOpacity = 0.6

        let buttonWidth: CGFloat = 36
        let buttonHeight: CGFloat = 42
        let spacing: CGFloat = 2
        let padding: CGFloat = 6

        let popupWidth = CGFloat(accents.count) * buttonWidth + CGFloat(accents.count - 1) * spacing + padding * 2
        let popupHeight = buttonHeight + padding * 2

        // Position above the key
        let keyFrame = key.convert(key.bounds, to: self)
        var popupX = keyFrame.midX - popupWidth / 2
        var popupY = keyFrame.minY - popupHeight - 8

        // If popup would clip above the view, show below the key instead
        if popupY < 0 {
            popupY = keyFrame.maxY + 8
        }

        // Keep within horizontal bounds
        popupX = max(sidePadding, min(bounds.width - popupWidth - sidePadding, popupX))

        popup.frame = CGRect(x: popupX, y: popupY, width: popupWidth, height: popupHeight)

        // Add accent buttons
        for (index, accent) in accents.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(accent, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 22)
            btn.setTitleColor(Colors.keyText, for: .normal)
            btn.backgroundColor = .clear
            btn.tag = index
            btn.frame = CGRect(
                x: padding + CGFloat(index) * (buttonWidth + spacing),
                y: padding,
                width: buttonWidth,
                height: buttonHeight
            )
            popup.addSubview(btn)
            accentButtons.append(btn)
        }

        addSubview(popup)
        accentPopup = popup

        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    private func updateAccentSelection(for gesture: UILongPressGestureRecognizer) {
        guard let popup = accentPopup else { return }

        let location = gesture.location(in: popup)

        for btn in accentButtons {
            let isSelected = btn.frame.contains(location)
            btn.backgroundColor = isSelected ? Colors.returnBlue : .clear  // Blue highlight
        }
    }

    private func selectAccentAndDismiss(for gesture: UILongPressGestureRecognizer) {
        guard let popup = accentPopup, let _ = activeKeyForAccent else {
            dismissAccentPopup()
            return
        }

        let location = gesture.location(in: popup)

        var selectedAccent: String?
        for btn in accentButtons {
            if btn.frame.contains(location), let title = btn.title(for: .normal) {
                selectedAccent = title
                break
            }
        }

        if let accent = selectedAccent {
            let finalAccent = (isShifted || isCapsLock) ? accent.uppercased() : accent
            onKeyTapped?(finalAccent)

            // Auto-unshift
            if isShifted && !isCapsLock {
                isShifted = false
                updateKeyLabels()
            }
        }

        dismissAccentPopup()
    }

    private func dismissAccentPopup() {
        accentPopup?.removeFromSuperview()
        accentPopup = nil
        accentButtons.removeAll()
        activeKeyForAccent = nil
    }

    private func showPunctuationPopup(for key: KeyButton) {
        dismissAccentPopup()
        dismissPunctuationPopup()

        let rows: [[String]] = [
            [".", ",", "?", "!", ":", ";", "…"],
            ["'", "\"", "“", "”", "‘", "’", "—", "–"],
            ["(", ")", "[", "]", "{", "}", "<", ">"],
            ["@", "#", "$", "%", "&", "*", "+", "="],
            ["/", "\\", "|", "_", "~", "`", "^", "•"]
        ]

        let popup = UIView()
        popup.backgroundColor = Colors.popupBackground
        popup.layer.cornerRadius = 10
        popup.layer.shadowColor = Colors.keyShadow.cgColor
        popup.layer.shadowOffset = CGSize(width: 0, height: 4)
        popup.layer.shadowRadius = 12
        popup.layer.shadowOpacity = 0.6

        let buttonWidth: CGFloat = 30
        let buttonHeight: CGFloat = 34
        let horizontalSpacing: CGFloat = 4
        let verticalSpacing: CGFloat = 4
        let padding: CGFloat = 8

        let maxCols = rows.map(\.count).max() ?? 0
        let popupWidth = CGFloat(maxCols) * buttonWidth + CGFloat(max(maxCols - 1, 0)) * horizontalSpacing + padding * 2
        let popupHeight = CGFloat(rows.count) * buttonHeight + CGFloat(max(rows.count - 1, 0)) * verticalSpacing + padding * 2

        let keyFrame = key.convert(key.bounds, to: self)
        var popupX = keyFrame.midX - popupWidth / 2
        var popupY = keyFrame.minY - popupHeight - 8
        if popupY < 0 {
            popupY = keyFrame.maxY + 8
        }
        popupX = max(sidePadding, min(bounds.width - popupWidth - sidePadding, popupX))

        popup.frame = CGRect(x: popupX, y: popupY, width: popupWidth, height: popupHeight)

        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = CGFloat(row.count) * buttonWidth + CGFloat(max(row.count - 1, 0)) * horizontalSpacing
            var x = (popupWidth - rowWidth) / 2
            let y = padding + CGFloat(rowIndex) * (buttonHeight + verticalSpacing)

            for symbol in row {
                let button = UIButton(type: .system)
                button.frame = CGRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
                button.setTitle(symbol, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 19, weight: .regular)
                button.setTitleColor(Colors.keyText, for: .normal)
                button.backgroundColor = Colors.keyBackground
                button.layer.cornerRadius = 6
                button.addAction(UIAction { [weak self] _ in
                    self?.onKeyTapped?(symbol)
                    self?.dismissPunctuationPopup()
                }, for: .touchUpInside)
                popup.addSubview(button)
                x += buttonWidth + horizontalSpacing
            }
        }

        punctuationPopup = popup
        addSubview(popup)
    }

    private func dismissPunctuationPopup() {
        punctuationPopup?.removeFromSuperview()
        punctuationPopup = nil
    }

    // MARK: - Update Helpers

    private func updateKeyLabels() {
        for btn in keyButtons where !btn.keyValue.isEmpty {
            let displayKey = (isShifted || isCapsLock) ? btn.keyValue.uppercased() : btn.keyValue
            btn.setTitle(displayKey, for: .normal)
        }
    }

    private func updateShiftButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        for btn in keyButtons where btn.isShiftKey {
            btn.tintColor = Colors.keyText
            btn.layer.borderColor = Colors.keyBorder.cgColor
            if isCapsLock {
                btn.backgroundColor = Colors.specialKeyActive
                btn.setImage(UIImage(systemName: "capslock.fill", withConfiguration: config), for: .normal)
                btn.setTitle(nil, for: .normal)
            } else if isShifted {
                btn.backgroundColor = Colors.specialKeyActive
                btn.setImage(UIImage(systemName: "shift.fill", withConfiguration: config), for: .normal)
                btn.setTitle(nil, for: .normal)
            } else {
                btn.backgroundColor = Colors.specialKey
                btn.setImage(UIImage(systemName: "shift", withConfiguration: config), for: .normal)
                btn.setTitle(nil, for: .normal)
            }
        }
    }

    // MARK: - Public

    public func show(in view: UIView) {
        frame = view.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        view.addSubview(self)

        UIView.animate(withDuration: 0.15) {
            self.alpha = 1
        }
    }

    public func dismiss() {
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    public enum DictationState {
        case idle
        case recording
        case processing
    }

    private var currentDictationState: DictationState = .idle

    /// Update spacebar appearance to reflect dictation state
    public func setDictationState(_ state: DictationState) {
        currentDictationState = state
        applyDictationState(state, animated: true)
    }

    private func applyDictationState(_ state: DictationState, animated: Bool) {
        isDictationActive = state != .idle

        guard let spaceBtn = keyButtons.first(where: { $0.tag == 412 }) else { return }
        let activeConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let updates = {
            spaceBtn.imageView?.contentMode = .scaleAspectFit
            spaceBtn.tintColor = Colors.keyText
            spaceBtn.imageView?.transform = .identity
            self.removeSpaceIdleHintStack(from: spaceBtn)
            self.removeSpaceStateHintStack(from: spaceBtn)

            switch state {
            case .idle:
                self.applySpecialKeyRestingStyle(spaceBtn)
                // Match the dictate key stack geometry so transitions feel physically stable.
                spaceBtn.setImage(nil, for: .normal)
                spaceBtn.setTitle(nil, for: .normal)
                self.addSpaceIdleHintStack(to: spaceBtn)
            case .recording:
                // Keep dictation affordance aligned with key styling but restore clear state cue.
                self.applySpecialKeyRestingStyle(spaceBtn)
                spaceBtn.backgroundColor = Colors.specialKeyActive
                spaceBtn.layer.borderColor = Colors.keyBorderPressed.cgColor
                spaceBtn.layer.shadowOpacity = self.keyRestingShadowOpacity
                spaceBtn.setImage(UIImage(systemName: "stop.fill", withConfiguration: activeConfig), for: .normal)
                spaceBtn.setTitle(nil, for: .normal)
                self.addSpaceStateHintStack(to: spaceBtn, text: "TAP TO STOP")
            case .processing:
                self.applySpecialKeyRestingStyle(spaceBtn)
                spaceBtn.backgroundColor = Colors.keyPressed
                spaceBtn.layer.borderColor = Colors.keyBorderPressed.cgColor
                spaceBtn.layer.shadowOpacity = self.keyRestingShadowOpacity
                spaceBtn.setImage(UIImage(systemName: "ellipsis", withConfiguration: activeConfig), for: .normal)
                spaceBtn.setTitle(nil, for: .normal)
                self.addSpaceStateHintStack(to: spaceBtn, text: "TRANSCRIBING")
            }
        }

        if animated {
            UIView.animate(withDuration: 0.15, animations: updates)
        } else {
            updates()
        }
    }

    private func addSpaceIdleHintStack(to button: UIButton) {
        guard button.viewWithTag(spaceIdleHintStackTag) == nil else { return }

        let stack = UIStackView()
        stack.tag = spaceIdleHintStackTag
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic.fill"))
        iconView.tintColor = Colors.keyText.withAlphaComponent(0.11)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let labelView = UILabel()
        labelView.text = "LONG TAP"
        labelView.font = .systemFont(ofSize: 8, weight: .medium)
        labelView.textColor = Colors.keyText.withAlphaComponent(0.14)

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(labelView)

        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    private func removeSpaceIdleHintStack(from button: UIButton) {
        button.viewWithTag(spaceIdleHintStackTag)?.removeFromSuperview()
    }

    private func addSpaceStateHintStack(to button: UIButton, text: String) {
        guard button.viewWithTag(spaceStateHintStackTag) == nil else { return }

        let label = UILabel()
        label.tag = spaceStateHintStackTag
        label.text = text
        label.font = .systemFont(ofSize: 8, weight: .semibold)
        label.textColor = Colors.keyText.withAlphaComponent(0.5)
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4)
        ])
    }

    private func removeSpaceStateHintStack(from button: UIButton) {
        button.viewWithTag(spaceStateHintStackTag)?.removeFromSuperview()
    }

    /// Sets an exact reference frame from the slot-grid dictate key for width matching
    /// and optional visual alignment guides.
    public func setSpaceAlignmentReference(frame: CGRect?, showGuide _: Bool) {
        spaceFrameReference = frame
        spaceWidthReference = frame?.width
        setNeedsLayout()
    }
}
#endif
