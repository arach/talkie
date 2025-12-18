//
//  HotkeyRecorder.swift
//  Talkie
//
//  Hotkey recording UI for Live settings
//  Ported from TalkieLive with instrumentation
//

import SwiftUI
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

// MARK: - Hotkey Recorder Button

struct HotkeyRecorderButton: View {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool
    var showReset: Bool = true

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
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(isCancelHovered ? .white : .accentColor.opacity(0.6))
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
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(isRecording ? 0.2 : (isHovered ? 0.18 : 0.12)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Reset button (only when not recording and not default)
            if showReset && !isRecording && hotkey != .default {
                Button(action: {
                    hotkey = .default
                    logger.info("Hotkey reset to default: \(HotkeyConfig.default.displayString)")
                    NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                }) {
                    Text("Reset")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isResetHovered ? .white : Theme.current.foregroundTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isResetHovered ? Theme.current.border : Color.clear)
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
            DispatchQueue.main.async {
                hotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                isRecording = false

                logger.info("Hotkey captured: \(hotkey.displayString)")

                // Notify AppDelegate to re-register hotkey
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
        }
        view.onCancel = {
            DispatchQueue.main.async {
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
    var isCapturing = false
    var onKeyCapture: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { isCapturing }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)

        // Escape key (53) cancels recording
        if keyCode == 53 {
            onCancel?()
            return
        }

        // Ignore modifier-only keys
        if keyCode == 55 || keyCode == 56 || keyCode == 58 || keyCode == 59 ||
           keyCode == 54 || keyCode == 57 || keyCode == 60 || keyCode == 61 ||
           keyCode == 62 || keyCode == 63 {
            return
        }

        // Build Carbon modifiers
        var carbonModifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if event.modifierFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        onKeyCapture?(keyCode, carbonModifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't call super - swallow modifier changes
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
}
