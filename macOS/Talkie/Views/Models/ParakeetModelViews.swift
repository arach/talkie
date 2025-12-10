//
//  ParakeetModelViews.swift
//  Talkie macOS
//
//  Extracted from ModelsContentView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

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
                            .foregroundColor(settings.statusActive)
                    }
                } else if isDownloaded {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(settings.statusActive)
                            .frame(width: 6, height: 6)
                        Text("READY")
                            .font(settings.monoXS)
                            .foregroundColor(settings.statusActive)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 8))
                        Text("AVAILABLE")
                            .font(settings.monoXS)
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Model name
            Text(modelName)
                .font(.system(size: 12, weight: .semibold))
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
                            .foregroundColor(.blue.opacity(0.8))
                        Spacer()
                        Button(action: onCancel) {
                            Text("CANCEL")
                                .font(settings.monoXS)
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

