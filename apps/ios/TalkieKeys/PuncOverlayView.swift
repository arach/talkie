//
//  PuncOverlayView.swift
//  TalkieKeys
//
//  Punctuation overlay that slides up from above the keyboard.
//  Two rows of punctuation characters + a Symbols mode switch.
//  Follows the same show/dismiss/auto-dismiss pattern as PillTrayView.
//

import UIKit

@available(iOS 17.0, *)
final class PuncOverlayView: UIView {

    // MARK: - Design Constants

    private enum Design {
        static let rowHeight: CGFloat = 32
        static let rowSpacing: CGFloat = 5
        static let buttonSpacing: CGFloat = 5
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 5
        static let cornerRadius: CGFloat = 10
        static let buttonCornerRadius: CGFloat = 6
        static let animationDuration: TimeInterval = 0.25
        static let autoDismissDelay: TimeInterval = 5.0

        static var overlayHeight: CGFloat {
            verticalPadding + rowHeight + rowSpacing + rowHeight + verticalPadding
        }

        static let buttonBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.10)
                : UIColor(white: 0.0, alpha: 0.06)
        }

        static let textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        }

        static let buttonBorder = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.14)
                : UIColor(white: 0.0, alpha: 0.08)
        }
    }

    // MARK: - Callbacks

    var onPuncInsert: ((String) -> Void)?
    var onSwitchToSymbols: (() -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var autoDismissWorkItem: DispatchWorkItem?
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Punctuation Sets (two rows)

    private static let row1: [(label: String, insert: String)] = [
        (".", "."), (",", ","), ("?", "?"), ("!", "!"), ("'", "'"),
    ]

    private static let row2: [(label: String, insert: String)] = [
        (":", ":"), (";", ";"), ("\"", "\""), ("-", "-"), ("…", "…"),
    ]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        lightImpact.prepare()
        mediumImpact.prepare()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        // Blur background
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = Design.cornerRadius
        blur.clipsToBounds = true
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Vertical stack for two rows
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = Design.rowSpacing
        vStack.alignment = .fill
        vStack.distribution = .fillEqually
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: topAnchor, constant: Design.verticalPadding),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Design.verticalPadding),
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Design.horizontalPadding),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Design.horizontalPadding),
        ])

        // Row 1: common punctuation
        let stack1 = makeRow(Self.row1)
        vStack.addArrangedSubview(stack1)

        // Row 2: more punctuation + Symbols button
        let stack2 = makeRow(Self.row2, appendSymbols: true)
        vStack.addArrangedSubview(stack2)
    }

    private func makeRow(_ items: [(label: String, insert: String)], appendSymbols: Bool = false) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Design.buttonSpacing
        stack.alignment = .fill
        stack.distribution = .fillEqually

        for punc in items {
            let btn = makePuncButton(label: punc.label)
            btn.addAction(UIAction { [weak self] _ in
                self?.lightImpact.impactOccurred()
                self?.lightImpact.prepare()
                self?.onPuncInsert?(punc.insert)
                self?.dismissAnimated()
            }, for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }

        if appendSymbols {
            let symbolsBtn = makePuncButton(label: "#@+")
            symbolsBtn.addAction(UIAction { [weak self] _ in
                self?.mediumImpact.impactOccurred()
                self?.mediumImpact.prepare()
                self?.onSwitchToSymbols?()
                self?.dismissAnimated()
            }, for: .touchUpInside)
            stack.addArrangedSubview(symbolsBtn)
        }

        return stack
    }

    private func makePuncButton(label: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        btn.setTitleColor(Design.textColor, for: .normal)
        btn.backgroundColor = Design.buttonBackground
        btn.layer.cornerRadius = Design.buttonCornerRadius
        btn.layer.borderWidth = 0.45
        btn.layer.borderColor = Design.buttonBorder.cgColor
        return btn
    }

    // MARK: - Show / Dismiss

    func showAnimated(in parent: UIView, above bottomY: CGFloat, sidePadding: CGFloat = 5) {
        let originY = bottomY - Design.overlayHeight - 4
        frame = CGRect(
            x: sidePadding,
            y: max(0, originY),
            width: parent.bounds.width - sidePadding * 2,
            height: Design.overlayHeight
        )
        autoresizingMask = [.flexibleWidth]
        parent.addSubview(self)

        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 10)

        UIView.animate(
            withDuration: Design.animationDuration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            self.alpha = 1
            self.transform = .identity
        }

        scheduleAutoDismiss()
    }

    func dismissAnimated() {
        cancelAutoDismiss()

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: .curveEaseIn,
            animations: {
                self.alpha = 0
                self.transform = CGAffineTransform(translationX: 0, y: 10)
            }
        ) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissAnimated()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.autoDismissDelay, execute: workItem)
    }

    private func cancelAutoDismiss() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
    }
}
