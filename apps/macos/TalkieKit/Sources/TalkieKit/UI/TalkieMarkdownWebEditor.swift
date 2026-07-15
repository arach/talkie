//
//  TalkieMarkdownWebEditor.swift
//  TalkieKit
//
//  WKWebView-backed Markdown editor used by Compose. The native side keeps
//  the document as a plain String; the web side owns editing affordances
//  (CodeMirror 6, Markdown syntax, review decorations) and reports every
//  text/selection change through a narrow JS bridge.
//

import Foundation
import Observation
import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
@Observable
public final class TalkieMarkdownWebEditorBridge {
    public private(set) var isReady = false

    @ObservationIgnored private var evaluator: ((String) -> Void)?
    @ObservationIgnored private var focusRequester: (() -> Void)?
    @ObservationIgnored private var pendingScripts: [String] = []

    public init() {}

    public func focus() {
        focusRequester?()
        call("focus")
    }

    public func blur() {
        call("blur")
    }

    public func insertTextAtCursor(_ text: String) {
        call("insertTextAtCursor", jsonLiteral(text))
    }

    public func replaceRange(from: Int, to: Int, with text: String) {
        call("replaceRange", "\(from)", "\(to)", jsonLiteral(text))
    }

    public func setSelection(anchor: Int, head: Int? = nil) {
        let payload: [String: Any] = [
            "anchor": anchor,
            "head": head ?? anchor,
        ]
        call("setSelection", jsonObject(payload))
    }

    public func undo() {
        call("undo")
    }

    public func redo() {
        call("redo")
    }

    public func clearReviewRanges() {
        call("clearReviewRanges")
    }

    public func setReviewRanges(_ ranges: [TalkieMarkdownReviewRange]) {
        call("setReviewRanges", jsonObject(ranges.map(\.dictionary)))
    }

    fileprivate func attach(
        evaluator: @escaping (String) -> Void,
        focusRequester: (() -> Void)? = nil
    ) {
        self.evaluator = evaluator
        self.focusRequester = focusRequester
        flushIfReady()
    }

    fileprivate func detach() {
        evaluator = nil
        focusRequester = nil
        isReady = false
        pendingScripts.removeAll()
    }

    fileprivate func markReady() {
        isReady = true
        flushIfReady()
    }

    private func call(_ function: String, _ arguments: String...) {
        let script = "window.TalkieEditor?.\(function)(\(arguments.joined(separator: ",")));"
        evaluateOrQueue(script)
    }

    fileprivate func evaluateOrQueue(_ script: String) {
        guard isReady, let evaluator else {
            pendingScripts.append(script)
            return
        }
        evaluator(script)
    }

    private func flushIfReady() {
        guard isReady, let evaluator else { return }
        let scripts = pendingScripts
        pendingScripts.removeAll()
        for script in scripts {
            evaluator(script)
        }
    }
}

public struct TalkieMarkdownReviewRange: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case insertion
        case deletion
        case replacement
    }

    public var id: String
    public var kind: Kind
    public var from: Int
    public var to: Int

    public init(id: String, kind: Kind, from: Int, to: Int) {
        self.id = id
        self.kind = kind
        self.from = from
        self.to = to
    }

    fileprivate var dictionary: [String: Any] {
        [
            "id": id,
            "kind": kind.rawValue,
            "from": from,
            "to": to,
        ]
    }
}

public struct TalkieMarkdownWebEditorAppearance: Equatable, Sendable {
    public var fontSize: Double
    public var lineHeight: Double
    public var textColor: String
    public var mutedTextColor: String
    public var accentColor: String
    public var selectionColor: String
    public var insertionColor: String
    public var insertionBorderColor: String
    public var deletionColor: String
    public var deletionBorderColor: String
    public var widgetBackgroundColor: String

    public init(
        fontSize: Double = 14,
        lineHeight: Double = 1.58,
        textColor: String = "#232423",
        mutedTextColor: String = "rgba(35,36,35,0.52)",
        accentColor: String = "#9A6A22",
        selectionColor: String = "rgba(154,106,34,0.22)",
        insertionColor: String = "rgba(57,128,74,0.18)",
        insertionBorderColor: String = "rgba(57,128,74,0.40)",
        deletionColor: String = "rgba(196,58,28,0.18)",
        deletionBorderColor: String = "rgba(196,58,28,0.40)",
        widgetBackgroundColor: String = "rgba(248,248,247,0.96)"
    ) {
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.textColor = textColor
        self.mutedTextColor = mutedTextColor
        self.accentColor = accentColor
        self.selectionColor = selectionColor
        self.insertionColor = insertionColor
        self.insertionBorderColor = insertionBorderColor
        self.deletionColor = deletionColor
        self.deletionBorderColor = deletionBorderColor
        self.widgetBackgroundColor = widgetBackgroundColor
    }

    fileprivate var dictionary: [String: Any] {
        [
            "fontSize": fontSize,
            "lineHeight": lineHeight,
            "textColor": textColor,
            "mutedTextColor": mutedTextColor,
            "accentColor": accentColor,
            "selectionColor": selectionColor,
            "insertionColor": insertionColor,
            "insertionBorderColor": insertionBorderColor,
            "deletionColor": deletionColor,
            "deletionBorderColor": deletionBorderColor,
            "widgetBackgroundColor": widgetBackgroundColor,
        ]
    }
}

#if os(macOS)
private final class TalkieMarkdownEditingWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        requestEditorFocus()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        requestEditorFocus()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        requestEditorFocus()
        super.otherMouseDown(with: event)
    }
}

public struct TalkieMarkdownWebEditor: NSViewRepresentable {
    @Binding private var text: String
    @Binding private var selectedRange: NSRange?
    private let placeholder: String
    private let appearance: TalkieMarkdownWebEditorAppearance
    private let bridge: TalkieMarkdownWebEditorBridge?

    public init(
        text: Binding<String>,
        selectedRange: Binding<NSRange?>,
        placeholder: String = "",
        appearance: TalkieMarkdownWebEditorAppearance = .init(),
        bridge: TalkieMarkdownWebEditorBridge? = nil
    ) {
        self._text = text
        self._selectedRange = selectedRange
        self.placeholder = placeholder
        self.appearance = appearance
        self.bridge = bridge
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(context: context)
        context.coordinator.attach(to: webView)
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(parent: self, webView: webView)
    }

    public static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(webView: webView)
    }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let webView = TalkieMarkdownEditingWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.loadComposeEditorAsset()
        return webView
    }
}
#elseif os(iOS)
public struct TalkieMarkdownWebEditor: UIViewRepresentable {
    @Binding private var text: String
    @Binding private var selectedRange: NSRange?
    private let placeholder: String
    private let appearance: TalkieMarkdownWebEditorAppearance
    private let bridge: TalkieMarkdownWebEditorBridge?

    public init(
        text: Binding<String>,
        selectedRange: Binding<NSRange?>,
        placeholder: String = "",
        appearance: TalkieMarkdownWebEditorAppearance = .init(),
        bridge: TalkieMarkdownWebEditorBridge? = nil
    ) {
        self._text = text
        self._selectedRange = selectedRange
        self.placeholder = placeholder
        self.appearance = appearance
        self.bridge = bridge
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(context: context)
        context.coordinator.attach(to: webView)
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(parent: self, webView: webView)
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(webView: webView)
    }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        webView.allowsBackForwardNavigationGestures = false
        webView.loadComposeEditorAsset()
        return webView
    }
}
#endif

extension TalkieMarkdownWebEditor {
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate static let messageHandlerName = "talkieEditor"

        private var parent: TalkieMarkdownWebEditor
        private weak var webView: WKWebView?
        private var isLoaded = false
        private var lastKnownText = ""
        private var lastConfigurationJSON = ""

        fileprivate init(parent: TalkieMarkdownWebEditor) {
            self.parent = parent
            super.init()
        }

        fileprivate func attach(to webView: WKWebView) {
            self.webView = webView
            parent.bridge?.attach(
                evaluator: { [weak webView] script in
                    webView?.evaluateJavaScript(script)
                },
                focusRequester: { [weak webView] in
                    webView?.requestEditorFocus()
                }
            )
        }

        fileprivate func update(parent: TalkieMarkdownWebEditor, webView: WKWebView) {
            self.parent = parent
            self.webView = webView
            parent.bridge?.attach(
                evaluator: { [weak webView] script in
                    webView?.evaluateJavaScript(script)
                },
                focusRequester: { [weak webView] in
                    webView?.requestEditorFocus()
                }
            )
            configureIfNeeded()
            syncTextIfNeeded()
        }

        fileprivate func teardown(webView: WKWebView) {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
            webView.configuration.userContentController.removeAllUserScripts()
            webView.loadHTMLString("", baseURL: nil)
            parent.bridge?.detach()
            self.webView = nil
            isLoaded = false
        }

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                isLoaded = true
                parent.bridge?.markReady()
                configureIfNeeded(force: true)
                syncTextIfNeeded(force: true)
            case "change":
                guard let nextText = body["text"] as? String else { return }
                lastKnownText = nextText
                if parent.text != nextText {
                    parent.text = nextText
                }
            case "selection":
                handleSelection(body)
            case "focus":
                webView?.requestEditorFocus()
            case "blur":
                break
            case "reviewAction":
                break
            default:
                break
            }
        }

        private func handleSelection(_ body: [String: Any]) {
            let from = body["from"] as? Int ?? 0
            let to = body["to"] as? Int ?? from
            let length = max(0, to - from)
            let nextRange = length > 0 ? NSRange(location: from, length: length) : nil
            if parent.selectedRange != nextRange {
                parent.selectedRange = nextRange
            }
        }

        private func configureIfNeeded(force: Bool = false) {
            guard isLoaded else { return }
            var config = parent.appearance.dictionary
            config["placeholder"] = parent.placeholder
            config["editable"] = true
            let json = jsonObject(config)
            guard force || json != lastConfigurationJSON else { return }
            lastConfigurationJSON = json
            evaluate("window.TalkieEditor?.configure(\(json));")
        }

        private func syncTextIfNeeded(force: Bool = false) {
            guard isLoaded else { return }
            guard force || parent.text != lastKnownText else { return }
            lastKnownText = parent.text
            evaluate("window.TalkieEditor?.setText(\(jsonLiteral(parent.text)));")
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script)
        }
    }
}

private extension WKWebView {
    func requestEditorFocus() {
        #if os(macOS)
        window?.makeFirstResponder(self)
        #elseif os(iOS)
        becomeFirstResponder()
        #endif
    }

    func loadComposeEditorAsset() {
        guard let indexURL = Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "ComposeWebEditor"
        ) else {
            loadHTMLString("<html><body></body></html>", baseURL: nil)
            return
        }

        loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
}

private func jsonLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let encoded = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return encoded
}

private func jsonObject(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let encoded = String(data: data, encoding: .utf8) else {
        return "null"
    }
    return encoded
}
