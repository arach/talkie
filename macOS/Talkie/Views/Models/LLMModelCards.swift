//
//  LLMModelCards.swift
//  Talkie macOS
//
//  Extracted from ModelsContentView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

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

