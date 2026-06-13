//
//  CaptureBarPanel.swift
//  Talkie
//
//  Unified capture bar showing Screenshot/Video mode tabs with [A]rea [S]creen [D]ow options.
//  Hyper+S opens in Screenshot mode, Hyper+R opens in Video mode. Tab toggles between modes.
//
//  Follows the Talkie design language:
//  - LiquidGlass tab selector with matchedGeometryEffect
//  - Gradient overlay + gradient border (GlassCard pattern)
//  - Pulsing red dot in video mode (ScreenRecordingPill pattern)
//  - Fade in/out panel transitions
//

import AppKit
import SwiftUI
import TalkieKit

// MARK: - Capture Chord Controller Protocol

@MainActor
protocol CaptureChordController {
    func beginChord(initialMode: CaptureBarMode, options: CaptureChordOptions) async -> CaptureBarResult?
}

extension CaptureChordController {
    func beginChord(initialMode: CaptureBarMode) async -> CaptureBarResult? {
        await beginChord(initialMode: initialMode, options: .captureOnly)
    }
}

extension NSEvent {
    func isOpeningCaptureChordKey(initialMode: CaptureBarMode) -> Bool {
        let expectedKey = switch initialMode {
        case .screenshot: "s"
        case .video: "r"
        }
        guard charactersIgnoringModifiers?.lowercased() == expectedKey else { return false }

        let hyperModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let activeModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return activeModifiers.isSuperset(of: hyperModifiers)
    }
}

// MARK: - Capture HUD Position

enum CaptureHUDPosition: String, CaseIterable, Codable {
    /// Anchor the HUD near the mouse cursor (default — smart edge flip).
    case cursor
    /// Pin the HUD to the top-center preview lane, near the tray.
    case fixed

    var label: String {
        switch self {
        case .cursor: return "Near cursor"
        case .fixed:  return "Top preview"
        }
    }

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .fixed:  return "rectangle.tophalf.inset.filled"
        }
    }
}

// MARK: - Screenshot Launcher

enum ScreenshotLauncher: String, CaseIterable, Codable {
    case builtin
    case screenshotX = "screenshotx"
    case cleanshotX = "cleanshotx"
    case system

    var label: String {
        switch self {
        case .builtin: return "Built-in"
        case .screenshotX: return "ScreenshotX"
        case .cleanshotX: return "CleanShot X"
        case .system: return "System Preview"
        }
    }

    var detail: String? {
        switch self {
        case .builtin: return "Capture to tray, no external editor"
        case .screenshotX: return "Annotate & markup"
        case .cleanshotX: return "Annotate, blur, & share"
        case .system: return "macOS Preview editor"
        }
    }

    var bundleID: String? {
        switch self {
        case .builtin: return nil
        case .screenshotX: return "cc.simonbs.ScreenshotX"
        case .cleanshotX: return "pl.maketheweb.cleanshotx"
        case .system: return nil
        }
    }

    var isInstalled: Bool {
        switch self {
        case .builtin, .system: return true
        default:
            // Primary: bundle ID lookup via Launch Services
            if let bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                return true
            }
            // Fallback: check common install paths by app name
            if let appName {
                let paths = [
                    "/Applications/\(appName).app",
                    NSHomeDirectory() + "/Applications/\(appName).app",
                    "/Applications/Setapp/\(appName).app"
                ]
                return paths.contains { FileManager.default.fileExists(atPath: $0) }
            }
            return false
        }
    }

    /// App name for filesystem fallback detection.
    private var appName: String? {
        switch self {
        case .screenshotX: return "ScreenshotX"
        case .cleanshotX: return "CleanShot X"
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .builtin: return "camera.shutter.button"
        case .screenshotX: return "rectangle.dashed.badge.record"
        case .cleanshotX: return "sparkle.magnifyingglass"
        case .system: return "command.square"
        }
    }

    /// Resolved app URL using bundle ID or filesystem fallback.
    var resolvedAppURL: URL? {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        guard let appName else { return nil }
        let paths = [
            "/Applications/\(appName).app",
            NSHomeDirectory() + "/Applications/\(appName).app",
            "/Applications/Setapp/\(appName).app"
        ]
        return paths.compactMap { path in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }.first
    }

    /// Open a file in this editor app.
    @MainActor
    func openFile(_ fileURL: URL) async {
        guard let appURL = resolvedAppURL else {
            Log(.system).warning("\(label) not found for edit")
            return
        }
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
            Log(.system).info("Opened \(fileURL.lastPathComponent) in \(label)")
        } catch {
            Log(.system).error("Failed to open in \(label): \(error)")
        }
    }

    /// Whether this launcher can be used as an edit tool (external editors only).
    var isEditTool: Bool {
        switch self {
        case .screenshotX, .cleanshotX: return true
        case .builtin, .system: return false
        }
    }
}

// MARK: - Capture Mode Tab

enum CaptureBarMode: String, CaseIterable {
    case screenshot
    case video
}

struct CaptureChordOptions: Equatable {
    var showCameraOption: Bool = false
    var showTrayOption: Bool = false
    var showSelectionOption: Bool = false

    static let captureOnly = CaptureChordOptions()
    static let captureWithPeripherals = CaptureChordOptions(
        showTrayOption: true,
        showSelectionOption: true
    )
}

// MARK: - Result Type

enum CaptureBarResult {
    case screenshot(CaptureMode)     // A/S/D in screenshot mode
    case screenshotRegion(CGRect)    // Region was selected by the armed overlay
    case screenRecord(CaptureMode)   // A/S/D in video mode
    case toggleCamera                // C key
    case saveSelection               // N key
    case viewTray                    // T key
    case pasteLastTray               // V key

    /// Whether the action should keep the previous app in focus.
    /// Screenshot/record/camera are background ops; tray viewer needs Talkie foreground.
    var isBackground: Bool {
        switch self {
        case .screenshot, .screenshotRegion, .screenRecord, .toggleCamera, .pasteLastTray, .saveSelection: return true
        case .viewTray: return false
        }
    }
}

// MARK: - Observable State

@MainActor
@Observable
final class CaptureBarState {
    var mode: CaptureBarMode = .screenshot
    var showCameraOption: Bool = false
    var showTrayOption: Bool = false
    var showSelectionOption: Bool = false
    var trayCount: Int = 0
    /// Currently armed capture mode. Region is the preselected default
    /// when the HUD opens — the picker visual highlights this cell, and
    /// ↵ commits it. A/S/D keep their existing single-press fire
    /// behavior so muscle memory holds; the preselection is for users
    /// who want to see what's default and confirm with ↵.
    var selectedCaptureMode: CaptureMode = .region
    /// Click callback from the SwiftUI view.
    /// `nil` result = interaction only (e.g. mode toggle), resets timeout but doesn't dismiss.
    var onAction: ((CaptureBarResult?) -> Void)?
    /// Optional commit callback for HUDs that expose an explicit Start/Capture button.
    /// Controllers own the exact commit behavior because screenshot region capture can
    /// have an armed overlay that should stay alive until the user picks a region.
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
}

// MARK: - Panel

@MainActor
final class CaptureBarPanel {

    private var panel: NSPanel?
    let state = CaptureBarState()

    func show(mode: CaptureBarMode, showCameraOption: Bool, showTrayOption: Bool, showSelectionOption: Bool, trayCount: Int) {
        dismiss()

        state.mode = mode
        state.showCameraOption = showCameraOption
        state.showTrayOption = showTrayOption
        state.showSelectionOption = showSelectionOption
        state.trayCount = trayCount

        let hostingView = NSHostingView(rootView: CaptureBarView(state: state))
        hostingView.layer?.isOpaque = false

        // Size to fit content instead of a fixed frame
        let intrinsic = hostingView.fittingSize
        let width = ceil(intrinsic.width) + 8   // small breathing room
        let height = ceil(intrinsic.height) + 8

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .screenSaver + 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.sharingType = .none
        p.hidesOnDeactivate = false  // Stay visible even when Talkie isn't active app
        p.canHide = false

        // Position bottom-center of the screen under cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let x = screen.frame.midX - width / 2
        let y = screen.frame.minY + 80
        p.setFrameOrigin(NSPoint(x: x, y: y))

        // Fade in — show only the panel without activating Talkie or
        // bringing its main window forward
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        self.panel = p
    }

    func dismiss() {
        state.onAction = nil
        state.onStart = nil
        state.onCancel = nil

        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            p.contentView = nil
        })
    }

    func toggleMode() {
        state.mode = (state.mode == .screenshot) ? .video : .screenshot
    }
}

// MARK: - SwiftUI View

private struct CaptureBarView: View {
    @Bindable var state: CaptureBarState

    @Namespace private var tabAnimation

    private var isVideo: Bool { state.mode == .video }

    private var borderGradient: LinearGradient {
        if isVideo {
            return LinearGradient(
                colors: [Color.red.opacity(0.4), Color.red.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main bar
            HStack(spacing: 0) {
                // Mode tabs (LiquidGlass style)
                modeTabs
                    .padding(.trailing, 12)

                // Divider
                glassDivider

                // Capture options (A/S/D)
                captureOptions
                    .padding(.horizontal, 14)

                // Extras (C + W)
                glassDivider
                extras
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            ZStack {
                // Glass material base
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)

                // Subtle top-light gradient overlay (GlassCard pattern)
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.03),
                                Color.black.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Video mode: subtle red ambient glow
                if isVideo {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.04))
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderGradient, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.2), value: state.mode)
    }

    // MARK: - Mode Tabs (LiquidGlass pattern)

    private var modeTabs: some View {
        HStack(spacing: 2) {
            modeTab(.screenshot, icon: "camera.fill", label: "Screenshot")
            modeTab(.video, icon: "video.fill", label: "Video")
        }
        .padding(3)
        .background(
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        )
    }

    private func modeTab(_ mode: CaptureBarMode, icon: String, label: String) -> some View {
        let isActive = state.mode == mode
        let isVideoTab = mode == .video

        return HStack(spacing: 5) {
            if isVideoTab && isActive {
                // Pulsing red dot for active video mode
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .modifier(CaptureBarPulseModifier())
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
        }
        .foregroundColor(isActive ? .white : .white.opacity(0.45))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isActive {
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .matchedGeometryEffect(id: "captureTab", in: tabAnimation)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.mode)
    }

    // MARK: - Capture Options (A / S / D)

    private var captureOptions: some View {
        HStack(spacing: 16) {
            chordKey("A", label: "rea")
            chordKey("S", label: "creen")
            chordKey("D", label: "ow")
        }
    }

    // MARK: - Extras (C + N + V + T)

    private var extras: some View {
        HStack(spacing: 12) {
            if state.showCameraOption {
                // Camera toggle
                HStack(spacing: 3) {
                    Text("C")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
                        )
                    Image(systemName: "video.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange.opacity(0.6))
                }
            }

            if state.showSelectionOption {
                HStack(spacing: 3) {
                    Text("N")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.mint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.mint.opacity(0.3), lineWidth: 0.5)
                        )
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 9))
                        .foregroundColor(.mint.opacity(0.65))
                }
            }

            if state.showTrayOption {
                // Paste last tray item
                HStack(spacing: 3) {
                    Text("V")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5)
                        )
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9))
                        .foregroundColor(.green.opacity(0.6))
                }

                // Tray viewer
                HStack(spacing: 3) {
                    Text("T")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 0.5)
                        )
                    Text("\(state.trayCount)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.cyan.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Helpers

    private var glassDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.2), Color.white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 24)
    }

    private func chordKey(_ key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

// MARK: - Pulse Animation

private struct CaptureBarPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
