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
    let dictation = EphemeralTranscriber.shared

    var dictationError: String?
    var isCapturingScreenshot = false
    var screenshotError: String?

    @ObservationIgnored private var dictationStartedAt: Date?
    @ObservationIgnored private var dictationBaselineScreenshotIDs: Set<UUID> = []
    @ObservationIgnored private var dictationBaselineClipIDs: Set<UUID> = []

    func toggleDictation(sendTo session: ManagedAgentConsoleSession) {
        dictationError = nil

        if dictation.isRecording && dictation.activePurpose == .terminalDictation {
            Task {
                do {
                    let transcript = try await dictation.stopAndTranscribe()
                    let prompt = terminalPrompt(
                        transcript: transcript,
                        screenshots: screenshotsCapturedDuringDictation(),
                        clips: clipsCapturedDuringDictation()
                    )
                    resetDictationContext()
                    guard !prompt.isEmpty else { return }
                    session.send(prompt)
                } catch {
                    resetDictationContext()
                    dictationError = error.localizedDescription
                }
            }
            return
        }

        do {
            dictationStartedAt = Date()
            dictationBaselineScreenshotIDs = Set(ScreenshotTray.shared.items.map(\.id))
            dictationBaselineClipIDs = Set(ClipTray.shared.items.map(\.id))
            try dictation.startCapture(purpose: .terminalDictation)
        } catch {
            resetDictationContext()
            dictationError = error.localizedDescription
        }
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
            case .screenshotRegion(let rect):
                await captureSelectedScreenshot(mode: .region, preselectedRegion: rect, sendTo: session)
            case .screenRecord(let mode):
                await ScreenRecordingController.shared.startRecording(mode: mode)
            case .toggleCamera:
                guard FeatureFlags.shared.enableCameraBubble else { return }
                CameraBubbleController.shared.toggle()
            case .saveSelection:
                await TrayViewer.saveLatestSelectionToNote()
            case .viewTray:
                TrayViewer.shared.show()
            case .pasteLastTray:
                pasteLatestScreenshot(sendTo: session)
            }
        }
    }

    private func pasteLatestScreenshot(sendTo session: ManagedAgentConsoleSession) {
        guard let item = ScreenshotTray.shared.items.max(by: { $0.capturedAt < $1.capturedAt }) else {
            screenshotError = "No screenshot in tray"
            return
        }

        guard !isTerminalDictationActive else { return }
        session.send(screenshotPrompt(for: item))
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

        guard let item = await ScreenshotTray.shared.addReturningItem(
            data: capture.data,
            width: capture.width,
            height: capture.height,
            mode: mode,
            windowTitle: capture.windowTitle,
            appName: capture.appName,
            displayName: capture.displayName,
            initialThumbnail: capture.previewImage
        ) else {
            screenshotError = "Could not save screenshot"
            return
        }

        ScreenshotPreviewPanel.shared.attachFileURL(item.tempURL, to: previewID)

        guard !isTerminalDictationActive else { return }
        session.send(screenshotPrompt(for: item))

        TrayActionService.shared.persistStandaloneScreenshotToLibrary(item)
    }

    private var isTerminalDictationActive: Bool {
        dictation.activePurpose == .terminalDictation && (dictation.isRecording || dictation.isTranscribing)
    }

    private func resetDictationContext() {
        dictationStartedAt = nil
        dictationBaselineScreenshotIDs = []
        dictationBaselineClipIDs = []
    }

    private func screenshotPrompt(for item: TrayScreenshot) -> String {
        "Use this screenshot: \(item.tempURL.path)"
    }

    private func terminalPrompt(transcript: String, screenshots: [TrayScreenshot], clips: [TrayClip]) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        if !screenshots.isEmpty {
            let screenshotLines = screenshots.map { "- \($0.tempURL.path)" }
            sections.append("""
            Use these screenshots:
            \(screenshotLines.joined(separator: "\n"))
            """)
        }

        if !clips.isEmpty {
            let clipLines = clips.map { clip in
                "- \(clip.tempURL.path) (\(clipDurationLabel(clip.durationMs)))"
            }
            sections.append("""
            Use these screen recordings:
            \(clipLines.joined(separator: "\n"))
            """)
        }

        guard !sections.isEmpty else { return text }
        guard !text.isEmpty else { return sections.joined(separator: "\n\n") }

        return ([text] + sections).joined(separator: "\n\n")
    }

    private func screenshotsCapturedDuringDictation() -> [TrayScreenshot] {
        let startedAt = dictationStartedAt ?? .distantFuture
        return ScreenshotTray.shared.items
            .filter { item in
                item.capturedAt >= startedAt && !dictationBaselineScreenshotIDs.contains(item.id)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func clipsCapturedDuringDictation() -> [TrayClip] {
        let startedAt = dictationStartedAt ?? .distantFuture
        return ClipTray.shared.items
            .filter { item in
                item.capturedAt >= startedAt && !dictationBaselineClipIDs.contains(item.id)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func clipDurationLabel(_ durationMs: Int) -> String {
        let totalSeconds = max(durationMs, 0) / 1000
        guard totalSeconds >= 60 else { return "\(totalSeconds)s" }
        return "\(totalSeconds / 60)m \(totalSeconds % 60)s"
    }
}

struct ConsoleTerminalCaptureControls: View {
    let controller: ConsoleTerminalCaptureController
    let session: ManagedAgentConsoleSession

    var body: some View {
        HStack(spacing: 8) {
            ConsolePopoutScreenshotButton(
                isCapturing: controller.isCapturingScreenshot,
                error: controller.screenshotError,
                action: { controller.captureScreenshot(sendTo: session) }
            )

            ConsolePopoutDictationButton(
                isRecording: controller.dictation.isRecording && controller.dictation.activePurpose == .terminalDictation,
                isTranscribing: controller.dictation.isTranscribing && controller.dictation.activePurpose == .terminalDictation,
                error: controller.dictationError,
                action: { controller.toggleDictation(sendTo: session) }
            )
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

private struct ConsolePopoutDictationButton: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let error: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: isRecording || isTranscribing)

                if isRecording || isTranscribing || error != nil {
                    Text(label)
                        .font(.geistMono(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, isRecording || isTranscribing || error != nil ? 10 : 0)
            .frame(width: isRecording || isTranscribing || error != nil ? nil : 28, height: 28)
            .frame(minHeight: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(borderStyle, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var iconName: String {
        if isTranscribing { return "waveform" }
        return isRecording ? "stop.fill" : "mic.fill"
    }

    private var label: String {
        if error != nil { return "MIC" }
        if isTranscribing { return "TRANSCRIBING" }
        if isRecording { return "STOP" }
        return "MIC"
    }

    private var helpText: String {
        if let error { return error }
        if isTranscribing { return "Transcribing terminal dictation" }
        if isRecording { return "Stop and insert dictation" }
        return "Dictate into terminal"
    }

    private var foregroundStyle: Color {
        if error != nil { return .orange }
        if isRecording { return .white }
        if isTranscribing { return Theme.current.accent }
        return isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary
    }

    private var backgroundStyle: Color {
        if error != nil { return .orange.opacity(0.18) }
        if isRecording { return .red.opacity(0.88) }
        if isTranscribing { return Theme.current.accent.opacity(0.16) }
        return isHovered ? Theme.current.surfaceHover : Theme.current.surface1.opacity(0.9)
    }

    private var borderStyle: Color {
        if error != nil { return .orange.opacity(0.35) }
        if isRecording { return .white.opacity(0.28) }
        if isTranscribing { return Theme.current.accent.opacity(0.35) }
        return Theme.current.border.opacity(0.78)
    }

    private var shadowColor: Color {
        if isRecording { return .red.opacity(0.22) }
        return .black.opacity(0.22)
    }
}
