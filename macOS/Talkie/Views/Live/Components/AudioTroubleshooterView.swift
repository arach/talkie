//
//  AudioTroubleshooterView.swift
//  TalkieLive
//
//  Beautiful troubleshooting UI for audio issues
//

import SwiftUI
import AVFoundation

// MARK: - Troubleshooter Sheet Controller

@MainActor
final class AudioTroubleshooterController: ObservableObject {
    static let shared = AudioTroubleshooterController()

    @Published var isShowing = false

    private init() {}

    func show() {
        isShowing = true
        // Run diagnostics when shown
        Task {
            await AudioDiagnostics.shared.runDiagnostics()
        }
    }

    func hide() {
        isShowing = false
    }
}

// MARK: - Main Troubleshooter View

struct AudioTroubleshooterView: View {
    @ObservedObject private var diagnostics = AudioDiagnostics.shared
    @ObservedObject private var controller = AudioTroubleshooterController.shared
    @State private var selectedFixIndex: Int = 0
    @State private var isTestingAudio = false
    @State private var audioTestResult: (success: Bool, peakLevel: Float, message: String)?
    @State private var isRequestingPermission = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .background(TalkieTheme.border)

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Permission request card (if needed)
                    permissionCard

                    // Status overview
                    if let result = diagnostics.lastResult {
                        statusOverview(result)
                    }

                    // Audio Test button
                    audioTestSection

                    // Checklist
                    if let result = diagnostics.lastResult {
                        checklistSection(result)
                    }

                    // Suggested fixes
                    if let result = diagnostics.lastResult, !result.suggestedFixes.isEmpty {
                        fixesSection(result)
                    }

                    // Loading state
                    if diagnostics.isRunningDiagnostics {
                        loadingView
                    }
                }
                .padding(20)
            }

            Divider()
                .background(TalkieTheme.border)

            // Footer
            footer
        }
        .frame(width: 520, height: 600)
        .background(TalkieTheme.surface)
        .onAppear {
            Task {
                await diagnostics.runDiagnostics()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Troubleshooter")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Let's figure out what's wrong")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            Button(action: { controller.hide() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .padding(8)
                    .background(Circle().fill(TalkieTheme.hover))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Permission Card

    @ViewBuilder
    private var permissionCard: some View {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        if status != .authorized {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(SemanticColor.warning.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: status == .denied ? "mic.slash.fill" : "mic.badge.plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(SemanticColor.warning)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status == .denied ? "Microphone Access Denied" : "Microphone Access Required")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Text(status == .denied
                             ? "Enable microphone access in System Settings"
                             : "TalkieLive needs microphone access to record")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textSecondary)
                    }

                    Spacer()
                }

                Button(action: {
                    isRequestingPermission = true
                    Task {
                        _ = await diagnostics.requestMicrophonePermission()
                        isRequestingPermission = false
                    }
                }) {
                    HStack(spacing: 6) {
                        if isRequestingPermission {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: status == .denied ? "gear" : "mic.fill")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(status == .denied ? "Open System Settings" : "Request Microphone Access")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SemanticColor.warning)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isRequestingPermission)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SemanticColor.warning.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SemanticColor.warning.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Audio Test Section

    private var audioTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AUDIO TEST")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)

            HStack(spacing: 12) {
                // Test result indicator
                if let result = audioTestResult {
                    ZStack {
                        Circle()
                            .fill((result.success ? SemanticColor.success : SemanticColor.error).opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: result.success ? "waveform" : "waveform.badge.exclamationmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(result.success ? SemanticColor.success : SemanticColor.error)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.success ? "Audio Capture Working" : "Audio Test Failed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Text(result.message)
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textSecondary)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(TalkieTheme.hover)
                            .frame(width: 36, height: 36)

                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Test Microphone")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Text("Verify audio capture is working")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textSecondary)
                    }
                }

                Spacer()

                Button(action: {
                    isTestingAudio = true
                    audioTestResult = nil
                    Task {
                        let result = await diagnostics.performAudioTest()
                        audioTestResult = result
                        isTestingAudio = false
                    }
                }) {
                    HStack(spacing: 4) {
                        if isTestingAudio {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        Text(isTestingAudio ? "Testing..." : "Run Test")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SemanticColor.info)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isTestingAudio)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TalkieTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(TalkieTheme.border, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Status Overview

    private func statusOverview(_ result: AudioDiagnosticResult) -> some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor(result.overallStatus).opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: statusIcon(result.overallStatus))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(statusColor(result.overallStatus))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(result.overallStatus))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(statusSubtitle(result))
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            // Re-run button
            Button(action: {
                Task { await diagnostics.runDiagnostics() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(diagnostics.isRunningDiagnostics)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(statusColor(result.overallStatus).opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Checklist Section

    private func checklistSection(_ result: AudioDiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIAGNOSTIC CHECKLIST")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(result.checks.enumerated()), id: \.element.id) { index, check in
                    checkRow(check, isLast: index == result.checks.count - 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TalkieTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(TalkieTheme.border, lineWidth: 1)
                    )
            )
        }
    }

    private func checkRow(_ check: DiagnosticCheck, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: check.status.systemIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(statusColor(check.status))
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(check.detail)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            // Icon
            Image(systemName: check.icon)
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .background(TalkieTheme.border)
                    .padding(.leading, 46)
            }
        }
    }

    // MARK: - Fixes Section

    private func fixesSection(_ result: AudioDiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUGGESTED STEPS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(TalkieTheme.textTertiary)

            VStack(spacing: 8) {
                ForEach(Array(result.suggestedFixes.enumerated()), id: \.element.id) { index, fix in
                    fixRow(fix, stepNumber: index + 1)
                }
            }
        }
    }

    private func fixRow(_ fix: AudioFix, stepNumber: Int) -> some View {
        Button(action: {
            Task {
                _ = await diagnostics.applyFix(fix)
            }
        }) {
            HStack(spacing: 12) {
                // Step number
                ZStack {
                    Circle()
                        .fill(fix.isPrimary ? SemanticColor.info.opacity(0.15) : TalkieTheme.hover)
                        .frame(width: 24, height: 24)

                    Text("\(stepNumber)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(fix.isPrimary ? SemanticColor.info : TalkieTheme.textSecondary)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(fix.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)

                        if fix.isPrimary {
                            Text("RECOMMENDED")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(SemanticColor.info)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(SemanticColor.info.opacity(0.15))
                                )
                        }

                        if fix.isManual {
                            Text("MANUAL")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(TalkieTheme.hover)
                                )
                        }
                    }

                    Text(fix.description)
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                }

                Spacer()

                // Action icon
                if diagnostics.isApplyingFix && diagnostics.fixInProgress?.id == fix.id {
                    ProgressView()
                        .controlSize(.small)
                } else if fix.isManual {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 12))
                        .foregroundColor(TalkieTheme.textTertiary)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(fix.isPrimary ? SemanticColor.info : TalkieTheme.textTertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TalkieTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(fix.isPrimary ? SemanticColor.info.opacity(0.3) : TalkieTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(diagnostics.isApplyingFix)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Running diagnostics...")
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textSecondary)
        }
        .padding(20)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let result = diagnostics.lastFixResult {
                HStack(spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(result.success ? SemanticColor.success : SemanticColor.warning)

                    Text(result.message)
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Done") {
                controller.hide()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func statusColor(_ status: DiagnosticCheck.CheckStatus) -> Color {
        switch status {
        case .passed: return SemanticColor.success
        case .warning: return SemanticColor.warning
        case .failed: return SemanticColor.error
        case .info: return SemanticColor.info
        }
    }

    private func statusIcon(_ status: DiagnosticCheck.CheckStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func statusTitle(_ status: DiagnosticCheck.CheckStatus) -> String {
        switch status {
        case .passed: return "Everything looks good"
        case .warning: return "Minor issues detected"
        case .failed: return "Issues found"
        case .info: return "Diagnostics complete"
        }
    }

    private func statusSubtitle(_ result: AudioDiagnosticResult) -> String {
        let issueCount = result.possibleIssues.count
        if issueCount == 0 {
            return "All \(result.checks.count) checks passed"
        } else if issueCount == 1 {
            return "1 issue needs attention"
        } else {
            return "\(issueCount) issues need attention"
        }
    }
}

// MARK: - Quick Fix Button (for inline use)

struct QuickFixButton: View {
    @ObservedObject private var diagnostics = AudioDiagnostics.shared

    var body: some View {
        Button(action: {
            Task {
                await diagnostics.quickFix()
            }
        }) {
            HStack(spacing: 4) {
                if diagnostics.isApplyingFix {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .medium))
                }
                Text("Fix")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(SemanticColor.info)
            )
        }
        .buttonStyle(.plain)
        .disabled(diagnostics.isApplyingFix)
    }
}

// MARK: - Troubleshoot Link (for inline use in warnings)

struct TroubleshootLink: View {
    var body: some View {
        Button(action: {
            AudioTroubleshooterController.shared.show()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .medium))
                Text("Troubleshoot")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SemanticColor.warning)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    AudioTroubleshooterView()
        .frame(width: 520, height: 600)
}
