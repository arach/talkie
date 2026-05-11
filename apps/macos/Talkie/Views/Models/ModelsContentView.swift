//
//  ModelsContentView.swift
//  Talkie macOS
//
//  Comprehensive model management UI for LLM providers
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")
// MARK: - Notifications

extension NSNotification.Name {
    static let navigateToSettings = NSNotification.Name("navigateToSettings")
    static let navigateToAgentSettings = NSNotification.Name("navigateToAgentSettings")
    static let navigateToEngineMonitor = NSNotification.Name("navigateToEngineMonitor")
    static let navigateToAgentMonitor = NSNotification.Name("navigateToAgentMonitor")

    @available(*, deprecated, renamed: "navigateToAgentSettings")
    static let navigateToLiveSettings = navigateToAgentSettings
    @available(*, deprecated, renamed: "navigateToAgentMonitor")
    static let navigateToLiveMonitor = navigateToAgentMonitor

    #if DEBUG
    /// Debug navigation for screenshots: talkie://d/{path}
    static let debugNavigate = NSNotification.Name("debugNavigate")
    #endif
}

struct ModelsContentView: View {
    private let registry = LLMProviderRegistry.shared
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    private let whisperService = WhisperService.shared
    private let parakeetService = ParakeetService.shared
    @State private var downloadingWhisperModel: WhisperModel?
    @State private var whisperDownloadTask: Task<Void, Never>?
    @State private var downloadingParakeetModel: ParakeetModel?
    @State private var parakeetDownloadTask: Task<Void, Never>?

    // Responsive breakpoints
    private let stackBreakpoint: CGFloat = 900    // Below: stack sections vertically (needs ~750px for side-by-side)
    private let compactBreakpoint: CGFloat = 600  // Below: single-column grids

    var body: some View {
        GeometryReader { geometry in
            let isNarrow = geometry.size.width < stackBreakpoint
            let isCompact = geometry.size.width < compactBreakpoint

            TalkiePage("Models", style: .pageOnly) {
                // Responsive layout: side-by-side when wide, stacked when narrow
                if isNarrow {
                    VStack(alignment: .leading, spacing: 20) {
                        cloudProvidersSectionView(isCompact: isCompact)
                        speechToTextSectionView(isCompact: isCompact)
                    }
                } else {
                    cloudProvidersSectionView(isCompact: isCompact)

                    Divider()

                    speechToTextSectionView(isCompact: isCompact)
                }
            }
        }
        .background(settingsManager.midnightBase)
        .task {
            await registry.refreshModels()
        }
    }
    // MARK: - Section Views (for responsive layout)

    @ViewBuilder
    private func cloudProvidersSectionView(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(settingsManager.midnightAccentCloud)
                    .frame(width: 3, height: 14)

                Text("CLOUD PROVIDERS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(settingsManager.midnightTextSecondary)
                Spacer()
                Text("API CONFIGURATION")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(settingsManager.midnightTextTertiary)
            }

            cloudProvidersGridView(isCompact: isCompact)
        }
    }

    @ViewBuilder
    private func speechToTextSectionView(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(settingsManager.midnightAccentSTT)
                    .frame(width: 3, height: 14)

                Text("SPEECH-TO-TEXT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(settingsManager.midnightTextSecondary)
                Spacer()
                Text("HIGH FIDELITY AUDIO")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(settingsManager.midnightTextTertiary)
            }

            speechToTextColumnView(isCompact: isCompact)
        }
    }

    // MARK: - Cloud Providers

    @State private var configuringProvider: String?

    @ViewBuilder
    private var cloudProvidersSection: some View {
        @Bindable var settings = settingsManager


        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            CompactProviderCard(
                name: "OpenAI",
                isConfigured: settingsManager.openaiApiKey != nil,
                icon: "brain.head.profile",
                modelCount: 4,
                highlights: [
                    "GPT-4o: Best reasoning + vision",
                    "GPT-4o Mini: Fast, cost-effective",
                    "128K context, JSON mode"
                ],
                isConfiguring: configuringProvider == "openai",
                apiKeyBinding: Binding(
                    get: { settingsManager.openaiApiKey ?? "" },
                    set: { settingsManager.openaiApiKey = $0.isEmpty ? nil : $0 }
                ),
                onConfigure: {
                    withAnimation {
                        configuringProvider = configuringProvider == "openai" ? nil : "openai"
                    }
                },
                onCancel: {
                    withAnimation {
                        configuringProvider = nil
                    }
                },
                onSave: {
                                        withAnimation {
                        configuringProvider = nil
                    }
                }
            )

            CompactProviderCard(
                name: "Anthropic",
                isConfigured: settingsManager.anthropicApiKey != nil,
                icon: "sparkles",
                modelCount: 3,
                highlights: [
                    "Sonnet 3.5: Top analysis + coding",
                    "Haiku 3.5: Ultra-fast responses",
                    "200K context, extended thinking"
                ],
                isConfiguring: configuringProvider == "anthropic",
                apiKeyBinding: Binding(
                    get: { settingsManager.anthropicApiKey ?? "" },
                    set: { settingsManager.anthropicApiKey = $0.isEmpty ? nil : $0 }
                ),
                onConfigure: {
                    withAnimation {
                        configuringProvider = configuringProvider == "anthropic" ? nil : "anthropic"
                    }
                },
                onCancel: {
                    withAnimation {
                        configuringProvider = nil
                    }
                },
                onSave: {
                                        withAnimation {
                        configuringProvider = nil
                    }
                }
            )

            CompactProviderCard(
                name: "Gemini",
                isConfigured: settingsManager.hasValidApiKey,
                icon: "cloud.fill",
                modelCount: 2,
                highlights: [
                    "1.5 Pro: Large context (2M tokens)",
                    "1.5 Flash: Low latency",
                    "Free tier available"
                ],
                isConfiguring: configuringProvider == "gemini",
                apiKeyBinding: $settings.geminiApiKey,
                onConfigure: {
                    withAnimation {
                        configuringProvider = configuringProvider == "gemini" ? nil : "gemini"
                    }
                },
                onCancel: {
                    withAnimation {
                        configuringProvider = nil
                    }
                },
                onSave: {
                                        withAnimation {
                        configuringProvider = nil
                    }
                }
            )

            CompactProviderCard(
                name: "Groq",
                isConfigured: settingsManager.groqApiKey != nil,
                icon: "bolt.fill",
                modelCount: 4,
                highlights: [
                    "Llama 3.3 70B: Powerful open model",
                    "Ultra-fast inference (500+ tok/s)",
                    "Free tier, low-cost scaling"
                ],
                isConfiguring: configuringProvider == "groq",
                apiKeyBinding: Binding(
                    get: { settingsManager.groqApiKey ?? "" },
                    set: { settingsManager.groqApiKey = $0.isEmpty ? nil : $0 }
                ),
                onConfigure: {
                    withAnimation {
                        configuringProvider = configuringProvider == "groq" ? nil : "groq"
                    }
                },
                onCancel: {
                    withAnimation {
                        configuringProvider = nil
                    }
                },
                onSave: {
                                        withAnimation {
                        configuringProvider = nil
                    }
                }
            )
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Cloud Providers Grid (Showcase Style)

    @State private var expandedCloudProvider: String?

    @ViewBuilder
    private func cloudProvidersGridView(isCompact: Bool) -> some View {
        let columns: [GridItem] = isCompact
            ? [GridItem(.flexible())]  // Single column when compact
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]  // 2 columns otherwise

        LazyVGrid(columns: columns, spacing: 8) {
            ExpandableCloudProviderCard(
                providerId: "openai",
                name: "OpenAI",
                tagline: "Industry standard for reasoning and vision",
                isConfigured: settingsManager.openaiApiKey != nil,
                isExpanded: expandedCloudProvider == "openai",
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedCloudProvider = expandedCloudProvider == "openai" ? nil : "openai"
                    }
                },
                onConfigure: {
                    // Deep link to Settings - API Keys section
                    NavigationState.shared.navigateToSettings(.aiProviders)
                }
            )

            ExpandableCloudProviderCard(
                providerId: "anthropic",
                name: "Anthropic",
                tagline: "Extended thinking and nuanced understanding",
                isConfigured: settingsManager.anthropicApiKey != nil,
                isExpanded: expandedCloudProvider == "anthropic",
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedCloudProvider = expandedCloudProvider == "anthropic" ? nil : "anthropic"
                    }
                },
                onConfigure: {
                    NavigationState.shared.navigateToSettings(.aiProviders)
                }
            )

            ExpandableCloudProviderCard(
                providerId: "gemini",
                name: "Gemini",
                tagline: "Multimodal powerhouse with massive context",
                isConfigured: settingsManager.hasValidApiKey,
                isExpanded: expandedCloudProvider == "gemini",
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedCloudProvider = expandedCloudProvider == "gemini" ? nil : "gemini"
                    }
                },
                onConfigure: {
                    NavigationState.shared.navigateToSettings(.aiProviders)
                }
            )

            ExpandableCloudProviderCard(
                providerId: "groq",
                name: "Groq",
                tagline: "Ultra-fast inference at scale",
                isConfigured: settingsManager.groqApiKey != nil,
                isExpanded: expandedCloudProvider == "groq",
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedCloudProvider = expandedCloudProvider == "groq" ? nil : "groq"
                    }
                },
                onConfigure: {
                    NavigationState.shared.navigateToSettings(.aiProviders)
                }
            )
        }
    }

    // MARK: - Speech-to-Text Column (Compact Grid)

    @ViewBuilder
    private func speechToTextColumnView(isCompact: Bool) -> some View {
        let sttColumns: [GridItem] = isCompact
            ? [GridItem(.flexible())]  // Single column when compact
            : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]  // 2 columns otherwise

        VStack(alignment: .leading, spacing: 12) {
            #if arch(arm64)
            // Parakeet family section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("PARAKEET")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("— NVIDIA")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(settingsManager.midnightTextTertiary)
                }

                LazyVGrid(columns: sttColumns, spacing: 8) {
                    ForEach(ParakeetModel.allCases, id: \.rawValue) { model in
                        STTModelCard(
                            name: model.sttCardName,
                            family: .parakeet,
                            size: model.sttCardSize,
                            speedTier: model.sttSpeedTier,
                            languageInfo: model.sttLanguages,
                            isDownloaded: parakeetService.isModelDownloaded(model),
                            isDownloading: downloadingParakeetModel == model,
                            downloadProgress: downloadingParakeetModel == model ? 0.5 : 0,
                            onDownload: { downloadParakeetModel(model) },
                            onDelete: { deleteParakeetModel(model) }
                        )
                    }
                }
            }

            // Whisper family section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("WHISPER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("— OpenAI")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(settingsManager.midnightTextTertiary)
                }

                LazyVGrid(columns: sttColumns, spacing: 8) {
                    ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                        STTModelCard(
                            name: model.sttCardName,
                            family: .whisper,
                            size: model.sttCardSize,
                            speedTier: model.sttSpeedTier,
                            languageInfo: model.sttLanguages,
                            isDownloaded: whisperService.isModelDownloaded(model),
                            isDownloading: downloadingWhisperModel == model,
                            downloadProgress: downloadingWhisperModel == model ? 0.5 : 0,
                            onDownload: { downloadWhisperModel(model) },
                            onDelete: { deleteWhisperModel(model) }
                        )
                    }
                }
            }
            #else
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("STT requires Apple Silicon")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(CornerRadius.sm)
            #endif
        }
    }

    // Legacy section (for reference)
    private var speechToTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if arch(arm64)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                // Whisper family card
                WhisperFamilyCard(
                    models: WhisperModel.allCases,
                    whisperService: whisperService,
                    downloadingModel: downloadingWhisperModel,
                    onDownload: { model in downloadWhisperModel(model) },
                    onDelete: { model in deleteWhisperModel(model) },
                    onCancel: { cancelWhisperDownload() }
                )

                // Parakeet family card
                ParakeetFamilyCard(
                    models: ParakeetModel.allCases,
                    parakeetService: parakeetService,
                    downloadingModel: downloadingParakeetModel,
                    onDownload: { model in downloadParakeetModel(model) },
                    onDelete: { model in deleteParakeetModel(model) },
                    onCancel: { cancelParakeetDownload() }
                )
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Local STT requires Apple Silicon (M1/M2/M3)")
                        .font(settingsManager.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(CornerRadius.xs)
            }
            #endif
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Whisper Actions

    private func downloadWhisperModel(_ model: WhisperModel) {
        logger.debug("[Whisper] Download button clicked for: \(model.displayName)")
        #if arch(arm64)
        guard !whisperService.isModelDownloaded(model) else {
            logger.debug("[Whisper] Model already downloaded: \(model.displayName)")
            return
        }

        logger.debug("[Whisper] Starting download for: \(model.rawValue)")
        downloadingWhisperModel = model

        whisperDownloadTask = Task {
            do {
                try await whisperService.downloadModel(model)
                await MainActor.run {
                    downloadingWhisperModel = nil
                    whisperDownloadTask = nil
                }
                logger.debug("[Whisper] Downloaded: \(model.displayName)")
            } catch is CancellationError {
                await MainActor.run {
                    downloadingWhisperModel = nil
                    whisperDownloadTask = nil
                }
                logger.debug("[Whisper] Download cancelled")
            } catch {
                await MainActor.run {
                    downloadingWhisperModel = nil
                    whisperDownloadTask = nil
                }
                logger.debug("[Whisper] Download failed: \(error)")
            }
        }
        #else
        logger.debug("[Whisper] Download requires Apple Silicon (arm64)")
        #endif
    }

    private func cancelWhisperDownload() {
        whisperDownloadTask?.cancel()
        downloadingWhisperModel = nil
        whisperDownloadTask = nil
    }

    private func deleteWhisperModel(_ model: WhisperModel) {
        #if arch(arm64)
        do {
            try whisperService.deleteModel(model)
            logger.debug("[Whisper] Deleted: \(model.displayName)")
        } catch {
            logger.debug("[Whisper] Delete failed: \(error)")
        }
        #endif
    }

    // MARK: - Parakeet Actions

    private func downloadParakeetModel(_ model: ParakeetModel) {
        logger.debug("[Parakeet] Download button clicked for: \(model.displayName)")
        #if arch(arm64)
        guard !parakeetService.isModelDownloaded(model) else {
            logger.debug("[Parakeet] Model already downloaded: \(model.displayName)")
            return
        }

        logger.debug("[Parakeet] Starting download for: \(model.rawValue)")
        downloadingParakeetModel = model

        parakeetDownloadTask = Task {
            do {
                try await parakeetService.downloadModel(model)
                await MainActor.run {
                    downloadingParakeetModel = nil
                    parakeetDownloadTask = nil
                }
                logger.debug("[Parakeet] Downloaded: \(model.displayName)")
            } catch is CancellationError {
                await MainActor.run {
                    downloadingParakeetModel = nil
                    parakeetDownloadTask = nil
                }
                logger.debug("[Parakeet] Download cancelled")
            } catch {
                await MainActor.run {
                    downloadingParakeetModel = nil
                    parakeetDownloadTask = nil
                }
                logger.debug("[Parakeet] Download failed: \(error)")
            }
        }
        #else
        logger.debug("[Parakeet] Download requires Apple Silicon (arm64)")
        #endif
    }

    private func cancelParakeetDownload() {
        parakeetDownloadTask?.cancel()
        downloadingParakeetModel = nil
        parakeetDownloadTask = nil
    }

    private func deleteParakeetModel(_ model: ParakeetModel) {
        #if arch(arm64)
        do {
            try parakeetService.deleteModel(model)
            logger.debug("[Parakeet] Deleted: \(model.displayName)")
        } catch {
            logger.debug("[Parakeet] Delete failed: \(error)")
        }
        #endif
    }

}


#Preview {
    ModelsContentView()
        .frame(width: 800, height: 600)
}
