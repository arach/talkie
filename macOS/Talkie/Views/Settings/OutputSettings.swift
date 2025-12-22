//
//  OutputSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Output Settings View

struct OutputSettingsView: View {
    @State private var outputDirectory: String = SaveFileStepConfig.defaultOutputDirectory
    @State private var showingFolderPicker = false
    @State private var statusMessage: String?

    // Path aliases
    @State private var pathAliases: [String: String] = SaveFileStepConfig.pathAliases
    @State private var newAliasName: String = ""
    @State private var newAliasPath: String = ""
    @State private var showingAliasFolderPicker = false
    private let settings = SettingsManager.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.down.doc",
                title: "OUTPUT",
                subtitle: "Configure default output location and path aliases for workflows."
            )
        } content: {
            // MARK: - Default Output Folder Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("DEFAULT OUTPUT FOLDER")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("~/Documents/Talkie", text: $outputDirectory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                        Button(action: { showingFolderPicker = true }) {
                            Image(systemName: "folder")
                                .font(Theme.current.fontSM)
                        }
                        .buttonStyle(.bordered)
                        .help("Browse for folder")

                        Button(action: saveDirectory) {
                            Text("Save")
                                .font(Theme.current.fontXSMedium)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Current value display
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(Theme.current.fontXS)
                            .foregroundColor(settings.resolvedAccentColor)
                        Text(SaveFileStepConfig.defaultOutputDirectory)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        if let message = statusMessage {
                            HStack(spacing: 4) {
                                Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(message.contains("✓") ? .green : .orange)
                                Text(message)
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(message.contains("✓") ? .green : .orange)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.current.surface1)
                    .cornerRadius(6)

                    // Quick actions row
                    HStack(spacing: 8) {
                        Button(action: openInFinder) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("Open in Finder")
                            }
                            .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.bordered)

                        Button(action: createDirectory) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                Text("Create Folder")
                            }
                            .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.bordered)

                        Button(action: resetToDefault) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Path Aliases Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("PATH ALIASES")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !pathAliases.isEmpty {
                        Text("\(pathAliases.count) DEFINED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.8))
                    }
                }

                Text("Define shortcuts like @Obsidian, @Notes to use in file paths")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.secondary.opacity(0.8))

                // Existing aliases
                if !pathAliases.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(pathAliases.sorted(by: { $0.key < $1.key }), id: \.key) { alias, path in
                            HStack(spacing: 12) {
                                // Alias name with icon
                                HStack(spacing: 4) {
                                    Image(systemName: "at")
                                        .font(.system(size: 10))
                                        .foregroundColor(.purple)
                                    Text(alias)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                                .frame(width: 100, alignment: .leading)

                                // Arrow
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.5))

                                // Path
                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                // Delete button
                                Button(action: { removeAlias(alias) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Theme.current.surface1)
                            .cornerRadius(6)
                        }
                    }
                }

                // Add new alias
                VStack(alignment: .leading, spacing: 8) {
                    Text("ADD NEW ALIAS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Text("@")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.purple)
                            TextField("Obsidian", text: $newAliasName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 100)
                        }

                        TextField("/path/to/folder", text: $newAliasPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                        Button(action: { showingAliasFolderPicker = true }) {
                            Image(systemName: "folder")
                                .font(Theme.current.fontSM)
                        }
                        .buttonStyle(.bordered)

                        Button(action: addAlias) {
                            Text("Add")
                                .font(Theme.current.fontXSMedium)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newAliasName.isEmpty || newAliasPath.isEmpty)
                    }
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)

                // Usage hint
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.yellow)
                    Text("Use in Save File step directory: @Obsidian/Voice Notes")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(6)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    outputDirectory = url.path
                    saveDirectory()
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingAliasFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    newAliasPath = url.path
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .onAppear {
            outputDirectory = SaveFileStepConfig.defaultOutputDirectory
            pathAliases = SaveFileStepConfig.pathAliases
        }
    }

    private func saveDirectory() {
        let path = outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            statusMessage = "Path cannot be empty"
            return
        }

        // Expand ~ to home directory
        let expandedPath: String
        if path.hasPrefix("~") {
            expandedPath = NSString(string: path).expandingTildeInPath
        } else {
            expandedPath = path
        }

        SaveFileStepConfig.defaultOutputDirectory = expandedPath
        outputDirectory = expandedPath
        statusMessage = "✓ Output directory saved"

        // Clear status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == "✓ Output directory saved" {
                statusMessage = nil
            }
        }
    }

    private func openInFinder() {
        let path = SaveFileStepConfig.defaultOutputDirectory
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            statusMessage = "Folder doesn't exist yet. Create it first."
        }
    }

    private func createDirectory() {
        do {
            try SaveFileStepConfig.ensureDefaultDirectoryExists()
            statusMessage = "✓ Folder created"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "✓ Folder created" {
                    statusMessage = nil
                }
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func resetToDefault() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            statusMessage = "Error: Cannot access documents directory"
            return
        }
        let defaultPath = documents.appendingPathComponent("Talkie").path
        outputDirectory = defaultPath
        SaveFileStepConfig.defaultOutputDirectory = defaultPath
        statusMessage = "✓ Reset to ~/Documents/Talkie"
    }

    private func addAlias() {
        let name = newAliasName.trimmingCharacters(in: .whitespacesAndNewlines)
        var path = newAliasPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !path.isEmpty else { return }

        // Expand ~ to home directory
        if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        }

        SaveFileStepConfig.setPathAlias(name, path: path)
        pathAliases = SaveFileStepConfig.pathAliases
        newAliasName = ""
        newAliasPath = ""
        statusMessage = "✓ Added @\(name)"

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == "✓ Added @\(name)" {
                statusMessage = nil
            }
        }
    }

    private func removeAlias(_ name: String) {
        SaveFileStepConfig.removePathAlias(name)
        pathAliases = SaveFileStepConfig.pathAliases
    }
}

