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

@MainActor
final class AccessibilityInstallAssistant {
    static let shared = AccessibilityInstallAssistant()

    private var panel: NSPanel?

    private init() {}

    func present(target: AccessibilityInstallTarget) {
        openAccessibilitySettingsPane()

        let content = AccessibilityInstallAssistantView(
            target: target,
            onOpenSettings: { [weak self] in self?.openAccessibilitySettingsPane() },
            onRevealApp: { Self.reveal(target.appURL) },
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

    private func openAccessibilitySettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
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
    let onOpenSettings: () -> Void
    let onRevealApp: () -> Void
    let onClose: () -> Void

    @State private var isGranted = false

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: target.appURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "accessibility")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isGranted ? SemanticColor.success : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background((isGranted ? SemanticColor.success : Color.accentColor).opacity(0.14))
                    .clipShape(.rect(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add \(target.displayName) to Accessibility")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Drag this app into the Accessibility list, or toggle it if it is already listed.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Label(isGranted ? "Granted" : "Waiting", systemImage: isGranted ? "checkmark.circle.fill" : "arrow.down.app")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(isGranted ? SemanticColor.success : Theme.current.foregroundMuted)
            }

            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(spacing: Spacing.xs) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 52, height: 52)

                    Image(systemName: "hand.draw")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.accentColor)
                }
                .frame(width: 92, height: 92)
                .background(Theme.current.surface1)
                .overlay {
                    NativeAppFileDragSource(appURL: target.appURL, dragImage: appIcon)
                        .frame(width: 92, height: 92)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                .clipShape(.rect(cornerRadius: CornerRadius.sm))
                .help("Drag \(target.appURL.lastPathComponent) into the Accessibility list")

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
        .padding(Spacing.lg)
        .frame(width: 430)
        .background(Theme.current.surface)
        .task(id: target.id) {
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor
    private func refreshStatus() async {
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
    }
}

private struct NativeAppFileDragSource: NSViewRepresentable {
    let appURL: URL
    let dragImage: NSImage

    func makeNSView(context: Context) -> NativeAppFileDragSourceView {
        NativeAppFileDragSourceView(appURL: appURL, dragImage: dragImage)
    }

    func updateNSView(_ nsView: NativeAppFileDragSourceView, context: Context) {
        nsView.appURL = appURL
        nsView.dragImage = dragImage
    }
}

private final class NativeAppFileDragSourceView: NSView, NSDraggingSource {
    var appURL: URL {
        didSet {
            toolTip = "Drag \(appURL.lastPathComponent) into the Accessibility list"
        }
    }
    var dragImage: NSImage

    private var dragStartLocation: NSPoint?
    private let dragThreshold: CGFloat = 4
    private var isDragging = false

    init(appURL: URL, dragImage: NSImage) {
        self.appURL = appURL
        self.dragImage = dragImage
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

        let draggingItem = NSDraggingItem(pasteboardWriter: TalkieInternalDrag.pasteboardItem(for: appURL))
        let imageSize = NSSize(width: 64, height: 64)
        let imageFrame = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        draggingItem.setDraggingFrame(imageFrame, contents: dragImage)

        beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
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
    }
}
