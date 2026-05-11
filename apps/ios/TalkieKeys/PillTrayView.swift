//
//  PillTrayView.swift
//  TalkieKeys
//
//  Overlay pill tray that slides down from the top of the keyboard area.
//  Provides quick actions: Open Talkie, Globe (switch keyboard), Engine status.
//

import UIKit
import TalkieMobileKit

private let log = Log(.ui)

@available(iOS 17.0, *)
final class PillTrayView: UIView {

    // MARK: - Design Constants

    private enum Design {
        static let pillHeight: CGFloat = 28
        static let pillSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 4
        static let totalHeight: CGFloat = 36
        static let pillCornerRadius: CGFloat = 14
        static let animationDuration: TimeInterval = 0.25
        static let autoDismissDelay: TimeInterval = 4.0

        static let pillBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 0.95)
                : UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 0.95)
        }

        static let textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        }

        static let trayBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.85)
                : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.85)
        }
    }

    // MARK: - Callbacks

    var onOpenTalkie: (() -> Void)?
    var onSwitchKeyboard: (() -> Void)?
    var onEngineStatus: (() -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var autoDismissWorkItem: DispatchWorkItem?

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
        // Blur background
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Pill stack
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Design.pillSpacing
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        stack.addArrangedSubview(makePill(icon: "app.badge", label: "Talkie", action: #selector(openTalkieTapped)))
        stack.addArrangedSubview(makePill(icon: "globe", label: "Globe", action: #selector(switchKeyboardTapped)))
        stack.addArrangedSubview(makePill(icon: "waveform", label: "Status", action: #selector(engineStatusTapped)))

        // Tap outside to dismiss
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    private func makePill(icon: String, label: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.backgroundColor = Design.pillBackground
        btn.layer.cornerRadius = Design.pillCornerRadius

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.image = UIImage(systemName: icon, withConfiguration: config)
        buttonConfig.title = label
        buttonConfig.imagePadding = 4
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        buttonConfig.baseForegroundColor = Design.textColor
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2)
            .withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2)
        buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont(descriptor: descriptor, size: 11)
            return outgoing
        }
        btn.configuration = buttonConfig

        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: Design.pillHeight).isActive = true

        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - Show / Dismiss

    func showAnimated(in parent: UIView, below topY: CGFloat) {
        frame = CGRect(x: 0, y: topY - Design.totalHeight, width: parent.bounds.width, height: Design.totalHeight)
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -Design.totalHeight)
        parent.addSubview(self)

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
        log.info("Pill tray shown")
    }

    func dismissAnimated() {
        cancelAutoDismiss()

        UIView.animate(
            withDuration: Design.animationDuration,
            delay: 0,
            options: .curveEaseIn,
            animations: {
                self.alpha = 0
                self.transform = CGAffineTransform(translationX: 0, y: -Design.totalHeight)
            }
        ) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }

        log.info("Pill tray dismissed")
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

    // MARK: - Actions

    @objc private func openTalkieTapped() {
        cancelAutoDismiss()
        onOpenTalkie?()
        dismissAnimated()
    }

    @objc private func switchKeyboardTapped() {
        cancelAutoDismiss()
        onSwitchKeyboard?()
        dismissAnimated()
    }

    @objc private func engineStatusTapped() {
        cancelAutoDismiss()
        onEngineStatus?()
        dismissAnimated()
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        // Only dismiss if tap is outside all pill buttons
        for subview in subviews where subview is UIStackView {
            for pill in (subview as! UIStackView).arrangedSubviews {
                if pill.frame.contains(self.convert(location, to: subview)) {
                    return
                }
            }
        }
        dismissAnimated()
    }
}
