//
//  SSHTerminalGhosttySurfaceView.swift
//  Talkie iOS
//
//  Ghostty-backed SSH terminal surface that reuses Talkie's SSH session and
//  hosted keyboard flow.
//

import SwiftUI

#if canImport(TermBridgeKit)
import TermBridgeKit

struct SSHTerminalGhosttySurfaceView: View {
    let session: SSHTerminalSession
    let focusRequestID: Int
    let dismissRequestID: Int
    let refitRequestID: Int
    let onTerminalTap: () -> Void

    @State private var controller = TermBridgeKitTerminalController()
    @State private var sessionBridge = SessionBridge()

    var body: some View {
        GeometryReader { proxy in
            let fontSize = preferredFontSize(for: proxy.size)

            TermBridgeKitTerminalView(
                controller: controller,
                showsSystemKeyboard: false,
                fontSize: fontSize
            )
            .id("ghostty-\(Int(fontSize * 10))")
            .background(.black)
            .accessibilityIdentifier("ssh.terminal")
            .accessibilityLabel("SSH terminal")
            .accessibilityHint("Tap to open the keyboard and type into the remote shell.")
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        guard session.status == .connected else { return }
                        onTerminalTap()
                        controller.focus()
                    }
            )
        }
        .onDisappear {
            sessionBridge.unbind()
        }
        .task(id: ObjectIdentifier(session)) {
            sessionBridge.bind(session: session, controller: controller)
        }
        .onChange(of: focusRequestID) { _, _ in
            guard session.status == .connected else { return }
            controller.focus()
        }
        .onChange(of: dismissRequestID) { _, _ in
            controller.blur()
        }
        .onChange(of: refitRequestID) { _, _ in }
    }

    private func preferredFontSize(for size: CGSize) -> Double {
        let width = max(size.width, 240)
        let height = max(size.height, 180)
        let isLandscape = width > height

        let targetColumns = isLandscape ? 96.0 : 52.0
        let targetRows = isLandscape ? 24.0 : 18.0

        // Empirically, Ghostty on iPhone lands near these point-to-cell ratios.
        let widthLimitedSize = width / (targetColumns * 0.76)
        let heightLimitedSize = height / (targetRows * 1.62)
        let raw = min(widthLimitedSize, heightLimitedSize)
        let clamped = min(max(raw, 7.5), 11.0)
        return (clamped * 2).rounded() / 2
    }
}

private final class SessionBridge: NSObject, SSHTerminalSession.Listener {
    private weak var session: SSHTerminalSession?
    private weak var controller: TermBridgeKitTerminalController?

    @MainActor
    func bind(session: SSHTerminalSession, controller: TermBridgeKitTerminalController) {
        if self.session !== session {
            self.session?.attach(listener: nil, replayTranscript: false)
            self.session = session
        }

        self.controller = controller
        controller.onInputText = { [weak session] text in
            session?.send(text)
        }
        controller.onDeleteBackward = { [weak session] in
            session?.send("\u{7F}")
        }
        controller.onTransportWrite = { [weak session] data in
            session?.send(data)
        }
        controller.onSizeChange = { [weak session] size in
            session?.resize(
                columns: size.columns,
                rows: size.rows,
                pixelWidth: size.columns * size.cellWidthPixels,
                pixelHeight: size.rows * size.cellHeightPixels
            )
        }

        session.attach(listener: self)
    }

    @MainActor
    func unbind() {
        session?.attach(listener: nil, replayTranscript: false)
        session = nil

        controller?.onInputText = nil
        controller?.onDeleteBackward = nil
        controller?.onTransportWrite = nil
        controller?.onSizeChange = nil
        controller = nil
    }

    nonisolated func sshTerminalSession(_ session: SSHTerminalSession, didResetTranscript transcript: Data) {
        Task { @MainActor [weak self] in
            self?.controller?.processRemoteOutput(Data("\u{1B}c".utf8))
            guard !transcript.isEmpty else { return }
            self?.controller?.processRemoteOutput(transcript)
        }
    }

    nonisolated func sshTerminalSession(_ session: SSHTerminalSession, didReceiveOutput chunk: Data) {
        Task { @MainActor [weak self] in
            self?.controller?.processRemoteOutput(chunk)
        }
    }
}

#else

struct SSHTerminalGhosttySurfaceView: View {
    let session: SSHTerminalSession
    let focusRequestID: Int
    let dismissRequestID: Int
    let refitRequestID: Int
    let onTerminalTap: () -> Void

    var body: some View {
        Color.black
            .overlay {
                Text("Ghostty renderer unavailable in this build.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
    }
}

#endif
