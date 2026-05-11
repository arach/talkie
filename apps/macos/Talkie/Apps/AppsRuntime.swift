//
//  AppsRuntime.swift
//  Talkie
//
//  Runtime for Talkie Apps.
//
//  Architecture:
//  - Background scripts run in JSContext (JavaScriptCore) - lightweight, no sandbox noise
//  - UI panels (when requested) use WKWebView - contained, lazy-loaded
//
//  JS API follows Chrome extension conventions (talkie.events, talkie.storage, etc.)
//

import JavaScriptCore
import WebKit
import SwiftUI
import TalkieKit

private let log = Log(.system)

// MARK: - Apps Runtime

@MainActor
@Observable
final class AppsRuntime: NSObject {
    // MARK: - Singleton

    static let shared = AppsRuntime()

    // MARK: - State

    /// Apps discovered and managed by AppManager
    internal var loadedApps: [String: LoadedApp] = [:]

    /// JSContext for each app's background script (lightweight, no WebContent)
    private var contexts: [String: JSContext] = [:]

    /// WKWebView for apps that need UI rendering (lazy, only created on demand)
    private var uiWebViews: [String: WKWebView] = [:]
    private var backgroundScriptsLoaded = false
    private var hasStarted = false

    private(set) var appManager: AppManager!

    private var isFrameworkEnabled: Bool {
        SettingsManager.shared.extensionsFrameworkEnabled
    }

    var isStarted: Bool {
        hasStarted
    }

    // MARK: - Directories

    var userAppsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Talkie/Apps", isDirectory: true)
    }

    var bundledAppsDirectory: URL? {
        // Apps are in Resources/Apps/ within the bundled Resources folder
        Bundle.main.resourceURL?.appendingPathComponent("Resources/Apps", isDirectory: true)
    }

    /// Data directory for a specific app (for JSON storage, etc.)
    func dataDirectory(for appId: String) -> URL {
        userAppsDirectory.appendingPathComponent("\(appId)/data", isDirectory: true)
    }

    /// Storage file path for an app's local storage
    func storageFile(for appId: String) -> URL {
        dataDirectory(for: appId).appendingPathComponent("storage.json")
    }

    // MARK: - Init

    private override init() {
        super.init()
        appManager = AppManager(runtime: self)
        ensureDirectories()
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: userAppsDirectory, withIntermediateDirectories: true)
        log.debug("Apps directory: \(userAppsDirectory.path)")
    }

    /// Ensure data directory exists for an app
    private func ensureDataDirectory(for appId: String) {
        let dataDir = dataDirectory(for: appId)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    // MARK: - JSON Storage Helpers

    /// Pending storage writes (for debouncing)
    private var pendingWrites: [String: [String: Any]] = [:]
    private var writeTimers: [String: Timer] = [:]
    private let writeDebounceInterval: TimeInterval = 0.5  // 500ms debounce

    /// Read all stored data for an app from its JSON file
    private func readStorage(for appId: String) -> [String: Any] {
        // Return pending writes if available (not yet flushed to disk)
        if let pending = pendingWrites[appId] {
            return pending
        }
        let file = storageFile(for: appId)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// Queue a storage write with debouncing (coalesces rapid writes)
    private func queueStorageWrite(_ storage: [String: Any], for appId: String) {
        pendingWrites[appId] = storage

        // Cancel existing timer for this app
        writeTimers[appId]?.invalidate()

        // Schedule new write after debounce interval
        writeTimers[appId] = Timer.scheduledTimer(withTimeInterval: writeDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushStorage(for: appId)
            }
        }
    }

    /// Flush pending writes to disk
    private func flushStorage(for appId: String) {
        guard let storage = pendingWrites.removeValue(forKey: appId) else { return }
        writeTimers.removeValue(forKey: appId)

        let success = writeStorageToDisk(storage, for: appId)
        if !success {
            log.warning("Storage write failed for app \(appId), data may be lost")
        }
    }

    /// Write storage data for an app to its JSON file
    /// - Returns: true if write succeeded, false otherwise
    @discardableResult
    private func writeStorageToDisk(_ storage: [String: Any], for appId: String) -> Bool {
        ensureDataDirectory(for: appId)
        let file = storageFile(for: appId)

        guard let data = try? JSONSerialization.data(withJSONObject: storage, options: [.prettyPrinted, .sortedKeys]) else {
            log.error("Failed to serialize storage for app \(appId)")
            return false
        }

        do {
            try data.write(to: file, options: .atomic)
            log.debug("Storage written for app \(appId)")
            return true
        } catch {
            log.error("Failed to write storage for app \(appId): \(error)")
            return false
        }
    }

    /// Flush all pending storage writes (call on app termination)
    func flushAllPendingWrites() {
        for appId in pendingWrites.keys {
            flushStorage(for: appId)
        }
    }

    // MARK: - Lifecycle

    func start(preloadBackgroundScripts: Bool = false) {
        guard isFrameworkEnabled else {
            if hasStarted || backgroundScriptsLoaded || !contexts.isEmpty || !uiWebViews.isEmpty || !loadedApps.isEmpty {
                stop()
            }
            return
        }

        if !hasStarted {
            appManager.discoverApps()
            hasStarted = true
            log.info("AppsRuntime started: \(loadedApps.count) apps discovered")
        }

        if preloadBackgroundScripts {
            loadEnabledBackgroundScriptsIfNeeded()
        }
    }

    func ensureStarted(preloadBackgroundScripts: Bool = false) {
        start(preloadBackgroundScripts: preloadBackgroundScripts)
    }

    func stop() {
        // Flush any pending storage writes before stopping
        flushAllPendingWrites()
        for timer in writeTimers.values {
            timer.invalidate()
        }
        writeTimers.removeAll()
        pendingWrites.removeAll()

        contexts.removeAll()

        for (_, webView) in uiWebViews {
            webView.stopLoading()
        }
        uiWebViews.removeAll()

        for appId in Array(loadedApps.keys) {
            guard var app = loadedApps[appId] else { continue }
            app.isLoaded = false
            loadedApps[appId] = app
        }

        backgroundScriptsLoaded = false
        hasStarted = false
        loadedApps.removeAll()
        log.info("AppsRuntime stopped")
    }

    private func loadEnabledBackgroundScriptsIfNeeded() {
        guard hasStarted else { return }
        guard !backgroundScriptsLoaded else { return }
        for (id, app) in loadedApps where app.isEnabled {
            loadApp(id)
        }
        backgroundScriptsLoaded = true
    }

    // MARK: - App Loading

    func loadApp(_ appId: String) {
        guard isFrameworkEnabled else { return }
        ensureStarted()
        guard hasStarted else { return }

        guard var app = loadedApps[appId] else {
            log.error("App not found: \(appId)")
            return
        }

        guard let scriptURL = app.backgroundScriptURL else {
            log.error("App has no background script: \(appId)")
            return
        }

        guard let scriptContent = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            log.error("Failed to read script: \(scriptURL.path)")
            app.loadError = "Failed to read script"
            loadedApps[appId] = app
            return
        }

        guard let context = JSContext() else {
            log.error("Failed to create JSContext for app: \(appId)")
            return
        }

        context.exceptionHandler = { _, exception in
            if let exception = exception {
                log.error("JS Exception in app \(appId): \(exception)")
            }
        }

        setupBridge(context: context, appId: appId, appDirectory: app.directory)
        contexts[appId] = context
        context.evaluateScript(scriptContent)

        app.isLoaded = true
        app.loadedAt = Date()
        app.loadError = nil
        loadedApps[appId] = app

        log.info("Loaded app: \(app.manifest.name)")
    }

    func unloadApp(_ appId: String) {
        guard hasStarted else { return }

        guard var app = loadedApps[appId] else { return }

        contexts.removeValue(forKey: appId)

        // Clean up any UI WebView
        if let webView = uiWebViews.removeValue(forKey: appId) {
            webView.stopLoading()
        }

        app.isLoaded = false
        loadedApps[appId] = app

        log.info("Unloaded app: \(app.manifest.name)")
    }

    func reloadApp(_ appId: String) {
        guard isFrameworkEnabled else { return }
        ensureStarted()
        guard hasStarted else { return }
        unloadApp(appId)
        loadApp(appId)
    }

    func reloadAllApps() {
        guard isFrameworkEnabled else { return }
        ensureStarted()
        guard hasStarted else { return }
        for id in Array(contexts.keys) {
            reloadApp(id)
        }
    }

    // MARK: - Bridge Setup (JSContext)

    private func setupBridge(context: JSContext, appId: String, appDirectory: URL) {
        // Console logging
        let consoleLog: @convention(block) (String) -> Void = { message in
            log.debug("[App:\(appId)] \(message)")
        }
        context.setObject(consoleLog, forKeyedSubscript: "_consoleLog" as NSString)
        context.evaluateScript("console = { log: _consoleLog, error: _consoleLog, warn: _consoleLog, info: _consoleLog };")

        // Core API structure + event system
        context.evaluateScript("""
        (function() {
            'use strict';
            const eventListeners = {};

            globalThis.__talkieEmit = function(event, data) {
                const listeners = eventListeners[event] || [];
                listeners.forEach(fn => {
                    try { fn(data); } catch (e) { console.error('Event handler error: ' + e); }
                });
            };

            const createEvent = (name) => ({
                addListener: (fn) => {
                    if (!eventListeners[name]) eventListeners[name] = [];
                    eventListeners[name].push(fn);
                },
                removeListener: (fn) => {
                    const arr = eventListeners[name] || [];
                    const idx = arr.indexOf(fn);
                    if (idx >= 0) arr.splice(idx, 1);
                },
                hasListener: (fn) => (eventListeners[name] || []).includes(fn)
            });

            globalThis.talkie = {
                events: {
                    onMemoCreated: createEvent('memoCreated'),
                    onDictationCompleted: createEvent('dictationCompleted'),
                    onPolishCompleted: createEvent('polishCompleted'),
                    onSessionStarted: createEvent('sessionStarted')
                },
                storage: { local: { get: null, set: null } },
                state: { get: null },
                notifications: { create: null },
                ui: { showPanel: null },
                data: { getActivityByDay: null },
                navigation: { goToDate: null }
            };

            console.log('Talkie API initialized');
        })();
        """)

        // Storage API (JSON file-based, per-app isolation)
        let storageGet: @convention(block) (JSValue, JSValue) -> Void = { [weak self] keysValue, callbackValue in
            guard let self = self else { return }
            let keys: [String] = keysValue.isString ? [keysValue.toString()] :
                                 keysValue.isArray ? (keysValue.toArray() as? [String] ?? []) : []
            let storage = self.readStorage(for: appId)
            var result: [String: Any] = [:]
            for key in keys {
                if let value = storage[key] {
                    result[key] = value
                }
            }
            if callbackValue.isObject && !callbackValue.isUndefined {
                callbackValue.call(withArguments: [result])
            }
        }
        context.setObject(storageGet, forKeyedSubscript: "_storageGet" as NSString)
        context.evaluateScript("talkie.storage.local.get = _storageGet;")

        let storageSet: @convention(block) (JSValue, JSValue) -> Void = { [weak self] itemsValue, callbackValue in
            guard let self = self else { return }
            if let items = itemsValue.toDictionary() as? [String: Any] {
                var storage = self.readStorage(for: appId)
                for (key, value) in items {
                    storage[key] = value
                }
                self.queueStorageWrite(storage, for: appId)
            }
            if callbackValue.isObject && !callbackValue.isUndefined {
                callbackValue.call(withArguments: [])
            }
        }
        context.setObject(storageSet, forKeyedSubscript: "_storageSet" as NSString)
        context.evaluateScript("talkie.storage.local.set = _storageSet;")

        // State API
        let stateGet: @convention(block) (JSValue, JSValue) -> Void = { keysValue, callbackValue in
            let keys: [String] = keysValue.isString ? [keysValue.toString()] :
                                 keysValue.isArray ? (keysValue.toArray() as? [String] ?? []) : []
            Task { @MainActor in
                let manager = ExtensionManager.shared
                var result: [String: Any] = [:]
                for key in keys {
                    switch key {
                    case "memoCount": result[key] = manager.memoCount
                    case "dictationCount": result[key] = manager.dictationCount
                    case "totalWords": result[key] = manager.totalWords
                    case "currentStreak": result[key] = manager.currentStreak
                    case "sessionCount": result[key] = manager.sessionCount
                    case "polishCount": result[key] = manager.polishCount
                    case "workflowCount": result[key] = manager.workflowCount
                    default: break
                    }
                }
                if callbackValue.isObject && !callbackValue.isUndefined {
                    callbackValue.call(withArguments: [result])
                }
            }
        }
        context.setObject(stateGet, forKeyedSubscript: "_stateGet" as NSString)
        context.evaluateScript("talkie.state.get = _stateGet;")

        // Notifications API (native toasts)
        let notificationsCreate: @convention(block) (String, JSValue, JSValue) -> Void = { _, optionsValue, callbackValue in
            let title = optionsValue.objectForKeyedSubscript("title")?.toString() ?? ""
            let message = optionsValue.objectForKeyedSubscript("message")?.toString() ?? ""
            let iconUrl = optionsValue.objectForKeyedSubscript("iconUrl")?.toString()

            Task { @MainActor in
                ExtensionManager.shared.showToast(ExtensionToast(
                    title: title,
                    subtitle: message,
                    icon: iconUrl ?? "star.fill"
                ))
                if callbackValue.isObject && !callbackValue.isUndefined {
                    callbackValue.call(withArguments: [])
                }
            }
        }
        context.setObject(notificationsCreate, forKeyedSubscript: "_notificationsCreate" as NSString)
        context.evaluateScript("talkie.notifications.create = _notificationsCreate;")

        // Data API (activity data for widgets)
        let dataGetActivityByDay: @convention(block) (JSValue, JSValue) -> Void = { daysValue, callbackValue in
            let days = daysValue.isNumber ? Int(daysValue.toInt32()) : 91
            Task { @MainActor in
                guard DatabaseManager.shared.isInitialized else {
                    if callbackValue.isObject && !callbackValue.isUndefined {
                        callbackValue.call(withArguments: [[:] as [String: Any]])
                    }
                    return
                }
                let repo = TalkieObjectRepository()
                var result: [String: Any] = [:]
                if let dictationActivity = try? await repo.dictationActivityByDay(days: days) {
                    for (key, val) in dictationActivity {
                        result[key] = val
                    }
                }
                // Also add memo heatmap data
                let memoData = MemosViewModel.shared.heatmapData
                for (key, val) in memoData {
                    result[key] = (result[key] as? Int ?? 0) + val
                }
                if callbackValue.isObject && !callbackValue.isUndefined {
                    callbackValue.call(withArguments: [result])
                }
            }
        }
        context.setObject(dataGetActivityByDay, forKeyedSubscript: "_dataGetActivityByDay" as NSString)
        context.evaluateScript("talkie.data.getActivityByDay = _dataGetActivityByDay;")

        // Navigation API (navigate to date-filtered views)
        let navigationGoToDate: @convention(block) (JSValue) -> Void = { dateValue in
            let dateString = dateValue.toString() ?? ""
            Task { @MainActor in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: dateString) {
                    NavigationState.shared.navigateToDate(date)
                }
            }
        }
        context.setObject(navigationGoToDate, forKeyedSubscript: "_navigationGoToDate" as NSString)
        context.evaluateScript("talkie.navigation.goToDate = _navigationGoToDate;")

        // UI API (for showing HTML panels - lazy WebView creation)
        let showPanel: @convention(block) (JSValue, JSValue) -> Void = { [weak self] optionsValue, callbackValue in
            guard let self = self else { return }

            let htmlFile = optionsValue.objectForKeyedSubscript("html")?.toString() ?? "panel.html"
            let width = optionsValue.objectForKeyedSubscript("width")?.toInt32() ?? 400
            let height = optionsValue.objectForKeyedSubscript("height")?.toInt32() ?? 300

            Task { @MainActor in
                self.showUIPanel(
                    appId: appId,
                    appDirectory: appDirectory,
                    htmlFile: htmlFile,
                    width: Int(width),
                    height: Int(height)
                )
                if callbackValue.isObject && !callbackValue.isUndefined {
                    callbackValue.call(withArguments: [])
                }
            }
        }
        context.setObject(showPanel, forKeyedSubscript: "_showPanel" as NSString)
        context.evaluateScript("talkie.ui.showPanel = _showPanel;")
    }

    // MARK: - UI Panel (WKWebView - lazy)

    private func showUIPanel(appId: String, appDirectory: URL, htmlFile: String, width: Int, height: Int) {
        let htmlURL = appDirectory.appendingPathComponent(htmlFile)

        guard FileManager.default.fileExists(atPath: htmlURL.path) else {
            log.warning("App \(appId) requested panel but \(htmlFile) not found")
            return
        }

        // Create WebView only when needed
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        webView.loadFileURL(htmlURL, allowingReadAccessTo: appDirectory)

        uiWebViews[appId] = webView

        // TODO: Present the WebView in a popover or sheet
        // For now, just log that we created it
        log.info("Created UI panel for app \(appId): \(htmlFile) (\(width)x\(height))")
    }

    // MARK: - Widget Apps

    /// Apps that declare a widget in their manifest (for Home page inline rendering)
    var widgetApps: [LoadedApp] {
        guard isFrameworkEnabled else { return [] }
        ensureStarted()
        guard hasStarted else { return [] }
        return loadedApps.values.filter { $0.manifest.widget != nil && $0.isEnabled }
    }

    /// Create a WKWebView configured for inline widget rendering
    func createWidgetWebView(for app: LoadedApp, messageHandler: WKScriptMessageHandler) -> WKWebView? {
        guard isFrameworkEnabled else { return nil }
        ensureStarted()
        guard hasStarted else { return nil }

        guard let widgetURL = app.widgetURL,
              FileManager.default.fileExists(atPath: widgetURL.path) else {
            log.warning("Widget HTML not found for app \(app.id)")
            return nil
        }

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Add message handler for JS -> Swift communication
        let contentController = config.userContentController
        contentController.add(messageHandler, name: "talkie")

        // Inject theme CSS variables and bridge APIs
        let themeScript = WKUserScript(
            source: Self.themeInjectionScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(themeScript)

        let bridgeScript = WKUserScript(
            source: Self.widgetBridgeScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")  // Transparent background
        webView.loadFileURL(widgetURL, allowingReadAccessTo: app.directory)

        return webView
    }

    /// CSS variables matching current theme colors, injected into widget WebViews
    static func themeInjectionScript() -> String {
        let theme = Theme.current
        return """
        (function() {
            const style = document.createElement('style');
            style.textContent = `
                :root {
                    --foreground: \(theme.foreground.cssHex);
                    --foreground-secondary: \(theme.foregroundSecondary.cssHex);
                    --foreground-muted: \(theme.foregroundMuted.cssHex);
                    --background: transparent;
                    --surface-1: \(theme.surface1.cssHex);
                    --surface-2: \(theme.surface2.cssHex);
                    --border: \(theme.border.cssHex);
                    --accent: \(theme.accent.cssHex);
                    --activity-color: \(theme.activityHeatmapColor.cssHex);
                }
                body {
                    background: transparent !important;
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    color: var(--foreground);
                    -webkit-user-select: none;
                    cursor: default;
                }
            `;
            document.documentElement.appendChild(style);
        })();
        """
    }

    /// Bridge API available in widget HTML (talkie.data, talkie.navigation via postMessage)
    static func widgetBridgeScript() -> String {
        return """
        (function() {
            'use strict';
            const callbacks = {};
            let callbackId = 0;

            window.talkie = {
                data: {
                    getActivityByDay: function(days, callback) {
                        const id = ++callbackId;
                        callbacks[id] = callback;
                        window.webkit.messageHandlers.talkie.postMessage({
                            type: 'data.getActivityByDay',
                            days: days || 91,
                            callbackId: id
                        });
                    }
                },
                navigation: {
                    goToDate: function(dateString) {
                        window.webkit.messageHandlers.talkie.postMessage({
                            type: 'navigation.goToDate',
                            date: dateString
                        });
                    }
                },
                _resolveCallback: function(id, data) {
                    if (callbacks[id]) {
                        callbacks[id](data);
                        delete callbacks[id];
                    }
                }
            };
        })();
        """
    }

    // MARK: - Event Emission

    func emit(event: String, data: [String: Any]) {
        guard isFrameworkEnabled else { return }
        // Defer extension runtime bootstrap and JSContext creation until first event.
        ensureStarted(preloadBackgroundScripts: true)
        guard hasStarted else { return }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            log.error("Failed to serialize event data")
            return
        }

        let js = "__talkieEmit('\(event)', \(jsonString));"
        for (_, context) in contexts {
            context.evaluateScript(js)
        }
    }

    // MARK: - Event Hooks

    func notifyMemoCreated(wordCount: Int, memoCount: Int, totalWords: Int) {
        log.debug("Emitting memoCreated to \(contexts.count) app(s)")
        emit(event: "memoCreated", data: [
            "wordCount": wordCount,
            "memoCount": memoCount,
            "totalWords": totalWords
        ])
    }

    func notifyDictationCompleted(wordCount: Int, dictationCount: Int) {
        log.debug("Emitting dictationCompleted to \(contexts.count) app(s)")
        emit(event: "dictationCompleted", data: [
            "wordCount": wordCount,
            "dictationCount": dictationCount
        ])
    }

    func notifyPolishCompleted(instruction: String, polishCount: Int) {
        log.debug("Emitting polishCompleted to \(contexts.count) app(s)")
        emit(event: "polishCompleted", data: [
            "instruction": instruction,
            "polishCount": polishCount
        ])
    }

    func notifySessionStarted(sessionNumber: Int) {
        log.debug("Emitting sessionStarted to \(contexts.count) app(s)")
        emit(event: "sessionStarted", data: [
            "sessionNumber": sessionNumber
        ])
    }
}

// MARK: - Color CSS Hex Extension

extension Color {
    /// Convert SwiftUI Color to CSS hex string (e.g., "#ffffff")
    var cssHex: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = nsColor.alphaComponent
        if a < 1.0 {
            return String(format: "rgba(%d,%d,%d,%.2f)", r, g, b, a)
        }
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
