//
//  CloudProviderViews.swift
//  Talkie macOS
//
//  Extracted from ModelsContentView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Expandable Cloud Provider Card (Showcase Style)

struct ExpandableCloudProviderCard: View {
    let providerId: String  // "openai", "anthropic", "gemini", "groq"
    let name: String
    let tagline: String
    let isConfigured: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onConfigure: () -> Void  // Deep link to Settings

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    /// Models from centralized LLMConfig.json
    private var models: [LLMConfig.ModelConfig] {
        LLMConfig.shared.config(for: providerId)?.models ?? []
    }

    /// Default model ID for this provider
    private var defaultModelId: String? {
        LLMConfig.shared.config(for: providerId)?.defaultModel
    }

    /// Provider metadata (taglines, URLs)
    private var metadata: CloudProviderMetadata.Info? {
        CloudProviderMetadata.info(for: providerId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Provider icon
                    RoundedRectangle(cornerRadius: 6)
                        .fill(providerColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(name.prefix(1)))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(providerColor)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(settings.midnightTextPrimary)
                        Text("\(models.count) models")
                            .font(.system(size: 10))
                            .foregroundColor(settings.midnightTextTertiary)
                    }
                    .frame(width: 85, alignment: .leading)

                    Text(tagline)
                        .font(.system(size: 11))
                        .foregroundColor(settings.midnightTextSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Status pill
                    Group {
                        if isConfigured {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(settings.midnightStatusReady)
                                    .frame(width: 6, height: 6)
                                Text("READY")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(settings.midnightStatusReady)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(settings.midnightStatusReady.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(settings.midnightStatusReady.opacity(0.25), lineWidth: 1))
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 70, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(settings.midnightTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.expandableRow)

            // Expanded content - model showcase
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .background(settings.midnightBorder)
                        .padding(.horizontal, 16)

                    // Model rows
                    ForEach(models, id: \.id) { model in
                        CloudModelRow(
                            model: model,
                            isDefault: model.id == defaultModelId,
                            isConfigured: isConfigured,
                            providerColor: providerColor
                        )
                    }

                    // Footer with links and configure button
                    HStack {
                        // Links from CloudProviderMetadata
                        if let docsURL = metadata?.docsURL {
                            Button(action: { NSWorkspace.shared.open(docsURL) }) {
                                HStack(spacing: 4) {
                                    Text("Docs")
                                        .font(.system(size: 10))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(settings.midnightTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        if let pricingURL = metadata?.pricingURL {
                            Button(action: { NSWorkspace.shared.open(pricingURL) }) {
                                HStack(spacing: 4) {
                                    Text("Pricing")
                                        .font(.system(size: 10))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(settings.midnightTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Configure button
                        if !isConfigured {
                            Button(action: onConfigure) {
                                HStack(spacing: 4) {
                                    Image(systemName: "key")
                                        .font(.system(size: 9))
                                    Text("Configure")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(settings.midnightTextSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(settings.midnightButtonPrimary)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? settings.midnightSurfaceHover : settings.midnightSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded ? settings.midnightBorderActive : (isHovered ? settings.midnightBorderActive : settings.midnightBorder),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .fixedSize(horizontal: false, vertical: true)  // Don't stretch in grid rows
    }

    private var providerColor: Color {
        switch providerId {
        case "openai": return .green
        case "anthropic": return .orange
        case "gemini": return .blue
        case "groq": return .red
        default: return .gray
        }
    }
}

// MARK: - Cloud Model Row

struct CloudModelRow: View {
    let model: LLMConfig.ModelConfig
    let isDefault: Bool
    let isConfigured: Bool
    let providerColor: Color

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Model name column - fixed width for table alignment
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(settings.midnightTextPrimary)

                if isDefault {
                    Text("★")
                        .font(.system(size: 9))
                        .foregroundColor(providerColor)
                }
            }
            .frame(width: 140, alignment: .leading)

            // Description column - fills remaining space
            if let description = model.description {
                Text("·")
                    .foregroundColor(settings.midnightTextTertiary)
                    .padding(.trailing, 8)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(settings.midnightTextTertiary)
                    .lineLimit(1)
            }

            Spacer()
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

// MARK: - Legacy Compact Cloud Provider Row (kept for reference)

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

    private let settings = SettingsManager.shared

    var body: some View {
        EmptyView()  // Deprecated - use ExpandableCloudProviderCard instead
    }
}
