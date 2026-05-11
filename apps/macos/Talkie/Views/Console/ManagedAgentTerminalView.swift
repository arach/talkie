//
//  ManagedAgentTerminalView.swift
//  Talkie
//
//  Native Ghostty-backed terminal surface for a managed agent console session.
//

import SwiftUI
import TalkieKit

struct ManagedAgentTerminalAppearance: Equatable {
    var theme: ConsoleTerminalThemeOption = .graphite
    var fontSize: Double? = nil

    static let `default` = ManagedAgentTerminalAppearance()
}

#if canImport(TermBridgeKit)
import TermBridgeKit

struct ManagedAgentTerminalView: View {
    let session: ManagedAgentConsoleSession
    @Binding var isReady: Bool
    var holdLoader: Bool = false
    var loaderReplayToken: UUID = UUID()
    var appearance: ManagedAgentTerminalAppearance = .default
    var backgroundColor: Color = .black
    var foregroundColor: Color = .white

    @State private var controller = TermBridgeKitTerminalController()
    @State private var sessionBridge = SessionBridge()

    private var bootSequenceKey: String {
        "\(session.id.uuidString)-\(loaderReplayToken.uuidString)-\(holdLoader)"
    }

    var body: some View {
        TermBridgeKitTerminalView(
            controller: controller,
            showsSystemKeyboard: false,
            fontSize: appearance.fontSize
        )
        .background(backgroundColor)
        .accessibilityIdentifier("managed-agent-terminal")
        .accessibilityLabel("Managed agent terminal")
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    controller.focus()
                }
        )
        .onDisappear {
            sessionBridge.unbind()
            isReady = false
        }
        .task(id: session.id) {
            sessionBridge.bind(session: session, controller: controller)
        }
        .task(id: appearance) {
            sessionBridge.updateAppearance(appearance, controller: controller)
        }
        .task(id: bootSequenceKey) {
            isReady = false
            guard !holdLoader else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            isReady = true
            controller.focus()
        }
    }
}

@MainActor
private final class SessionBridge: NSObject, ManagedAgentConsoleSession.Listener {
    private weak var session: ManagedAgentConsoleSession?
    private weak var controller: TermBridgeKitTerminalController?
    private var appearance: ManagedAgentTerminalAppearance = .default

    func bind(session: ManagedAgentConsoleSession, controller: TermBridgeKitTerminalController) {
        if self.session !== session {
            self.session?.detach(listener: self)
            self.session = session
        }

        self.controller = controller
        controller.onInputText = { [weak session] text in
            session?.send(text)
        }
        controller.onDeleteBackward = { [weak session] in
            session?.send(Data([0x7F]))
        }
        controller.onTransportWrite = { [weak session] data in
            session?.send(data)
        }
        controller.onSizeChange = { [weak session] size in
            session?.resize(columns: size.columns, rows: size.rows)
        }

        session.attach(listener: self)
        applyAppearance(to: controller)
    }

    func updateAppearance(_ appearance: ManagedAgentTerminalAppearance, controller: TermBridgeKitTerminalController? = nil) {
        self.appearance = appearance
        applyAppearance(to: controller ?? self.controller)
    }

    func unbind() {
        session?.detach(listener: self)
        session = nil

        controller?.onInputText = nil
        controller?.onDeleteBackward = nil
        controller?.onTransportWrite = nil
        controller?.onSizeChange = nil
        controller = nil
    }

    private func applyAppearance(to controller: TermBridgeKitTerminalController?) {
        guard let controller else { return }
        controller.processRemoteOutput(Data(appearance.theme.applyEscapeSequence.utf8))
    }

    nonisolated func consoleSession(_ session: ManagedAgentConsoleSession, didResetTranscript transcript: Data) {
        Task { @MainActor [weak self] in
            self?.controller?.processRemoteOutput(Data("\u{1B}c".utf8))
            if let sequence = self?.appearance.theme.applyEscapeSequence {
                self?.controller?.processRemoteOutput(Data(sequence.utf8))
            }
            guard !transcript.isEmpty else { return }
            self?.controller?.processRemoteOutput(transcript)
        }
    }

    nonisolated func consoleSession(_ session: ManagedAgentConsoleSession, didReceiveOutput chunk: Data) {
        Task { @MainActor [weak self] in
            self?.controller?.processRemoteOutput(chunk)
        }
    }
}

#else

struct ManagedAgentTerminalView: View {
    let session: ManagedAgentConsoleSession
    @Binding var isReady: Bool
    var holdLoader: Bool = false
    var loaderReplayToken: UUID = UUID()
    var appearance: ManagedAgentTerminalAppearance = .default
    var backgroundColor: Color = .black
    var foregroundColor: Color = .white

    var body: some View {
        backgroundColor
            .overlay {
                Text("Native terminal renderer unavailable in this build.")
                    .font(.system(size: appearance.fontSize ?? 13, weight: .medium, design: .rounded))
                    .foregroundStyle(foregroundColor.opacity(0.7))
            }
            .onAppear {
                isReady = !holdLoader
            }
            .onDisappear {
                isReady = false
            }
            .onChange(of: holdLoader) { _, newValue in
                isReady = !newValue
            }
            .onChange(of: loaderReplayToken) { _, _ in
                isReady = !holdLoader
            }
    }
}

#endif

private extension ConsoleTerminalThemeOption {
    var applyEscapeSequence: String {
        terminalColors.applyEscapeSequence
    }

    private var terminalColors: ManagedAgentTerminalColors {
        switch self {
        case .graphite:
            .init(
                background: .init(red: 0x0B, green: 0x11, blue: 0x17),
                foreground: .init(red: 0xE6, green: 0xED, blue: 0xF5),
                cursor: .init(red: 0x7D, green: 0xC4, blue: 0xFF),
                selectionBackground: .init(red: 0x1A, green: 0x2A, blue: 0x39),
                ansiPalette: [
                    .init(red: 0x0B, green: 0x11, blue: 0x17),
                    .init(red: 0xFF, green: 0x6B, blue: 0x6B),
                    .init(red: 0x7C, green: 0xE3, blue: 0x9B),
                    .init(red: 0xF2, green: 0xC9, blue: 0x4C),
                    .init(red: 0x7D, green: 0xC4, blue: 0xFF),
                    .init(red: 0xC7, green: 0x92, blue: 0xEA),
                    .init(red: 0x61, green: 0xD6, blue: 0xD6),
                    .init(red: 0xD8, green: 0xE0, blue: 0xE8),
                    .init(red: 0x4B, green: 0x5A, blue: 0x67),
                    .init(red: 0xFF, green: 0x8F, blue: 0x8F),
                    .init(red: 0x9B, green: 0xF0, blue: 0xB4),
                    .init(red: 0xFF, green: 0xDB, blue: 0x75),
                    .init(red: 0xA7, green: 0xD7, blue: 0xFF),
                    .init(red: 0xDD, green: 0xB8, blue: 0xFF),
                    .init(red: 0x8E, green: 0xEA, blue: 0xEA),
                    .init(red: 0xF3, green: 0xF7, blue: 0xFB)
                ]
            )
        case .tokyoNight:
            .init(
                background: .init(red: 0x24, green: 0x29, blue: 0x3A),
                foreground: .init(red: 0xC0, green: 0xCA, blue: 0xF5),
                cursor: .init(red: 0x7A, green: 0xA2, blue: 0xF7),
                selectionBackground: .init(red: 0x33, green: 0x40, blue: 0x5A),
                ansiPalette: [
                    .init(red: 0x1A, green: 0x1B, blue: 0x26),
                    .init(red: 0xF7, green: 0x76, blue: 0x8E),
                    .init(red: 0x9E, green: 0xCE, blue: 0x6A),
                    .init(red: 0xE0, green: 0xAF, blue: 0x68),
                    .init(red: 0x7A, green: 0xA2, blue: 0xF7),
                    .init(red: 0xBB, green: 0x9A, blue: 0xF7),
                    .init(red: 0x7D, green: 0xCF, blue: 0xF7),
                    .init(red: 0xA9, green: 0xB1, blue: 0xD6),
                    .init(red: 0x41, green: 0x45, blue: 0x68),
                    .init(red: 0xFF, green: 0x9E, blue: 0xB3),
                    .init(red: 0xB9, green: 0xF2, blue: 0x7C),
                    .init(red: 0xFF, green: 0xC7, blue: 0x77),
                    .init(red: 0x9A, green: 0xB8, blue: 0xFF),
                    .init(red: 0xD7, green: 0xB5, blue: 0xFF),
                    .init(red: 0x9E, green: 0xE6, blue: 0xFF),
                    .init(red: 0xC0, green: 0xCA, blue: 0xF5)
                ]
            )
        case .nord:
            .init(
                background: .init(red: 0x2E, green: 0x34, blue: 0x40),
                foreground: .init(red: 0xE5, green: 0xE9, blue: 0xF0),
                cursor: .init(red: 0x88, green: 0xC0, blue: 0xD0),
                selectionBackground: .init(red: 0x43, green: 0x4C, blue: 0x5E),
                ansiPalette: [
                    .init(red: 0x2E, green: 0x34, blue: 0x40),
                    .init(red: 0xBF, green: 0x61, blue: 0x6A),
                    .init(red: 0xA3, green: 0xBE, blue: 0x8C),
                    .init(red: 0xEB, green: 0xCB, blue: 0x8B),
                    .init(red: 0x81, green: 0xA1, blue: 0xC1),
                    .init(red: 0xB4, green: 0x8E, blue: 0xAD),
                    .init(red: 0x88, green: 0xC0, blue: 0xD0),
                    .init(red: 0xD8, green: 0xDE, blue: 0xE9),
                    .init(red: 0x4C, green: 0x56, blue: 0x66),
                    .init(red: 0xD0, green: 0x87, blue: 0x70),
                    .init(red: 0xB8, green: 0xD6, blue: 0x99),
                    .init(red: 0xF2, green: 0xD9, blue: 0xA0),
                    .init(red: 0x8F, green: 0xBC, blue: 0xBB),
                    .init(red: 0xC8, green: 0xA2, blue: 0xC8),
                    .init(red: 0x9D, green: 0xE3, blue: 0xEF),
                    .init(red: 0xEC, green: 0xEF, blue: 0xF4)
                ]
            )
        case .catppuccin:
            .init(
                background: .init(red: 0x1E, green: 0x1E, blue: 0x2E),
                foreground: .init(red: 0xCD, green: 0xD6, blue: 0xF4),
                cursor: .init(red: 0x89, green: 0xB4, blue: 0xFA),
                selectionBackground: .init(red: 0x45, green: 0x47, blue: 0x5A),
                ansiPalette: [
                    .init(red: 0x1E, green: 0x1E, blue: 0x2E),
                    .init(red: 0xF3, green: 0x8B, blue: 0xA8),
                    .init(red: 0xA6, green: 0xE3, blue: 0xA1),
                    .init(red: 0xF9, green: 0xE2, blue: 0xAF),
                    .init(red: 0x89, green: 0xB4, blue: 0xFA),
                    .init(red: 0xC9, green: 0xA0, blue: 0xDC),
                    .init(red: 0x94, green: 0xE2, blue: 0xD5),
                    .init(red: 0xBA, green: 0xC2, blue: 0xDE),
                    .init(red: 0x58, green: 0x5B, blue: 0x70),
                    .init(red: 0xF5, green: 0xA9, blue: 0xB8),
                    .init(red: 0xB9, green: 0xF2, blue: 0xB0),
                    .init(red: 0xFA, green: 0xE8, blue: 0xC8),
                    .init(red: 0xA6, green: 0xC8, blue: 0xFF),
                    .init(red: 0xD7, green: 0xB3, blue: 0xF0),
                    .init(red: 0xA7, green: 0xEF, blue: 0xE1),
                    .init(red: 0xCD, green: 0xD6, blue: 0xF4)
                ]
            )
        case .solarizedLight:
            .init(
                background: .init(red: 0xFD, green: 0xF6, blue: 0xE3),
                foreground: .init(red: 0x58, green: 0x6E, blue: 0x75),
                cursor: .init(red: 0x26, green: 0x8B, blue: 0xD2),
                selectionBackground: .init(red: 0xEE, green: 0xE8, blue: 0xD5),
                ansiPalette: [
                    .init(red: 0x07, green: 0x36, blue: 0x42),
                    .init(red: 0xDC, green: 0x32, blue: 0x2F),
                    .init(red: 0x85, green: 0x99, blue: 0x00),
                    .init(red: 0xB5, green: 0x89, blue: 0x00),
                    .init(red: 0x26, green: 0x8B, blue: 0xD2),
                    .init(red: 0xD3, green: 0x36, blue: 0x82),
                    .init(red: 0x2A, green: 0xA1, blue: 0x98),
                    .init(red: 0xEE, green: 0xE8, blue: 0xD5),
                    .init(red: 0x00, green: 0x2B, blue: 0x36),
                    .init(red: 0xCB, green: 0x4B, blue: 0x16),
                    .init(red: 0x58, green: 0x6E, blue: 0x75),
                    .init(red: 0x65, green: 0x7B, blue: 0x83),
                    .init(red: 0x83, green: 0x94, blue: 0x96),
                    .init(red: 0x6C, green: 0x71, blue: 0xC4),
                    .init(red: 0x93, green: 0xA1, blue: 0xA1),
                    .init(red: 0xFD, green: 0xF6, blue: 0xE3)
                ]
            )
        }
    }
}

private struct ManagedAgentTerminalColors {
    let background: ManagedAgentTerminalRGB
    let foreground: ManagedAgentTerminalRGB
    let cursor: ManagedAgentTerminalRGB
    let selectionBackground: ManagedAgentTerminalRGB?
    let ansiPalette: [ManagedAgentTerminalRGB]

    var applyEscapeSequence: String {
        var commands = [
            foreground.osc(command: 10),
            background.osc(command: 11),
            cursor.osc(command: 12)
        ]

        for (index, color) in ansiPalette.enumerated() {
            commands.append(color.osc(command: 4, parameter: index))
        }

        if let selectionBackground {
            commands.append(selectionBackground.osc(command: 17))
        }

        return commands.joined()
    }
}

private struct ManagedAgentTerminalRGB {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    func osc(command: Int, parameter: Int? = nil) -> String {
        let prefix = if let parameter {
            "\(command);\(parameter)"
        } else {
            "\(command)"
        }

        return "\u{1B}]\(prefix);rgb:\(component(red))/\(component(green))/\(component(blue))\u{07}"
    }

    private func component(_ value: UInt8) -> String {
        String(format: "%04X", Int(value) * 257)
    }
}
