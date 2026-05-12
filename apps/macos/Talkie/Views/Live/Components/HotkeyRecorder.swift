//
//  HotkeyRecorder.swift
//  Talkie
//
//  Hotkey recording UI for Live settings
//  Ported from TalkieAgent with instrumentation
//

import SwiftUI
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "AgentSettings")

// MARK: - Recording Coordinator

@MainActor
final class HotkeyRecordingCoordinator {
    static let shared = HotkeyRecordingCoordinator()

    private var activeRecorderCount = 0

    var isRecording: Bool {
        activeRecorderCount > 0
    }

    private init() { }

    func beginRecording() {
        activeRecorderCount += 1
        guard activeRecorderCount == 1 else { return }
        NotificationCenter.default.post(name: .hotkeyRecordingStateDidChange, object: true)
    }

    func endRecording() {
        guard activeRecorderCount > 0 else { return }
        activeRecorderCount -= 1
        guard activeRecorderCount == 0 else { return }
        NotificationCenter.default.post(name: .hotkeyRecordingStateDidChange, object: false)
    }
}

// MARK: - Hotkey Recorder Button

struct HotkeyRecorderButton: View {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool
    var showReset: Bool = true
    var resetValue: HotkeyConfig = .default

    @State private var isHovered = false
    @State private var isCancelHovered = false
    @State private var isResetHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Main button
            Button(action: {
                isRecording.toggle()
                logger.debug("Hotkey recording \(isRecording ? "started" : "stopped")")
            }) {
                HStack(spacing: 6) {
                    Text(isRecording ? "Press keys..." : hotkey.displayString)
                        .foregroundColor(.accentColor)

                    // Cancel X button when recording
                    if isRecording {
                        Button(action: {
                            isRecording = false
                            logger.debug("Hotkey recording cancelled")
                        }) {
                            Image(systemName: "xmark")
                                .font(.techLabelSmall)
                                .foregroundColor(isCancelHovered ? .white : .accentColor.opacity(Opacity.prominent))
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(isCancelHovered ? Color.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { isCancelHovered = $0 }
                    }
                }
                .font(.bodyMedium)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(Color.accentColor.opacity(isRecording ? Opacity.medium : (isHovered ? Opacity.medium : Opacity.light)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Reset button (only when not recording and not default)
            if showReset && !isRecording && hotkey != resetValue {
                Button(action: {
                    hotkey = resetValue
                    logger.info("Hotkey reset to default: \(resetValue.displayString)")
                    NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                }) {
                    Text("Reset")
                        .font(.labelSmall)
                        .foregroundColor(isResetHovered ? .white : Theme.current.foregroundMuted)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs * 2)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(isResetHovered ? Color.secondary.opacity(Opacity.medium) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isResetHovered = $0 }
            }
        }
        .background(
            HotkeyRecorderNSView(isRecording: $isRecording, hotkey: $hotkey)
                .frame(width: 0, height: 0)
        )
    }
}

// MARK: - NSView Wrapper for Key Capture

struct HotkeyRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeyConfig

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCapture = { keyCode, modifiers in
            Task { @MainActor in
                hotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                isRecording = false

                logger.info("Hotkey captured: \(hotkey.displayString)")

                // Notify AppDelegate to re-register hotkey
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
        }
        view.onCancel = {
            Task { @MainActor in
                isRecording = false
                logger.debug("Key capture cancelled")
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isCapturing = isRecording
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

// MARK: - Key Capture View

class KeyCaptureView: NSView {
    var isCapturing = false {
        didSet {
            if isCapturing && !oldValue {
                HotkeyRecordingCoordinator.shared.beginRecording()
                installMonitor()
            } else if !isCapturing && oldValue {
                removeMonitor()
                HotkeyRecordingCoordinator.shared.endRecording()
            }
        }
    }
    var onKeyCapture: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { isCapturing }

    private func installMonitor() {
        removeMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isCapturing else { return event }

            let keyCode = UInt32(event.keyCode)

            // Escape cancels
            if keyCode == 53 {
                self.onCancel?()
                return nil
            }

            // Ignore modifier-only keys
            let modifierOnlyKeys: Set<UInt32> = [55, 56, 58, 59, 54, 57, 60, 61, 62, 63]
            if modifierOnlyKeys.contains(keyCode) {
                return nil
            }

            // Build Carbon modifiers
            var carbonModifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

            self.onKeyCapture?(keyCode, carbonModifiers)
            return nil // consume the event
        }
    }

    private func removeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if isCapturing {
            Task { @MainActor in
                HotkeyRecordingCoordinator.shared.endRecording()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        // Handled by local monitor
    }

    override func flagsChanged(with event: NSEvent) {
        // Swallow modifier changes when capturing
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
    static let captureChordDidChange = Notification.Name("captureChordDidChange")
    static let hotkeyRecordingStateDidChange = Notification.Name("hotkeyRecordingStateDidChange")
}
