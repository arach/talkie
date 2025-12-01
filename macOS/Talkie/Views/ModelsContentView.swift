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
    @State private var selectedProviderId: String = "gemini"
    @State private var downloadingModelId: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("MODELS & INTELLIGENCE")
                        .font(settingsManager.fontBodyBold)
                        .tracking(2)
                        .foregroundColor(.primary)

                    Text("Manage AI providers and local models")
                        .font(settingsManager.fontSM)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Divider()

                // Cloud Providers Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("☁️ CLOUD PROVIDERS")
                        .font(settingsManager.fontSMBold)
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)

                    cloudProvidersSection
                }

                Divider()

                // Local Providers Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("💻 LOCAL PROVIDERS")
                        .font(settingsManager.fontSMBold)
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)

                    localProvidersSection
                }

                Spacer()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
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

    // MARK: - Local Providers

    @State private var downloadingLocalModelId: String?

    private var localProvidersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if arch(arm64)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(registry.allModels.filter { $0.provider == "mlx" }) { model in
                    CompactModelCard(
                        model: model,
                        isDownloading: downloadingModelId == model.id,
                        downloadProgress: downloadProgress,
                        onDownload: { downloadModel(model) },
                        onDelete: { deleteModel(model) },
                        onCancel: { cancelDownload() }
                    )
                }
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("MLX requires Apple Silicon (M1/M2/M3)")
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
                print("✅ Downloaded model: \(model.displayName)")
            } catch is CancellationError {
                downloadingModelId = nil
                downloadTask = nil
                print("⏸️ Download cancelled")
            } catch {
                downloadingModelId = nil
                downloadTask = nil
                print("❌ Failed to download model: \(error)")
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
                print("🗑️ Deleted model: \(model.displayName)")
            } catch {
                print("❌ Failed to delete model: \(error)")
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
        .background(Color(NSColor.controlBackgroundColor))
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
        .background(Color(NSColor.textBackgroundColor))
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

// MARK: - Compact Model Card

struct CompactModelCard: View {
    let model: LLMModel
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var modelHighlight: String {
        switch model.id {
        case "mlx-community/Llama-3.2-1B-Instruct-4bit":
            return "1B • ~700MB"
        case "mlx-community/Qwen2.5-1.5B-Instruct-4bit":
            return "1.5B • ~1GB"
        case "mlx-community/Qwen2.5-3B-Instruct-4bit":
            return "3B • ~2GB"
        case "mlx-community/Qwen2.5-7B-Instruct-4bit":
            return "7B • ~4GB"
        case "mlx-community/Llama-3.2-3B-Instruct-4bit":
            return "3B • ~2GB"
        case "mlx-community/gemma-2-9b-it-4bit":
            return "9B • ~5GB"
        default:
            return model.size
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon + Name
            HStack(spacing: 8) {
                Image(systemName: model.isInstalled ? "checkmark.circle.fill" : "cpu")
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(model.isInstalled ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(SettingsManager.shared.fontXS)
                        .lineLimit(1)

                    Text(modelHighlight)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Spacer()

            // Action button
            if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: downloadProgress)
                    HStack {
                        Text("\(Int(downloadProgress * 100))%")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(SettingsManager.shared.fontXS)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.orange)
                    }
                }
            } else if model.isInstalled {
                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(SettingsManager.shared.fontXS)
                        Text("Delete")
                            .font(SettingsManager.shared.fontXS)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(SettingsManager.shared.fontXS)
                        Text("Download")
                            .font(SettingsManager.shared.fontXS)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(height: 90)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Compact Provider Card

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

    var body: some View {
        ZStack {
            // Back side - Configuration
            VStack(alignment: .leading, spacing: 8) {
                Text("Configure \(name)")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.primary)

                SecureField("API Key", text: apiKeyBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(SettingsManager.shared.fontXS)
                    .controlSize(.small)

                HStack(spacing: 6) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Save") { onSave() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(10)
            .frame(height: 90)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
            .opacity(isConfiguring ? 1 : 0)
            .rotation3DEffect(.degrees(isConfiguring ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            .zIndex(isConfiguring ? 1 : 0)

            // Front side - Provider info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(isConfigured ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(SettingsManager.shared.fontXS)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(isConfigured ? Color.green : Color.orange)
                                .frame(width: 5, height: 5)

                            Text(isConfigured ? "ACTIVE" : "SETUP")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(0.3)
                                .foregroundColor(isConfigured ? .green : .orange)
                        }
                    }
                    Spacer()
                }

                Spacer()

                Button(action: onConfigure) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(SettingsManager.shared.fontXS)
                        Text("Configure")
                            .font(SettingsManager.shared.fontXS)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .frame(height: 90)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .opacity(isConfiguring ? 0 : 1)
            .rotation3DEffect(.degrees(isConfiguring ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .zIndex(isConfiguring ? 0 : 1)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isConfiguring)
    }
}
