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
    static let navigateToLiveSettings = NSNotification.Name("navigateToLiveSettings")
}

struct ModelsContentView: View {
    @StateObject private var registry = LLMProviderRegistry.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var whisperService = WhisperService.shared
    @StateObject private var parakeetService = ParakeetService.shared
    @State private var selectedProviderId: String = "gemini"
    @State private var downloadingModelId: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadTask: Task<Void, Never>?
    @State private var downloadingWhisperModel: WhisperModel?
    @State private var whisperDownloadTask: Task<Void, Never>?
    @State private var downloadingParakeetModel: ParakeetModel?
    @State private var parakeetDownloadTask: Task<Void, Never>?

    @State private var expandedFamily: String? = "Llama"  // Default expanded

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with breadcrumb
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOOLS / MODELS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(settingsManager.midnightTextTertiary)

                    HStack(spacing: 8) {
                        Text("MODELS & INTELLIGENCE")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(settingsManager.midnightTextPrimary)
                        Text("✦")
                            .font(.system(size: 14))
                            .foregroundColor(settingsManager.midnightBadgeRecommended)
                    }

                    Text("Manage your inference providers and local models. Download specialized variants for specific tasks or hardware constraints.")
                        .font(.system(size: 12))
                        .foregroundColor(settingsManager.midnightTextSecondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Two-column layout: Local Models | Speech-to-Text
                // Each column expands independently without affecting the other
                HStack(alignment: .top, spacing: 16) {
                    // Left column: Local Models
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            // Vertical accent bar - Purple
                            RoundedRectangle(cornerRadius: 1)
                                .fill(settingsManager.midnightAccentLocalModels)
                                .frame(width: 3, height: 14)

                            Text("LOCAL MODELS")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(settingsManager.midnightTextSecondary)
                            Spacer()
                            Text("PRIVATE ON-DEVICE")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(settingsManager.midnightTextTertiary)
                        }

                        localModelsColumn
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)  // Don't stretch to match sibling

                    // Right column: Speech-to-Text
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            // Vertical accent bar - Green
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

                        speechToTextColumn
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)  // Don't stretch to match sibling
                }
                .padding(.horizontal, 24)

                Divider()
                    .padding(.horizontal, 24)

                // Cloud Providers Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        // Vertical accent bar - Blue
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

                    cloudProvidersGrid
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        .background(settingsManager.midnightBase)
        .task {
            await registry.refreshModels()
        }
    }

    // MARK: - Cloud Providers

    @State private var configuringProvider: String?

    private var cloudProvidersSection: some View {
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
                    settingsManager.saveSettings()
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
                    settingsManager.saveSettings()
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
                apiKeyBinding: $settingsManager.geminiApiKey,
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
                    settingsManager.saveSettings()
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
                    settingsManager.saveSettings()
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

    private var cloudProvidersGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 8) {
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
                    NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                    NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                    NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
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
                    NotificationCenter.default.post(name: .navigateToSettings, object: "apiKeys")
                }
            )
        }
    }

    // MARK: - Local Models Column

    @State private var downloadingLocalModelId: String?

    // Model family definitions with metadata
    struct ModelFamilyInfo {
        let name: String
        let prefix: String
        let provider: String
        let description: String
        let isRecommended: Bool
    }

    private let modelFamilies: [ModelFamilyInfo] = [
        ModelFamilyInfo(name: "Llama 3", prefix: "Llama", provider: "Meta", description: "The most capable openly available LLM family with excellent reasoning and instruction following.", isRecommended: false),
        ModelFamilyInfo(name: "Phi", prefix: "Phi", provider: "Microsoft", description: "A highly capable small language model optimized for efficiency.", isRecommended: true),
        ModelFamilyInfo(name: "Mistral", prefix: "Mistral", provider: "Mistral AI", description: "Engineered for high performance and efficient inference.", isRecommended: false),
        ModelFamilyInfo(name: "Qwen", prefix: "Qwen", provider: "Alibaba", description: "Strong multilingual performance and coding capabilities.", isRecommended: false)
    ]

    private func modelsForFamily(_ prefix: String) -> [LLMModel] {
        registry.allModels.filter { $0.provider == "mlx" && $0.id.contains(prefix) }
    }

    private var localModelsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if arch(arm64)
            ForEach(modelFamilies, id: \.name) { family in
                let familyModels = modelsForFamily(family.prefix)
                if !familyModels.isEmpty {
                    ExpandableModelFamilyCard(
                        family: family,
                        models: familyModels,
                        isExpanded: expandedFamily == family.prefix,
                        downloadingModelId: downloadingModelId,
                        downloadProgress: downloadProgress,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedFamily = expandedFamily == family.prefix ? nil : family.prefix
                            }
                        },
                        onDownload: { model in downloadModel(model) },
                        onDelete: { model in deleteModel(model) },
                        onCancel: { cancelDownload() }
                    )
                }
            }
            #else
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("MLX requires Apple Silicon")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            #endif
        }
    }

    // MARK: - Speech-to-Text Column

    @State private var expandedSTT: String? = nil

    private var speechToTextColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if arch(arm64)
            // Parakeet card
            ExpandableSTTCard(
                name: "Parakeet",
                provider: "Nvidia",
                description: "The fastest speech-to-text model available with near real-time transcription.",
                isRecommended: true,
                isExpanded: expandedSTT == "parakeet",
                isActive: parakeetService.loadedModel != nil,
                hasInstalledModel: parakeetService.downloadedModels.count > 0,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedSTT = expandedSTT == "parakeet" ? nil : "parakeet"
                    }
                }
            ) {
                ParakeetVariantTable(
                    parakeetService: parakeetService,
                    downloadingModel: downloadingParakeetModel,
                    onDownload: { model in downloadParakeetModel(model) },
                    onDelete: { model in deleteParakeetModel(model) }
                )
            }

            // Whisper card
            ExpandableSTTCard(
                name: "Whisper",
                provider: "OpenAI",
                description: "General purpose speech recognition system trained on large-scale audio data.",
                isRecommended: false,
                isExpanded: expandedSTT == "whisper",
                isActive: whisperService.loadedModel != nil,
                hasInstalledModel: whisperService.downloadedModels.count > 0,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedSTT = expandedSTT == "whisper" ? nil : "whisper"
                    }
                }
            ) {
                WhisperVariantTable(
                    whisperService: whisperService,
                    downloadingModel: downloadingWhisperModel,
                    onDownload: { model in downloadWhisperModel(model) },
                    onDelete: { model in deleteWhisperModel(model) }
                )
            }
            #else
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("STT requires Apple Silicon")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
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
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
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

    // MARK: - Actions

    private func downloadModel(_ model: LLMModel) {
        #if arch(arm64)
        guard !model.isInstalled else { return }

        downloadingModelId = model.id
        downloadProgress = 0

        downloadTask = Task {
            do {
                let manager = MLXModelManager.shared
                try await manager.downloadModel(id: model.id) { progress in
                    DispatchQueue.main.async {
                        downloadProgress = progress
                    }
                }

                await registry.refreshModels()
                downloadingModelId = nil
                downloadTask = nil
                logger.debug("[MLX] Downloaded: \(model.displayName)")
            } catch is CancellationError {
                downloadingModelId = nil
                downloadTask = nil
                logger.debug("[MLX] Download cancelled")
            } catch {
                downloadingModelId = nil
                downloadTask = nil
                logger.debug("[MLX] Download failed: \(error)")
            }
        }
        #endif
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadingModelId = nil
        downloadProgress = 0
        downloadTask = nil
    }

    private func deleteModel(_ model: LLMModel) {
        #if arch(arm64)
        guard model.isInstalled else { return }

        Task {
            do {
                let manager = MLXModelManager.shared
                try manager.deleteModel(id: model.id)
                await registry.refreshModels()
                logger.debug("[MLX] Deleted: \(model.displayName)")
            } catch {
                logger.debug("[MLX] Delete failed: \(error)")
            }
        }
        #endif
    }
}


#Preview {
    ModelsContentView()
        .frame(width: 800, height: 600)
}
