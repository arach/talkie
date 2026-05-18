//
//  OnboardingNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — first-run experience. Three slides:
//  welcome / mic permission / keyboard setup. Donor is OnboardingView
//  (1401 lines); this is the rebuilt frame, deeper permission /
//  account flows still live in the donor.
//

import AVFoundation
import SwiftUI
import UIKit

struct OnboardingNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var slide: Slide = .welcome
    @State private var micPermissionHint: String?

    enum Slide: Int, CaseIterable {
        case welcome, mic, keyboard, done

        var nextLabel: String {
            switch self {
            case .welcome:  return "Continue"
            case .mic:      return "Grant access"
            case .keyboard: return "Open Settings"
            case .done:     return "Start using Talkie ›"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            ScrollView {
                Group {
                    switch slide {
                    case .welcome:  welcomeSlide
                    case .mic:      micSlide
                    case .keyboard: keyboardSlide
                    case .done:     doneSlide
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)

            Spacer()

            footer
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Slide.allCases, id: \.self) { s in
                let active = s.rawValue <= slide.rawValue
                Capsule()
                    .fill(active ? theme.currentTheme.chrome.accent : theme.currentTheme.chrome.edgeFaint)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Slides

    private var welcomeSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.top, 24)

            Text("Talk faster than you type.")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(theme.colors.textPrimary)
                .lineSpacing(2)

            Text("Talkie turns voice into the fastest input you have. Capture a thought, dictate from any keyboard, refine with AI — all in one shell.")
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 4)

            featureChip(systemImage: "mic.fill", label: "Real-time dictation, anywhere")
            featureChip(systemImage: "sparkles", label: "AI commands on any document")
            featureChip(systemImage: "antenna.radiowaves.left.and.right", label: "Pairs with your Mac")
        }
    }

    private var micSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.top, 24)

            Text("Microphone access")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(theme.colors.textPrimary)

            Text("Talkie records voice memos locally. Audio never leaves the device unless you explicitly sync — your transcripts live on disk first, the cloud second.")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textSecondary)

            permissionRow(systemImage: "mic", label: "Microphone", status: "Needed for voice")
            permissionRow(systemImage: "lock.fill", label: "On-device first", status: "No cloud upload")
            permissionRow(systemImage: "icloud", label: "iCloud sync", status: "Opt in, anytime")

            if let micPermissionHint {
                Text(micPermissionHint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var keyboardSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "keyboard")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.top, 24)

            Text("Add the keyboard")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(theme.colors.textPrimary)

            Text("The Talkie keyboard is what makes voice work everywhere. iOS asks you to add it once — here's the sequence.")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textSecondary)

            stepRow(n: 1, label: "Tap 'Open Settings' below")
            stepRow(n: 2, label: "Choose 'Add New Keyboard…'")
            stepRow(n: 3, label: "Pick Talkie, enable Full Access")

            Text("Full Access is what lets the keyboard talk to your memos. It stays on-device.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.top, 8)
        }
    }

    private var doneSlide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.top, 24)

            Text("You're set.")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(theme.colors.textPrimary)

            Text("Tap the voice button at the bottom-left to summon chrome. Long-press it anywhere to talk. The keyboard handles the rest.")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(theme.colors.textSecondary)

            featureChip(systemImage: "dot.radiowaves.left.and.right", label: "Tap to summon · long-press to talk")
            featureChip(systemImage: "sparkles", label: "Sonnet 4.6 powers AI commands")
        }
    }

    // MARK: - Helpers

    private func featureChip(systemImage: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func permissionRow(systemImage: String, label: String, status: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(status)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func stepRow(n: Int, label: String) -> some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.colors.cardBackground)
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.currentTheme.chrome.accent))
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button(action: advance) {
                Text(slide.nextLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)

            if slide != .done && slide != .welcome {
                Button(action: { slide = .done }) {
                    Text("Skip for now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private func advance() {
        switch slide {
        case .welcome:
            slide = .mic
        case .mic:
            requestMicrophoneThenAdvance()
        case .keyboard:
            openSettings()
            slide = .done
        case .done:
            AppShellRouter.shared.openHome()
        }
    }

    private func requestMicrophoneThenAdvance() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                if !granted {
                    micPermissionHint = "Microphone access was denied. You can enable it later in Settings."
                }
                slide = .keyboard
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
