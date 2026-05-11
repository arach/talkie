//
//  HomeAppWidgetView.swift
//  Talkie
//
//  Hosts a JS app widget's WKWebView inline on the Home page.
//  The WebView renders with a transparent background so the card shows through.
//  JS communicates with Swift via WKScriptMessageHandler (postMessage → talkie handler).
//

import SwiftUI
import WebKit
import TalkieKit

private let log = Log(.system)

// MARK: - Home App Widget View

struct HomeAppWidgetView: View {
    let app: LoadedApp

    var body: some View {
        WidgetCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Widget title bar
                HStack {
                    Text(app.manifest.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                // WebView content
                AppWidgetWebView(app: app)
                    .frame(minHeight: 220)
            }
        }
    }
}

// MARK: - WebView Representable

struct AppWidgetWebView: NSViewRepresentable {
    let app: LoadedApp

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        guard let webView = AppsRuntime.shared.createWidgetWebView(
            for: app,
            messageHandler: context.coordinator
        ) else {
            // Return an empty webview as fallback
            return WKWebView(frame: .zero)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op: WebView is loaded once
    }

    // MARK: - Coordinator (Message Handler)

    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "data.getActivityByDay":
                handleGetActivityByDay(body)

            case "navigation.goToDate":
                handleGoToDate(body)

            default:
                log.debug("Unknown widget message type: \(type)")
            }
        }

        private func handleGetActivityByDay(_ body: [String: Any]) {
            let days = body["days"] as? Int ?? 91
            let callbackId = body["callbackId"] as? Int ?? 0

            Task { @MainActor in
                guard DatabaseManager.shared.isInitialized else {
                    resolveCallback(callbackId, data: [:])
                    return
                }

                let repo = TalkieObjectRepository()
                var result: [String: Int] = [:]

                if let dictationActivity = try? await repo.dictationActivityByDay(days: days) {
                    for (key, val) in dictationActivity {
                        result[key] = val
                    }
                }

                // Also add memo heatmap data
                let memoData = MemosViewModel.shared.heatmapData
                for (key, val) in memoData {
                    result[key, default: 0] += val
                }

                resolveCallback(callbackId, data: result)
            }
        }

        private func handleGoToDate(_ body: [String: Any]) {
            guard let dateString = body["date"] as? String else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            Task { @MainActor in
                if let date = formatter.date(from: dateString) {
                    NavigationState.shared.navigateToDate(date)
                }
            }
        }

        private func resolveCallback(_ callbackId: Int, data: Any) {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }

            let js = "talkie._resolveCallback(\(callbackId), \(jsonString));"
            webView?.evaluateJavaScript(js)
        }
    }
}
