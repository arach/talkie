//
//  AccessibilityInstallAssistant.swift
//  TalkieAgent
//
//  Guided Accessibility setup for the agent app bundle.
//

import AppKit
import ApplicationServices
import SwiftUI
import TalkieKit

@MainActor
final class AccessibilityInstallAssistant {
    static let shared = AccessibilityInstallAssistant()

    private var panel: NSPanel?

    private init() {}

    func present() {
        Self.promptForCurrentProcessAccessibilityIfNeeded()
        openAccessibilitySettingsPane()

        let appURL = Bundle.main.bundleURL
        let content = AccessibilityInstallAssistantView(
            appURL: appURL,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            onOpenSettings: { [weak self] in self?.openAccessibilitySettingsPane() },
            onRevealApp: { Self.reveal(appURL) },
            onClose: { [weak self] in self?.close() }
        )

        if let panel {
            panel.contentViewController = NSHostingController(rootView: content)
            position(panel)
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 286),
            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Accessibility Setup"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = NSHostingController(rootView: content)
        panel.setContentSize(NSSize(width: 430, height: 286))

        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private func close() {
        panel?.close()
        panel = nil
    }

    private static func promptForCurrentProcessAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func openAccessibilitySettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        if !NSWorkspace.shared.open(url) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url.absoluteString]
            try? process.run()
        }
    }

    private func position(_ panel: NSPanel) {
        let size = CGSize(width: max(panel.frame.width, 430), height: max(panel.frame.height, 235))

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }

        let bounds = screen.visibleFrame
        let x = bounds.midX - size.width / 2
        let y = bounds.midY - size.height / 2
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private static func reveal(_ appURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}

@MainActor
private struct AccessibilityInstallAssistantView: View {
    let appURL: URL
    let bundleIdentifier: String
    let onOpenSettings: () -> Void
    let onRevealApp: () -> Void
    let onClose: () -> Void

    @State private var isGranted = false
    @State private var isRechecking = false
    @State private var scheduledRefreshTask: Task<Void, Never>?

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: appURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "accessibility")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isGranted ? Color.green : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background((isGranted ? Color.green : Color.accentColor).opacity(0.14))
                    .clipShape(.rect(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add TalkieAgent to Accessibility")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TalkieTheme.textPrimary)

                    Text("Drag this app into the Accessibility list, or toggle it if it is already listed.")
                        .font(.system(size: 11))
                        .foregroundStyle(TalkieTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Label(statusText, systemImage: statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isGranted ? Color.green : TalkieTheme.textTertiary)
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 6) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 52, height: 52)

                    Image(systemName: "hand.draw")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 92, height: 92)
                .background(TalkieTheme.surfaceCard)
                .overlay {
                    NativeAppFileDragSource(
                        appURL: appURL,
                        dragImage: appIcon,
                        onDragCompleted: schedulePermissionRefresh
                    )
                        .frame(width: 92, height: 92)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                .clipShape(.rect(cornerRadius: 8))
                .help("Drag \(appURL.lastPathComponent) into the Accessibility list")

                VStack(alignment: .leading, spacing: 3) {
                    Text("TalkieAgent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TalkieTheme.textPrimary)

                    Text("Dictation agent")
                        .font(.system(size: 11))
                        .foregroundStyle(TalkieTheme.textTertiary)

                    Text(bundleIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(TalkieTheme.textSecondary)
                        .textSelection(.enabled)

                    Text(appURL.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(TalkieTheme.textTertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button("Open Accessibility", systemImage: "gearshape") {
                    onOpenSettings()
                }

                Button("Reveal App", systemImage: "folder") {
                    onRevealApp()
                }

                Spacer()

                Button(isGranted ? "Done" : "Close") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(width: 430)
        .background(TalkieTheme.surface)
        .task {
            while !Task.isCancelled {
                isGranted = AccessibilityCache.shared.preflight()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear {
            scheduledRefreshTask?.cancel()
        }
    }

    private var statusText: String {
        if isGranted { return "Granted" }
        if isRechecking { return "Checking" }
        return "Waiting"
    }

    private var statusIcon: String {
        if isGranted { return "checkmark.circle.fill" }
        if isRechecking { return "arrow.clockwise" }
        return "arrow.down.app"
    }

    private func schedulePermissionRefresh() {
        scheduledRefreshTask?.cancel()
        isRechecking = true

        scheduledRefreshTask = Task { @MainActor in
            let delays: [Duration] = [
                .milliseconds(500),
                .seconds(1),
                .seconds(2),
                .seconds(4),
                .seconds(8)
            ]

            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }

                isGranted = AccessibilityCache.shared.preflight()
                PermissionManager.shared.checkAccessibility()

                if isGranted {
                    break
                }
            }

            isRechecking = false
        }
    }
}

private struct NativeAppFileDragSource: NSViewRepresentable {
    let appURL: URL
    let dragImage: NSImage
    let onDragCompleted: () -> Void

    func makeNSView(context: Context) -> NativeAppFileDragSourceView {
        NativeAppFileDragSourceView(
            appURL: appURL,
            dragImage: dragImage,
            onDragCompleted: onDragCompleted
        )
    }

    func updateNSView(_ nsView: NativeAppFileDragSourceView, context: Context) {
        nsView.appURL = appURL
        nsView.dragImage = dragImage
        nsView.onDragCompleted = onDragCompleted
    }
}

private final class NativeAppFileDragSourceView: NSView, NSDraggingSource {
    var appURL: URL {
        didSet {
            toolTip = "Drag \(appURL.lastPathComponent) into the Accessibility list"
        }
    }
    var dragImage: NSImage
    var onDragCompleted: () -> Void

    private var dragStartLocation: NSPoint?
    private let dragThreshold: CGFloat = 4
    private var isDragging = false

    init(appURL: URL, dragImage: NSImage, onDragCompleted: @escaping () -> Void) {
        self.appURL = appURL
        self.dragImage = dragImage
        self.onDragCompleted = onDragCompleted
        super.init(frame: .zero)
        toolTip = "Drag \(appURL.lastPathComponent) into the Accessibility list"
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let startLocation = dragStartLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance >= dragThreshold else { return }

        isDragging = true
        dragStartLocation = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let imageSize = NSSize(width: 64, height: 64)
        let imageFrame = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        draggingItem.setDraggingFrame(imageFrame, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        isDragging = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        dragStartLocation = nil
        onDragCompleted()
    }
}
