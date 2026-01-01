//
//  ModelStatusBadge.swift
//  Talkie
//
//  Status badge for AI models (STT and TTS).
//  Shows clear visual distinction between downloaded, loaded, and active states.
//

import SwiftUI
import TalkieKit

// MARK: - Model Status Badge

/// Visual status indicator for model lifecycle states
struct ModelStatusBadge: View {
    let state: ModelState
    let isActive: Bool

    private let settings = SettingsManager.shared

    init(state: ModelState, isActive: Bool = false) {
        self.state = state
        self.isActive = isActive
    }

    var body: some View {
        if let content = badgeContent {
            HStack(spacing: 4) {
                Circle()
                    .fill(content.color)
                    .frame(width: 5, height: 5)
                    .shadow(color: content.color.opacity(0.5), radius: content.glow ? 3 : 0)

                Text(content.text)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(content.color)
            }
        }
    }

    private var badgeContent: (text: String, color: Color, glow: Bool)? {
        if isActive {
            return ("ACTIVE", settings.midnightStatusActive, true)
        }

        switch state {
        case .loaded:
            return ("LOADED", settings.midnightStatusActive, true)
        case .downloaded:
            return ("READY", settings.midnightStatusReady, false)
        case .loading:
            return ("LOADING", .orange, false)
        case .downloading, .notDownloaded:
            return nil
        }
    }
}

// MARK: - Memory Badge

/// Shows memory usage for loaded models
struct MemoryBadge: View {
    let memoryMB: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "memorychip")
                .font(.system(size: 8))
            Text(formattedMemory)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
        }
        .foregroundColor(Theme.current.foregroundMuted)
    }

    private var formattedMemory: String {
        if memoryMB >= 1000 {
            return String(format: "%.1f GB", Double(memoryMB) / 1000)
        }
        return "\(memoryMB) MB"
    }
}

// MARK: - Provider Badge

/// Shows provider/family badge with accent color
struct ProviderBadge: View {
    let provider: ModelProvider

    var body: some View {
        Text(provider.badge)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(ModelAccentColor.color(for: provider))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(ModelAccentColor.color(for: provider).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Speed Tier Badge

/// Shows speed tier for STT models
struct SpeedTierBadge: View {
    let tier: STTSpeedTier

    var body: some View {
        Text(tier.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tier.color)
    }
}

// MARK: - Local/Cloud Badge

/// Shows whether a model is local or cloud-based
struct LocalCloudBadge: View {
    let isLocal: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isLocal ? "desktopcomputer" : "cloud")
                .font(.system(size: 8))
            Text(isLocal ? "LOCAL" : "CLOUD")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
        }
        .foregroundColor(isLocal ? .green : .blue)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background((isLocal ? Color.green : Color.blue).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Preview

#Preview("Model Status Badges") {
    VStack(alignment: .leading, spacing: 16) {
        Group {
            Text("Status Badges").font(.headline)

            HStack(spacing: 16) {
                VStack {
                    ModelStatusBadge(state: .loaded, isActive: true)
                    Text("Active").font(.caption)
                }
                VStack {
                    ModelStatusBadge(state: .loaded)
                    Text("Loaded").font(.caption)
                }
                VStack {
                    ModelStatusBadge(state: .downloaded)
                    Text("Ready").font(.caption)
                }
                VStack {
                    ModelStatusBadge(state: .loading)
                    Text("Loading").font(.caption)
                }
            }
        }

        Group {
            Text("Provider Badges").font(.headline)

            HStack(spacing: 8) {
                ProviderBadge(provider: .whisper)
                ProviderBadge(provider: .parakeet)
                ProviderBadge(provider: .kokoro)
                ProviderBadge(provider: .elevenLabs)
            }
        }

        Group {
            Text("Memory Badge").font(.headline)

            HStack(spacing: 16) {
                MemoryBadge(memoryMB: 500)
                MemoryBadge(memoryMB: 800)
                MemoryBadge(memoryMB: 1500)
            }
        }

        Group {
            Text("Local/Cloud").font(.headline)

            HStack(spacing: 8) {
                LocalCloudBadge(isLocal: true)
                LocalCloudBadge(isLocal: false)
            }
        }
    }
    .padding(24)
    .background(Color(white: 0.1))
    .frame(width: 400)
}
