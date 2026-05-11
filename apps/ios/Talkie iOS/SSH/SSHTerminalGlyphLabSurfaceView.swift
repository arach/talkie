//
//  SSHTerminalGlyphLabSurfaceView.swift
//  Talkie iOS
//
//  Standalone xterm renderer lab used to isolate glyph rendering without
//  SSH, tmux, or terminal session plumbing in the loop.
//

import SwiftUI
import WebKit

struct SSHTerminalGlyphLabSurfaceView: UIViewRepresentable {
    let refitRequestID: Int
    let captureData: Data?
    let chunkRecords: [SSHTerminalOutputChunkRecord]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.bouncesZoom = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.bind(webView: webView, captureData: captureData)
        context.coordinator.bind(chunkRecords: chunkRecords)
        context.coordinator.loadGlyphLab()

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.bind(webView: uiView, captureData: captureData)
        context.coordinator.bind(chunkRecords: chunkRecords)

        if context.coordinator.lastAppliedRefitRequestID != refitRequestID {
            context.coordinator.lastAppliedRefitRequestID = refitRequestID
            context.coordinator.refit()
        }
    }
}

extension SSHTerminalGlyphLabSurfaceView {
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastAppliedRefitRequestID = 0
        private var isReady = false
        private var pendingCaptureData: Data?
        private var pendingChunkRecords: [SSHTerminalOutputChunkRecord] = []

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

        func bind(webView: WKWebView, captureData: Data?) {
            self.webView = webView
            self.pendingCaptureData = captureData
            applyReplayIfReady()
        }

        func bind(chunkRecords: [SSHTerminalOutputChunkRecord]) {
            pendingChunkRecords = chunkRecords
            applyReplayIfReady()
        }

        func loadGlyphLab() {
            guard let webView else { return }
            guard let pageURL = Bundle.main.url(
                forResource: "glyph-lab",
                withExtension: "html",
                subdirectory: "SSHTerminal"
            ) ?? Bundle.main.url(
                forResource: "glyph-lab",
                withExtension: "html"
            ) else {
                return
            }

            webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        }

        func refit() {
            guard let webView else { return }

            webView.scrollView.setZoomScale(1, animated: false)
            webView.scrollView.zoomScale = 1
            webView.scrollView.contentOffset = .zero
            webView.scrollView.contentInset = .zero
            webView.setNeedsLayout()
            webView.layoutIfNeeded()
            webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
            webView.evaluateJavaScript("window.talkieGlyphLab?.refit?.();")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyReplayIfReady()
        }

        private func applyReplayIfReady() {
            guard isReady, let webView else { return }

            if !pendingChunkRecords.isEmpty,
               let literal = Self.chunkRecordsLiteral(for: pendingChunkRecords) {
                webView.evaluateJavaScript("window.talkieGlyphLab?.setChunkRecords(\(literal));")
                return
            }

            guard let pendingCaptureData, !pendingCaptureData.isEmpty else { return }
            guard let literal = Self.base64Literal(for: pendingCaptureData) else { return }
            webView.evaluateJavaScript("window.talkieGlyphLab?.setBytes(\(literal));")
        }

        private static func base64Literal(for data: Data) -> String? {
            let encoded = data.base64EncodedString()
            guard let literal = try? JSONEncoder().encode(encoded),
                  let string = String(data: literal, encoding: .utf8) else {
                return nil
            }

            return string
        }

        private static func chunkRecordsLiteral(for records: [SSHTerminalOutputChunkRecord]) -> String? {
            guard let literal = try? JSONEncoder().encode(records),
                  let string = String(data: literal, encoding: .utf8) else {
                return nil
            }

            return string
        }

        @objc
        private func appDidBecomeActive() {
            refit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.refit()
            }
        }
    }
}
