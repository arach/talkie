//
//  ConsolePopoutManager.swift
//  Talkie
//
//  Opens a managed agent session in its own AppKit window. The session has a
//  single listener, so the popout claims it while open — the inline view
//  shows a placeholder until the popout closes.
//

import AppKit
import Observation
import SwiftUI
import TalkieKit

@MainActor
@Observable
final class ConsolePopoutManager {
    static let shared = ConsolePopoutManager()

    private(set) var poppedOutSessionIDs: Set<UUID> = []

    @ObservationIgnored
    private var windows: [UUID: NSWindow] = [:]

    @ObservationIgnored
    private var observers: [UUID: NSObjectProtocol] = [:]

    @ObservationIgnored
    private var windowSessionIDs: [UUID: Set<UUID>] = [:]

    private init() {}

    func isPoppedOut(_ sessionID: UUID) -> Bool {
        poppedOutSessionIDs.contains(sessionID)
    }

    func openOrFocus(session: ManagedAgentConsoleSession, settingsManager: SettingsManager) {
        if let windowID = findWindowID(containing: session.id),
           let window = windows[windowID] {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let windowID = session.id
        let content = ConsolePopoutContent(session: session, windowID: windowID)
            .environment(settingsManager)

        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(session.profile.title) — Console"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 880, height: 560))
        window.backgroundColor = NSColor(settingsManager.consoleTerminalTheme.backgroundColor)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleClose(windowID: windowID)
            }
        }

        windows[windowID] = window
        observers[windowID] = observer
        markSessionPoppedOut(session.id, in: windowID)
        window.makeKeyAndOrderFront(nil)
    }

    func markSessionPoppedOut(_ sessionID: UUID, in windowID: UUID) {
        windowSessionIDs[windowID, default: []].insert(sessionID)
        poppedOutSessionIDs.insert(sessionID)
    }

    private func handleClose(windowID: UUID) {
        if let observer = observers.removeValue(forKey: windowID) {
            NotificationCenter.default.removeObserver(observer)
        }
        windows.removeValue(forKey: windowID)
        let closedSessionIDs = windowSessionIDs.removeValue(forKey: windowID) ?? []
        for sessionID in closedSessionIDs where findWindowID(containing: sessionID) == nil {
            poppedOutSessionIDs.remove(sessionID)
        }
    }

    private func findWindowID(containing sessionID: UUID) -> UUID? {
        windowSessionIDs.first { _, sessionIDs in
            sessionIDs.contains(sessionID)
        }?.key
    }
}

private struct ConsolePopoutContent: View {
    let session: ManagedAgentConsoleSession
    let windowID: UUID
    @Environment(SettingsManager.self) private var settingsManager
    @State private var ready = false
    @State private var captureController = ConsoleTerminalCaptureController()
    @State private var tabs: [ConsolePopoutSessionTab]
    @State private var activeSessionID: UUID
    @State private var nextTabNumber = 2

    init(session: ManagedAgentConsoleSession, windowID: UUID) {
        self.session = session
        self.windowID = windowID
        _tabs = State(initialValue: [
            ConsolePopoutSessionTab(
                session: session,
                label: session.profile.title
            )
        ])
        _activeSessionID = State(initialValue: session.id)
    }

    private var activeSession: ManagedAgentConsoleSession {
        tabs.first { $0.session.id == activeSessionID }?.session ?? session
    }

    var body: some View {
        VStack(spacing: 0) {
            ConsolePopoutTabStrip(
                tabs: tabs,
                activeSessionID: activeSessionID,
                select: selectTab,
                addTab: addTab
            )

            Rectangle()
                .fill(Theme.current.border.opacity(0.55))
                .frame(height: 1)

            ZStack(alignment: .topTrailing) {
                ManagedAgentTerminalView(
                    session: activeSession,
                    isReady: $ready,
                    holdLoader: false,
                    loaderReplayToken: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                    appearance: settingsManager.consoleTerminalAppearance,
                    backgroundColor: settingsManager.consoleTerminalTheme.backgroundColor,
                    foregroundColor: settingsManager.consoleTerminalTheme.foregroundColor
                )
                .id(activeSession.id)

                ConsoleTerminalCaptureControls(
                    controller: captureController,
                    session: activeSession
                )
                .padding(.top, 10)
                .padding(.trailing, 10)

                ConsoleTerminalDictationDock(
                    controller: captureController,
                    session: activeSession
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Theme.current.surfaceBase)
        .task {
            markActiveSessionPoppedOut()
        }
        .onChange(of: activeSessionID) { _, _ in
            markActiveSessionPoppedOut()
        }
        .onChange(of: activeSession.id) { _, _ in
            markActiveSessionPoppedOut()
        }
        .onDisappear {
            stopPopoutOwnedSessions()
        }
    }

    private func selectTab(_ tab: ConsolePopoutSessionTab) {
        activeSessionID = tab.session.id
        markActiveSessionPoppedOut()
    }

    private func addTab() {
        let source = activeSession
        let newSession = ManagedAgentConsoleSession(
            profile: source.profile,
            workspace: source.workspace,
            prompt: source.prompt,
            notes: source.notes,
            prefersConsoleTmux: source.prefersConsoleTmux
        )
        let label = "\(source.profile.title) \(nextTabNumber)"
        nextTabNumber += 1
        tabs.append(ConsolePopoutSessionTab(session: newSession, label: label, isPopoutOwned: true))
        activeSessionID = newSession.id
        markActiveSessionPoppedOut()
        newSession.start()
    }

    private func markActiveSessionPoppedOut() {
        ConsolePopoutManager.shared.markSessionPoppedOut(activeSession.id, in: windowID)
    }

    private func stopPopoutOwnedSessions() {
        for tab in tabs where tab.isPopoutOwned {
            tab.session.stop()
        }
    }
}

@MainActor
@Observable
final class ConsoleTerminalCaptureController {
    let dictation = DictationInput.shared

    var copyStatus: TerminalCopyStatus?
    var dictationError: String?
    var isCapturingScreenshot = false
    var screenshotError: String?

    /// True after a dictation transcript has been typed into the session's
    /// input line (but not yet submitted). Drives the contextual Submit
    /// button in the bottom-center mic dock — cleared on submit or when a
    /// new dictation begins.
    var hasPendingDictation = false

    func copyTerminalOutput(from session: ManagedAgentConsoleSession) {
        let status: TerminalCopyStatus = session.copyTranscriptToClipboard() ? .copied : .empty
        copyStatus = status

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard self?.copyStatus == status else { return }
            self?.copyStatus = nil
        }
    }

    func toggleDictation(sendTo session: ManagedAgentConsoleSession) {
        dictationError = nil

        if dictation.isPreparing && dictation.activePurpose == .terminalDictation {
            return
        }

        if dictation.isRecording && dictation.activePurpose == .terminalDictation {
            Task {
                do {
                    let transcript = try await dictation.stopAndTranscribe()
                    let prompt = terminalPrompt(transcript: transcript)
                    resetDictationContext()
                    guard !prompt.isEmpty else { return }
                    // Type the transcript into the input line without submitting
                    // it — the contextual Submit button sends the return.
                    session.send(prompt)
                    hasPendingDictation = true
                } catch {
                    resetDictationContext()
                    dictationError = error.localizedDescription
                }
            }
            return
        }

        hasPendingDictation = false

        Task {
            do {
                try await dictation.startCapture(purpose: .terminalDictation)
            } catch {
                resetDictationContext()
                dictationError = error.localizedDescription
            }
        }
    }

    /// Sends a return to submit the dictated text sitting in the input line.
    func submitPendingDictation(to session: ManagedAgentConsoleSession) {
        guard hasPendingDictation else { return }
        session.send("\r")
        hasPendingDictation = false
    }

    func captureScreenshot(sendTo session: ManagedAgentConsoleSession) {
        guard !isCapturingScreenshot else { return }
        screenshotError = nil
        isCapturingScreenshot = true

        Task {
            defer { isCapturingScreenshot = false }

            let chord: any CaptureChordController = CaptureHUDController()

            guard let result = await chord.beginChord(initialMode: .screenshot) else { return }

            switch result {
            case .screenshot(let mode):
                await captureSelectedScreenshot(mode: mode, sendTo: session)
            case .screenshotMarkup(let mode):
                await captureSelectedScreenshot(mode: mode, sendTo: session)
            case .screenshotRegion(let rect):
                await captureSelectedScreenshot(mode: .region, preselectedRegion: rect, sendTo: session)
            case .screenshotMarkupRegion(let rect):
                await captureSelectedScreenshot(mode: .region, preselectedRegion: rect, sendTo: session)
            case .screenRecord(let mode):
                await ScreenRecordingController.shared.startRecording(mode: mode)
            case .toggleCamera:
                guard FeatureFlags.shared.enableCameraBubble else { return }
                CameraBubbleController.shared.toggle()
            case .saveSelection:
                logRetiredTrayAction("save selection")
            case .viewTray:
                logRetiredTrayAction("view tray")
            case .pasteLastTray:
                logRetiredTrayAction("paste last")
            }
        }
    }

    private func pasteLatestScreenshot(sendTo session: ManagedAgentConsoleSession) {
        _ = session
        screenshotError = "Tray capture paste is retired"
    }

    private func captureSelectedScreenshot(
        mode: CaptureMode,
        preselectedRegion: CGRect? = nil,
        sendTo session: ManagedAgentConsoleSession
    ) async {
        guard let capture = await ScreenshotCaptureService.shared.captureStandalone(
            mode: mode,
            preselectedRegion: preselectedRegion
        ) else {
            screenshotError = "Screenshot capture cancelled"
            return
        }

        let previewID = ScreenshotPreviewPanel.shared.show(
            thumbnail: capture.previewImage,
            sourceWidth: capture.width,
            sourceHeight: capture.height
        )

        guard let savedURL = await persistConsoleCapture(capture, mode: mode) else {
            screenshotError = "Could not save screenshot"
            return
        }

        ScreenshotPreviewPanel.shared.attachFileURL(savedURL, to: previewID)

        guard !isTerminalDictationActive else { return }
        session.send(screenshotPrompt(for: savedURL))
    }

    private var isTerminalDictationActive: Bool {
        dictation.activePurpose == .terminalDictation
            && (dictation.isPreparing || dictation.isRecording || dictation.isTranscribing)
    }

    private func resetDictationContext() {
    }

    private func screenshotPrompt(for url: URL) -> String {
        "Use this screenshot: \(url.path)"
    }

    private func terminalPrompt(transcript: String) -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clipDurationLabel(_ durationMs: Int) -> String {
        let totalSeconds = max(durationMs, 0) / 1000
        guard totalSeconds >= 60 else { return "\(totalSeconds)s" }
        return "\(totalSeconds / 60)m \(totalSeconds % 60)s"
    }

    private func logRetiredTrayAction(_ action: String) {
        Log(.ui).info("Console tray action ignored; tray is retired", detail: action)
    }

    private func persistConsoleCapture(_ result: CaptureResult, mode: CaptureMode) async -> URL? {
        let captureId = UUID()
        guard let savedURL = ScreenshotStorage.save(
            result.data,
            recordingId: captureId,
            timestampMs: 0,
            index: 0,
            capturedAt: result.capturedAt,
            captureMode: mode.rawValue,
            width: result.width,
            height: result.height,
            windowTitle: result.windowTitle,
            appName: result.appName,
            displayName: result.displayName
        ) else {
            return nil
        }

        let screenshot = RecordingScreenshot(
            filename: savedURL.lastPathComponent,
            timestampMs: 0,
            captureMode: mode.rawValue,
            width: result.width,
            height: result.height,
            windowTitle: result.windowTitle,
            appName: result.appName,
            appBundleID: result.appBundleID,
            displayName: result.displayName
        )
        let titleSource = [result.appName, result.windowTitle, result.displayName]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { return nil }
                return trimmed
            }
            .first

        var capture = TalkieObject.newCapture(
            id: captureId,
            title: titleSource.map { "\($0) capture" }
        )
        if titleSource != nil || result.appBundleID != nil {
            capture.metadataJSON = RecordingMetadata(
                app: AppContext(
                    bundleId: result.appBundleID,
                    name: result.appName,
                    windowTitle: result.windowTitle
                )
            ).toJSON()
        }
        capture.assetsJSON = TalkieObjectAssets(screenshots: [screenshot]).toJSON()

        do {
            try await TalkieObjectRepository().saveRecording(capture)
            await RecordingsViewModel.shared.loadRecordings()
            return savedURL
        } catch {
            Log(.ui).error("Console screenshot Library write failed: \(error.localizedDescription)")
            return nil
        }
    }
}

enum TerminalCopyStatus: Equatable {
    case copied
    case empty
}

struct ConsoleTerminalCaptureControls: View {
    let controller: ConsoleTerminalCaptureController
    let session: ManagedAgentConsoleSession

    var body: some View {
        HStack(spacing: 8) {
            ConsolePopoutCopyButton(
                status: controller.copyStatus,
                action: { controller.copyTerminalOutput(from: session) }
            )

            ConsolePopoutScreenshotButton(
                isCapturing: controller.isCapturingScreenshot,
                error: controller.screenshotError,
                action: { controller.captureScreenshot(sendTo: session) }
            )
        }
    }
}

/// Bottom-center mic dock — mirrors the compose sheet's mic placement. The
/// mic is always present; a Submit button appears beside it once a dictation
/// transcript has been typed into the input line and disappears on send.
struct ConsoleTerminalDictationDock: View {
    let controller: ConsoleTerminalCaptureController
    let session: ManagedAgentConsoleSession

    private var isRecording: Bool {
        controller.dictation.isRecording && controller.dictation.activePurpose == .terminalDictation
    }

    private var isStarting: Bool {
        controller.dictation.isPreparing && controller.dictation.activePurpose == .terminalDictation
    }

    private var isTranscribing: Bool {
        controller.dictation.isTranscribing && controller.dictation.activePurpose == .terminalDictation
    }

    private var showsSubmit: Bool {
        controller.hasPendingDictation && !isStarting && !isRecording && !isTranscribing
    }

    var body: some View {
        HStack(spacing: 10) {
            ConsoleTerminalMicButton(
                isStarting: isStarting,
                isRecording: isRecording,
                isTranscribing: isTranscribing,
                error: controller.dictationError,
                action: { controller.toggleDictation(sendTo: session) }
            )

            if showsSubmit {
                ConsoleTerminalSubmitButton(
                    action: { controller.submitPendingDictation(to: session) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showsSubmit)
        .animation(.easeInOut(duration: 0.18), value: isStarting)
        .animation(.easeInOut(duration: 0.18), value: isRecording)
        .animation(.easeInOut(duration: 0.18), value: isTranscribing)
    }
}

private struct ConsoleTerminalMicButton: View {
    let isStarting: Bool
    let isRecording: Bool
    let isTranscribing: Bool
    let error: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(backgroundStyle)
                    .overlay(
                        Circle().strokeBorder(borderStyle, lineWidth: 1)
                    )
                    .frame(width: 46, height: 46)

                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(foregroundStyle)
                    .symbolEffect(.pulse, options: .repeating, isActive: isStarting || isRecording || isTranscribing)
            }
            .shadow(color: shadowColor, radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var iconName: String {
        if isStarting { return "mic.badge.plus" }
        if isTranscribing { return "waveform" }
        return isRecording ? "stop.fill" : "mic.fill"
    }

    private var helpText: String {
        if let error { return error }
        if isStarting { return "Starting terminal dictation" }
        if isTranscribing { return "Transcribing terminal dictation" }
        if isRecording { return "Stop and insert dictation" }
        return "Dictate into terminal"
    }

    private var foregroundStyle: Color {
        if error != nil { return .orange }
        if isRecording { return .white }
        if isStarting || isTranscribing { return Theme.current.accent }
        return isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary
    }

    private var backgroundStyle: Color {
        if error != nil { return .orange.opacity(0.18) }
        if isRecording { return .red.opacity(0.9) }
        if isStarting || isTranscribing { return Theme.current.accent.opacity(0.16) }
        return isHovered ? Theme.current.surfaceHover : Theme.current.surface1.opacity(0.95)
    }

    private var borderStyle: Color {
        if error != nil { return .orange.opacity(0.35) }
        if isRecording { return .white.opacity(0.28) }
        if isStarting || isTranscribing { return Theme.current.accent.opacity(0.35) }
        return Theme.current.border.opacity(0.78)
    }

    private var shadowColor: Color {
        if isRecording { return .red.opacity(0.28) }
        return .black.opacity(0.28)
    }
}

private struct ConsoleTerminalSubmitButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text("Submit")
                    .font(.geist(size: 13, weight: .semibold))

                Image(systemName: "return")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.current.accent.opacity(isHovered ? 1 : 0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Theme.current.accent.opacity(0.32), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Send dictated text to the terminal")
    }
}

private struct ConsolePopoutCopyButton: View {
    let status: TerminalCopyStatus?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))

                if status != nil {
                    Text(label)
                        .font(.geistMono(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, status == nil ? 0 : 10)
            .frame(width: status == nil ? 28 : nil, height: 28)
            .frame(minHeight: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(borderStyle, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("c", modifiers: .command)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var iconName: String {
        switch status {
        case .copied:
            "checkmark"
        case .empty, .none:
            "doc.on.doc"
        }
    }

    private var label: String {
        switch status {
        case .copied:
            "COPIED"
        case .empty:
            "EMPTY"
        case nil:
            "COPY"
        }
    }

    private var helpText: String {
        switch status {
        case .copied:
            "Copied terminal output"
        case .empty:
            "No terminal output to copy"
        case nil:
            "Copy terminal output"
        }
    }

    private var foregroundStyle: Color {
        switch status {
        case .copied:
            .green
        case .empty:
            .orange
        case nil:
            isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary
        }
    }

    private var backgroundStyle: Color {
        switch status {
        case .copied:
            .green.opacity(0.16)
        case .empty:
            .orange.opacity(0.18)
        case nil:
            isHovered ? Theme.current.surfaceHover : Theme.current.surface1.opacity(0.9)
        }
    }

    private var borderStyle: Color {
        switch status {
        case .copied:
            .green.opacity(0.35)
        case .empty:
            .orange.opacity(0.35)
        case nil:
            Theme.current.border.opacity(0.78)
        }
    }
}

private struct ConsolePopoutSessionTab: Identifiable {
    let session: ManagedAgentConsoleSession
    let label: String
    var isPopoutOwned = false

    var id: UUID { session.id }
}

private struct ConsolePopoutTabStrip: View {
    let tabs: [ConsolePopoutSessionTab]
    let activeSessionID: UUID
    let select: (ConsolePopoutSessionTab) -> Void
    let addTab: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    ConsolePopoutTabButton(
                        tab: tab,
                        isSelected: tab.id == activeSessionID,
                        action: { select(tab) }
                    )
                }

                Button(action: addTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.current.foreground.opacity(0.045))
                        )
                }
                .buttonStyle(.plain)
                .help("New \(tabs.first?.session.profile.title ?? "terminal") tab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(height: 42)
        .background(Theme.current.surface1.opacity(0.72))
    }
}

private struct ConsolePopoutTabButton: View {
    let tab: ConsolePopoutSessionTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    ConsolePopoutSessionIcon(session: tab.session, isSelected: isSelected)
                        .frame(width: 16, height: 16)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                        .offset(x: 3, y: -2)
                }

                Text(tab.label)
                    .font(.geist(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        switch tab.session.status {
        case .launching:
            return .orange
        case .running:
            return .green
        case .exited(let code):
            return code == 0 ? Theme.current.foregroundMuted : .orange
        case .failed:
            return .red
        }
    }

    private var backgroundColor: Color {
        if isSelected { return Theme.current.surfaceHover }
        return isHovered ? Theme.current.foreground.opacity(0.055) : .clear
    }

    private var borderColor: Color {
        isSelected ? Theme.current.border.opacity(0.9) : .clear
    }

    private var helpText: String {
        "\(tab.label) - \(tab.session.statusLabel)"
    }
}

private struct ConsolePopoutSessionIcon: View {
    let session: ManagedAgentConsoleSession
    let isSelected: Bool

    var body: some View {
        if session.profile.harness == .claude, let claudeImage = NSImage(named: "ProviderLogos/Anthropic") {
            Image(nsImage: claudeImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: session.profile.symbolName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        }
    }
}

private struct ConsolePopoutScreenshotButton: View {
    let isCapturing: Bool
    let error: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isCapturing ? "camera.metering.center.weighted" : "camera.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: isCapturing)

                if isCapturing || error != nil {
                    Text(label)
                        .font(.geistMono(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, isCapturing || error != nil ? 10 : 0)
            .frame(width: isCapturing || error != nil ? nil : 28, height: 28)
            .frame(minHeight: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(borderStyle, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var label: String {
        if error != nil { return "SHOT" }
        return isCapturing ? "CAPTURING" : "SHOT"
    }

    private var helpText: String {
        if let error { return error }
        if isCapturing { return "Capturing screenshot" }
        return "Attach screenshot to terminal"
    }

    private var foregroundStyle: Color {
        if error != nil { return .orange }
        if isCapturing { return Theme.current.accent }
        return isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary
    }

    private var backgroundStyle: Color {
        if error != nil { return .orange.opacity(0.18) }
        if isCapturing { return Theme.current.accent.opacity(0.16) }
        return isHovered ? Theme.current.surfaceHover : Theme.current.surface1.opacity(0.9)
    }

    private var borderStyle: Color {
        if error != nil { return .orange.opacity(0.35) }
        if isCapturing { return Theme.current.accent.opacity(0.35) }
        return Theme.current.border.opacity(0.78)
    }
}
