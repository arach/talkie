//
//  NotchAnimationInspector.swift
//  Talkie
//
//  Floating inspector for scrubbing the notch extension animation.
//

import AppKit
import SwiftUI
import TalkieKit

private let notchInspectorLog = Log(.ui)

private enum NotchExtensionWidthReference: String, CaseIterable, Identifiable {
    case core
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core:
            return "Core"
        case .full:
            return "Full Body"
        }
    }
}

private enum NotchRecordingExtensionPreview: String, CaseIterable, Identifiable {
    case live
    case collapsed
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .collapsed:
            return "Collapsed"
        case .expanded:
            return "Expanded"
        }
    }
}

@MainActor
final class NotchAnimationInspectorController: NSObject, NSWindowDelegate {
    static let shared = NotchAnimationInspectorController()

    private var panel: NSPanel?

    private override init() {
        super.init()
    }

    func showIfEnabled() {
        seedDefaultsIfNeeded()
        guard NotchSettings.shared.inspectorEnabled else { return }
        show()
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let content = NSHostingView(
            rootView: NotchAnimationInspectorView(
                onClose: { [weak self] in self?.dismiss() },
                onScreenshot: { metadataLines in
                    NotchComposer.shared.captureOverlaySnapshot(metadataLines: metadataLines)
                }
            )
        )

        let size = NSSize(width: 420, height: 640)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = content
        panel.title = "Notch Animator"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 200, y: 200, width: 1200, height: 800)
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 20,
            y: visibleFrame.maxY - size.height - 32
        )
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        notchInspectorLog.info("NotchAnimationInspector: panel shown")
    }

    func dismiss() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        notchInspectorLog.info("NotchAnimationInspector: panel hidden")
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    private func seedDefaultsIfNeeded() {
        // Defaults now managed by NotchSettings.shared
    }
}

private struct NotchAnimationInspectorView: View {
    let onClose: () -> Void
    let onScreenshot: (_ metadataLines: [String]) -> Void

    @Bindable private var ns = NotchSettings.shared

    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var showAdvancedMotion = false
    @State private var showIndicatorStyling = false
    @State private var showPlaybackTools = false

    private var recordingExtensionPreview: NotchRecordingExtensionPreview {
        get { NotchRecordingExtensionPreview(rawValue: ns.inspectorRecordingExtensionPreviewRaw) ?? .live }
        set { ns.inspectorRecordingExtensionPreviewRaw = newValue.rawValue }
    }

    private var extensionWidthReference: NotchExtensionWidthReference {
        get { NotchExtensionWidthReference(rawValue: ns.inspectorExtensionWidthReferenceRaw) ?? .full }
        set { ns.inspectorExtensionWidthReferenceRaw = newValue.rawValue }
    }

    private var shellStyle: NotchVirtualDisplayStyle {
        get { NotchVirtualDisplayStyle(rawValue: ns.shellStyleRaw) ?? .auto }
        set { ns.shellStyleRaw = newValue.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Notch Animator")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                    Button("Shot", systemImage: "camera") {
                        onScreenshot(screenshotMetadataLines)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Toggle("Enable Inspector", isOn: $ns.inspectorEnabled)
                Toggle("Scrub With Slider", isOn: $ns.inspectorScrubEnabled)

                Picker("Shell Style", selection: $ns.shellStyleRaw) {
                    ForEach(NotchVirtualDisplayStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text(shellStyle.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Applies to the external-shell mock and live external-display overlay.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                NotchAnimationMockPreview(
                    progress: ns.inspectorProgress,
                    barAttachStart: ns.inspectorBarAttachStart,
                    barAttachDuration: ns.inspectorBarAttachDuration,
                    expansionStart: ns.inspectorExpansionStart,
                    extensionWidthReferenceRaw: ns.inspectorExtensionWidthReferenceRaw,
                    extensionWidthMatch: ns.inspectorExtensionWidthMatch,
                    extensionWidthDelta: ns.inspectorExtensionWidthDelta,
                    extensionYOffset: ns.inspectorExtensionYOffset,
                    extensionDropDistance: ns.inspectorExtensionDropDistance
                )

                Text("Mock notch tracks Frame so you can tune attach/drop behavior before validating against the live notch.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                sliderRow(
                    "Frame",
                    value: $ns.inspectorProgress,
                    range: 0...1,
                    step: 0.001,
                    valueText: { value in
                        "\((value * 100).formatted(.number.precision(.fractionLength(1))))%"
                    }
                )

                Picker("Recording Extension", selection: $ns.inspectorRecordingExtensionPreviewRaw) {
                    ForEach(NotchRecordingExtensionPreview.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!ns.inspectorScrubEnabled)

                Text(ns.inspectorScrubEnabled
                    ? "Recording Extension mode applies while scrubbing."
                    : "Recording Extension mode is preview-only and inactive when Scrub is off.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)

                sliderRow(
                    "Attach Start Frame",
                    value: $ns.inspectorBarAttachStart,
                    range: 0...0.9,
                    step: 0.01,
                    valueText: { value in
                        "\((value * 100).formatted(.number.precision(.fractionLength(0))))%"
                    }
                )

                sliderRow(
                    "Expansion Start",
                    value: $ns.inspectorExpansionStart,
                    range: 0...0.95,
                    step: 0.01,
                    valueText: { value in
                        "\((value * 100).formatted(.number.precision(.fractionLength(0))))%"
                    }
                )

                sliderRow(
                    "Width Match",
                    value: $ns.inspectorExtensionWidthMatch,
                    range: 0.75...1.25,
                    step: 0.01,
                    valueText: { value in
                        "\((value * 100).formatted(.number.precision(.fractionLength(0))))%"
                    }
                )

                sliderRow(
                    "Extension Y Offset",
                    value: $ns.inspectorExtensionYOffset,
                    range: -40...40,
                    step: 0.5,
                    valueText: { value in
                        "\(value.formatted(.number.precision(.fractionLength(1)))) pt"
                    }
                )

                DisclosureGroup("Motion + Width (Advanced)", isExpanded: $showAdvancedMotion) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Width Reference", selection: $ns.inspectorExtensionWidthReferenceRaw) {
                            ForEach(NotchExtensionWidthReference.allCases) { reference in
                                Text(reference.title).tag(reference.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        sliderRow(
                            "Attach Duration",
                            value: $ns.inspectorBarAttachDuration,
                            range: 0.06...0.50,
                            step: 0.01,
                            valueText: { value in
                                "\((value * 100).formatted(.number.precision(.fractionLength(0))))%"
                            }
                        )

                        sliderRow(
                            "Width Fine Offset",
                            value: $ns.inspectorExtensionWidthDelta,
                            range: -120...240,
                            step: 1,
                            valueText: { value in
                                "\(value.formatted(.number.precision(.fractionLength(0)))) pt"
                            }
                        )

                        sliderRow(
                            "Reveal Travel",
                            value: $ns.inspectorExtensionDropDistance,
                            range: 0...24,
                            step: 0.5,
                            valueText: { value in
                                "\(value.formatted(.number.precision(.fractionLength(1)))) pt"
                            }
                        )

                        Text("Reveal Travel only affects hidden -> visible motion; at 100% Frame it has no effect.")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

                DisclosureGroup("Inside-Notch Indicator", isExpanded: $showIndicatorStyling) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show Dots", isOn: $ns.trayStripShowDots)

                        sliderRow(
                            "Indicator Width",
                            value: $ns.trayStripWidth,
                            range: 28...120,
                            step: 1,
                            valueText: { value in
                                "\(value.formatted(.number.precision(.fractionLength(0)))) pt"
                            }
                        )

                        sliderRow(
                            "Indicator Height",
                            value: $ns.trayStripHeight,
                            range: 4...16,
                            step: 0.5,
                            valueText: { value in
                                "\(value.formatted(.number.precision(.fractionLength(1)))) pt"
                            }
                        )

                        sliderRow(
                            "Dot Size",
                            value: $ns.trayStripDotSize,
                            range: 1.5...4.5,
                            step: 0.1,
                            valueText: { value in
                                "\(value.formatted(.number.precision(.fractionLength(1)))) pt"
                            }
                        )

                        sliderRow(
                            "Border Opacity",
                            value: $ns.trayStripBorderOpacity,
                            range: 0...0.8,
                            step: 0.01,
                            valueText: { value in
                                "\((value * 100).formatted(.number.precision(.fractionLength(0))))%"
                            }
                        )

                        sliderRow(
                            "Indicator Y Offset",
                            value: $ns.trayStripYOffset,
                            range: -50...50,
                            step: 0.5,
                            valueText: { value in
                                "\(value.formatted(.number.precision(.fractionLength(1)))) pt"
                            }
                        )

                        HStack(spacing: 8) {
                            Text("Max Dots")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Stepper(
                                "\(ns.trayStripMaxDots)",
                                value: $ns.trayStripMaxDots,
                                in: 1...8
                            )
                            .frame(width: 118)
                        }
                    }
                    .padding(.top, 6)
                }

                DisclosureGroup("Playback Tools", isExpanded: $showPlaybackTools) {
                    HStack(spacing: 8) {
                        Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                            if isPlaying {
                                stopPlayback()
                            } else {
                                startPlayback()
                            }
                        }
                        .buttonStyle(.bordered)

                        Text("Speed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Slider(value: $ns.inspectorPlaybackSpeed, in: 0.25...2.5, step: 0.05)
                            .frame(minWidth: 80)

                        Text("\(ns.inspectorPlaybackSpeed.formatted(.number.precision(.fractionLength(2))))x")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.top, 6)
                }

                HStack(spacing: 8) {
                    Button("Reset") {
                        reset()
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 8)

                    Button("Hide") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Attach Start Frame is when the strip starts locking into the notch body. Attach Duration is how long that lock-in takes.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .frame(width: 408)
        .onChange(of: ns.inspectorEnabled) { _, isEnabled in
            if !isEnabled {
                stopPlayback()
            }
        }
        .onChange(of: ns.inspectorScrubEnabled) { _, isScrubbing in
            if !isScrubbing {
                stopPlayback()
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }

    @ViewBuilder
    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(valueText(value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Slider(value: value, in: range, step: step)
        }
    }

    private func reset() {
        stopPlayback()
        ns.inspectorProgress = 0
        ns.inspectorExtensionWidthMatch = 1.0
        ns.inspectorExtensionWidthReferenceRaw = NotchExtensionWidthReference.full.rawValue
        ns.inspectorExtensionWidthDelta = 0
        ns.inspectorExtensionYOffset = -7.5
        ns.inspectorExtensionDropDistance = 8
        ns.inspectorExpansionStart = 0.24
        ns.inspectorBarAttachStart = 0.06
        ns.inspectorBarAttachDuration = 0.20
        ns.inspectorRecordingExtensionPreviewRaw = NotchRecordingExtensionPreview.live.rawValue
        ns.inspectorPlaybackSpeed = 1.0
        ns.shellStyleRaw = NotchVirtualDisplayStyle.auto.rawValue
        ns.trayStripShowDots = true
        ns.trayStripWidth = 56
        ns.trayStripHeight = 9
        ns.trayStripDotSize = 2.6
        ns.trayStripMaxDots = 5
        ns.trayStripBorderOpacity = 0.24
        ns.trayStripYOffset = 46
    }

    private func startPlayback() {
        stopPlayback()
        ns.inspectorScrubEnabled = true
        if ns.inspectorProgress >= 0.999 {
            ns.inspectorProgress = 0
        }

        let cycleDuration = max(0.25, 1.6 / max(0.25, ns.inspectorPlaybackSpeed))
        let startProgress = ns.inspectorProgress
        let startDate = Date()

        isPlaying = true
        playbackTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let elapsed = Date().timeIntervalSince(startDate)
                let next = startProgress + (elapsed / cycleDuration)
                self.ns.inspectorProgress = next.truncatingRemainder(dividingBy: 1)
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private var screenshotMetadataLines: [String] {
        [
            "Frame: \((ns.inspectorProgress * 100).formatted(.number.precision(.fractionLength(1))))%",
            "Recording Extension: \(recordingExtensionPreview.title)",
            "Expansion Start: \((ns.inspectorExpansionStart * 100).formatted(.number.precision(.fractionLength(0))))%",
            "Attach Start Frame: \((ns.inspectorBarAttachStart * 100).formatted(.number.precision(.fractionLength(0))))%",
            "Attach Duration: \((ns.inspectorBarAttachDuration * 100).formatted(.number.precision(.fractionLength(0))))%",
            "Shell Style: \(shellStyle.title)",
            "Width Reference: \(extensionWidthReference.title)",
            "Width Match: \((ns.inspectorExtensionWidthMatch * 100).formatted(.number.precision(.fractionLength(0))))%",
            "Width Fine Offset: \(ns.inspectorExtensionWidthDelta.formatted(.number.precision(.fractionLength(0)))) pt",
            "Extension Y Offset: \(ns.inspectorExtensionYOffset.formatted(.number.precision(.fractionLength(1)))) pt",
            "Reveal Travel: \(ns.inspectorExtensionDropDistance.formatted(.number.precision(.fractionLength(1)))) pt",
            "Indicator: \(ns.trayStripWidth.formatted(.number.precision(.fractionLength(0))))x\(ns.trayStripHeight.formatted(.number.precision(.fractionLength(1)))) Dot \(ns.trayStripDotSize.formatted(.number.precision(.fractionLength(1)))) Max \(ns.trayStripMaxDots) Border \(Int((ns.trayStripBorderOpacity * 100).rounded()))%",
            "Scrub With Slider: \(ns.inspectorScrubEnabled ? "On" : "Off")"
        ]
    }
}

private struct NotchAnimationMockPreview: View {
    let progress: Double
    let barAttachStart: Double
    let barAttachDuration: Double
    let expansionStart: Double
    let extensionWidthReferenceRaw: String
    let extensionWidthMatch: Double
    let extensionWidthDelta: Double
    let extensionYOffset: Double
    let extensionDropDistance: Double

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var clampedExpansionStart: CGFloat {
        CGFloat(min(max(expansionStart, 0), 0.95))
    }

    private var clampedBarAttachStart: CGFloat {
        CGFloat(min(max(barAttachStart, 0), 0.90))
    }

    private var clampedBarAttachDuration: CGFloat {
        CGFloat(min(max(barAttachDuration, 0.06), 0.50))
    }

    private var widthReference: NotchExtensionWidthReference {
        NotchExtensionWidthReference(rawValue: extensionWidthReferenceRaw) ?? .core
    }

    private var clampedWidthMatch: CGFloat {
        CGFloat(min(max(extensionWidthMatch, 0.75), 1.25))
    }

    private var attachProgress: CGFloat {
        guard clampedProgress > clampedBarAttachStart else { return 0 }
        let span = max(0.001, clampedBarAttachDuration)
        return min(1, max(0, (clampedProgress - clampedBarAttachStart) / span))
    }

    private var revealProgress: CGFloat {
        guard clampedProgress > clampedExpansionStart else { return 0 }
        let span = max(0.001, 1 - clampedExpansionStart)
        return min(1, max(0, (clampedProgress - clampedExpansionStart) / span))
    }

    private var notchWidth: CGFloat {
        let compact: CGFloat = 170
        let hover: CGFloat = 214
        let expanded: CGFloat = 254
        let split: CGFloat = 0.45

        if attachProgress <= split {
            let local = split > 0 ? attachProgress / split : 0
            return interpolate(compact, hover, local)
        }

        let trailingSpan = max(0.001, 1 - split)
        let local = min(1, max(0, (attachProgress - split) / trailingSpan))
        return interpolate(hover, expanded, local)
    }

    private var wingWidth: CGFloat {
        let rest: CGFloat = 0
        let hover: CGFloat = 10
        let active: CGFloat = 18
        let split: CGFloat = 0.45

        if attachProgress <= split {
            let local = split > 0 ? attachProgress / split : 0
            return interpolate(rest, hover, local)
        }

        let trailingSpan = max(0.001, 1 - split)
        let local = min(1, max(0, (attachProgress - split) / trailingSpan))
        return interpolate(hover, active, local)
    }

    private var fullBodyWidth: CGFloat {
        notchWidth + (wingWidth * 2)
    }

    private var referenceWidth: CGFloat {
        switch widthReference {
        case .core:
            notchWidth
        case .full:
            fullBodyWidth
        }
    }

    private var barStartWidth: CGFloat {
        let coreStart = interpolate(170, 254, clampedBarAttachStart)
        let referenceStart = widthReference == .full ? coreStart + 20 : coreStart
        return max(120, (referenceStart * clampedWidthMatch) + CGFloat(extensionWidthDelta))
    }

    private var barWidth: CGFloat {
        let target = max(120, (referenceWidth * clampedWidthMatch) + CGFloat(extensionWidthDelta))
        let start = max(120, barStartWidth)
        let progress = attachProgress
        return interpolate(start, target, progress)
    }

    private var extensionWidth: CGFloat {
        max(120, (referenceWidth * clampedWidthMatch) + CGFloat(extensionWidthDelta))
    }

    private var extensionHeight: CGFloat {
        26 + (102 * revealProgress)
    }

    private var extensionDropOffset: CGFloat {
        let drop = CGFloat(max(0, extensionDropDistance))
        return CGFloat(extensionYOffset) + ((1 - revealProgress) * -drop)
    }

    private var notchOpacity: CGFloat {
        0.45 + (attachProgress * 0.55)
    }

    private var islandDropOffset: CGFloat {
        (1 - attachProgress) * -12
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(white: 0.05))
                    .frame(width: barWidth, height: 3)
                    .offset(y: (1 - attachProgress) * -2)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.05))
                        .frame(width: fullBodyWidth, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )

                    BottomRoundedRect(radius: 12)
                        .fill(Color.black.opacity(0.14))
                        .frame(width: notchWidth, height: 32)
                        .overlay(
                            BottomRoundedRect(radius: 12)
                                .stroke(Color.white.opacity(0.03), lineWidth: 0.5)
                        )
                }
                .opacity(notchOpacity)
                .offset(y: islandDropOffset)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color(white: 0.05))
                        .frame(width: extensionWidth, height: 3)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.05))
                        .frame(width: extensionWidth, height: extensionHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                }
                .offset(y: extensionDropOffset)
                .scaleEffect(x: 1, y: max(0.01, revealProgress), anchor: .top)
                .opacity(Double(revealProgress))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, progress))
        return from + ((to - from) * clamped)
    }
}

private struct BottomRoundedRect: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()

        return path
    }
}
