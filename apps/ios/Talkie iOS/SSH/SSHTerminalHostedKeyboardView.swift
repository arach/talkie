//
//  SSHTerminalHostedKeyboardView.swift
//  Talkie iOS
//
//  In-app hosted Talkie keyboard for the SSH terminal.
//

import SwiftUI
import TalkieMobileKit
import UIKit

struct SSHTerminalHostedKeyboardView: UIViewRepresentable {
    let session: SSHTerminalSession
    @Binding var isPresented: Bool
    @Binding var preferredHeight: CGFloat
    @Binding var controlModifierState: SSHTerminalControlModifierState
    @Binding var shiftModifierState: SSHTerminalControlModifierState

    private static let terminalMinimalSlotConfigs: [Int: SlotConfig] = [
        1: SlotConfig(type: .action, label: "SHIFT", content: "SHIFT"),
        2: .text("C", inserts: "c"),
        3: .text("V", inserts: "v"),
        4: .space,
        5: .text("Q", inserts: "q"),
        6: .text("*", inserts: "*"),
        7: .action("ENTER", icon: "return"),
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> HostedTalkieKeyboardView {
        let keyboard = HostedTalkieKeyboardView()
        configure(keyboard, coordinator: context.coordinator)
        return keyboard
    }

    func updateUIView(_ uiView: HostedTalkieKeyboardView, context: Context) {
        context.coordinator.session = session
        context.coordinator.setPresented = { presented in
            isPresented = presented
        }
        context.coordinator.controlModifierState = { controlModifierState }
        context.coordinator.setControlModifierState = { nextState in
            controlModifierState = nextState
        }
        context.coordinator.shiftModifierState = { shiftModifierState }
        context.coordinator.setShiftModifierState = { nextState in
            shiftModifierState = nextState
        }

        uiView.inputHost = context.coordinator
        uiView.customMinimalSlotConfigs = Self.terminalMinimalSlotConfigs
        uiView.showsMinimalDictateButton = false
        context.coordinator.keyboard = uiView

        let nextHeight = uiView.intrinsicContentSize.height
        if abs(preferredHeight - nextHeight) > 0.5 {
            DispatchQueue.main.async {
                preferredHeight = nextHeight
            }
        }
    }

    private func configure(_ keyboard: HostedTalkieKeyboardView, coordinator: Coordinator) {
        coordinator.keyboard = keyboard
        coordinator.setPresented = { presented in
            isPresented = presented
        }
        coordinator.controlModifierState = { controlModifierState }
        coordinator.setControlModifierState = { nextState in
            controlModifierState = nextState
        }
        coordinator.shiftModifierState = { shiftModifierState }
        coordinator.setShiftModifierState = { nextState in
            shiftModifierState = nextState
        }
        keyboard.inputHost = coordinator
        keyboard.customMinimalSlotConfigs = Self.terminalMinimalSlotConfigs
        keyboard.showsMinimalDictateButton = false
        keyboard.onDictationToggle = { [weak coordinator] in
            coordinator?.toggleDictation()
        }
        keyboard.onLayoutHeightChange = { [weak keyboard] in
            guard let keyboard else { return }
            let nextHeight = keyboard.intrinsicContentSize.height
            DispatchQueue.main.async {
                preferredHeight = nextHeight
            }
        }
        DispatchQueue.main.async {
            preferredHeight = keyboard.intrinsicContentSize.height
        }
    }
}

extension SSHTerminalHostedKeyboardView {
    @MainActor
    final class Coordinator: NSObject, KeyboardInputHost {
        var session: SSHTerminalSession
        weak var keyboard: HostedTalkieKeyboardView?
        var setPresented: ((Bool) -> Void)?
        var controlModifierState: (() -> SSHTerminalControlModifierState)?
        var setControlModifierState: ((SSHTerminalControlModifierState) -> Void)?
        var shiftModifierState: (() -> SSHTerminalControlModifierState)?
        var setShiftModifierState: ((SSHTerminalControlModifierState) -> Void)?

        private let dictationController = InlineDictationController()

        init(session: SSHTerminalSession) {
            self.session = session
            super.init()

            dictationController.onStateChange = { [weak self] state in
                self?.applyDictationState(state)
            }
            dictationController.onTranscript = { [weak self] transcript in
                guard let self else { return }
                self.performKeyboardAction(.insert(transcript))
                self.keyboard?.showDictationSuccessFeedback()
            }
            dictationController.onError = { [weak self] _ in
                self?.keyboard?.setDictationState(.idle)
            }
        }

        func performKeyboardAction(_ action: KeyboardAction) {
            switch action {
            case .insert(let text):
                sendTranslatedInput(text)
            case .deleteBackward:
                session.send("\u{7F}")
            case .copy:
                break
            case .selectAll:
                break
            case .paste:
                guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else { return }
                sendTranslatedInput(clipboardText)
            case .toggleShift:
                let currentState = shiftModifierState?() ?? .inactive
                let nextState: SSHTerminalControlModifierState = currentState == .armed ? .inactive : .armed
                setShiftModifierState?(nextState)
            case .toggleControl:
                let currentState = controlModifierState?() ?? .inactive
                let nextState: SSHTerminalControlModifierState = currentState == .armed ? .inactive : .armed
                setControlModifierState?(nextState)
            case .tab:
                session.send("\t")
            case .escape:
                session.send("\u{1B}")
            case .enter:
                session.send("\r")
            case .interrupt:
                session.sendInterrupt()
            case .dismissKeyboard:
                setPresented?(false)
            case .moveCursor(let movement):
                switch movement {
                case .left:
                    session.send("\u{1B}[D")
                case .right:
                    session.send("\u{1B}[C")
                case .up:
                    session.send("\u{1B}[A")
                case .down:
                    session.send("\u{1B}[B")
                case .wordLeft:
                    session.send("\u{1B}b")
                case .wordRight:
                    session.send("\u{1B}f")
                }
            }
        }

        func toggleDictation() {
            switch dictationController.currentState {
            case .idle:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.dictationController.start()
                }
            case .recording:
                dictationController.stop(insertTranscript: true)
            case .transcribing:
                break
            }
        }

        private func applyDictationState(_ state: InlineDictationController.State) {
            let nextState: HostedTalkieKeyboardView.DictationState
            switch state {
            case .idle:
                nextState = .idle
            case .recording:
                nextState = .recording
            case .transcribing:
                nextState = .processing
            }
            keyboard?.setDictationState(nextState)
        }

        private func sendTranslatedInput(_ text: String) {
            let controlState = controlModifierState?() ?? .inactive
            let shiftState = shiftModifierState?() ?? .inactive
            guard let resolved = SSHTerminalInputTranslator.resolvedInput(
                for: text,
                controlModifierState: controlState,
                shiftModifierState: shiftState
            ) else {
                return
            }

            session.send(resolved.payload)

            if resolved.consumedControl {
                consumeControlModifierIfNeeded()
            }

            if resolved.consumedShift {
                consumeShiftModifierIfNeeded()
            }
        }

        private func consumeControlModifierIfNeeded() {
            guard let controlModifierState, controlModifierState().consumesAfterUse else { return }
            setControlModifierState?(.inactive)
        }

        private func consumeShiftModifierIfNeeded() {
            guard let shiftModifierState, shiftModifierState().consumesAfterUse else { return }
            setShiftModifierState?(.inactive)
        }
    }
}
