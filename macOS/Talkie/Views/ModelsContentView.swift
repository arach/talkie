//
//  ModelsContentView.swift
//  Talkie macOS
//
//  Comprehensive model management UI for LLM providers
//

import SwiftUI

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
                        .tracking(1)
                        .foregroundColor(settingsManager.midnightTextTertiary)

                    HStack(spacing: 8) {
                        Text("MODELS & INTELLIGENCE")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(1)
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
                HStack(alignment: .top, spacing: 16) {
                    // Left column: Local Models
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            // Vertical accent bar
                            RoundedRectangle(cornerRadius: 1)
                                .fill(settingsManager.midnightAccentBar)
                                .frame(width: 3, height: 14)

                            Text("LOCAL MODELS")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(settingsManager.midnightTextSecondary)
                            Spacer()
                            Text("PRIVATE ON-DEVICE")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(settingsManager.midnightTextTertiary)
                        }

                        localModelsColumn
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right column: Speech-to-Text
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            // Vertical accent bar
                            RoundedRectangle(cornerRadius: 1)
                                .fill(settingsManager.midnightAccentBar)
                                .frame(width: 3, height: 14)

                            Text("SPEECH-TO-TEXT")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(settingsManager.midnightTextSecondary)
                            Spacer()
                            Text("HIGH FIDELITY AUDIO")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(settingsManager.midnightTextTertiary)
                        }

                        speechToTextColumn
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)

                Divider()
                    .padding(.horizontal, 24)

                // Cloud Providers Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        // Vertical accent bar
                        RoundedRectangle(cornerRadius: 1)
                            .fill(settingsManager.midnightAccentBar)
                            .frame(width: 3, height: 14)

                        Text("CLOUD PROVIDERS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
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

    // MARK: - Cloud Providers Grid (New Design)

    private var cloudProvidersGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 0) {
            CompactCloudProviderRow(
                name: "OpenAI",
                provider: "OpenAI",
                description: "The industry standard for reasoning and general-purpose AI tasks.",
                contextSize: "128K",
                ttft: "~1.2s",
                isConfigured: settingsManager.openaiApiKey != nil,
                isRecommended: false,
                isExpanded: configuringProvider == "openai",
                apiKeyBinding: Binding(
                    get: { settingsManager.openaiApiKey ?? "" },
                    set: { settingsManager.openaiApiKey = $0.isEmpty ? nil : $0 }
                ),
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configuringProvider = configuringProvider == "openai" ? nil : "openai"
                    }
                },
                onSave: { settingsManager.saveSettings() }
            )

            CompactCloudProviderRow(
                name: "Anthropic",
                provider: "Anthropic",
                description: "Claude 3 offers near-instant responses with extended thinking capabilities.",
                contextSize: "200K",
                ttft: "~1.5s",
                isConfigured: settingsManager.anthropicApiKey != nil,
                isRecommended: true,
                isExpanded: configuringProvider == "anthropic",
                apiKeyBinding: Binding(
                    get: { settingsManager.anthropicApiKey ?? "" },
                    set: { settingsManager.anthropicApiKey = $0.isEmpty ? nil : $0 }
                ),
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configuringProvider = configuringProvider == "anthropic" ? nil : "anthropic"
                    }
                },
                onSave: { settingsManager.saveSettings() }
            )

            CompactCloudProviderRow(
                name: "Gemini",
                provider: "Google",
                description: "Google's multimodal powerhouse. Features massive context windows.",
                contextSize: "2M",
                ttft: "~0.8s",
                isConfigured: settingsManager.hasValidApiKey,
                isRecommended: false,
                isExpanded: configuringProvider == "gemini",
                apiKeyBinding: $settingsManager.geminiApiKey,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configuringProvider = configuringProvider == "gemini" ? nil : "gemini"
                    }
                },
                onSave: { settingsManager.saveSettings() }
            )

            CompactCloudProviderRow(
                name: "Groq",
                provider: "Groq",
                description: "LPU Inference Engine designed for real-time AI at scale.",
                contextSize: "128K",
                ttft: "~0.1s",
                isConfigured: settingsManager.groqApiKey != nil,
                isRecommended: false,
                isExpanded: configuringProvider == "groq",
                apiKeyBinding: Binding(
                    get: { settingsManager.groqApiKey ?? "" },
                    set: { settingsManager.groqApiKey = $0.isEmpty ? nil : $0 }
                ),
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configuringProvider = configuringProvider == "groq" ? nil : "groq"
                    }
                },
                onSave: { settingsManager.saveSettings() }
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
        VStack(alignment: .leading, spacing: 0) {
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
        VStack(alignment: .leading, spacing: 0) {
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
        print("[Whisper] Download button clicked for: \(model.displayName)")

        #if arch(arm64)
        guard !whisperService.isModelDownloaded(model) else {
            print("[Whisper] Model already downloaded: \(model.displayName)")
            return
        }

        print("[Whisper] Starting download for: \(model.rawValue)")
        downloadingWhisperModel = model

        whisperDownloadTask = Task {
            do {
                try await whisperService.downloadModel(model)
                await MainActor.run {
                    downloadingWhisperModel = nil
                    whisperDownloadTask = nil
                }
                print("[Whisper] Downloaded: \(model.displayName)")
            } catch is CancellationError {
                await MainActor.run {
                    downloadingWhisperModel = nil
                    whisperDownloadTask = nil
                }
                print("[Whisper] Download cancelled")
            } catch {
                await MainActor.run {
                    downloadingWhisperModel = nil
                    whisperDownloadTask = nil
                }
                print("[Whisper] Download failed: \(error)")
            }
        }
        #else
        print("[Whisper] Download requires Apple Silicon (arm64)")
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
            print("[Whisper] Deleted: \(model.displayName)")
        } catch {
            print("[Whisper] Delete failed: \(error)")
        }
        #endif
    }

    // MARK: - Parakeet Actions

    private func downloadParakeetModel(_ model: ParakeetModel) {
        print("[Parakeet] Download button clicked for: \(model.displayName)")

        #if arch(arm64)
        guard !parakeetService.isModelDownloaded(model) else {
            print("[Parakeet] Model already downloaded: \(model.displayName)")
            return
        }

        print("[Parakeet] Starting download for: \(model.rawValue)")
        downloadingParakeetModel = model

        parakeetDownloadTask = Task {
            do {
                try await parakeetService.downloadModel(model)
                await MainActor.run {
                    downloadingParakeetModel = nil
                    parakeetDownloadTask = nil
                }
                print("[Parakeet] Downloaded: \(model.displayName)")
            } catch is CancellationError {
                await MainActor.run {
                    downloadingParakeetModel = nil
                    parakeetDownloadTask = nil
                }
                print("[Parakeet] Download cancelled")
            } catch {
                await MainActor.run {
                    downloadingParakeetModel = nil
                    parakeetDownloadTask = nil
                }
                print("[Parakeet] Download failed: \(error)")
            }
        }
        #else
        print("[Parakeet] Download requires Apple Silicon (arm64)")
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
            print("[Parakeet] Deleted: \(model.displayName)")
        } catch {
            print("[Parakeet] Delete failed: \(error)")
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
                print("[MLX] Downloaded: \(model.displayName)")
            } catch is CancellationError {
                downloadingModelId = nil
                downloadTask = nil
                print("[MLX] Download cancelled")
            } catch {
                downloadingModelId = nil
                downloadTask = nil
                print("[MLX] Download failed: \(error)")
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
                print("[MLX] Deleted: \(model.displayName)")
            } catch {
                print("[MLX] Delete failed: \(error)")
            }
        }
        #endif
    }
}

// MARK: - Provider Card

struct ProviderCard<Content: View>: View {
    let name: String
    let status: String
    let isConfigured: Bool
    let icon: String
    let models: [String]
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(isConfigured ? .blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(SettingsManager.shared.fontBody)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConfigured ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(status.uppercased())
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(0.5)
                            .foregroundColor(isConfigured ? .green : .orange)
                    }
                }

                Spacer()
            }

            // Models list
            if !models.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(models, id: \.self) { model in
                        HStack(spacing: 6) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(model)
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Custom content
            content()
        }
        .padding(16)
        .background(SettingsManager.shared.surface1)
        .cornerRadius(8)
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: LLMModel
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Model info
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(SettingsManager.shared.fontSM)

                HStack(spacing: 8) {
                    Text(model.size)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)

                    if let sizeGB = model.sizeInGB {
                        Text("~\(String(format: "%.1f", sizeGB))GB")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                    }

                    if model.isInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(SettingsManager.shared.fontXS)
                            Text("INSTALLED")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(0.5)
                        }
                        .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            // Actions
            if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 80)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
            } else if model.isInstalled {
                Button(action: onDelete) {
                    Text("DELETE")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(0.5)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(SettingsManager.shared.fontXS)
                        Text("DOWNLOAD")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(0.5)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(SettingsManager.shared.surfaceInput)
        .cornerRadius(6)
    }
}

// MARK: - Button Style

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsManager.shared.fontXSBold)
            .tracking(1)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue)
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

#Preview {
    ModelsContentView()
        .frame(width: 800, height: 600)
}

// MARK: - Compact Model Card (Spec Sheet Style)

struct CompactModelCard: View {
    let model: LLMModel
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var modelCode: String {
        if model.id.contains("Llama-3.2-1B") { return "MLX-L1" }
        if model.id.contains("Llama-3.2-3B") { return "MLX-L3" }
        if model.id.contains("Qwen2.5-1.5B") { return "MLX-Q1" }
        if model.id.contains("Qwen2.5-3B") { return "MLX-Q3" }
        if model.id.contains("Qwen2.5-7B") { return "MLX-Q7" }
        if model.id.contains("gemma-2-9b") { return "MLX-G9" }
        return "MLX-X"
    }

    private var paramCount: String {
        if model.id.contains("1B") { return "1B" }
        if model.id.contains("1.5B") { return "1.5B" }
        if model.id.contains("3B") { return "3B" }
        if model.id.contains("7B") { return "7B" }
        if model.id.contains("9b") { return "9B" }
        return "—"
    }

    private var diskSize: String {
        if model.id.contains("1B") && !model.id.contains("1.5B") { return "700" }
        if model.id.contains("1.5B") { return "1.0G" }
        if model.id.contains("3B") { return "2.0G" }
        if model.id.contains("7B") { return "4.0G" }
        if model.id.contains("9b") { return "5.0G" }
        return "—"
    }

    private var quantization: String {
        "4bit"
    }

    private var huggingFaceURL: URL? {
        URL(string: "https://huggingface.co/\(model.id)")
    }

    private var paperURL: URL? {
        if model.id.contains("Llama") {
            return URL(string: "https://arxiv.org/abs/2407.21783")
        } else if model.id.contains("Qwen") {
            return URL(string: "https://arxiv.org/abs/2309.16609")
        } else if model.id.contains("gemma") {
            return URL(string: "https://arxiv.org/abs/2408.00118")
        } else if model.id.contains("Phi") {
            return URL(string: "https://arxiv.org/abs/2404.14219")
        } else if model.id.contains("Mistral") {
            return URL(string: "https://arxiv.org/abs/2310.06825")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Model code + Status
            HStack {
                Text(modelCode)
                    .font(settings.monoXS)
                    .tracking(settings.trackingNormal)
                    .foregroundColor(settings.specLabelColor)

                Spacer()

                if model.isInstalled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 6, height: 6)
                        Text("READY")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(settings.statusActive)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 8))
                        Text("AVAILABLE")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Model name
            Text(model.displayName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(settings.trackingTight)
                .foregroundColor(settings.specValueColor)
                .lineLimit(2)
                .padding(.bottom, 6)

            // Links row
            HStack(spacing: 12) {
                if let url = huggingFaceURL {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 3) {
                            Text("Model")
                                .font(settings.monoXS)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                if let url = paperURL {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 3) {
                            Text("Paper")
                                .font(settings.monoXS)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(settings.specDividerOpacity))
                .frame(height: 1)
                .padding(.horizontal, -12)
                .padding(.bottom, 8)

            // Specs grid
            HStack(spacing: 0) {
                specCell(label: "PARAMS", value: paramCount)
                Spacer()
                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(width: 1, height: 24)
                Spacer()
                specCell(label: "SIZE", value: diskSize)
                Spacer()
                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(width: 1, height: 24)
                Spacer()
                specCell(label: "QUANT", value: quantization)
            }
            .padding(.bottom, 10)

            Spacer()

            // Action
            if isDownloading {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(settings.specDividerOpacity))
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.6), .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(downloadProgress))
                        }
                    }
                    .frame(height: 3)
                    .cornerRadius(1.5)

                    HStack {
                        Text("DOWNLOADING \(Int(downloadProgress * 100))%")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(.blue.opacity(0.8))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(settings.monoXS)
                                .tracking(settings.trackingNormal)
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if model.isInstalled {
                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 9))
                        Text("REMOVE")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                        Text("DOWNLOAD")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(
                            colors: [Color.primary.opacity(0.06), Color.primary.opacity(settings.specDividerOpacity)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    )
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(height: 170)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground
                LinearGradient(
                    colors: [Color.primary.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? Color.white.opacity(0.2) :
                    model.isInstalled ? settings.cardBorderActive : settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(settings.monoXS)
                .tracking(settings.trackingWide)
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(settings.monoBody)
                .foregroundColor(settings.specValueColor)
        }
        .frame(minWidth: 35)
    }
}

// MARK: - Compact Provider Card (Spec Sheet Style)

struct CompactProviderCard: View {
    let name: String
    let isConfigured: Bool
    let icon: String
    let modelCount: Int
    let highlights: [String]
    let isConfiguring: Bool
    let apiKeyBinding: Binding<String>
    let onConfigure: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var providerCode: String {
        switch name {
        case "OpenAI": return "OAI-4"
        case "Anthropic": return "ANT-C"
        case "Gemini": return "GEM-1"
        case "Groq": return "GRQ-L"
        default: return "PRV-X"
        }
    }

    private var logoName: String {
        switch name {
        case "OpenAI": return "ProviderLogos/OpenAI"
        case "Anthropic": return "ProviderLogos/Anthropic"
        case "Gemini": return "ProviderLogos/Google"
        case "Groq": return "ProviderLogos/Groq"
        default: return ""
        }
    }

    private var contextSize: String {
        switch name {
        case "OpenAI": return "128K"
        case "Anthropic": return "200K"
        case "Gemini": return "2M"
        case "Groq": return "128K"
        default: return "—"
        }
    }

    private var latency: String {
        switch name {
        case "OpenAI": return "~1.2s"
        case "Anthropic": return "~1.5s"
        case "Gemini": return "~0.8s"
        case "Groq": return "~0.1s"
        default: return "—"
        }
    }

    private var modelCountStr: String {
        "\(modelCount)"
    }

    private var modelsURL: URL? {
        switch name {
        case "OpenAI": return URL(string: "https://platform.openai.com/docs/models")
        case "Anthropic": return URL(string: "https://docs.anthropic.com/en/docs/about-claude/models")
        case "Gemini": return URL(string: "https://ai.google.dev/gemini-api/docs/models/gemini")
        case "Groq": return URL(string: "https://console.groq.com/docs/models")
        default: return nil
        }
    }

    private var apiDocsURL: URL? {
        switch name {
        case "OpenAI": return URL(string: "https://platform.openai.com/docs/api-reference")
        case "Anthropic": return URL(string: "https://docs.anthropic.com/en/api/getting-started")
        case "Gemini": return URL(string: "https://ai.google.dev/gemini-api/docs")
        case "Groq": return URL(string: "https://console.groq.com/docs/quickstart")
        default: return nil
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isConfigured {
            Color.green.opacity(0.08)
        } else {
            LinearGradient(
                colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        ZStack {
            // Back side - Configuration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CONFIGURE")
                        .font(settings.monoSM)
                        .tracking(settings.trackingWide)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                SecureField("API Key", text: apiKeyBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                Spacer()

                Button(action: onSave) {
                    Text("SAVE")
                        .font(settings.monoSM)
                        .tracking(settings.trackingWide)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(settings.specDividerOpacity))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(height: 140)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(settings.cardBackgroundHover)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
            )
            .opacity(isConfiguring ? 1 : 0)
            .rotation3DEffect(.degrees(isConfiguring ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            .zIndex(isConfiguring ? 1 : 0)

            // Front side - Provider card
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text(providerCode)
                        .font(settings.monoXS)
                        .tracking(settings.trackingNormal)
                        .foregroundColor(settings.specLabelColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(2)

                    Spacer()

                    if isConfigured {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.statusActive)
                                .frame(width: 6, height: 6)
                                .shadow(color: settings.statusActive.opacity(0.5), radius: 3)
                            Text("ACTIVE")
                                .font(settings.monoXS)
                                .tracking(settings.trackingNormal)
                                .foregroundColor(settings.statusActive)
                        }
                    } else {
                        Text("SETUP")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(settings.statusWarning)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Logo + Name
                HStack(spacing: 8) {
                    if !logoName.isEmpty {
                        Image(logoName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundColor(isConfigured ? .primary : .secondary)
                    }

                    Text(name.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(settings.trackingNormal)
                        .foregroundColor(settings.specValueColor)
                }
                .padding(.bottom, 4)

                // Links row
                HStack(spacing: 12) {
                    if let url = modelsURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            HStack(spacing: 3) {
                                Text("Models")
                                    .font(settings.monoXS)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 7))
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    if let url = apiDocsURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            HStack(spacing: 3) {
                                Text("API")
                                    .font(settings.monoXS)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 7))
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(height: 1)
                    .padding(.horizontal, -12)
                    .padding(.bottom, 8)

                // Specs grid
                HStack(spacing: 0) {
                    specCell(label: "CTX", value: contextSize)
                    Spacer()
                    Rectangle()
                        .fill(Color.primary.opacity(settings.specDividerOpacity))
                        .frame(width: 1, height: 24)
                    Spacer()
                    specCell(label: "TTFT", value: latency)
                    Spacer()
                    Rectangle()
                        .fill(Color.primary.opacity(settings.specDividerOpacity))
                        .frame(width: 1, height: 24)
                    Spacer()
                    specCell(label: "MDLS", value: modelCountStr)
                }
                .padding(.bottom, 10)

                Spacer()

                // Action
                Button(action: onConfigure) {
                    HStack(spacing: 6) {
                        Image(systemName: isConfigured ? "checkmark.seal.fill" : "key.fill")
                            .font(.system(size: 9))
                        Text(isConfigured ? "CONFIGURED" : "CONFIGURE")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(isConfigured ? settings.statusActive.opacity(0.7) : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(buttonBackground)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isConfigured ? settings.cardBorderReady : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(height: 170)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    settings.cardBackgroundDark
                    settings.cardBackground
                    LinearGradient(
                        colors: [Color.primary.opacity(0.03), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered ? Color.white.opacity(0.2) :
                        isConfigured ? settings.cardBorderActive : settings.cardBorderDefault,
                        lineWidth: isHovered ? 1.5 : 1
                    )
            )
            .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
            .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
            .opacity(isConfiguring ? 0 : 1)
            .rotation3DEffect(.degrees(isConfiguring ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .zIndex(isConfiguring ? 0 : 1)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isConfiguring)
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(settings.monoXS)
                .tracking(settings.trackingWide)
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(settings.monoBody)
                .foregroundColor(settings.specValueColor)
        }
        .frame(minWidth: 35)
    }
}

// MARK: - Whisper Model Card (Spec Sheet Style)

struct WhisperModelCard: View {
    let model: WhisperModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Float
    let isLoaded: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var modelCode: String {
        switch model {
        case .tiny: return "WSP-T"
        case .base: return "WSP-B"
        case .small: return "WSP-S"
        case .distilLargeV3: return "WSP-L3"
        }
    }

    private var tierLevel: String {
        switch model {
        case .tiny: return "I"
        case .base: return "II"
        case .small: return "III"
        case .distilLargeV3: return "IV"
        }
    }

    private var modelName: String {
        switch model {
        case .tiny: return "WHISPER TINY"
        case .base: return "WHISPER BASE"
        case .small: return "WHISPER SMALL"
        case .distilLargeV3: return "WHISPER LARGE V3"
        }
    }

    private var modelSize: String {
        switch model {
        case .tiny: return "39"
        case .base: return "74"
        case .small: return "244"
        case .distilLargeV3: return "756"
        }
    }

    private var rtfRatio: String {
        switch model {
        case .tiny: return "0.07"
        case .base: return "0.10"
        case .small: return "0.17"
        case .distilLargeV3: return "0.33"
        }
    }

    private var accuracy: String {
        switch model {
        case .tiny: return "72"
        case .base: return "81"
        case .small: return "88"
        case .distilLargeV3: return "95"
        }
    }

    private var accentColor: Color {
        if isLoaded { return .green }
        if isDownloaded { return .blue }
        return .primary
    }

    private var repoURL: URL {
        URL(string: "https://github.com/argmaxinc/WhisperKit")!
    }

    private var paperURL: URL {
        URL(string: "https://arxiv.org/abs/2212.04356")!  // Whisper paper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Tier badge
                Text("TIER \(tierLevel)")
                    .font(settings.monoXS)
                    .tracking(settings.trackingNormal)
                    .foregroundColor(settings.specLabelColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(2)

                Spacer()

                // Status indicator
                if isLoaded {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 6, height: 6)
                            .shadow(color: settings.statusActive.opacity(0.5), radius: 3)
                        Text("ACTIVE")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(settings.statusActive)
                    }
                } else if isDownloaded {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 6, height: 6)
                        Text("READY")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(settings.statusActive)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 8))
                        Text("AVAILABLE")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Model name
            Text(modelName)
                .font(.system(size: 12, weight: .semibold))
                .tracking(settings.trackingNormal)
                .foregroundColor(settings.specValueColor)
                .padding(.bottom, 6)

            // Links row
            HStack(spacing: 12) {
                Button(action: { NSWorkspace.shared.open(repoURL) }) {
                    HStack(spacing: 3) {
                        Text("Model")
                            .font(settings.monoXS)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { NSWorkspace.shared.open(paperURL) }) {
                    HStack(spacing: 3) {
                        Text("Paper")
                            .font(settings.monoXS)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(settings.specDividerOpacity))
                .frame(height: 1)
                .padding(.horizontal, -12)
                .padding(.bottom, 10)

            // Specs grid with visual separators
            HStack(spacing: 0) {
                specCell(label: "SIZE", value: modelSize, unit: "MB")

                Spacer()

                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(width: 1, height: 28)

                Spacer()

                specCell(label: "RTF", value: rtfRatio, unit: "x")

                Spacer()

                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(width: 1, height: 28)

                Spacer()

                specCell(label: "ACC", value: accuracy, unit: "%")
            }
            .padding(.bottom, 12)

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 6) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(settings.specDividerOpacity))
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.6), .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(downloadProgress))
                        }
                    }
                    .frame(height: 3)
                    .cornerRadius(1.5)

                    HStack {
                        Text("DOWNLOADING \(Int(downloadProgress * 100))%")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(.blue.opacity(0.8))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(settings.monoXS)
                                .tracking(settings.trackingNormal)
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if isDownloaded {
                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 9))
                        Text("REMOVE")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                        Text("DOWNLOAD")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(
                            colors: [Color.primary.opacity(0.06), Color.primary.opacity(settings.specDividerOpacity)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    )
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(height: 170)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground

                // Subtle gradient overlay for depth
                LinearGradient(
                    colors: [Color.primary.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? Color.white.opacity(0.2) :
                    isLoaded ? settings.cardBorderActive :
                    isDownloaded ? settings.cardBorderReady :
                    settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func specCell(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(settings.monoXS)
                .tracking(settings.trackingWide)
                .foregroundColor(settings.specLabelColor)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(settings.monoLarge)
                    .foregroundColor(settings.specValueColor)
                Text(unit)
                    .font(settings.monoSM)
                    .foregroundColor(settings.specUnitColor)
            }
        }
        .frame(minWidth: 40)
    }
}

// MARK: - Parakeet Model Card (Spec Sheet Style)

struct ParakeetModelCard: View {
    let model: ParakeetModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Float
    let isLoaded: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var modelCode: String {
        switch model {
        case .v2: return "PKT-V2"
        case .v3: return "PKT-V3"
        }
    }

    private var tierLevel: String {
        switch model {
        case .v2: return "EN"
        case .v3: return "ML"
        }
    }

    private var modelName: String {
        switch model {
        case .v2: return "PARAKEET V2"
        case .v3: return "PARAKEET V3"
        }
    }

    private var modelSize: String {
        switch model {
        case .v2: return "600"
        case .v3: return "600"
        }
    }

    private var rtfRatio: String {
        switch model {
        case .v2: return "0.05"
        case .v3: return "0.06"
        }
    }

    private var languages: String {
        switch model {
        case .v2: return "1"
        case .v3: return "25"
        }
    }

    private var repoURL: URL {
        URL(string: "https://github.com/FluidInference/FluidAudio")!
    }

    private var paperURL: URL {
        // Parakeet model paper
        URL(string: "https://arxiv.org/abs/2409.17143")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Tier badge (EN = English only, ML = Multilingual)
                Text("TIER \(tierLevel)")
                    .font(settings.monoXS)
                    .tracking(settings.trackingNormal)
                    .foregroundColor(settings.specLabelColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(2)

                Spacer()

                // Status indicator
                if isLoaded {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 6, height: 6)
                            .shadow(color: settings.statusActive.opacity(0.5), radius: 3)
                        Text("ACTIVE")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(settings.statusActive)
                    }
                } else if isDownloaded {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 6, height: 6)
                        Text("READY")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(settings.statusActive)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 8))
                        Text("AVAILABLE")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Model name
            Text(modelName)
                .font(.system(size: 12, weight: .semibold))
                .tracking(settings.trackingNormal)
                .foregroundColor(settings.specValueColor)
                .padding(.bottom, 6)

            // Links row
            HStack(spacing: 12) {
                Button(action: { NSWorkspace.shared.open(repoURL) }) {
                    HStack(spacing: 3) {
                        Text("Model")
                            .font(settings.monoXS)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { NSWorkspace.shared.open(paperURL) }) {
                    HStack(spacing: 3) {
                        Text("Paper")
                            .font(settings.monoXS)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(settings.specDividerOpacity))
                .frame(height: 1)
                .padding(.horizontal, -12)
                .padding(.bottom, 10)

            // Specs grid with visual separators
            HStack(spacing: 0) {
                specCell(label: "SIZE", value: modelSize, unit: "MB")

                Spacer()

                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(width: 1, height: 28)

                Spacer()

                specCell(label: "RTF", value: rtfRatio, unit: "x")

                Spacer()

                Rectangle()
                    .fill(Color.primary.opacity(settings.specDividerOpacity))
                    .frame(width: 1, height: 28)

                Spacer()

                specCell(label: "LANG", value: languages, unit: "")
            }
            .padding(.bottom, 12)

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 6) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(settings.specDividerOpacity))
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.6), .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(downloadProgress))
                        }
                    }
                    .frame(height: 3)
                    .cornerRadius(1.5)

                    HStack {
                        Text("DOWNLOADING \(Int(downloadProgress * 100))%")
                            .font(settings.monoXS)
                            .tracking(settings.trackingNormal)
                            .foregroundColor(.blue.opacity(0.8))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(settings.monoXS)
                                .tracking(settings.trackingNormal)
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if isDownloaded {
                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 9))
                        Text("REMOVE")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                        Text("DOWNLOAD")
                            .font(settings.monoSM)
                            .tracking(settings.trackingWide)
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(
                            colors: [Color.primary.opacity(0.06), Color.primary.opacity(settings.specDividerOpacity)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    )
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(height: 170)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground

                // Subtle gradient overlay for depth
                LinearGradient(
                    colors: [Color.primary.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? Color.white.opacity(0.2) :
                    isLoaded ? settings.cardBorderActive :
                    isDownloaded ? settings.cardBorderReady :
                    settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func specCell(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(settings.monoXS)
                .tracking(settings.trackingWide)
                .foregroundColor(settings.specLabelColor)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(settings.monoLarge)
                    .foregroundColor(settings.specValueColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(settings.monoSM)
                        .foregroundColor(settings.specUnitColor)
                }
            }
        }
        .frame(minWidth: 40)
    }
}

// MARK: - Expandable Model Family Card (New Design)

struct ExpandableModelFamilyCard: View {
    let family: ModelsContentView.ModelFamilyInfo
    let models: [LLMModel]
    let isExpanded: Bool
    let downloadingModelId: String?
    let downloadProgress: Double
    let onToggle: () -> Void
    let onDownload: (LLMModel) -> Void
    let onDelete: (LLMModel) -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var hasInstalledModel: Bool {
        models.contains { $0.isInstalled }
    }

    private var activeModel: LLMModel? {
        models.first { $0.isInstalled }
    }

    private func specValue(for prefix: String) -> (params: String, quant: String) {
        // Get from first model in family
        if let first = models.first, let def = MLXModelCatalog.model(byId: first.id) {
            return (def.size, def.quantization)
        }
        return ("—", "—")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Family icon placeholder
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.midnightSurfaceElevated)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(family.name.prefix(1)))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(settings.midnightTextSecondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(family.name.uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(settings.midnightTextPrimary)

                            if family.isRecommended {
                                Text("RECOMMENDED")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(settings.midnightBadgeRecommended)
                                    .foregroundColor(.black)
                                    .cornerRadius(3)
                            }
                        }
                        Text(family.provider)
                            .font(.system(size: 10))
                            .foregroundColor(settings.midnightTextTertiary)
                    }

                    Spacer()

                    // Description (truncated)
                    Text(family.description)
                        .font(.system(size: 11))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)

                    Spacer()

                    // Specs preview
                    HStack(spacing: 16) {
                        VStack(spacing: 1) {
                            Text("PARAMS")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValue(for: family.prefix).params)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }

                        VStack(spacing: 1) {
                            Text("QUANT")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValue(for: family.prefix).quant)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }
                    }

                    // Status
                    if hasInstalledModel {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.midnightStatusActive)
                                .frame(width: 6, height: 6)
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(settings.midnightStatusActive)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(settings.midnightStatusActive.opacity(0.15))
                        .cornerRadius(4)
                    } else {
                        Text("NOT INSTALLED")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(settings.midnightTextTertiary)
                    }

                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(settings.midnightTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Expanded content - variant table
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .background(settings.midnightBorder)
                        .padding(.horizontal, 16)

                    // Table header
                    HStack(spacing: 0) {
                        Text("VARIANT")
                            .frame(width: 140, alignment: .leading)
                        Text("SIZE")
                            .frame(width: 80, alignment: .leading)
                        Text("SPECS")
                            .frame(width: 60, alignment: .leading)
                        Text("FEATURES")
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("ACTION")
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // Table rows
                    ForEach(models, id: \.id) { model in
                        ModelVariantRow(
                            model: model,
                            isDownloading: downloadingModelId == model.id,
                            downloadProgress: downloadProgress,
                            onDownload: { onDownload(model) },
                            onDelete: { onDelete(model) }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded ? settings.midnightBorderActive : settings.midnightBorder,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Model Variant Row

struct ModelVariantRow: View {
    let model: LLMModel
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    private var catalogDef: MLXModelDefinition? {
        MLXModelCatalog.model(byId: model.id)
    }

    private var variantName: String {
        if model.id.contains("1B") && !model.id.contains("1.5B") { return "1B Instruct" }
        if model.id.contains("1.5B") { return "1.5B Instruct" }
        if model.id.contains("3B") { return "3B Instruct" }
        if model.id.contains("3.5") { return "3.5 Mini" }
        if model.id.contains("7B") { return "7B Instruct" }
        if model.id.contains("8B") { return "8B Instruct" }
        if model.id.contains("70B") { return "70B Instruct" }
        return model.displayName
    }

    private var variantSubtitle: String {
        if model.id.contains("1B") { return "Mobile friendly" }
        if model.id.contains("3B") || model.id.contains("3.5") { return "Entry level" }
        if model.id.contains("7B") || model.id.contains("8B") { return "Standard" }
        if model.id.contains("70B") { return "High capabilities" }
        return ""
    }

    var body: some View {
        HStack(spacing: 0) {
            // Variant name
            VStack(alignment: .leading, spacing: 1) {
                Text(variantName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(model.isInstalled ? settings.midnightStatusReady : settings.midnightTextPrimary)
                Text(variantSubtitle)
                    .font(.system(size: 9))
                    .foregroundColor(settings.midnightTextTertiary)
            }
            .frame(width: 140, alignment: .leading)

            // Size
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 9))
                    .foregroundColor(settings.midnightTextTertiary)
                Text(catalogDef?.diskSize ?? "—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextSecondary)
            }
            .frame(width: 80, alignment: .leading)

            // Specs
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                    .foregroundColor(settings.midnightTextTertiary)
                Text("—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextSecondary)
            }
            .frame(width: 60, alignment: .leading)

            // Features
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.system(size: 9))
                    .foregroundColor(settings.midnightTextTertiary)
                Text(catalogDef?.quantization ?? "4-bit")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(settings.midnightTextSecondary)
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            // Action
            if isDownloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(settings.midnightTextSecondary)
                }
                .frame(width: 100, alignment: .trailing)
            } else if model.isInstalled {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                    Text("READY")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(settings.midnightStatusReady)
                .frame(width: 100, alignment: .trailing)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Text("DOWNLOAD")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(settings.midnightTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(settings.midnightButtonPrimary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .frame(width: 100, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? settings.midnightSurfaceElevated : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Expandable STT Card

struct ExpandableSTTCard<Content: View>: View {
    let name: String
    let provider: String
    let description: String
    let isRecommended: Bool
    let isExpanded: Bool
    let isActive: Bool
    let hasInstalledModel: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    @StateObject private var settings = SettingsManager.shared

    private func specValues() -> (size: String, rtf: String) {
        if name == "Whisper" {
            return ("39MB", "0.07x")
        } else {
            return ("600MB", "0.05x")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Icon placeholder
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.midnightSurfaceElevated)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: name == "Whisper" ? "waveform" : "bolt.fill")
                                .font(.system(size: 14))
                                .foregroundColor(settings.midnightTextSecondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(name.uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(settings.midnightTextPrimary)

                            if isRecommended {
                                Text("RECOMMENDED")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(settings.midnightBadgeRecommended)
                                    .foregroundColor(.black)
                                    .cornerRadius(3)
                            }
                        }
                        Text(provider)
                            .font(.system(size: 10))
                            .foregroundColor(settings.midnightTextTertiary)
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Specs
                    HStack(spacing: 12) {
                        VStack(spacing: 1) {
                            Text("SIZE")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValues().size)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }

                        VStack(spacing: 1) {
                            Text("RTF")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(specValues().rtf)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextPrimary)
                        }
                    }

                    // Status
                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(settings.midnightStatusActive)
                                .frame(width: 6, height: 6)
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(settings.midnightStatusActive)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(settings.midnightStatusActive.opacity(0.15))
                        .cornerRadius(4)
                    } else if hasInstalledModel {
                        Text("READY")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(settings.midnightStatusReady)
                    } else {
                        Text("NOT INSTALLED")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(settings.midnightTextTertiary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(settings.midnightTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(settings.midnightBorder)
                    .padding(.horizontal, 16)
                content()
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded ? settings.midnightBorderActive : settings.midnightBorder,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Whisper Variant Table

struct WhisperVariantTable: View {
    let whisperService: WhisperService
    let downloadingModel: WhisperModel?
    let onDownload: (WhisperModel) -> Void
    let onDelete: (WhisperModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                let meta = WhisperModelCatalog.metadata(for: model)
                STTVariantRow(
                    name: meta?.displayName ?? model.rawValue,
                    size: "\(meta?.sizeMB ?? 0)MB",
                    accuracy: "\(meta?.accuracy ?? 0)%",
                    rtf: String(format: "%.2fx", meta?.rtf ?? 0),
                    isInstalled: whisperService.isModelDownloaded(model),
                    isActive: whisperService.loadedModel == model,
                    isDownloading: downloadingModel == model,
                    onDownload: { onDownload(model) },
                    onDelete: { onDelete(model) }
                )
            }
        }
    }
}

// MARK: - Parakeet Variant Table

struct ParakeetVariantTable: View {
    let parakeetService: ParakeetService
    let downloadingModel: ParakeetModel?
    let onDownload: (ParakeetModel) -> Void
    let onDelete: (ParakeetModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ParakeetModel.allCases, id: \.rawValue) { model in
                let meta = ParakeetModelCatalog.metadata(for: model)
                STTVariantRow(
                    name: meta?.displayName ?? model.rawValue,
                    size: "\(meta?.sizeMB ?? 0)MB",
                    accuracy: meta?.languagesBadge ?? "—",
                    rtf: String(format: "%.2fx", meta?.rtf ?? 0),
                    isInstalled: parakeetService.isModelDownloaded(model),
                    isActive: parakeetService.loadedModel == model,
                    isDownloading: downloadingModel == model,
                    onDownload: { onDownload(model) },
                    onDelete: { onDelete(model) }
                )
            }
        }
    }
}

// MARK: - STT Variant Row

struct STTVariantRow: View {
    let name: String
    let size: String
    let accuracy: String
    let rtf: String
    let isInstalled: Bool
    let isActive: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isInstalled ? settings.midnightStatusReady : settings.midnightTextPrimary)
                .frame(width: 60, alignment: .leading)

            Text(size)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.midnightTextSecondary)
                .frame(width: 60, alignment: .leading)

            Text(accuracy)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.midnightTextSecondary)
                .frame(width: 40, alignment: .leading)

            Text(rtf)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.midnightTextSecondary)
                .frame(width: 50, alignment: .leading)

            Spacer()

            if isDownloading {
                ProgressView()
                    .scaleEffect(0.6)
            } else if isInstalled {
                if isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.midnightStatusActive)
                            .frame(width: 5, height: 5)
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(settings.midnightStatusActive)
                    }
                } else {
                    Text("READY")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(settings.midnightStatusReady)
                }
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Text("DOWNLOAD")
                            .font(.system(size: 9, weight: .semibold))
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(settings.midnightTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(settings.midnightButtonPrimary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isHovered ? settings.midnightSurfaceElevated : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Compact Cloud Provider Row

struct CompactCloudProviderRow: View {
    let name: String
    let provider: String
    let description: String
    let contextSize: String
    let ttft: String
    let isConfigured: Bool
    let isRecommended: Bool
    let isExpanded: Bool
    @Binding var apiKeyBinding: String
    let onToggle: () -> Void
    let onSave: () -> Void

    @StateObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Provider icon
                    RoundedRectangle(cornerRadius: 6)
                        .fill(providerColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(name.prefix(1)))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(providerColor)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(name.uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(settings.midnightTextPrimary)

                            if isRecommended {
                                Text("RECOMMENDED")
                                    .font(.system(size: 7, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(settings.midnightBadgeRecommended)
                                    .foregroundColor(.black)
                                    .cornerRadius(2)
                            }
                        }
                        Text(provider)
                            .font(.system(size: 9))
                            .foregroundColor(settings.midnightTextTertiary)
                    }

                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Specs
                    HStack(spacing: 10) {
                        VStack(spacing: 0) {
                            Text("CTX")
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(contextSize)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextSecondary)
                        }

                        VStack(spacing: 0) {
                            Text("TTFT")
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.midnightTextTertiary)
                            Text(ttft)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(settings.midnightTextSecondary)
                        }
                    }

                    // Status
                    if isConfigured {
                        Text("CONFIGURED")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(settings.midnightStatusReady)
                    } else {
                        Text("NOT CONFIGURED")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(settings.midnightTextTertiary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(settings.midnightTextTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Expanded content - API key input
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(settings.midnightBorder)

                    Text("API KEY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(settings.midnightTextTertiary)

                    HStack(spacing: 8) {
                        SecureField("Enter API key...", text: $apiKeyBinding)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(settings.midnightSurfaceElevated)
                            .cornerRadius(4)

                        Button(action: onSave) {
                            Text("SAVE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(settings.midnightTextPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(settings.midnightButtonPrimary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isExpanded ? settings.midnightBorderActive : settings.midnightBorder, lineWidth: 1)
        )
    }

    private var providerColor: Color {
        switch name.lowercased() {
        case "openai": return .green
        case "anthropic": return .orange
        case "gemini": return .blue
        case "groq": return .red
        default: return .gray
        }
    }
}

// MARK: - Family Model Card (MLX) - Integrated Tabular Design (Legacy)

struct FamilyModelCard: View {
    let familyName: String
    let models: [LLMModel]
    let downloadingModelId: String?
    let downloadProgress: Double
    let onDownload: (LLMModel) -> Void
    let onDelete: (LLMModel) -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var selectedModelIndex: Int = 0
    @State private var hoveredModelIndex: Int? = nil
    @State private var isHovered = false

    private var displayedModelIndex: Int {
        hoveredModelIndex ?? selectedModelIndex
    }

    private var displayedModel: LLMModel? {
        guard displayedModelIndex < models.count else { return nil }
        return models[displayedModelIndex]
    }

    private var selectedModel: LLMModel? {
        guard selectedModelIndex < models.count else { return nil }
        return models[selectedModelIndex]
    }

    private var isDownloading: Bool {
        guard let model = selectedModel else { return false }
        return downloadingModelId == model.id
    }

    private var paperURL: URL? {
        // Get from catalog
        if let firstModel = models.first,
           let def = MLXModelCatalog.model(byId: firstModel.id) {
            return def.paperURL
        }
        return nil
    }

    private func variantLabel(for model: LLMModel) -> String {
        // Get from catalog
        if let def = MLXModelCatalog.model(byId: model.id) {
            return def.size
        }
        return "—"
    }

    private func diskSize(for model: LLMModel) -> String {
        // Get from catalog
        if let def = MLXModelCatalog.model(byId: model.id) {
            return def.diskSize
        }
        return "—"
    }

    private func quantization(for model: LLMModel) -> String {
        // Get from catalog
        if let def = MLXModelCatalog.model(byId: model.id) {
            return def.quantization
        }
        return "—"
    }

    private func huggingFaceURL(for model: LLMModel) -> URL? {
        if let def = MLXModelCatalog.model(byId: model.id) {
            return def.huggingFaceURL
        }
        return nil
    }

    private var hasInstalledModel: Bool {
        models.contains { $0.isInstalled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with family name and status
            HStack(alignment: .center) {
                Text(familyName.uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(settings.specValueColor)

                Spacer()

                if hasInstalledModel {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 7, height: 7)
                        Text("READY")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.statusActive)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Integrated Tab Bar
            HStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    ModelTab(
                        label: variantLabel(for: model),
                        isSelected: selectedModelIndex == index,
                        isHovered: hoveredModelIndex == index,
                        isInstalled: model.isInstalled,
                        onTap: { selectedModelIndex = index },
                        onHover: { isHovering in
                            hoveredModelIndex = isHovering ? index : nil
                        }
                    )
                }
                Spacer()
            }

            // Specs area (connected to tabs)
            VStack(spacing: 0) {
                // Top border connects to active tab
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                if let model = displayedModel {
                    HStack(spacing: 16) {
                        specCell(label: "PARAMS", value: variantLabel(for: model))
                        specCell(label: "SIZE", value: diskSize(for: model))
                        specCell(label: "QUANT", value: quantization(for: model))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .animation(.easeInOut(duration: 0.15), value: displayedModelIndex)
                }
            }
            .background(Color.primary.opacity(0.02))
            .cornerRadius(0)

            // Links row
            HStack(spacing: 16) {
                if let model = displayedModel, let url = huggingFaceURL(for: model) {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 4) {
                            Text("Model")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                if let url = paperURL {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 4) {
                            Text("Paper")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer()

            // Action button
            if let model = selectedModel {
                if isDownloading {
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                Rectangle()
                                    .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * CGFloat(downloadProgress))
                            }
                        }
                        .frame(height: 4)
                        .cornerRadius(2)

                        HStack {
                            Text("DOWNLOADING \(Int(downloadProgress * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.blue.opacity(0.9))
                            Spacer()
                            Button(action: onCancel) {
                                Text("CANCEL")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(settings.statusError)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if model.isInstalled {
                    Button(action: { onDelete(model) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11))
                            Text("REMOVE")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { onDownload(model) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12))
                            Text("DOWNLOAD")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                            AnyView(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        )
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: 200)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground
                LinearGradient(colors: [Color.primary.opacity(0.03), Color.clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered ? Color.white.opacity(0.2) :
                    hasInstalledModel ? settings.cardBorderActive : settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if let idx = models.firstIndex(where: { $0.isInstalled }) {
                selectedModelIndex = idx
            }
        }
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(settings.specValueColor)
        }
    }
}

// MARK: - Model Tab Component

struct ModelTab: View {
    let label: String
    let isSelected: Bool
    let isHovered: Bool
    let isInstalled: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    @StateObject private var settings = SettingsManager.shared

    private var isActive: Bool { isSelected || isHovered }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium, design: .monospaced))

                if isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(settings.statusActive)
                }
            }
            .foregroundColor(
                isActive ? (isInstalled ? settings.statusActive : settings.specValueColor) :
                (isInstalled ? settings.statusActive.opacity(0.7) : .secondary.opacity(0.6))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isActive ? Color.primary.opacity(0.06) : Color.clear
            )
            .overlay(
                Rectangle()
                    .fill(isSelected ? settings.statusActive : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
    }
}

// MARK: - Whisper Family Card - Integrated Tabular Design

struct WhisperFamilyCard: View {
    let models: [WhisperModel]
    let whisperService: WhisperService
    let downloadingModel: WhisperModel?
    let onDownload: (WhisperModel) -> Void
    let onDelete: (WhisperModel) -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var selectedModelIndex: Int = 0
    @State private var hoveredModelIndex: Int? = nil
    @State private var isHovered = false

    private var displayedModelIndex: Int {
        hoveredModelIndex ?? selectedModelIndex
    }

    private var displayedModel: WhisperModel {
        guard displayedModelIndex < models.count else { return models[0] }
        return models[displayedModelIndex]
    }

    private var selectedModel: WhisperModel {
        guard selectedModelIndex < models.count else { return models[0] }
        return models[selectedModelIndex]
    }

    private var isDownloading: Bool {
        downloadingModel == selectedModel
    }

    private var hasInstalledModel: Bool {
        models.contains { whisperService.isModelDownloaded($0) }
    }

    private func variantLabel(for model: WhisperModel) -> String {
        WhisperModelCatalog.metadata(for: model)?.displayName ?? "—"
    }

    private func accuracy(for model: WhisperModel) -> String {
        guard let meta = WhisperModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.accuracy)%"
    }

    private func modelSize(for model: WhisperModel) -> String {
        guard let meta = WhisperModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.sizeMB)MB"
    }

    private func rtf(for model: WhisperModel) -> String {
        guard let meta = WhisperModelCatalog.metadata(for: model) else { return "—" }
        return String(format: "%.2fx", meta.rtf)
    }

    private var repoURL: URL { WhisperModelCatalog.repoURL }
    private var paperURL: URL { WhisperModelCatalog.paperURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .center) {
                Text("WHISPER")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(settings.specValueColor)

                Spacer()

                if hasInstalledModel {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 7, height: 7)
                        Text("READY")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.statusActive)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Integrated Tab Bar
            HStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.rawValue) { index, model in
                    STTModelTab(
                        label: variantLabel(for: model),
                        badge: accuracy(for: model),
                        isSelected: selectedModelIndex == index,
                        isHovered: hoveredModelIndex == index,
                        isInstalled: whisperService.isModelDownloaded(model),
                        isActive: whisperService.loadedModel == model,
                        onTap: { selectedModelIndex = index },
                        onHover: { isHovering in
                            hoveredModelIndex = isHovering ? index : nil
                        }
                    )
                }
                Spacer()
            }

            // Specs area (connected to tabs)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 16) {
                    specCell(label: "SIZE", value: modelSize(for: displayedModel))
                    specCell(label: "RTF", value: rtf(for: displayedModel))
                    specCell(label: "ACC", value: accuracy(for: displayedModel))
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .animation(.easeInOut(duration: 0.15), value: displayedModelIndex)
            }
            .background(Color.primary.opacity(0.02))

            // Links row
            HStack(spacing: 16) {
                Button(action: { NSWorkspace.shared.open(repoURL) }) {
                    HStack(spacing: 4) {
                        Text("Repo")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { NSWorkspace.shared.open(paperURL) }) {
                    HStack(spacing: 4) {
                        Text("Paper")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                            Rectangle()
                                .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(whisperService.downloadProgress))
                        }
                    }
                    .frame(height: 4)
                    .cornerRadius(2)

                    HStack {
                        Text("DOWNLOADING \(Int(whisperService.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.9))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if whisperService.isModelDownloaded(selectedModel) {
                Button(action: { onDelete(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                        Text("REMOVE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onDownload(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("DOWNLOAD")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    )
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: 210)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground
                LinearGradient(colors: [Color.primary.opacity(0.03), Color.clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered ? Color.white.opacity(0.2) :
                    hasInstalledModel ? settings.cardBorderActive : settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if let idx = models.firstIndex(where: { whisperService.isModelDownloaded($0) }) {
                selectedModelIndex = idx
            }
        }
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(settings.specValueColor)
        }
    }
}

// MARK: - Parakeet Family Card - Integrated Tabular Design

struct ParakeetFamilyCard: View {
    let models: [ParakeetModel]
    let parakeetService: ParakeetService
    let downloadingModel: ParakeetModel?
    let onDownload: (ParakeetModel) -> Void
    let onDelete: (ParakeetModel) -> Void
    let onCancel: () -> Void

    @StateObject private var settings = SettingsManager.shared
    @State private var selectedModelIndex: Int = 0
    @State private var hoveredModelIndex: Int? = nil
    @State private var isHovered = false

    private var displayedModelIndex: Int {
        hoveredModelIndex ?? selectedModelIndex
    }

    private var displayedModel: ParakeetModel {
        guard displayedModelIndex < models.count else { return models[0] }
        return models[displayedModelIndex]
    }

    private var selectedModel: ParakeetModel {
        guard selectedModelIndex < models.count else { return models[0] }
        return models[selectedModelIndex]
    }

    private var isDownloading: Bool {
        downloadingModel == selectedModel
    }

    private var hasInstalledModel: Bool {
        models.contains { parakeetService.isModelDownloaded($0) }
    }

    private func variantLabel(for model: ParakeetModel) -> String {
        ParakeetModelCatalog.metadata(for: model)?.displayName ?? "—"
    }

    private func languagesBadge(for model: ParakeetModel) -> String {
        ParakeetModelCatalog.metadata(for: model)?.languagesBadge ?? "—"
    }

    private func languagesCount(for model: ParakeetModel) -> String {
        guard let meta = ParakeetModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.languages)"
    }

    private func modelSize(for model: ParakeetModel) -> String {
        guard let meta = ParakeetModelCatalog.metadata(for: model) else { return "—" }
        return "\(meta.sizeMB)MB"
    }

    private func rtf(for model: ParakeetModel) -> String {
        guard let meta = ParakeetModelCatalog.metadata(for: model) else { return "—" }
        return String(format: "%.2fx", meta.rtf)
    }

    private var repoURL: URL { ParakeetModelCatalog.repoURL }
    private var paperURL: URL { ParakeetModelCatalog.paperURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .center) {
                Text("PARAKEET")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(0.5)
                    .foregroundColor(settings.specValueColor)

                Spacer()

                if hasInstalledModel {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 7, height: 7)
                        Text("READY")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.statusActive)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Integrated Tab Bar
            HStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.rawValue) { index, model in
                    STTModelTab(
                        label: variantLabel(for: model),
                        badge: languagesBadge(for: model),
                        isSelected: selectedModelIndex == index,
                        isHovered: hoveredModelIndex == index,
                        isInstalled: parakeetService.isModelDownloaded(model),
                        isActive: parakeetService.loadedModel == model,
                        onTap: { selectedModelIndex = index },
                        onHover: { isHovering in
                            hoveredModelIndex = isHovering ? index : nil
                        }
                    )
                }
                Spacer()
            }

            // Specs area (connected to tabs)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 16) {
                    specCell(label: "SIZE", value: "~600MB")
                    specCell(label: "RTF", value: "0.05x")
                    specCell(label: "LANG", value: languagesCount(for: displayedModel))
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .animation(.easeInOut(duration: 0.15), value: displayedModelIndex)
            }
            .background(Color.primary.opacity(0.02))

            // Links row
            HStack(spacing: 16) {
                Button(action: { NSWorkspace.shared.open(repoURL) }) {
                    HStack(spacing: 4) {
                        Text("Repo")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: { NSWorkspace.shared.open(paperURL) }) {
                    HStack(spacing: 4) {
                        Text("Paper")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                            Rectangle()
                                .fill(LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(parakeetService.downloadProgress))
                        }
                    }
                    .frame(height: 4)
                    .cornerRadius(2)

                    HStack {
                        Text("DOWNLOADING \(Int(parakeetService.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.9))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(settings.statusError)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if parakeetService.isModelDownloaded(selectedModel) {
                Button(action: { onDelete(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                        Text("REMOVE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onDownload(selectedModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("DOWNLOAD")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(isHovered ? .accentColor : settings.specValueColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isHovered ? AnyView(Color.accentColor.opacity(0.1)) :
                        AnyView(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    )
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? Color.accentColor.opacity(0.3) : settings.cardBorderDefault, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: 210)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                settings.cardBackgroundDark
                settings.cardBackground
                LinearGradient(colors: [Color.primary.opacity(0.03), Color.clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHovered ? Color.white.opacity(0.2) :
                    hasInstalledModel ? settings.cardBorderActive : settings.cardBorderDefault,
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(color: Color.white.opacity(isHovered ? 0.06 : 0), radius: 8, x: 0, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if let idx = models.firstIndex(where: { parakeetService.isModelDownloaded($0) }) {
                selectedModelIndex = idx
            }
        }
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(settings.specLabelColor)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(settings.specValueColor)
        }
    }
}

// MARK: - STT Model Tab Component

struct STTModelTab: View {
    let label: String
    let badge: String
    let isSelected: Bool
    let isHovered: Bool
    let isInstalled: Bool
    let isActive: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    @StateObject private var settings = SettingsManager.shared

    private var isActiveState: Bool { isSelected || isHovered }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 12, weight: isActiveState ? .semibold : .medium, design: .monospaced))

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(isActive ? settings.statusActive : settings.statusActive.opacity(0.8))
                    }
                }

                Text(badge)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .foregroundColor(
                isActive ? settings.statusActive :
                isActiveState ? (isInstalled ? settings.statusActive : settings.specValueColor) :
                (isInstalled ? settings.statusActive.opacity(0.7) : .secondary.opacity(0.6))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isActiveState ? Color.primary.opacity(0.06) : Color.clear
            )
            .overlay(
                Rectangle()
                    .fill(isSelected ? settings.statusActive : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
    }
}
