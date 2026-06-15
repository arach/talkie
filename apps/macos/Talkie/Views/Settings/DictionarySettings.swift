//
//  DictionarySettings.swift
//  Talkie
//
//  Multi-dictionary settings with expandable cards and inline editing
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TalkieKit

// MARK: - Dictionary Settings View

struct DictionarySettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "character.book.closed",
                title: "DICTIONARIES",
                subtitle: "Word replacements applied to transcriptions."
            )
        } content: {
            DictionarySettingsContent()
        }
    }
}

// MARK: - Dictionary Settings Content (embeddable as tab)

struct DictionarySettingsContent: View {
    @ObservedObject private var manager = DictionaryManager.shared

    @State private var expandedDictionaryId: UUID?
    @State private var isCreatingNew = false
    @State private var newDictionaryName = ""
    @State private var isDragOver = false
    @State private var searchText = ""
    @State private var filterMatchType: DictionaryMatchType?

    // Navigation state
    @State private var showPlayground = false
    @State private var showImport = false

    // Presets
    @State private var availablePresets: [PresetInfo] = []
    @State private var isLoadingPresets = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Global toggle
            globalToggle

            // Default dictionary (YOUR WORDS)
            if let defaultDict = manager.defaultDictionary {
                defaultDictionarySection(defaultDict)
            }

            // Named dictionaries (ADDITIONAL DICTIONARIES)
            namedDictionariesSection

            // Presets section (collapsed by default)
            if !availablePresets.isEmpty {
                DisclosureGroup {
                    presetsSection
                } label: {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.purple)
                            .frame(width: 3, height: 14)

                        Text("PRESETS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Text("\(availablePresets.count) AVAILABLE")
                            .font(.techLabelSmall)
                            .foregroundColor(Color.purple.opacity(Opacity.prominent))
                    }
                }
                .accentColor(Theme.current.foregroundSecondary)
                .settingsSectionCard(padding: Spacing.md)
            }

            // Tools row (Test + Import inline)
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    // Test Playground — 3/4 width
                    ToolButton(
                        icon: "play.circle",
                        title: "Test",
                        subtitle: "Playground",
                        action: { showPlayground = true }
                    )
                    .frame(maxWidth: .infinity)

                    // Import — 1/4 width, toggles inline drop zone
                    ToolButton(
                        icon: "arrow.down.doc",
                        title: "Import",
                        subtitle: ".json",
                        isActive: showImport,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showImport.toggle()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                }

                // Expanded import area
                if showImport {
                    importSection
                        .padding(.top, Spacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .settingsSectionCard(padding: Spacing.md)
        }
        .sheet(isPresented: $showPlayground) {
            DictionaryTestPlayground()
                .frame(width: 750, height: 650)
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

    // MARK: - Global Toggle

    private var globalToggle: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Colored bar header
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(manager.isGloballyEnabled ? SemanticColor.success : Theme.current.foregroundSecondary)
                    .frame(width: 3, height: 14)

                Text("DICTIONARY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if manager.totalEntryCount > 0 {
                    Text("\(manager.enabledEntryCount)/\(manager.totalEntryCount) ACTIVE")
                        .font(.techLabelSmall)
                        .foregroundColor(manager.isGloballyEnabled ? SemanticColor.success : Theme.current.foregroundSecondary)
                }
            }

            // Icon + label + toggle row
            HStack(spacing: Spacing.sm) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 16))
                    .foregroundColor(manager.isGloballyEnabled ? SemanticColor.success : Theme.current.foregroundSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Enable Dictionary Processing")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)
                    Text("Apply word replacements to all transcriptions")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                Toggle("", isOn: $manager.isGloballyEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(availablePresets) { preset in
                PresetRow(
                    preset: preset,
                    onInstall: { installPreset(preset) },
                    onUninstall: { uninstallPreset(preset) }
                )
            }
        }
        .padding(.top, Spacing.xs)
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
                TalkieConsole.info("Failed to install preset: \(error)")
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
                TalkieConsole.info("Failed to uninstall preset: \(error)")
            }
        }
    }

    // MARK: - Filtered Entries

    /// Total entry count in the default dictionary
    private var defaultDictionaryEntryCount: Int {
        manager.defaultDictionary?.entries.count ?? 0
    }

    /// Whether mixed match types exist in the default dictionary
    private var defaultDictionaryHasMixedTypes: Bool {
        guard let dict = manager.defaultDictionary else { return false }
        let types = Set(dict.entries.map(\.matchType))
        return types.count > 1
    }

    /// Filter entries for a given dictionary by search text + match type
    private func filteredEntries(for dictionary: TalkieDictionary) -> [DictionaryEntry] {
        dictionary.entries.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.trigger.localizedCaseInsensitiveContains(searchText) ||
                entry.replacement.localizedCaseInsensitiveContains(searchText)
            let matchesType = filterMatchType == nil || entry.matchType == filterMatchType
            return matchesSearch && matchesType
        }
    }

    // MARK: - Default Dictionary Section ("YOUR WORDS")

    @State private var showAddDefaultEntry = false
    @State private var editingDefaultEntryId: UUID?
    @State private var showAllDefaultEntries = false

    private let defaultVisibleEntryLimit = 8

    /// True only when mixed match types exist in the default dictionary
    private var defaultShowTypeBadges: Bool {
        guard let dict = manager.defaultDictionary else { return false }
        let types = Set(dict.entries.map(\.matchType))
        return types.count > 1
    }

    private func defaultDictionarySection(_ dictionary: TalkieDictionary) -> some View {
        let entries = filteredEntries(for: dictionary)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: 3, height: 14)

                Text("YOUR WORDS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if !dictionary.entries.isEmpty {
                    Text("\(dictionary.enabledEntryCount)/\(dictionary.entries.count) ACTIVE")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            // Entries shown directly (no card-within-card)
            if dictionary.entries.isEmpty {
                // Empty state
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("No entries yet")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)

                    Text("Add your first word replacement")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .multilineTextAlignment(.center)

                    Button(action: { showAddDefaultEntry = true }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add First Entry")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .sheet(isPresented: $showAddDefaultEntry) {
                        AddEntrySheet(
                            onSave: { entry in
                                Task { await manager.addEntry(to: dictionary.id, entry: entry) }
                                showAddDefaultEntry = false
                            },
                            onCancel: { showAddDefaultEntry = false }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            } else if entries.isEmpty && !searchText.isEmpty {
                // Filtered to empty
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                    Text("No entries match \"\(searchText)\"")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(Theme.current.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            } else if !dictionary.entries.isEmpty {
                // Column headers
                HStack(spacing: Spacing.sm) {
                    Text("SOURCE")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("REPLACEMENT")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if defaultShowTypeBadges {
                        Text("TYPE")
                            .frame(width: 60, alignment: .center)
                    }
                }
                .font(.techLabelSmall)
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(Theme.current.surface1.opacity(0.5))
                .cornerRadius(CornerRadius.sm)

                // Entry rows
                let visibleEntries = (showAllDefaultEntries || !searchText.isEmpty)
                    ? entries
                    : Array(entries.prefix(defaultVisibleEntryLimit))
                let hiddenCount = entries.count - visibleEntries.count

                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    DictionaryEntryRow(
                        entry: entry,
                        showTypeBadge: defaultShowTypeBadges,
                        rowIndex: index,
                        editingEntryId: $editingDefaultEntryId,
                        onToggle: { Task { await manager.toggleEntry(in: dictionary.id, entry: entry) } },
                        onUpdate: { updated in Task { await manager.updateEntry(in: dictionary.id, entry: updated) } },
                        onDelete: { Task { await manager.deleteEntry(from: dictionary.id, entry: entry) } }
                    )
                }

                // Show more / show less
                if entries.count > defaultVisibleEntryLimit && searchText.isEmpty {
                    Button(action: { showAllDefaultEntries.toggle() }) {
                        Text(showAllDefaultEntries ? "Show less" : "Show \(hiddenCount) more…")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Add entry button
            if !dictionary.entries.isEmpty {
                Button(action: { showAddDefaultEntry = true }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text("Add Entry")
                            .font(Theme.current.fontXS)
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showAddDefaultEntry) {
                    AddEntrySheet(
                        onSave: { entry in
                            Task { await manager.addEntry(to: dictionary.id, entry: entry) }
                            showAddDefaultEntry = false
                        },
                        onCancel: { showAddDefaultEntry = false }
                    )
                }
            }

            // Search/filter (only when >8 entries, at bottom of section)
            if defaultDictionaryEntryCount > 8 {
                HStack(spacing: Spacing.sm) {
                    // Search field
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)

                        TextField("Filter entries…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.monoSmall)

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Type filter pills (only when mixed types)
                    if defaultDictionaryHasMixedTypes {
                        ForEach(DictionaryMatchType.allCases, id: \.self) { type in
                            let isActive = filterMatchType == type
                            Button(action: {
                                filterMatchType = isActive ? nil : type
                            }) {
                                Text(type.displayName.lowercased())
                                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
                                    .foregroundColor(isActive ? matchTypeColor(for: type) : Theme.current.foregroundMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(isActive ? matchTypeColor(for: type).opacity(Opacity.medium) : Theme.current.surface1)
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Named Dictionaries Section ("ADDITIONAL DICTIONARIES")

    private var namedDictionariesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.teal)
                    .frame(width: 3, height: 14)

                Text("ADDITIONAL DICTIONARIES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if !manager.namedDictionaries.isEmpty {
                    Text("\(manager.namedDictionaries.count)")
                        .font(.techLabelSmall)
                        .foregroundColor(Color.teal.opacity(Opacity.prominent))
                }
            }

            // Named dictionary cards
            VStack(spacing: Spacing.sm) {
                ForEach(manager.namedDictionaries) { dictionary in
                    DictionaryCard(
                        dictionary: dictionary,
                        filteredEntries: filteredEntries(for: dictionary),
                        searchText: searchText,
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

                // New dictionary button
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
        .settingsSectionCard(padding: Spacing.md)
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
                                TalkieConsole.info("Failed to import: \(error)")
                            }
                        }
                    } else if let data = item as? Data {
                        Task { @MainActor in
                            do {
                                _ = try await manager.importDictionary(from: data)
                            } catch {
                                TalkieConsole.info("Failed to import: \(error)")
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
                                TalkieConsole.info("Failed to import: \(error)")
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

// MARK: - Match Type Color Helper

private func matchTypeColor(for matchType: DictionaryMatchType) -> Color {
    switch matchType {
    case .word: return .blue
    case .phrase: return .purple
    case .regex: return .orange
    case .fuzzy: return .cyan
    }
}

// MARK: - Dictionary Card

struct DictionaryCard: View {
    let dictionary: TalkieDictionary
    let filteredEntries: [DictionaryEntry]
    let searchText: String
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void
    let onAddEntry: (DictionaryEntry) -> Void
    let onUpdateEntry: (DictionaryEntry) -> Void
    let onDeleteEntry: (DictionaryEntry) -> Void
    let onToggleEntry: (DictionaryEntry) -> Void

    @State private var showDeleteConfirm = false
    @State private var showAddEntry = false
    @State private var showAllEntries = false
    @State private var editingEntryId: UUID?

    private let visibleEntryLimit = 8

    /// Path to dictionary file directory
    private var dictionaryDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
    }

    /// True only when mixed match types exist in this dictionary
    private var showTypeBadges: Bool {
        let types = Set(dictionary.entries.map(\.matchType))
        return types.count > 1
    }

    /// When all entries share one type, show it in the header
    private var uniformType: DictionaryMatchType? {
        let types = Set(dictionary.entries.map(\.matchType))
        return types.count == 1 ? types.first : nil
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

                // Name and info
                VStack(alignment: .leading, spacing: 2) {
                    Text(dictionary.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(dictionary.isEnabled ? Theme.current.foreground : Theme.current.foregroundMuted)

                    HStack(spacing: Spacing.xs) {
                        Text("\(dictionary.entries.count) entries")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if dictionary.source != .manual && dictionary.source != .system {
                            Text("·")
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(dictionary.source.displayName)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        if let type = uniformType {
                            Text("·")
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text("all \(type.displayName.lowercased())")
                                .font(Theme.current.fontXS)
                                .foregroundColor(matchTypeColor(for: type).opacity(Opacity.prominent))
                        }
                    }
                }

                Spacer()

                // Overflow menu (always visible, subtle)
                Menu {
                    Button(action: revealInFinder) {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    Divider()
                    Button(role: .destructive, action: { showDeleteConfirm = true }) {
                        Label("Delete…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)

                // Enable toggle (switch on right)
                Toggle("", isOn: .init(
                    get: { dictionary.isEnabled },
                    set: { _ in onToggleEnabled() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
            .padding(Spacing.sm)
            .background(Theme.current.backgroundSecondary)

            // Expanded content
            if isExpanded {
                Divider().background(Theme.current.border)

                VStack(spacing: 0) {
                    if dictionary.entries.isEmpty {
                        // Empty state
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "text.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(Theme.current.foregroundMuted)

                            Text("No entries yet")
                                .font(Theme.current.fontSMBold)
                                .foregroundColor(Theme.current.foreground)

                            Text("Add your first word replacement")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .multilineTextAlignment(.center)

                            Button(action: { showAddEntry = true }) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add First Entry")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                    } else if filteredEntries.isEmpty && !searchText.isEmpty {
                        // Filtered to empty
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                            Text("No entries match \"\(searchText)\"")
                                .font(Theme.current.fontXS)
                        }
                        .foregroundColor(Theme.current.foregroundMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                    } else {
                        // Column headers
                        HStack(spacing: Spacing.sm) {
                            Text("SOURCE")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("REPLACEMENT")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if showTypeBadges {
                                Text("TYPE")
                                    .frame(width: 60, alignment: .center)
                            }
                        }
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Theme.current.surface1.opacity(0.5))

                        // Entry rows (capped at 8 unless expanded or searching)
                        let visibleEntries = (showAllEntries || !searchText.isEmpty)
                            ? filteredEntries
                            : Array(filteredEntries.prefix(visibleEntryLimit))
                        let hiddenCount = filteredEntries.count - visibleEntries.count

                        ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                            DictionaryEntryRow(
                                entry: entry,
                                showTypeBadge: showTypeBadges,
                                rowIndex: index,
                                editingEntryId: $editingEntryId,
                                onToggle: { onToggleEntry(entry) },
                                onUpdate: onUpdateEntry,
                                onDelete: { onDeleteEntry(entry) }
                            )
                        }

                        // Show more / show less toggle
                        if filteredEntries.count > visibleEntryLimit && searchText.isEmpty {
                            Button(action: { showAllEntries.toggle() }) {
                                Text(showAllEntries ? "Show less" : "Show \(hiddenCount) more…")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.xs)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Add entry button
                    if !dictionary.entries.isEmpty {
                        Button(action: { showAddEntry = true }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9))
                                Text("Add Entry")
                                    .font(Theme.current.fontXS)
                            }
                            .foregroundColor(Theme.current.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xs)
                        }
                        .buttonStyle(.plain)
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
        .sheet(isPresented: $showAddEntry) {
            AddEntrySheet(
                onSave: { entry in
                    onAddEntry(entry)
                    showAddEntry = false
                },
                onCancel: { showAddEntry = false }
            )
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dictionaryDirectoryURL.path)
    }
}

// MARK: - Dictionary Entry Row

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let showTypeBadge: Bool
    let rowIndex: Int
    @Binding var editingEntryId: UUID?
    let onToggle: () -> Void
    let onUpdate: (DictionaryEntry) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var isEditing: Bool { editingEntryId == entry.id }

    private var accentColor: Color {
        matchTypeColor(for: entry.matchType)
    }

    var body: some View {
        if isEditing {
            InlineEntryEditor(
                entry: entry,
                showTypeBadge: showTypeBadge,
                onSave: { updated in
                    onUpdate(updated)
                    editingEntryId = nil
                },
                onCancel: { editingEntryId = nil },
                onToggle: onToggle,
                onDelete: onDelete
            )
        } else {
            HStack(spacing: Spacing.sm) {
                // Source (trigger)
                Text(entry.trigger)
                    .font(.monoSmall)
                    .foregroundColor(entry.isEnabled ? Theme.current.foreground : Theme.current.foregroundMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                // Replacement in accent color
                Text(entry.replacement)
                    .font(.monoSmall)
                    .foregroundColor(entry.isEnabled ? Theme.current.accent : Theme.current.foregroundMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                // Conditional type badge
                if showTypeBadge {
                    Text(entry.matchType.displayName.lowercased())
                        .font(.system(size: 9))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(Opacity.medium))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .opacity(entry.isEnabled ? 1.0 : 0.45)
            .background(rowIndex.isMultiple(of: 2) ? Theme.current.surface1.opacity(0.3) : Color.clear)
            .background(isHovered ? Theme.current.backgroundTertiary : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { editingEntryId = entry.id }
            .contextMenu {
                Button(action: onToggle) {
                    Label(entry.isEnabled ? "Disable" : "Enable", systemImage: entry.isEnabled ? "eye.slash" : "eye")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Add Entry Sheet

struct AddEntrySheet: View {
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void

    @State private var trigger: String = ""
    @State private var replacement: String = ""
    @State private var matchType: DictionaryMatchType = .word

    private enum Field: Hashable {
        case trigger, replacement
    }
    @FocusState private var focusedField: Field?

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

    private var isRegexValid: Bool { regexValidationError == nil }

    private var canSave: Bool {
        !trigger.isEmpty && !replacement.isEmpty && isRegexValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("ADD NEW ENTRY")
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider().background(Theme.current.border)

            // Form fields
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Source text
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SOURCE TEXT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    TextField(matchType == .regex ? "e.g. v(\\d+)" : "e.g. clawd", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoSmall)
                        .focused($focusedField, equals: .trigger)
                        .onSubmit { focusedField = .replacement }
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(matchType == .regex && !trigger.isEmpty && !isRegexValid ? Color.red : Color.clear, lineWidth: 1)
                        )
                }

                // Replacement
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("REPLACEMENT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    TextField(matchType == .regex ? "e.g. version $1" : "e.g. Claude", text: $replacement)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoSmall)
                        .focused($focusedField, equals: .replacement)
                        .onSubmit { if canSave { save() } }
                }

                // Regex validation error
                if let error = regexValidationError {
                    Text("Invalid regex: \(error)")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }

                // Type picker
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("TYPE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(spacing: Spacing.xs) {
                        ForEach(DictionaryMatchType.allCases, id: \.self) { type in
                            let isActive = matchType == type
                            Button(action: { matchType = type }) {
                                Text(type.displayName.uppercased())
                                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                    .foregroundColor(isActive ? matchTypeColor(for: type) : Theme.current.foregroundMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                                            .fill(isActive ? matchTypeColor(for: type).opacity(Opacity.medium) : Theme.current.surface1)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                                            .stroke(isActive ? matchTypeColor(for: type).opacity(0.4) : Theme.current.border, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(matchType.description)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .padding(Spacing.lg)

            Divider().background(Theme.current.border)

            // Footer buttons
            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Button("Add Entry", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!canSave)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .frame(width: 400)
        .background(Theme.current.background)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .trigger
            }
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    private func save() {
        let newEntry = DictionaryEntry(
            trigger: trigger.trimmingCharacters(in: .whitespaces),
            replacement: replacement.trimmingCharacters(in: .whitespaces),
            matchType: matchType
        )
        onSave(newEntry)
    }
}

// MARK: - Inline Entry Editor

struct InlineEntryEditor: View {
    var entry: DictionaryEntry?
    var showTypeBadge: Bool = false
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var trigger: String = ""
    @State private var replacement: String = ""
    @State private var matchType: DictionaryMatchType = .word

    // Focus state for keyboard navigation
    private enum Field: Hashable {
        case trigger, replacement
    }
    @FocusState private var focusedField: Field?

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

    private var accentColor: Color {
        matchTypeColor(for: matchType)
    }

    private var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Two text fields aligned to the table columns
            HStack(spacing: Spacing.sm) {
                TextField(matchType == .regex ? "Pattern" : "Source word", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.monoSmall)
                    .focused($focusedField, equals: .trigger)
                    .onSubmit { focusedField = .replacement }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(matchType == .regex && !trigger.isEmpty && !isRegexValid ? Color.red : Color.clear, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)

                TextField(matchType == .regex ? "Replace ($1, $2)" : "Replacement", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(.monoSmall)
                    .focused($focusedField, equals: .replacement)
                    .onSubmit { if canSave { save() } }
                    .frame(maxWidth: .infinity)

                // Type badge placeholder to keep alignment
                if showTypeBadge {
                    Picker("", selection: $matchType) {
                        ForEach(DictionaryMatchType.allCases, id: \.self) { type in
                            Text(type.displayName.lowercased()).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 60)
                    .labelsHidden()
                }
            }

            // Regex validation error
            if let error = regexValidationError {
                Text("Invalid regex: \(error)")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            // Row 2: Match type (when no badge column) + actions
            HStack(spacing: Spacing.sm) {
                if !showTypeBadge {
                    Picker("", selection: $matchType) {
                        ForEach(DictionaryMatchType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 248)

                    Text(matchType.description)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                        .padding(.leading, Spacing.xs)
                }

                Spacer()

                // Destructive actions (only when editing existing entry)
                if isEditing {
                    if let onToggle {
                        Button(action: onToggle) {
                            Label(
                                entry?.isEnabled == true ? "Disable" : "Enable",
                                systemImage: entry?.isEnabled == true ? "eye.slash" : "eye"
                            )
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let onDelete {
                        Button(role: .destructive, action: {
                            onDelete()
                            onCancel()
                        }) {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Cancel / Save
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
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(CornerRadius.sm)
        .onAppear {
            if let entry = entry {
                trigger = entry.trigger
                replacement = entry.replacement
                matchType = entry.matchType
            }
            // Auto-focus trigger field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .trigger
            }
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
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
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? Theme.current.accent : Theme.current.foregroundSecondary)

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
            .background(isActive ? Theme.current.accent.opacity(0.08) : (isHovered ? Theme.current.backgroundTertiary : Theme.current.backgroundSecondary))
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isActive ? Theme.current.accent.opacity(0.3) : Theme.current.border, lineWidth: isActive ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Transform Rules Content (Symbolic Mapping)

/// Symbolic mapping settings, embedded by the Processing tab of ContextSettingsView.
struct TransformRulesContent: View {
    @ObservedObject private var manager = DictionaryManager.shared
    @State private var isReloadingRules = false
    @State private var reloadStatusMessage: String?
    @State private var reloadStatusIsError = false
    @State private var copyStatusMessage: String?

    private var symbolicMappingFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TalkieEngine/symbolic-mapping.json")
    }

    private var symbolicMappingFilePath: String {
        symbolicMappingFileURL.path.replacing(NSHomeDirectory(), with: "~")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.right.arrow.left")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("SYMBOLIC MAPPING")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $manager.isSymbolicMappingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Symbolic Mapping")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foreground)
                            Text("Convert spoken symbols like slash, dash, plus, and arrow.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                    .toggleStyle(.switch)

                    Divider()
                        .padding(.vertical, Spacing.sm)

                    Toggle(isOn: $manager.isFillerRemovalEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove Filler Words")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foreground)
                            Text("Clean up frequent fillers like um, uh, and uhm before replacements.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(Spacing.sm)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.md)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text("Rules File")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Text(symbolicMappingFilePath)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.current.backgroundTertiary)
                        .cornerRadius(CornerRadius.sm)

                    HStack(spacing: Spacing.xs) {
                        Button("Open") {
                            NSWorkspace.shared.open(symbolicMappingFileURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open rules JSON in default editor")

                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(symbolicMappingFileURL.path, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reveal rules JSON in Finder")

                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(symbolicMappingFileURL.path, forType: .string)
                            copyStatusMessage = "Path copied"

                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                copyStatusMessage = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Copy absolute path")

                        Spacer()

                        Button {
                            Task { @MainActor in
                                await reloadRulesFile()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isReloadingRules {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Reload")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isReloadingRules)
                        .help("Reload rules in the running engine")
                    }

                    if let copyStatusMessage {
                        Text(copyStatusMessage)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    if let reloadStatusMessage {
                        Text(reloadStatusMessage)
                            .font(Theme.current.fontXS)
                            .foregroundColor(reloadStatusIsError ? .orange : .green)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.md)
            }
        }
    }

    private func reloadRulesFile() async {
        isReloadingRules = true
        defer { isReloadingRules = false }

        do {
            try await EngineClient.shared.reloadSymbolicMapping()
            reloadStatusIsError = false
            reloadStatusMessage = "Rules reloaded in engine"
        } catch {
            reloadStatusIsError = true
            reloadStatusMessage = "Reload failed: \(error.localizedDescription)"
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            reloadStatusMessage = nil
        }
    }
}

// MARK: - Preview

#Preview("Dictionary Settings") {
    DictionarySettingsView()
        .frame(width: 500, height: 600)
}
