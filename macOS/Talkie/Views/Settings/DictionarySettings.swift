//
//  DictionarySettings.swift
//  Talkie
//
//  Personal dictionary settings - manage word replacements for transcriptions
//

import SwiftUI
import UniformTypeIdentifiers
import TalkieKit

// MARK: - Dictionary Settings View

struct DictionarySettingsView: View {
    @ObservedObject private var manager = DictionaryManager.shared

    @State private var showingAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var searchText = ""

    private var filteredEntries: [DictionaryEntry] {
        if searchText.isEmpty {
            return manager.entries
        }
        return manager.entries.filter {
            $0.trigger.localizedCaseInsensitiveContains(searchText) ||
            $0.replacement.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                sectionHeader

                // Dictionary entries
                entriesSection

                Spacer(minLength: Spacing.xl)
            }
            .padding(Spacing.lg)
        }
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEntrySheet(entry: nil) { newEntry in
                manager.addEntry(newEntry)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntrySheet(entry: entry) { updated in
                manager.updateEntry(updated)
            }
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("PERSONAL DICTIONARY")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Define word replacements applied to all transcriptions")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    // MARK: - Entries Section

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Toolbar
            HStack {
                // Search
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Theme.current.fontSM)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Theme.current.backgroundTertiary)
                .cornerRadius(CornerRadius.sm)
                .frame(maxWidth: 200)

                Spacer()

                // Actions
                HStack(spacing: Spacing.sm) {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add", systemImage: "plus")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Menu {
                        Button("Add Common Presets") {
                            manager.addCommonPresets()
                        }
                        Divider()
                        Button("Export JSON...") {
                            exportDictionary()
                        }
                        Button("Import JSON...") {
                            importDictionary()
                        }
                        Divider()
                        Button("Clear All", role: .destructive) {
                            manager.clearAll()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(Theme.current.fontSM)
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            // Entries list
            VStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    entriesList
                }
            }
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Theme.current.border, lineWidth: 0.5)
            )

            // Stats
            if !manager.entries.isEmpty {
                HStack {
                    Text("\(manager.entries.count) entries")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    let totalUsage = manager.entries.reduce(0) { $0 + $1.usageCount }
                    if totalUsage > 0 {
                        Text("• \(totalUsage) total replacements")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(Theme.current.foregroundMuted)

            Text(searchText.isEmpty ? "No dictionary entries" : "No matching entries")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)

            if searchText.isEmpty {
                Button("Add Your First Entry") {
                    showingAddSheet = true
                }
                .font(Theme.current.fontXS)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
    }

    private var entriesList: some View {
        VStack(spacing: 0) {
            ForEach(filteredEntries) { entry in
                DictionaryEntryRow(
                    entry: entry,
                    onToggle: { manager.toggleEntry(entry) },
                    onEdit: { editingEntry = entry },
                    onDelete: { manager.deleteEntry(entry) }
                )

                if entry.id != filteredEntries.last?.id {
                    Divider()
                        .background(Theme.current.border)
                }
            }
        }
    }

    // MARK: - Import/Export

    private func exportDictionary() {
        guard let data = manager.exportJSON() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "talkie-dictionary.json"

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                _ = try? manager.importJSON(data, merge: true)
            }
        }
    }
}

// MARK: - Dictionary Entry Row

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Enable toggle
            Toggle("", isOn: .init(
                get: { entry.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Trigger → Replacement
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(entry.trigger)
                        .font(Theme.current.fontSM.monospaced())
                        .foregroundColor(entry.isEnabled ? Theme.current.foreground : Theme.current.foregroundMuted)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(entry.replacement)
                        .font(Theme.current.fontSM.monospaced())
                        .foregroundColor(entry.isEnabled ? Theme.current.accent : Theme.current.foregroundMuted)
                }

                HStack(spacing: Spacing.xs) {
                    Text(entry.matchType.displayName)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    if let category = entry.category {
                        Text("• \(category)")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            }

            Spacer()

            // Usage count
            if entry.usageCount > 0 {
                Text("\(entry.usageCount)")
                    .font(Theme.current.fontXS.monospacedDigit())
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.xs)
            }

            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: Spacing.xs) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.current.foregroundSecondary)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(isHovered ? Theme.current.backgroundTertiary : Color.clear)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Dictionary Entry Sheet

struct DictionaryEntrySheet: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var trigger: String = ""
    @State private var replacement: String = ""
    @State private var matchType: DictionaryMatchType = .exact
    @State private var category: String = ""

    private var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Entry" : "Add Entry")
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
            .background(Theme.current.backgroundSecondary)

            Divider().background(Theme.current.border)

            // Form
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Trigger
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Trigger")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    TextField("e.g., react", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.current.fontSM.monospaced())
                }

                // Replacement
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Replace with")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    TextField("e.g., React", text: $replacement)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.current.fontSM.monospaced())
                }

                // Match type
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Match type")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Picker("", selection: $matchType) {
                        ForEach(DictionaryMatchType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(matchType.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                // Category (optional)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Category (optional)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    TextField("e.g., Technical", text: $category)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.current.fontSM)
                }
            }
            .padding(Spacing.md)

            Spacer()

            Divider().background(Theme.current.border)

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveEntry()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(trigger.isEmpty || replacement.isEmpty)
            }
            .padding(Spacing.md)
        }
        .frame(width: 360, height: 400)
        .background(Theme.current.background)
        .onAppear {
            if let entry = entry {
                trigger = entry.trigger
                replacement = entry.replacement
                matchType = entry.matchType
                category = entry.category ?? ""
            }
        }
    }

    private func saveEntry() {
        let newEntry = DictionaryEntry(
            id: entry?.id ?? UUID(),
            trigger: trigger.trimmingCharacters(in: .whitespaces),
            replacement: replacement.trimmingCharacters(in: .whitespaces),
            matchType: matchType,
            isEnabled: entry?.isEnabled ?? true,
            category: category.isEmpty ? nil : category.trimmingCharacters(in: .whitespaces),
            createdAt: entry?.createdAt ?? Date(),
            usageCount: entry?.usageCount ?? 0
        )
        onSave(newEntry)
        dismiss()
    }
}
