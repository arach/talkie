//
//  AccessibilityInstallAssistant.swift
//  Talkie macOS
//
//  Codex-style helper for guiding users through macOS Accessibility setup.
//

import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics
import TalkieKit

enum PermissionKind: String {
    case accessibility
    case screenRecording

    var displayName: String {
        switch self {
        case .accessibility:   return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    var icon: String {
        switch self {
        case .accessibility:   return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }

    var settingsPaneURL: URL? {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    /// Whether granting this permission requires the app to be quit and relaunched.
    var requiresRelaunch: Bool {
        switch self {
        case .accessibility:   return false
        case .screenRecording: return true
        }
    }
}

enum AccessibilityInstallTarget: String, Identifiable {
    case talkie
    case agent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .talkie: return "Talkie"
        case .agent: return "TalkieAgent"
        }
    }

    var subtitle: String {
        switch self {
        case .talkie: return "Main app"
        case .agent: return "Dictation agent"
        }
    }

    @MainActor
    var bundleIdentifier: String {
        switch self {
        case .talkie:
            return TalkieEnvironment.current.talkieBundleId
        case .agent:
            return ServiceManager.shared.effectiveHelperEnvironment.bundleId(for: .agent)
        }
    }

    @MainActor
    var appURL: URL {
        switch self {
        case .talkie:
            return Bundle.main.bundleURL
        case .agent:
            let env = ServiceManager.shared.effectiveHelperEnvironment
            let stableURL = TalkieHelper.agent.userInstalledAppURL(for: env)
            if FileManager.default.fileExists(atPath: stableURL.path) {
                return stableURL
            }

            if let path = ServiceManager.shared.live.bundlePath,
               let appURL = Self.appBundleURL(containing: URL(fileURLWithPath: path)) {
                return appURL
            }

            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: env.bundleId(for: .agent)) {
                return appURL
            }

            return stableURL
        }
    }

    private static func appBundleURL(containing url: URL) -> URL? {
        var candidate = url

        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }
}

/// Utility-panel variant that can become key.
/// AppKit drag sessions can be silently swallowed from panels that refuse key status.
private final class AccessibilityInstallAssistantPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AccessibilityInstallAssistant {
    static let shared = AccessibilityInstallAssistant()

    private var panel: NSPanel?

    private init() {}

    func present(target: AccessibilityInstallTarget, permission: PermissionKind = .accessibility) {
        if target == .talkie, permission == .accessibility {
            Self.promptForCurrentProcessAccessibilityIfNeeded()
        }

        openSettingsPane(for: permission)

        let content = AccessibilityInstallAssistantView(
            target: target,
            permission: permission,
            onOpenSettings: { [weak self] in self?.openSettingsPane(for: permission) },
            onRevealApp: { Self.reveal(target.appURL) },
            onRelaunch: { Self.quitAndRelaunch() },
            onClose: { [weak self] in self?.close() }
        )

        if let panel {
            panel.contentViewController = NSHostingController(rootView: content)
            position(panel)
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }

        let panel = AccessibilityInstallAssistantPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 286),
            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(permission.displayName) Setup"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = NSHostingController(rootView: content)
        panel.setContentSize(NSSize(width: 430, height: 286))

        self.panel = panel
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
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

    private func openSettingsPane(for permission: PermissionKind) {
        guard let url = permission.settingsPaneURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Quit & relaunch — used after Screen Recording is toggled on, since macOS
    /// requires a relaunch for the permission to take effect.
    private static func quitAndRelaunch() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [
            "-c",
            "/bin/sleep 1; /usr/bin/open -n \"\(appURL.path)\""
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func position(_ panel: NSPanel) {
        let size = CGSize(
            width: max(panel.frame.width, 430),
            height: max(panel.frame.height, 235)
        )

        let anchor = Self.systemSettingsWindowBounds()
            ?? Self.largestCurrentAppWindowBounds(excluding: panel)

        guard let anchor else {
            positionOnMainScreen(panel, size: size)
            return
        }

        let displayBounds = Self.displayBounds(containing: anchor)
            ?? Self.displayBounds(containing: CGPoint(x: anchor.midX, y: anchor.midY))
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let centeredX = anchor.midX - size.width / 2
        let centeredY = anchor.midY - size.height / 2
        let x: CGFloat
        let y: CGFloat

        if anchor.maxY + gap + size.height <= displayBounds.maxY - margin {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = anchor.maxY + gap
        } else if anchor.minY - gap - size.height >= displayBounds.minY + margin {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = anchor.minY - gap - size.height
        } else if anchor.maxX + gap + size.width <= displayBounds.maxX - margin {
            x = anchor.maxX + gap
            y = clamp(centeredY, min: displayBounds.minY + margin, max: displayBounds.maxY - size.height - margin)
        } else if anchor.minX - gap - size.width >= displayBounds.minX + margin {
            x = anchor.minX - gap - size.width
            y = clamp(centeredY, min: displayBounds.minY + margin, max: displayBounds.maxY - size.height - margin)
        } else {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = displayBounds.maxY - size.height - margin
        }

        let topLeft = CGPoint(
            x: x,
            y: y
        )
        let origin = CGPoint(
            x: topLeft.x,
            y: displayBounds.maxY - (topLeft.y - displayBounds.minY) - size.height
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func positionOnMainScreen(_ panel: NSPanel, size: CGSize) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - size.width - 32
        let y = screenFrame.maxY - size.height - 72
        panel.setFrame(NSRect(x: max(screenFrame.minX + 16, x), y: max(screenFrame.minY + 16, y), width: size.width, height: size.height), display: true)
    }

    private static func systemSettingsWindowBounds() -> CGRect? {
        visibleWindowBounds {
            ($0[kCGWindowOwnerName as String] as? String) == "System Settings"
        }
    }

    private static func largestCurrentAppWindowBounds(excluding panel: NSPanel) -> CGRect? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return visibleWindowBounds {
            guard let ownerPID = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
                  ownerPID == currentPID else { return false }
            guard let bounds = windowBounds(from: $0), bounds.width > panel.frame.width + 40 else { return false }
            return true
        }
    }

    private static func visibleWindowBounds(where matches: (NSDictionary) -> Bool) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [NSDictionary] else {
            return nil
        }

        return windows
            .filter { matches($0) }
            .compactMap(windowBounds(from:))
            .filter { $0.width > 100 && $0.height > 100 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func windowBounds(from info: NSDictionary) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private static func displayBounds(containing rect: CGRect) -> CGRect? {
        displayBounds(containing: CGPoint(x: rect.midX, y: rect.midY))
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        return displays
            .map(CGDisplayBounds)
            .first { $0.contains(point) }
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(value, maximum))
    }

    private static func reveal(_ appURL: URL) {
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }
    }
}

@MainActor
private struct AccessibilityInstallAssistantView: View {
    let target: AccessibilityInstallTarget
    let permission: PermissionKind
    let onOpenSettings: () -> Void
    let onRevealApp: () -> Void
    let onRelaunch: () -> Void
    let onClose: () -> Void

    @State private var isGranted = false
    @State private var isRechecking = false
    @State private var scheduledRefreshTask: Task<Void, Never>?

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: target.appURL.path)
    }

    private var supportsDragToAdd: Bool {
        permission == .accessibility
    }

    private var headline: String {
        switch permission {
        case .accessibility:
            return "Add \(target.displayName) to Accessibility"
        case .screenRecording:
            return "Enable Screen Recording for \(target.displayName)"
        }
    }

    private var hint: String {
        switch permission {
        case .accessibility:
            return "Drag this app into the Accessibility list, or toggle it if it is already listed."
        case .screenRecording:
            return "Toggle \(target.displayName) on in Screen Recording, then click Quit & Relaunch — macOS requires a relaunch for this permission to take effect."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: permission.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isGranted ? SemanticColor.success : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background((isGranted ? SemanticColor.success : Color.accentColor).opacity(0.14))
                    .clipShape(.rect(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)

                    Text(hint)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Label(statusText, systemImage: statusIcon)
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(isGranted ? SemanticColor.success : Theme.current.foregroundMuted)
            }

            HStack(alignment: .center, spacing: Spacing.md) {
                dragCard

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(target.displayName)
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)

                    Text(target.subtitle)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(target.bundleIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .textSelection(.enabled)

                    Text(target.appURL.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.sm) {
                Button("Open \(permission.displayName)", systemImage: "gearshape") {
                    onOpenSettings()
                }

                Button("Reveal App", systemImage: "folder") {
                    onRevealApp()
                }

                Spacer()

                if permission.requiresRelaunch {
                    Button("Quit & Relaunch", systemImage: "arrow.clockwise.circle") {
                        onRelaunch()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Quit Talkie and reopen it so the new permission takes effect.")
                }

                Button(isGranted ? "Done" : "Close") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.lg)
        .frame(width: 430)
        .background(Theme.current.surface)
        .task(id: "\(target.id)-\(permission.rawValue)") {
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear {
            scheduledRefreshTask?.cancel()
        }
    }

    /// Drag card — SwiftUI VStack (icon + hand-draw glyph) with `.onDrag`
    /// attached. Uses the canonical Talkie pattern (matches
    /// `TrayDrawer.swift:46-48`, `TrayViewer.swift`): an `NSItemProvider`
    /// returned from `.onDrag` is the SwiftUI-native drag mechanism and
    /// works inside utility panels without any custom NSView,
    /// NSDraggingSource subclass, or first-responder dance.
    @ViewBuilder
    private var dragCard: some View {
        VStack(spacing: Spacing.xs) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 52, height: 52)

            if supportsDragToAdd {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.accentColor)
            }
        }
        .frame(width: 92, height: 92)
        .background(Theme.current.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .allowsHitTesting(false)
        )
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .help(supportsDragToAdd
              ? "Drag \(target.appURL.lastPathComponent) into the Accessibility list"
              : target.appURL.lastPathComponent)
        .onDrag {
            let provider = NSItemProvider(contentsOf: target.appURL) ?? NSItemProvider()
            provider.suggestedName = target.appURL.lastPathComponent
            schedulePermissionRefresh()
            return TalkieInternalDrag.mark(provider)
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

                await refreshStatus()

                if target == .talkie {
                    PermissionsManager.shared.checkAccessibilityPermission()
                }

                if isGranted {
                    break
                }
            }

            isRechecking = false
        }
    }

    @MainActor
    private func refreshStatus() async {
        switch permission {
        case .accessibility:
            switch target {
            case .talkie:
                isGranted = AXIsProcessTrusted()
            case .agent:
                if let permissions = await ServiceManager.shared.live.refreshPermissionsNow() {
                    isGranted = permissions.accessibility
                } else {
                    isGranted = ServiceManager.shared.live.hasAccessibilityPermission == true
                }
            }
        case .screenRecording:
            // Screen Recording status is per-process; only meaningful for .talkie target.
            isGranted = CGPreflightScreenCaptureAccess()
        }
    }
}

private struct NativeAppFileDragCard: NSViewRepresentable {
    let appURL: URL
    let appIcon: NSImage
    let showsDragGlyph: Bool
    let isDragEnabled: Bool
    let onDragCompleted: () -> Void

    func makeNSView(context: Context) -> NativeAppFileDragCardView {
        NativeAppFileDragCardView(
            appURL: appURL,
            appIcon: appIcon,
            showsDragGlyph: showsDragGlyph,
            isDragEnabled: isDragEnabled,
            onDragCompleted: onDragCompleted
        )
    }

    func updateNSView(_ nsView: NativeAppFileDragCardView, context: Context) {
        nsView.appURL = appURL
        nsView.appIcon = appIcon
        nsView.showsDragGlyph = showsDragGlyph
        nsView.isDragEnabled = isDragEnabled
        nsView.onDragCompleted = onDragCompleted
    }
}

private final class NativeAppFileDragCardView: NSView, NSDraggingSource {
    var appURL: URL {
        didSet {
            updateToolTip()
            needsDisplay = true
        }
    }
    var appIcon: NSImage {
        didSet {
            needsDisplay = true
        }
    }
    var showsDragGlyph: Bool {
        didSet {
            needsDisplay = true
        }
    }
    var isDragEnabled: Bool {
        didSet {
            updateToolTip()
            discardCursorRects()
            needsDisplay = true
        }
    }
    var onDragCompleted: () -> Void

    private var dragStartLocation: NSPoint?
    private let dragThreshold: CGFloat = 4
    private var isDragging = false

    init(
        appURL: URL,
        appIcon: NSImage,
        showsDragGlyph: Bool,
        isDragEnabled: Bool,
        onDragCompleted: @escaping () -> Void
    ) {
        self.appURL = appURL
        self.appIcon = appIcon
        self.showsDragGlyph = showsDragGlyph
        self.isDragEnabled = isDragEnabled
        self.onDragCompleted = onDragCompleted
        super.init(frame: .zero)
        updateToolTip()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let cardRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cornerRadius = CornerRadius.sm
        let cardPath = NSBezierPath(
            roundedRect: cardRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        NSColor(Theme.current.surface1).setFill()
        cardPath.fill()

        NSGraphicsContext.saveGraphicsState()
        cardPath.addClip()

        let iconSize = NSSize(width: 52, height: 52)
        let iconY = showsDragGlyph ? CGFloat(14) : (bounds.height - iconSize.height) / 2
        let iconRect = NSRect(
            x: (bounds.width - iconSize.width) / 2,
            y: iconY,
            width: iconSize.width,
            height: iconSize.height
        )
        appIcon.draw(in: iconRect)

        if showsDragGlyph,
           let symbol = NSImage(
            systemSymbolName: "hand.draw",
            accessibilityDescription: "Drag"
           )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
           ) {
            let symbolSize = NSSize(width: 16, height: 16)
            let symbolRect = NSRect(
                x: (bounds.width - symbolSize.width) / 2,
                y: iconRect.maxY + 4,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.isTemplate = true
            NSColor(Color.accentColor).set()
            symbol.draw(in: symbolRect)
        }

        NSGraphicsContext.restoreGraphicsState()

        let borderPath = NSBezierPath(
            roundedRect: cardRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        var dash: [CGFloat] = [5, 4]
        borderPath.setLineDash(&dash, count: dash.count, phase: 0)
        borderPath.lineWidth = 1
        NSColor(Color.accentColor).withAlphaComponent(0.35).setStroke()
        borderPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isDragEnabled else { return }
        NSLog("🟢 AccessibilityInstallAssistant drag mouseDown at \(event.locationInWindow)")
        window?.makeKey()
        let didBecomeFirstResponder = window?.makeFirstResponder(self) ?? false
        NSLog("🟢 AccessibilityInstallAssistant drag firstResponder=\(didBecomeFirstResponder) windowKey=\(window?.isKeyWindow ?? false)")
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragEnabled else { return }
        NSLog("🟢 AccessibilityInstallAssistant drag mouseDragged isDragging=\(isDragging) hasStart=\(dragStartLocation != nil)")
        guard !isDragging, let startLocation = dragStartLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        let distance = sqrt(dx * dx + dy * dy)

        NSLog("🟢 AccessibilityInstallAssistant drag distance=\(distance) threshold=\(dragThreshold)")
        guard distance >= dragThreshold else { return }
        NSLog("🟢 AccessibilityInstallAssistant beginDraggingSession")

        startDrag(with: event)
    }

    private func startDrag(with event: NSEvent) {
        let pasteboardItem = TalkieInternalDrag.pasteboardItem(for: appURL)
        NSLog("🟢 AccessibilityInstallAssistant drag appURL=\(appURL.path) exists=\(FileManager.default.fileExists(atPath: appURL.path)) types=\(pasteboardItem.types.map(\.rawValue))")

        isDragging = true
        dragStartLocation = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let imageSize = NSSize(width: 64, height: 64)
        let imageFrame = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        draggingItem.setDraggingFrame(imageFrame, contents: appIcon)

        let session = beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        isDragging = false
    }

    override func resetCursorRects() {
        if isDragEnabled {
            addCursorRect(bounds, cursor: .openHand)
        }
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

    private func updateToolTip() {
        toolTip = isDragEnabled
            ? "Drag \(appURL.lastPathComponent) into the Accessibility list"
            : appURL.lastPathComponent
    }
}
