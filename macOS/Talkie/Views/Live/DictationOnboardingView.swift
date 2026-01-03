//
//  DictationOnboardingView.swift
//  Talkie
//
//  Quick onboarding flow for users with 0 dictations
//  Validates permissions, sets hotkey, and starts first recording
//

import SwiftUI
import AVFoundation
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Onboarding Steps

enum DictationOnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case hotkey = 2
    case ready = 3
}

// MARK: - Main Onboarding View

struct DictationOnboardingView: View {
    @State private var currentStep: DictationOnboardingStep = .welcome
    @State private var hasMicPermission = false
    @State private var hasAccessibilityPermission = false
    @State private var isCheckingPermissions = false
    @Environment(LiveSettings.self) private var liveSettings

    var onComplete: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .hotkey:
                    hotkeyStep
                case .ready:
                    readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
        .onAppear {
            checkPermissions()
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(DictationOnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : TalkieTheme.surfaceCard)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Illustration
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: Spacing.sm) {
                Text("Voice Dictation")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Speak anywhere, type everywhere")
                    .font(.system(size: 14))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Feature highlights
            VStack(alignment: .leading, spacing: Spacing.md) {
                FeatureRow(
                    icon: "text.insert",
                    title: "Auto-Paste",
                    description: "Text appears at your cursor instantly"
                )

                FeatureRow(
                    icon: "keyboard",
                    title: "Global Hotkey",
                    description: "Start dictation from any app"
                )

                FeatureRow(
                    icon: "bolt.fill",
                    title: "Fast & Private",
                    description: "Local AI transcription on your Mac"
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)

            Spacer()

            // Actions
            VStack(spacing: Spacing.sm) {
                Button(action: { withAnimation { currentStep = .permissions } }) {
                    Text("Get Started")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentColor)
                        .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.system(size: 12))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Permissions Step

    private var permissionsStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.sm) {
                Text("Permissions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Talkie needs a few permissions to work")
                    .font(.system(size: 13))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            VStack(spacing: Spacing.md) {
                // Microphone
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "To hear your voice",
                    isGranted: hasMicPermission,
                    isRequired: true,
                    onRequest: requestMicPermission
                )

                // Accessibility
                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "For global hotkey & auto-paste",
                    isGranted: hasAccessibilityPermission,
                    isRequired: true,
                    onRequest: requestAccessibilityPermission
                )
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            // Actions
            VStack(spacing: Spacing.sm) {
                Button(action: { withAnimation { currentStep = .hotkey } }) {
                    HStack(spacing: Spacing.xs) {
                        Text(allPermissionsGranted ? "Continue" : "Continue Anyway")
                        if allPermissionsGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(allPermissionsGranted ? Color.accentColor : TalkieTheme.textMuted)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation { currentStep = .welcome } }) {
                    Text("Back")
                        .font(.system(size: 12))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .onAppear {
            // Start polling for permission changes
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    // MARK: - Hotkey Step

    private var hotkeyStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.sm) {
                Text("Your Hotkey")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Press this shortcut to start dictating")
                    .font(.system(size: 13))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            // Current hotkey display
            VStack(spacing: Spacing.lg) {
                HStack(spacing: Spacing.xs) {
                    ForEach(hotkeyParts, id: \.self) { part in
                        KeyCapLarge(symbol: part)
                    }
                }

                Text(liveSettings.hotkey.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)

                // Edit hotkey button
                HotkeyRecorderInline(hotkey: Binding(
                    get: { liveSettings.hotkey },
                    set: { liveSettings.hotkey = $0 }
                ))
            }
            .padding(Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(TalkieTheme.surfaceCard)
            )
            .padding(.horizontal, Spacing.lg)

            // Tips
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TipRow(icon: "hand.tap", text: "Press hotkey to start recording")
                TipRow(icon: "hand.tap", text: "Press again to stop and paste")
                TipRow(icon: "escape", text: "Press Esc to cancel")
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()

            // Actions
            VStack(spacing: Spacing.sm) {
                Button(action: { withAnimation { currentStep = .ready } }) {
                    Text("Looks Good")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentColor)
                        .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation { currentStep = .permissions } }) {
                    Text("Back")
                        .font(.system(size: 12))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Ready Step

    private var readyStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Success illustration
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
            }

            VStack(spacing: Spacing.sm) {
                Text("You're All Set!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Press \(liveSettings.hotkey.displayString) to start your first dictation")
                    .font(.system(size: 14))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Quick reminder
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    ForEach(hotkeyParts, id: \.self) { part in
                        KeyCapLarge(symbol: part)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundColor(TalkieTheme.textMuted)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(TalkieTheme.surfaceCard)
            )

            Spacer()

            // Actions
            VStack(spacing: Spacing.sm) {
                Button(action: startFirstDictation) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "mic.fill")
                        Text("Start First Dictation")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.accentColor)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)

                Button(action: onComplete) {
                    Text("I'll do it later")
                        .font(.system(size: 12))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Helpers

    private var hotkeyParts: [String] {
        // Parse the displayString which is like "⌥⌘L"
        let display = liveSettings.hotkey.displayString
        return display.map { String($0) }
    }

    private var allPermissionsGranted: Bool {
        hasMicPermission && hasAccessibilityPermission
    }

    private func checkPermissions() {
        hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    private func requestMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    hasMicPermission = granted
                }
            }
        } else if status == .denied || status == .restricted {
            // Open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func requestAccessibilityPermission() {
        if !AXIsProcessTrusted() {
            // Open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @State private var permissionTimer: Timer?

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                checkPermissions()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func startFirstDictation() {
        // Mark onboarding as complete
        onComplete()

        // Trigger dictation via TalkieLive
        ServiceManager.shared.live.toggleRecording()
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(CornerRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isRequired: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isGranted ? .green : .accentColor)
                .frame(width: 36, height: 36)
                .background(
                    (isGranted ? Color.green : Color.accentColor).opacity(0.1)
                )
                .cornerRadius(CornerRadius.sm)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TalkieTheme.textPrimary)

                    if isRequired {
                        Text("REQUIRED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            // Status / Action
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            } else {
                Button(action: onRequest) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.accentColor)
                        .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isGranted ? Color.green.opacity(0.05) : TalkieTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isGranted ? Color.green.opacity(0.2) : TalkieTheme.border, lineWidth: 1)
        )
    }
}

private struct KeyCapLarge: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(TalkieTheme.textPrimary)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(TalkieTheme.surfaceElevated)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(TalkieTheme.border, lineWidth: 1)
            )
    }
}

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textMuted)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textSecondary)
        }
    }
}

private struct HotkeyRecorderInline: View {
    @Binding var hotkey: HotkeyConfig
    @State private var isRecording = false

    var body: some View {
        Button(action: { isRecording.toggle() }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isRecording ? "keyboard" : "pencil")
                    .font(.system(size: 10))
                Text(isRecording ? "Press new shortcut..." : "Change Hotkey")
                    .font(.system(size: 11))
            }
            .foregroundColor(isRecording ? .orange : TalkieTheme.textMuted)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isRecording ? Color.orange.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .background(
            HotkeyCapture(isCapturing: $isRecording) { keyCode, modifiers in
                hotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                isRecording = false
            }
        )
    }
}

// Simple key capture view for inline hotkey recording
private struct HotkeyCapture: NSViewRepresentable {
    @Binding var isCapturing: Bool
    var onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let captureView = nsView as? KeyCaptureNSView else { return }
        captureView.isCapturing = isCapturing
        if isCapturing {
            DispatchQueue.main.async {
                captureView.window?.makeFirstResponder(captureView)
            }
        }
    }

    class KeyCaptureNSView: NSView {
        var isCapturing = false
        var onCapture: ((UInt32, UInt32) -> Void)?

        override var acceptsFirstResponder: Bool { isCapturing }

        override func keyDown(with event: NSEvent) {
            guard isCapturing else {
                super.keyDown(with: event)
                return
            }

            let keyCode = UInt32(event.keyCode)

            // Escape cancels
            if keyCode == 53 { return }

            // Ignore modifier-only keys
            let modifierKeys: Set<UInt32> = [55, 56, 58, 59, 54, 57, 60, 61, 62, 63]
            if modifierKeys.contains(keyCode) { return }

            // Build Carbon modifiers
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(Carbon.cmdKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(Carbon.optionKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(Carbon.controlKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(Carbon.shiftKey) }

            onCapture?(keyCode, modifiers)
        }
    }
}

// MARK: - Preview

#Preview("Welcome") {
    DictationOnboardingView(onComplete: {}, onSkip: {})
        .frame(width: 400, height: 600)
}
