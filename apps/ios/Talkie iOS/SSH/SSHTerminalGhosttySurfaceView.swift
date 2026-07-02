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
import UIKit

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
            .accessibilityHint("Tap to open the keyboard. Drag vertically to scroll terminal history.")
            .contentShape(Rectangle())
            .overlay {
                GhosttyTerminalScrollConfigurator()
                    .allowsHitTesting(false)
            }
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

private struct GhosttyTerminalScrollConfigurator: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        Task { @MainActor in
            context.coordinator.configure(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Task { @MainActor in
            context.coordinator.configure(from: uiView)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var configuredSurface: SurfaceContainerView?
        private var pendingRetryCount = 0

        func configure(from markerView: UIView) {
            guard let surface = findSurface(from: markerView) else {
                scheduleRetry(from: markerView)
                return
            }

            guard configuredSurface !== surface else { return }
            configuredSurface = surface
            pendingRetryCount = 0

            // TermBridgeKit owns the Ghostty scroll target/action. Talkie opts
            // into the same recognizer for normal one-finger phone scrolling.
            for recognizer in surface.gestureRecognizers ?? [] {
                guard let panRecognizer = recognizer as? UIPanGestureRecognizer else { continue }
                guard panRecognizer.minimumNumberOfTouches > 1 else { continue }

                panRecognizer.minimumNumberOfTouches = 1
                panRecognizer.maximumNumberOfTouches = max(1, panRecognizer.maximumNumberOfTouches)
                panRecognizer.cancelsTouchesInView = false
                panRecognizer.delaysTouchesBegan = false
                panRecognizer.delaysTouchesEnded = false
            }
        }

        private func scheduleRetry(from markerView: UIView) {
            guard pendingRetryCount < 12 else { return }
            pendingRetryCount += 1

            Task { @MainActor [weak self, weak markerView] in
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let markerView else { return }
                self.configure(from: markerView)
            }
        }

        private func findSurface(from markerView: UIView) -> SurfaceContainerView? {
            var searchRoot: UIView? = markerView
            var inspectedDepth = 0

            while let root = searchRoot, inspectedDepth < 8 {
                if let surface = root.firstDescendant(of: SurfaceContainerView.self) {
                    return surface
                }

                searchRoot = root.superview
                inspectedDepth += 1
            }

            return markerView.window?.firstDescendant(of: SurfaceContainerView.self)
        }
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
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
