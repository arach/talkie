//
//  SSHTerminalSurfaceView.swift
//  Talkie iOS
//
//  Embedded xterm.js surface for the iOS SSH terminal.
//

import SwiftUI
import TalkieMobileKit
import UIKit
import WebKit

struct SSHTerminalSurfaceView: UIViewRepresentable {
    let session: SSHTerminalSession
    let focusRequestID: Int
    let dismissRequestID: Int
    let refitRequestID: Int
    let onTerminalTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalContainerView {
        let configuration = WKWebViewConfiguration()
        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.bouncesZoom = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false

        let containerView = TerminalContainerView(webView: webView)
        configure(containerView, context: context)

        context.coordinator.bind(session: session, webView: webView)
        context.coordinator.loadTerminalShell()

        return containerView
    }

    func updateUIView(_ uiView: TerminalContainerView, context: Context) {
        configure(uiView, context: context)
        context.coordinator.bind(session: session, webView: uiView.webView)

        if uiView.lastAppliedFocusRequestID != focusRequestID {
            uiView.lastAppliedFocusRequestID = focusRequestID
            uiView.activateKeyboardInput()
        }

        if uiView.lastAppliedDismissRequestID != dismissRequestID {
            uiView.lastAppliedDismissRequestID = dismissRequestID
            uiView.deactivateKeyboardInput()
        }

        if uiView.lastAppliedRefitRequestID != refitRequestID {
            uiView.lastAppliedRefitRequestID = refitRequestID
            context.coordinator.hardRefitTerminal()
        }
    }

    private func configure(_ uiView: TerminalContainerView, context: Context) {
        uiView.onFocusTerminal = { [weak coordinator = context.coordinator] in
            coordinator?.focusTerminal()
        }
        uiView.onBlurTerminal = { [weak coordinator = context.coordinator] in
            coordinator?.blurTerminal()
        }
        uiView.onTerminalTap = onTerminalTap
        uiView.isKeyboardInputEnabled = session.status == .connected
    }
}

extension SSHTerminalSurfaceView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, SSHTerminalSession.Listener {
        static let messageHandlerName = "talkieTerminal"

        weak var webView: WKWebView?
        private weak var session: SSHTerminalSession?
        private var isReady = false
        private var pendingTranscript: Data?
        private var pendingJavaScriptEvaluations: [QueuedJavaScriptEvaluation] = []
        private var isEvaluatingJavaScript = false

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func bind(session: SSHTerminalSession, webView: WKWebView) {
            self.webView = webView

            if let boundSession = self.session, boundSession === session {
                return
            }

            self.session?.attach(listener: nil)
            self.session = session
            pendingTranscript = session.transcriptData

            if isReady {
                session.attach(listener: self)
            }
        }

        func loadTerminalShell() {
            guard let webView else { return }
            let indexURL = Bundle.main.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: "SSHTerminal"
            ) ?? Bundle.main.url(
                forResource: "index",
                withExtension: "html"
            )

            guard let indexURL else {
                return
            }

            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName else { return }
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                session?.attach(listener: self)
                flushTranscriptIfNeeded()
            case "input":
                if let text = body["text"] as? String {
                    session?.send(text)
                }
            case "resize":
                guard let cols = body["cols"] as? Int, let rows = body["rows"] as? Int else { return }
                let pixelWidth = body["pixelWidth"] as? Int ?? 0
                let pixelHeight = body["pixelHeight"] as? Int ?? 0
                session?.resize(columns: cols, rows: rows, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
            default:
                break
            }
        }

        func sshTerminalSession(_ session: SSHTerminalSession, didResetTranscript transcript: Data) {
            pendingTranscript = transcript
            flushTranscriptIfNeeded()
        }

        func sshTerminalSession(_ session: SSHTerminalSession, didReceiveOutput chunk: Data) {
            guard !chunk.isEmpty else { return }

            if !isReady {
                var data = pendingTranscript ?? Data()
                data.append(chunk)
                pendingTranscript = data
                return
            }

            guard let chunkLiteral = Self.base64Literal(for: chunk) else { return }
            evaluateJavaScript("window.talkieTerminal?.writeBytes(\(chunkLiteral));")
        }

        func sendInput(_ text: String) {
            session?.send(text)
        }

        func deleteBackward() {
            session?.send("\u{7F}")
        }

        func focusTerminal() {
            evaluateJavaScript("window.talkieTerminal?.focus?.();")
        }

        func blurTerminal() {
            evaluateJavaScript("window.talkieTerminal?.blur?.();")
        }

        func refitTerminal() {
            evaluateJavaScript("window.talkieTerminal?.refit?.();")
        }

        func hardRefitTerminal() {
            resetViewport()
            evaluateJavaScript("window.talkieTerminal?.hardRefit?.();")
        }

        private func flushTranscriptIfNeeded() {
            guard isReady, let pendingTranscript else { return }
            self.pendingTranscript = nil

            if pendingTranscript.isEmpty {
                evaluateJavaScript("window.talkieTerminal?.clear();")
                return
            }

            guard let transcriptLiteral = Self.base64Literal(for: pendingTranscript) else { return }
            evaluateJavaScript("window.talkieTerminal?.resetBytes(\(transcriptLiteral));")
        }

        private func evaluateJavaScript(
            _ script: String,
            completion: (() -> Void)? = nil
        ) {
            pendingJavaScriptEvaluations.append(
                QueuedJavaScriptEvaluation(
                    script: script,
                    completion: completion
                )
            )
            processNextJavaScriptEvaluationIfNeeded()
        }

        private func processNextJavaScriptEvaluationIfNeeded() {
            guard !isEvaluatingJavaScript else { return }
            guard let webView else { return }
            guard let next = pendingJavaScriptEvaluations.first else { return }

            isEvaluatingJavaScript = true
            webView.evaluateJavaScript(next.script) { [weak self] _, _ in
                guard let self else { return }
                defer {
                    self.isEvaluatingJavaScript = false
                    self.processNextJavaScriptEvaluationIfNeeded()
                }

                guard !self.pendingJavaScriptEvaluations.isEmpty else { return }
                self.pendingJavaScriptEvaluations.removeFirst().completion?()
            }
        }

        private static func base64Literal(for data: Data) -> String? {
            let encoded = data.base64EncodedString()
            guard let literal = try? JSONEncoder().encode(encoded),
                  let string = String(data: literal, encoding: .utf8) else {
                return nil
            }

            return string
        }

        @objc
        private func appDidBecomeActive() {
            hardRefitTerminal()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.hardRefitTerminal()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                self?.hardRefitTerminal()
            }
        }

        private func resetViewport() {
            guard let webView else { return }

            webView.scrollView.setZoomScale(1, animated: false)
            webView.scrollView.zoomScale = 1
            webView.scrollView.contentOffset = .zero
            webView.scrollView.contentInset = .zero
            webView.setNeedsLayout()
            webView.layoutIfNeeded()
        }
    }
}

private struct QueuedJavaScriptEvaluation {
    let script: String
    let completion: (() -> Void)?
}

final class TerminalContainerView: UIView {
    let webView: WKWebView
    var lastAppliedFocusRequestID = 0
    var lastAppliedDismissRequestID = 0
    var lastAppliedRefitRequestID = 0

    var onFocusTerminal: (() -> Void)? {
        didSet { }
    }

    var onBlurTerminal: (() -> Void)? {
        didSet { }
    }

    var onTerminalTap: (() -> Void)?

    var isKeyboardInputEnabled = false {
        didSet {
            guard !isKeyboardInputEnabled else { return }
            onBlurTerminal?()
        }
    }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = true
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityIdentifier = "ssh.terminal"
        accessibilityLabel = "SSH terminal"
        accessibilityHint = "Tap to open the keyboard and type into the remote shell."

        // Keep all text input on the native bridge. Letting WKWebView receive
        // touches can cause xterm's hidden textarea to become the effective
        // first responder, which drops us into the wrong keyboard/input mode.
        webView.isUserInteractionEnabled = false
        webView.clipsToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.clipsToBounds = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = true
        addGestureRecognizer(tapGesture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleTap() {
        guard isKeyboardInputEnabled else { return }
        onTerminalTap?()
        onFocusTerminal?()
    }

    func activateKeyboardInput() {
        guard isKeyboardInputEnabled else { return }
        onFocusTerminal?()
    }

    func deactivateKeyboardInput() {
        onBlurTerminal?()
    }
}
