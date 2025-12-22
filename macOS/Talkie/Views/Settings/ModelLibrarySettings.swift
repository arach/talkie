//
//  ModelLibrarySettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Model Library View
struct ModelLibraryView: View {
    @State var settingsManager = SettingsManager.shared

    let models: [(model: AIModel, installed: Bool)] = [
        (.geminiFlash, true),
        (.geminiPro, false)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .font(SettingsManager.shared.fontTitle)
                        Text("MODEL LIBRARY")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.primary)

                    Text("Manage the AI models available for your workflows. Download models to enable them in the Workflow Builder.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Models
                VStack(spacing: 16) {
                    ForEach(models, id: \.model.rawValue) { item in
                        ModelCard(model: item.model, installed: item.installed)
                    }
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsManager.surfaceInput)
    }
}

// MARK: - Model Card
struct ModelCard: View {
    let model: AIModel
    let installed: Bool
    private let settings = SettingsManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            Image(systemName: "sparkles")
                .font(SettingsManager.shared.fontHeadline)
                .foregroundColor(installed ? settings.resolvedAccentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(Theme.current.surface1)
                .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(model.badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model == .geminiPro ? Color.purple : settings.resolvedAccentColor)
                        .cornerRadius(4)
                }

                Text(model.description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("ID: \(model.rawValue)")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            // Status/Action
            if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.green)
                    Text("INSTALLED")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.green)
                }
            } else {
                Button(action: {}) {
                    Text("DOWNLOAD")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(settings.resolvedAccentColor)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }
}

