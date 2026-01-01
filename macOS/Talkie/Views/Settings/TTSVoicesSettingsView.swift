//
//  TTSVoicesSettingsView.swift
//  Talkie
//
//  Settings view for Text-to-Speech voice selection.
//  Manages local (Kokoro) and cloud (ElevenLabs) TTS voices.
//

import SwiftUI
import TalkieKit

struct TTSVoicesSettingsView: View {
    @State private var settings = SettingsManager.shared
    @State private var engineClient = EngineClient.shared

    // Voice data
    @State private var voices: [TTSVoiceInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // TTS status
    @State private var ttsIsLoaded = false
    @State private var ttsIdleSeconds: Double = -1
    @State private var ttsMemoryMB: Int = 800  // Default estimate

    // Preview
    @State private var isPreviewPlaying = false
    @State private var previewVoiceId: String?

    // Confirmation
    @State private var voiceToDelete: TTSVoiceInfo?
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
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                voiceList
            }
        }
        .onAppear {
            loadVoices()
            startStatusPolling()
        }
        .onDisappear {
            stopStatusPolling()
        }
        .alert("Delete Voice", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let voice = voiceToDelete {
                    deleteVoice(voice)
                }
            }
        } message: {
            if let voice = voiceToDelete {
                Text("Are you sure you want to remove \(voice.displayName)? You can re-download it later.")
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading voices...")
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("Failed to load voices")
                .font(.system(size: 13, weight: .medium))
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundSecondary)
            Button("Retry") {
                loadVoices()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Voice List

    private var voiceList: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Memory status banner (when loaded)
            if ttsIsLoaded {
                memoryStatusBanner
            }

            // Local voices section (Kokoro)
            localVoicesSection

            // Cloud voices section (future: ElevenLabs)
            // cloudVoicesSection
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
        .padding(10)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Local Voices Section

    private var localVoicesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: 3, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 1))

                Text("LOCAL VOICES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)

                LocalCloudBadge(isLocal: true)

                Spacer()

                Text("On-device synthesis")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Voice cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(localVoices, id: \.id) { voice in
                    voiceCard(for: voice)
                }
            }
        }
    }

    // MARK: - Voice Card

    private func voiceCard(for voice: TTSVoiceInfo) -> some View {
        let isSelected = settings.selectedTTSVoiceId == voice.id
        let state = computeState(for: voice)

        return ModelCard(
            name: voice.displayName,
            provider: .kokoro,
            state: state,
            isSelected: isSelected,
            onSelect: { selectVoice(voice) },
            onDownload: { downloadVoice(voice) },
            onDelete: { confirmDelete(voice) },
            onCancel: {},
            onUnload: ttsIsLoaded && !isSelected ? unloadTTS : nil
        ) {
            TTSVoiceCardDetail(
                language: voice.language,
                memoryMB: ttsIsLoaded ? ttsMemoryMB : nil,
                isLocal: true
            )
        }
    }

    // MARK: - Computed Properties

    private var localVoices: [TTSVoiceInfo] {
        voices.filter { $0.provider == "kokoro" }
    }

    private var cloudVoices: [TTSVoiceInfo] {
        voices.filter { $0.provider == "elevenlabs" }
    }

    private func computeState(for voice: TTSVoiceInfo) -> ModelState {
        // For Kokoro, it's "loaded" when the TTS engine is loaded and this voice is selected
        let isSelected = settings.selectedTTSVoiceId == voice.id
        if isSelected && ttsIsLoaded {
            return .loaded
        } else if voice.isDownloaded {
            return .downloaded
        } else {
            return .notDownloaded
        }
    }

    // MARK: - Actions

    private func loadVoices() {
        isLoading = true
        errorMessage = nil

        Task {
            let fetchedVoices = await engineClient.getAvailableTTSVoices()
            await MainActor.run {
                voices = fetchedVoices
                isLoading = false

                // If no voices returned, it might mean engine isn't connected
                if voices.isEmpty {
                    // Add a default Kokoro voice for display purposes
                    voices = [
                        TTSVoiceInfo(
                            id: "kokoro:default",
                            provider: "kokoro",
                            voiceId: "default",
                            displayName: "Kokoro",
                            description: "High-quality neural TTS voice",
                            language: "en-US",
                            isDownloaded: true,
                            isLoaded: ttsIsLoaded
                        )
                    ]
                }
            }
        }
    }

    private func selectVoice(_ voice: TTSVoiceInfo) {
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

    private func downloadVoice(_ voice: TTSVoiceInfo) {
        // For Kokoro, download is handled automatically during preload
        selectVoice(voice)
    }

    private func confirmDelete(_ voice: TTSVoiceInfo) {
        voiceToDelete = voice
        showDeleteConfirmation = true
    }

    private func deleteVoice(_ voice: TTSVoiceInfo) {
        // For Kokoro, "delete" means unload from memory
        // The model files are part of the engine bundle
        if ttsIsLoaded {
            unloadTTS()
        }
        voiceToDelete = nil
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

    private func previewVoice(_ voice: TTSVoiceInfo) {
        guard !isPreviewPlaying else { return }

        isPreviewPlaying = true
        previewVoiceId = voice.id

        Task {
            do {
                let sampleText = "Hello! I'm \(voice.displayName), your text-to-speech assistant."
                let audioPath = try await engineClient.synthesize(text: sampleText, voiceId: voice.id)
                // TODO: Play audio from audioPath
                print("Preview audio at: \(audioPath)")
            } catch {
                print("Preview failed: \(error)")
            }

            await MainActor.run {
                isPreviewPlaying = false
                previewVoiceId = nil
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

// MARK: - Preview

#Preview("TTS Voices Settings") {
    TTSVoicesSettingsView()
        .frame(width: 600, height: 500)
}
