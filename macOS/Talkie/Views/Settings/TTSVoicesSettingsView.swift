//
//  TTSVoicesSettingsView.swift
//  Talkie
//
//  Settings view for Text-to-Speech voice selection.
//  Uses static catalog with Engine status overlay.
//

import SwiftUI
import TalkieKit

struct TTSVoicesSettingsView: View {
    @State private var settings = SettingsManager.shared
    @State private var engineClient = EngineClient.shared

    // TTS status from engine
    @State private var ttsIsLoaded = false
    @State private var ttsIdleSeconds: Double = -1
    @State private var ttsMemoryMB: Int = 800

    // Confirmation
    @State private var voiceToDelete: String?
    @State private var showDeleteConfirmation = false

    // Timer for status polling
    @State private var statusTimer: Timer?

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "TEXT-TO-SPEECH VOICES",
                subtitle: "Select voice for speech synthesis"
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Memory status banner (when loaded)
                if ttsIsLoaded {
                    memoryStatusBanner
                }

                // Kokoro voices section
                kokoroSection
            }
        }
        .onAppear {
            startStatusPolling()
        }
        .onDisappear {
            stopStatusPolling()
        }
        .alert("Unload Voice?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unload", role: .destructive) {
                unloadTTS()
            }
        } message: {
            Text("This will unload the TTS model from memory, freeing ~800MB. The model will reload when you next use text-to-speech.")
        }
    }

    // MARK: - Memory Status Banner

    private var memoryStatusBanner: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.5), radius: 3)
                Text("TTS ENGINE LOADED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }

            Spacer()

            MemoryBadge(memoryMB: ttsMemoryMB)

            if ttsIdleSeconds >= 0 {
                Text("Idle: \(formatIdleTime(ttsIdleSeconds))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Button(action: unloadTTS) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("Unload")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .liquidGlassCard(cornerRadius: CornerRadius.sm, tint: Color.green.opacity(0.15), depth: .subtle)
    }

    // MARK: - Kokoro Section

    private var kokoroSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header with links
            sectionHeader(
                title: "KOKORO",
                subtitle: "Fast on-device neural TTS",
                color: TTSVoiceProvider.kokoro.color,
                repoURL: TTSVoiceCatalog.repoURL,
                demoURL: TTSVoiceCatalog.demoURL
            )

            // Voice cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(TTSVoiceCatalog.voices, id: \.id) { voice in
                    voiceCard(for: voice)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Section Header

    private func sectionHeader(
        title: String,
        subtitle: String,
        color: Color,
        repoURL: URL?,
        demoURL: URL?
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 1))

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.current.foreground)

            Text("•")
                .foregroundColor(Theme.current.foregroundMuted)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)

            LocalCloudBadge(isLocal: true)

            Spacer()

            // Links
            if let repoURL {
                Link(destination: repoURL) {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text("Repo")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }

            if let demoURL {
                Link(destination: demoURL) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 9))
                        Text("Demo")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Voice Card

    private func voiceCard(for voice: TTSVoiceMetadata) -> some View {
        let isSelected = settings.selectedTTSVoiceId == voice.id
        let isLoaded = isSelected && ttsIsLoaded

        return TTSVoiceCard(
            voice: voice,
            isSelected: isSelected,
            isLoaded: isLoaded,
            onSelect: { selectVoice(voice) },
            onUnload: isLoaded ? { showDeleteConfirmation = true } : nil
        )
    }

    // MARK: - Actions

    private func selectVoice(_ voice: TTSVoiceMetadata) {
        settings.selectedTTSVoiceId = voice.id

        // Preload the voice if not already loaded
        if !ttsIsLoaded {
            Task {
                do {
                    try await engineClient.preloadTTSVoice(voice.id)
                    await refreshStatus()
                } catch {
                    print("Failed to preload TTS voice: \(error)")
                }
            }
        }
    }

    private func unloadTTS() {
        Task {
            let success = await engineClient.unloadTTS()
            await MainActor.run {
                if success {
                    ttsIsLoaded = false
                    ttsIdleSeconds = -1
                }
            }
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        refreshStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            refreshStatus()
        }
    }

    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func refreshStatus() {
        Task {
            let status = await engineClient.getTTSStatus()
            await MainActor.run {
                ttsIsLoaded = status.isLoaded
                ttsIdleSeconds = status.idleSeconds
            }
        }
    }

    // MARK: - Helpers

    private func formatIdleTime(_ seconds: Double) -> String {
        if seconds < 0 { return "—" }
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }
}

// MARK: - TTS Voice Card

struct TTSVoiceCard: View {
    let voice: TTSVoiceMetadata
    let isSelected: Bool
    let isLoaded: Bool
    let onSelect: () -> Void
    var onUnload: (() -> Void)?

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent bar
            Rectangle()
                .fill(voice.provider.color.opacity(isSelected ? 1.0 : 0.3))
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 8) {
                // Header: Badge + Status
                HStack {
                    // Provider badge
                    Text(voice.provider.badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(voice.provider.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(voice.provider.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Gender badge
                    Text(voice.gender.prefix(1).uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.current.foregroundMuted.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    // Status badge
                    if isLoaded {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.midnightStatusActive)
                                .frame(width: 5, height: 5)
                                .shadow(color: settings.midnightStatusActive.opacity(0.5), radius: 3)
                            Text("LOADED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(settings.midnightStatusActive)
                        }
                    } else if isSelected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.midnightStatusReady)
                                .frame(width: 5, height: 5)
                            Text("SELECTED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(settings.midnightStatusReady)
                        }
                    }
                }

                // Voice name
                Text(voice.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(settings.midnightTextPrimary)
                    .lineLimit(1)

                // Description
                Text(voice.description)
                    .font(.system(size: 10))
                    .foregroundColor(settings.midnightTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Specs row
                HStack(spacing: 12) {
                    // Style
                    VStack(alignment: .leading, spacing: 1) {
                        Text("STYLE")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.midnightTextTertiary)
                        Text(voice.style)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(settings.midnightTextSecondary)
                    }

                    Spacer()

                    // Language
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("LANG")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.midnightTextTertiary)
                        Text(voice.language)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(settings.midnightTextSecondary)
                    }
                }

                Spacer(minLength: 4)

                // Action button
                actionButton
            }
            .padding(10)
        }
        .frame(height: 150)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBackground: Color {
        isHovered ? settings.midnightSurfaceHover : settings.midnightSurface
    }

    private var borderColor: Color {
        if isSelected {
            return voice.provider.color.opacity(0.6)
        }
        if isLoaded {
            return settings.midnightStatusActive.opacity(0.4)
        }
        if isHovered {
            return settings.midnightBorderActive
        }
        return settings.midnightBorder
    }

    @ViewBuilder
    private var actionButton: some View {
        HStack(spacing: 8) {
            if !isSelected {
                Button(action: onSelect) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9))
                        Text("Select")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let onUnload {
                Button(action: onUnload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9))
                        Text("Unload")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("TTS Voices Settings") {
    TTSVoicesSettingsView()
        .frame(width: 600, height: 500)
}
