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

// MARK: - Capture Mode Tab

struct CaptureChordOptions: Equatable {
    var showCameraOption: Bool = false
    var showTrayOption: Bool = false
    var showSelectionOption: Bool = false
    var showMarkupOption: Bool = false

    static let captureOnly = CaptureChordOptions()
    static let captureWithPeripherals = CaptureChordOptions(
        showTrayOption: true,
        showSelectionOption: true,
        showMarkupOption: true
    )
}

enum CaptureDestinationSettings {
    static let markupEnabled = "capture.markupDestinationEnabled"
}

// MARK: - Result Type

enum CaptureBarResult {
    case screenshot(CaptureMode)     // A/S/D in screenshot mode
    case screenshotMarkup(CaptureMode) // A/S/D in screenshot mode, then open Agent quick markup
    case screenshotRegion(CGRect)    // Region was selected by the armed overlay
    case screenshotMarkupRegion(CGRect) // Region selected by armed overlay, then open Agent quick markup
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
        case .screenshotMarkup, .screenshotMarkupRegion: return false
        case .viewTray: return false
        }
    }
}

// MARK: - Observable State

@MainActor
@Observable
final class CaptureBarState {
    var mode: CaptureBarMode = .screenshot {
        didSet {
            guard mode != oldValue else { return }
            onModeChanged?(mode)
        }
    }
    var showCameraOption: Bool = false
    var showTrayOption: Bool = false
    var showSelectionOption: Bool = false
    var showMarkupOption: Bool = false
    var trayCount: Int = 0
    /// Destination toggle for one-off share captures. When enabled in
    /// screenshot mode, A/S/D still pick the target but the captured PNG opens
    /// directly in Agent's quick markup surface instead of the tray preview.
    var markupDestinationEnabled: Bool = sharedBool(forKey: CaptureDestinationSettings.markupEnabled) {
        didSet {
            Self.setSharedBool(
                markupDestinationEnabled,
                forKey: CaptureDestinationSettings.markupEnabled
            )
        }
    }
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
    var onModeChanged: ((CaptureBarMode) -> Void)?

    var screenRecordingIncludesSystemAudio: Bool = sharedBool(
        forKey: AgentSettingsKey.screenRecordingIncludesSystemAudio
    ) {
        didSet {
            Self.setSharedBool(
                screenRecordingIncludesSystemAudio,
                forKey: AgentSettingsKey.screenRecordingIncludesSystemAudio
            )
        }
    }

    var screenRecordingIncludesMicrophone: Bool = sharedBool(
        forKey: AgentSettingsKey.screenRecordingIncludesMicrophone
    ) {
        didSet {
            Self.setSharedBool(
                screenRecordingIncludesMicrophone,
                forKey: AgentSettingsKey.screenRecordingIncludesMicrophone
            )
        }
    }

    var screenRecordingShowsCameraBubble: Bool = sharedBool(
        forKey: AgentSettingsKey.screenRecordingShowsCameraBubble
    ) {
        didSet {
            Self.setSharedBool(
                screenRecordingShowsCameraBubble,
                forKey: AgentSettingsKey.screenRecordingShowsCameraBubble
            )
        }
    }

    func reloadMarkupDestination() {
        markupDestinationEnabled = Self.sharedBool(forKey: CaptureDestinationSettings.markupEnabled)
    }

    private static func sharedBool(forKey key: String) -> Bool {
        TalkieSharedSettings.object(forKey: key) as? Bool ?? false
    }

    private static func setSharedBool(_ value: Bool, forKey key: String) {
        TalkieSharedSettings.set(value, forKey: key)
    }
}

// MARK: - Panel

@MainActor
final class CaptureBarPanel {

    private var panel: NSPanel?
    let state = CaptureBarState()

    func show(
        mode: CaptureBarMode,
        showCameraOption: Bool,
        showTrayOption: Bool,
        showSelectionOption: Bool,
        showMarkupOption: Bool,
        trayCount: Int
    ) {
        dismiss()

        state.mode = mode
        state.showCameraOption = showCameraOption
        state.showTrayOption = showTrayOption
        state.showSelectionOption = showSelectionOption
        state.showMarkupOption = showMarkupOption
        if showMarkupOption {
            state.reloadMarkupDestination()
        }
        state.trayCount = trayCount

        let hostingView = NSHostingView(rootView: CaptureBarView(state: state))
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

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
        p.hasShadow = false
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

    // MARK: - Extras (M + C + N + V + T)

    private var extras: some View {
        HStack(spacing: 12) {
            if state.showMarkupOption && !isVideo {
                HStack(spacing: 3) {
                    Text("M")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(state.markupDestinationEnabled ? Color.orange.opacity(0.18) : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.orange.opacity(0.36), lineWidth: 0.5)
                                )
                        )
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.system(size: 9))
                        .foregroundColor(.orange.opacity(state.markupDestinationEnabled ? 0.9 : 0.6))
                }
            }

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
