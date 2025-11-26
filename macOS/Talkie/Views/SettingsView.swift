//
//  SettingsView.swift
//  Talkie macOS
//
//  Settings and workflow management UI (inspired by EchoFlow)
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("TOOLS") {
                    NavigationLink(destination: WorkflowsView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                            Text("Workflows")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }

                    NavigationLink(destination: ActivityLogView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.system(size: 11))
                            Text("Activity Log")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }
                }

                Section("CONFIGURATION") {
                    NavigationLink(destination: ModelLibraryView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.system(size: 11))
                            Text("Model Library")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }

                    NavigationLink(destination: APISettingsView(settingsManager: settingsManager)) {
                        HStack(spacing: 8) {
                            Image(systemName: "key")
                                .font(.system(size: 11))
                            Text("API Settings")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            // Default detail view
            VStack(spacing: 20) {
                Image(systemName: "gear")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("SELECT A SETTING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }
}

// MARK: - API Settings View
struct APISettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "key")
                            .font(.system(size: 16))
                        Text("API SETTINGS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Configure your Gemini API key for workflow execution.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // API Key Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("GEMINI API KEY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        SecureField("AIzaSy...", text: $apiKeyInput)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)

                        Button(action: saveAPIKey) {
                            Text(settingsManager.hasValidApiKey ? "UPDATE" : "SAVE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    if settingsManager.hasValidApiKey {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text("API KEY CONFIGURED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.green)
                        }
                    }

                    Text("Get your API key from https://makersuite.google.com/app/apikey")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("STATUS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("API Key:")
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text(settingsManager.hasValidApiKey ? "Configured" : "Not Set")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(settingsManager.hasValidApiKey ? .green : .orange)
                    }

                    HStack {
                        Text("Selected Model:")
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text(settingsManager.selectedModel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            apiKeyInput = settingsManager.geminiApiKey
        }
        .alert("API Key Saved", isPresented: $showingSaveConfirmation) {
            Button("OK") {}
        } message: {
            Text("Your Gemini API key has been saved successfully.")
        }
    }

    private func saveAPIKey() {
        settingsManager.geminiApiKey = apiKeyInput
        settingsManager.saveSettings()
        showingSaveConfirmation = true
    }
}

// MARK: - Model Library View
struct ModelLibraryView: View {
    @ObservedObject var settingsManager = SettingsManager.shared

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
                            .font(.system(size: 16))
                        Text("MODEL LIBRARY")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
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
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Model Card
struct ModelCard: View {
    let model: AIModel
    let installed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundColor(installed ? .blue : .secondary)
                .frame(width: 32, height: 32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(model.badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model == .geminiPro ? Color.purple : Color.blue)
                        .cornerRadius(4)
                }

                Text(model.description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("ID: \(model.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            // Status/Action
            if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("INSTALLED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.green)
                }
            } else {
                Button(action: {}) {
                    Text("DOWNLOAD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Workflows View
struct WorkflowsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                        Text("WORKFLOWS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Manage and customize your workflow actions.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Workflow builder and customization")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Activity Log View
struct ActivityLogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 16))
                        Text("ACTIVITY LOG")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("View workflow execution history.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Activity log and execution history")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}
