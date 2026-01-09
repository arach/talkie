//
//  DictionarySettings.swift
//  Talkie
//
//  Multi-dictionary settings with expandable cards and inline editing
//

import SwiftUI
import UniformTypeIdentifiers
import TalkieKit

// MARK: - Dictionary Settings View

struct DictionarySettingsView: View {
    @ObservedObject private var manager = DictionaryManager.shared

    @State private var expandedDictionaryId: UUID?
    @State private var isCreatingNew = false
    @State private var newDictionaryName = ""
    @State private var isDragOver = false
    @State private var searchText = ""

    // Navigation state
    @State private var showPlayground = false
    @State private var showSuggestions = false
    @State private var showURLExtract = false

    // Presets
    @State private var availablePresets: [PresetInfo] = []
    @State private var isLoadingPresets = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                header

                // Global toggle
                globalToggle

                // Dictionary list
                dictionaryList

                // Presets section
                if !availablePresets.isEmpty {
                    presetsSection
                }

                // Drop zone + import info
                importSection

                // Tools section (last)
                toolsSection

                Spacer(minLength: Spacing.xl)
            }
            .padding(Spacing.lg)
        }
        .sheet(isPresented: $showPlayground) {
            DictionaryTestPlayground()
                .frame(width: 520, height: 580)
        }
        .sheet(isPresented: $showSuggestions) {
            DictionarySuggestionsView()
                .frame(width: 550, height: 600)
        }
        .sheet(isPresented: $showURLExtract) {
            DictionaryURLExtractModal()
        }
        .onAppear {
            Task {
                await manager.load()
                await manager.ensureDefaultDictionary()
                await loadPresets()
            }
        }
        .onDrop(of: [.json, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("DICTIONARIES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Word replacements applied to transcriptions")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            // Stats
            if manager.totalEntryCount > 0 {
                Text("\(manager.enabledEntryCount)/\(manager.totalEntryCount) entries active")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
    }

    // MARK: - Global Toggle

    private var globalToggle: some View {
        HStack {
            Toggle(isOn: $manager.isGloballyEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Dictionary Processing")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                    Text("Apply word replacements to all transcriptions")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        HStack(spacing: Spacing.sm) {
            // Test Playground
            ToolButton(
                icon: "play.circle",
                title: "Test",
                subtitle: "Playground",
                action: { showPlayground = true }
            )

            // AI Suggestions
            ToolButton(
                icon: "wand.and.stars",
                title: "AI",
                subtitle: "Suggestions",
                action: { showSuggestions = true }
            )

            // Extract from URL
            ToolButton(
                icon: "link.badge.plus",
                title: "Extract",
                subtitle: "from URL",
                action: { showURLExtract = true }
            )
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PRESETS")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: Spacing.xs) {
                ForEach(availablePresets) { preset in
                    PresetRow(
                        preset: preset,
                        onInstall: { installPreset(preset) },
                        onUninstall: { uninstallPreset(preset) }
                    )
                }
            }
        }
    }

    private func loadPresets() async {
        isLoadingPresets = true
        availablePresets = await DictionaryFileManager.shared.listAvailablePresets()
        isLoadingPresets = false
    }

    private func installPreset(_ preset: PresetInfo) {
        Task {
            do {
                _ = try await DictionaryFileManager.shared.installPreset(id: preset.id)
                await manager.load()  // Reload dictionaries
                await loadPresets()   // Refresh preset status
            } catch {
                print("Failed to install preset: \(error)")
            }
        }
    }

    private func uninstallPreset(_ preset: PresetInfo) {
        Task {
            do {
                try await DictionaryFileManager.shared.uninstallPreset(name: preset.name)
                await manager.load()  // Reload dictionaries
                await loadPresets()   // Refresh preset status
            } catch {
                print("Failed to uninstall preset: \(error)")
            }
        }
    }

    // MARK: - Dictionary List

    private var dictionaryList: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(manager.dictionaries) { dictionary in
                DictionaryCard(
                    dictionary: dictionary,
                    isExpanded: expandedDictionaryId == dictionary.id,
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedDictionaryId == dictionary.id {
                                expandedDictionaryId = nil
                            } else {
                                expandedDictionaryId = dictionary.id
                            }
                        }
                    },
                    onToggleEnabled: {
                        Task { await manager.toggleDictionary(dictionary) }
                    },
                    onDelete: {
                        Task { await manager.deleteDictionary(dictionary) }
                    },
                    onAddEntry: { entry in
                        Task { await manager.addEntry(to: dictionary.id, entry: entry) }
                    },
                    onUpdateEntry: { entry in
                        Task { await manager.updateEntry(in: dictionary.id, entry: entry) }
                    },
                    onDeleteEntry: { entry in
                        Task { await manager.deleteEntry(from: dictionary.id, entry: entry) }
                    },
                    onToggleEntry: { entry in
                        Task { await manager.toggleEntry(in: dictionary.id, entry: entry) }
                    }
                )
            }

            // New dictionary button (subtle, secondary action)
            if isCreatingNew {
                newDictionaryCard
            } else {
                Button(action: { isCreatingNew = true }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text("New Dictionary")
                            .font(Theme.current.fontXS)
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var newDictionaryCard: some View {
        VStack(spacing: Spacing.sm) {
            TextField("Dictionary name...", text: $newDictionaryName)
                .textFieldStyle(.roundedBorder)
                .font(Theme.current.fontSM)

            HStack {
                Button("Cancel") {
                    isCreatingNew = false
                    newDictionaryName = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Create") {
                    Task {
                        await manager.createDictionary(name: newDictionaryName)
                        isCreatingNew = false
                        newDictionaryName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDictionaryName.isEmpty)
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Drop zone
            VStack(spacing: Spacing.xs) {
                Image(systemName: isDragOver ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 20))
                    .foregroundColor(isDragOver ? Theme.current.accent : Theme.current.foregroundMuted)

                Text("Drop .json to import dictionary")
                    .font(Theme.current.fontXS)
                    .foregroundColor(isDragOver ? Theme.current.accent : Theme.current.foregroundMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [5]),
                        antialiased: true
                    )
                    .foregroundColor(isDragOver ? Theme.current.accent : Theme.current.border)
            )
            .background(isDragOver ? Theme.current.accent.opacity(0.05) : Color.clear)
            .cornerRadius(CornerRadius.md)
            .animation(.easeInOut(duration: 0.15), value: isDragOver)

            // JSON format info
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // JSON example
                    Text("""
                    {
                      "name": "My Dictionary",
                      "entries": [
                        { "trigger": "clawd", "replacement": "Claude" },
                        { "trigger": "open ai", "replacement": "OpenAI", "matchType": "phrase" },
                        { "trigger": "v(\\\\d+)", "replacement": "version $1", "matchType": "regex" },
                        { "trigger": "Claude", "replacement": "Claude", "matchType": "fuzzy" }
                      ]
                    }
                    """)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.sm)

                    // Match types list
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Match Types")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        VStack(alignment: .leading, spacing: 6) {
                            matchTypeRow(
                                type: "word",
                                description: "Matches whole words only",
                                example: "clawd → Claude"
                            )
                            matchTypeRow(
                                type: "phrase",
                                description: "Case-insensitive, matches anywhere",
                                example: "open ai → OpenAI"
                            )
                            matchTypeRow(
                                type: "regex",
                                description: "Regular expression with $1, $2 capture groups",
                                example: "v(\\d+) → version $1"
                            )
                            matchTypeRow(
                                type: "fuzzy",
                                description: "Approximate match for misspellings/mishearings",
                                example: "Claude catches clawd, claud, clowd"
                            )
                        }
                    }
                }
                .padding(.top, Spacing.sm)
            } label: {
                Text("Expected JSON format")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .accentColor(Theme.current.foregroundMuted)
            .padding(Spacing.sm)
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.md)
        }
    }

    private func matchTypeRow(type: String, description: String, example: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(type)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.current.accent)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foreground)

                Text(example)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.json.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        Task { @MainActor in
                            do {
                                _ = try await manager.importDictionary(from: url)
                            } catch {
                                print("Failed to import: \(error)")
                            }
                        }
                    } else if let data = item as? Data {
                        Task { @MainActor in
                            do {
                                _ = try await manager.importDictionary(from: data)
                            } catch {
                                print("Failed to import: \(error)")
                            }
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString),
                       url.pathExtension.lowercased() == "json" {
                        Task { @MainActor in
                            do {
                                _ = try await manager.importDictionary(from: url)
                            } catch {
                                print("Failed to import: \(error)")
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

// MARK: - Dictionary Card

struct DictionaryCard: View {
    let dictionary: TalkieDictionary
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void
    let onAddEntry: (DictionaryEntry) -> Void
    let onUpdateEntry: (DictionaryEntry) -> Void
    let onDeleteEntry: (DictionaryEntry) -> Void
    let onToggleEntry: (DictionaryEntry) -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false
    @State private var isAddingEntry = false

    /// Path to dictionary file
    private var dictionaryFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
            .appendingPathComponent("\(dictionary.id.uuidString).dict.json")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: Spacing.sm) {
                // Expand/collapse chevron
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

                // Enable toggle
                Toggle("", isOn: .init(
                    get: { dictionary.isEnabled },
                    set: { _ in onToggleEnabled() }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                // Name and info
                VStack(alignment: .leading, spacing: 2) {
                    Text(dictionary.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(dictionary.isEnabled ? Theme.current.foreground : Theme.current.foregroundMuted)

                    HStack(spacing: Spacing.xs) {
                        Text("\(dictionary.entries.count) entries")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if dictionary.source != .manual {
                            Text("•")
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(dictionary.source.displayName)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                }

                Spacer()

                // Actions (on hover)
                if isHovered {
                    HStack(spacing: Spacing.sm) {
                        Button(action: revealInFinder) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .help("Reveal in Finder")

                        Button(action: { showDeleteConfirm = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(isHovered ? Theme.current.backgroundTertiary : Theme.current.backgroundSecondary)
            .onHover { isHovered = $0 }

            // Expanded content
            if isExpanded {
                Divider().background(Theme.current.border)

                VStack(spacing: 0) {
                    // Entry rows first
                    if dictionary.entries.isEmpty && !isAddingEntry {
                        Text("No entries yet")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                    } else {
                        ForEach(dictionary.entries) { entry in
                            DictionaryEntryRow(
                                entry: entry,
                                onToggle: { onToggleEntry(entry) },
                                onUpdate: onUpdateEntry,
                                onDelete: { onDeleteEntry(entry) }
                            )
                            Divider().background(Theme.current.border)
                        }
                    }

                    // Add entry at the bottom (prominent)
                    if isAddingEntry {
                        InlineEntryEditor(
                            onSave: { entry in
                                onAddEntry(entry)
                                isAddingEntry = false
                            },
                            onCancel: { isAddingEntry = false }
                        )
                    } else {
                        Button(action: { isAddingEntry = true }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("Add Entry")
                                    .font(Theme.current.fontSMMedium)
                            }
                            .foregroundColor(Theme.current.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.current.accent.opacity(0.08))
                    }
                }
                .background(Theme.current.backgroundSecondary.opacity(0.5))
            }
        }
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(dictionary.isEnabled ? Theme.current.accent.opacity(0.3) : Theme.current.border, lineWidth: 0.5)
        )
        .alert("Delete Dictionary?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete '\(dictionary.name)' and all its entries.")
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(dictionaryFileURL.path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Dictionary Entry Row

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onUpdate: (DictionaryEntry) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isEditing = false

    // Column widths for alignment with editor
    private let sourceWidth: CGFloat = 120
    private let replaceWidth: CGFloat = 140
    private let typeWidth: CGFloat = 60

    var body: some View {
        if isEditing {
            InlineEntryEditor(
                entry: entry,
                onSave: { updated in
                    onUpdate(updated)
                    isEditing = false
                },
                onCancel: { isEditing = false }
            )
        } else {
            HStack(spacing: Spacing.sm) {
                // Enable toggle
                Toggle("", isOn: .init(
                    get: { entry.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                // Source (trigger)
                Text(entry.trigger)
                    .font(Theme.current.fontSM.monospaced())
                    .foregroundColor(entry.isEnabled ? Theme.current.foreground : Theme.current.foregroundMuted)
                    .frame(width: sourceWidth, alignment: .leading)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)

                // Replace (replacement)
                Text(entry.replacement)
                    .font(Theme.current.fontSM.monospaced())
                    .foregroundColor(entry.isEnabled ? Theme.current.accent : Theme.current.foregroundMuted)
                    .frame(width: replaceWidth, alignment: .leading)
                    .lineLimit(1)

                // Match type badge (right side)
                Text(entry.matchType.displayName.lowercased())
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: typeWidth)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(3)

                Spacer()

                // Actions (on hover)
                if isHovered {
                    HStack(spacing: Spacing.sm) {
                        Button(action: { isEditing = true }) {
                            Text("Edit")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.current.foregroundSecondary)

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Theme.current.backgroundTertiary : Color.clear)
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Inline Entry Editor

struct InlineEntryEditor: View {
    var entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void

    @State private var trigger: String = ""
    @State private var replacement: String = ""
    @State private var matchType: DictionaryMatchType = .word

    // Column widths for alignment with entry row
    private let sourceWidth: CGFloat = 120
    private let replaceWidth: CGFloat = 140
    private let typeWidth: CGFloat = 100

    /// Returns nil if valid, or error message if invalid regex
    private var regexValidationError: String? {
        guard matchType == .regex else { return nil }
        guard !trigger.isEmpty else { return nil }

        do {
            _ = try NSRegularExpression(pattern: trigger, options: [.caseInsensitive])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var isRegexValid: Bool {
        regexValidationError == nil
    }

    private var canSave: Bool {
        !trigger.isEmpty && !replacement.isEmpty && isRegexValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                // Placeholder for checkbox alignment
                Color.clear
                    .frame(width: 16, height: 16)

                // Source (trigger)
                TextField(matchType == .regex ? "Pattern" : "Source", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.current.fontSM.monospaced())
                    .frame(width: sourceWidth)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(matchType == .regex && !trigger.isEmpty && !isRegexValid ? Color.red : Color.clear, lineWidth: 1)
                    )

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)

                // Replace (replacement)
                TextField(matchType == .regex ? "Replace ($1, $2)" : "Replace", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.current.fontSM.monospaced())
                    .frame(width: replaceWidth)

                // Match type picker (right side, after source → replace)
                Picker("", selection: $matchType) {
                    ForEach(DictionaryMatchType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: typeWidth)

                Spacer()

                // Actions - prominent cancel and save buttons
                HStack(spacing: Spacing.xs) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSave)
                }
            }

            // Regex validation error
            if let error = regexValidationError {
                Text("Invalid regex: \(error)")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.leading, 24) // Align with fields
            }

            // Type description
            Text(matchType.description)
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.leading, 24) // Align with fields
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.accent.opacity(0.08))
        .onAppear {
            if let entry = entry {
                trigger = entry.trigger
                replacement = entry.replacement
                matchType = entry.matchType
            }
        }
    }

    private func save() {
        let newEntry = DictionaryEntry(
            id: entry?.id ?? UUID(),
            trigger: trigger.trimmingCharacters(in: .whitespaces),
            replacement: replacement.trimmingCharacters(in: .whitespaces),
            matchType: matchType,
            isEnabled: entry?.isEnabled ?? true,
            category: entry?.category,
            createdAt: entry?.createdAt ?? Date(),
            usageCount: entry?.usageCount ?? 0
        )
        onSave(newEntry)
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: PresetInfo
    let onInstall: () -> Void
    let onUninstall: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: preset.isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundColor(preset.isInstalled ? .green : Theme.current.foregroundMuted)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(preset.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    if let version = preset.version {
                        Text("v\(version)")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }

                HStack(spacing: Spacing.xs) {
                    Text("\(preset.entryCount) entries")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    if let description = preset.description {
                        Text("•")
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text(description)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Install/Uninstall button
            if preset.isInstalled {
                Button(action: onUninstall) {
                    Text("Remove")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: onInstall) {
                    Text("Install")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(Spacing.sm)
        .background(isHovered ? Theme.current.backgroundTertiary : Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.md)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Tool Button

private struct ToolButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(Theme.current.accent)

                VStack(spacing: 0) {
                    Text(title)
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foreground)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(isHovered ? Theme.current.backgroundTertiary : Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Theme.current.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview("Dictionary Settings") {
    DictionarySettingsView()
        .frame(width: 500, height: 600)
}
