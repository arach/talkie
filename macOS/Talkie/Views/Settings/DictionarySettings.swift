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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                header

                // Global toggle
                globalToggle

                // Dictionary list
                dictionaryList

                // Drop zone
                dropZone

                Spacer(minLength: Spacing.xl)
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            Task {
                await manager.load()
                await manager.ensureDefaultDictionary()
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

            // New dictionary button
            if isCreatingNew {
                newDictionaryCard
            } else {
                Button(action: { isCreatingNew = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("New Dictionary")
                            .font(Theme.current.fontSM)
                    }
                    .foregroundColor(Theme.current.accent)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.md)
                    .background(Theme.current.backgroundSecondary.opacity(0.5))
                    .cornerRadius(CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundColor(Theme.current.border)
                    )
                }
                .buttonStyle(.plain)
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

    // MARK: - Drop Zone

    private var dropZone: some View {
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
                    // Add entry row
                    if isAddingEntry {
                        InlineEntryEditor(
                            onSave: { entry in
                                onAddEntry(entry)
                                isAddingEntry = false
                            },
                            onCancel: { isAddingEntry = false }
                        )
                        Divider().background(Theme.current.border)
                    } else {
                        Button(action: { isAddingEntry = true }) {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 10))
                                Text("Add entry...")
                                    .font(Theme.current.fontXS)
                                Spacer()
                            }
                            .foregroundColor(Theme.current.accent)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.current.backgroundTertiary.opacity(0.5))

                        Divider().background(Theme.current.border)
                    }

                    // Entry rows
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

                            if entry.id != dictionary.entries.last?.id {
                                Divider().background(Theme.current.border)
                            }
                        }
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

                // Trigger → Replacement
                HStack(spacing: Spacing.xs) {
                    Text(entry.trigger)
                        .font(Theme.current.fontSM.monospaced())
                        .foregroundColor(entry.isEnabled ? Theme.current.foreground : Theme.current.foregroundMuted)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(entry.replacement)
                        .font(Theme.current.fontSM.monospaced())
                        .foregroundColor(entry.isEnabled ? Theme.current.accent : Theme.current.foregroundMuted)
                }

                // Match type badge - short form
                Text(entry.matchType == .exact ? "word" : "any")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)
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
    @State private var wholeWordOnly: Bool = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Trigger
            TextField("Source word", text: $trigger)
                .textFieldStyle(.roundedBorder)
                .font(Theme.current.fontSM.monospaced())
                .frame(minWidth: 90, maxWidth: 150)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundMuted)

            // Replacement
            TextField("Replacement", text: $replacement)
                .textFieldStyle(.roundedBorder)
                .font(Theme.current.fontSM.monospaced())
                .frame(minWidth: 90, maxWidth: 150)

            // Whole word toggle
            Toggle(isOn: $wholeWordOnly) {
                Text("Whole word")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .toggleStyle(.checkbox)
            .help("Match whole words only, or match anywhere in text")

            Spacer()

            // Actions
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.current.foregroundMuted)

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.current.accent)
            .disabled(trigger.isEmpty || replacement.isEmpty)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.accent.opacity(0.05))
        .onAppear {
            if let entry = entry {
                trigger = entry.trigger
                replacement = entry.replacement
                wholeWordOnly = entry.matchType == .exact
            }
        }
    }

    private func save() {
        let newEntry = DictionaryEntry(
            id: entry?.id ?? UUID(),
            trigger: trigger.trimmingCharacters(in: .whitespaces),
            replacement: replacement.trimmingCharacters(in: .whitespaces),
            matchType: wholeWordOnly ? .exact : .caseInsensitive,
            isEnabled: entry?.isEnabled ?? true,
            category: entry?.category,
            createdAt: entry?.createdAt ?? Date(),
            usageCount: entry?.usageCount ?? 0
        )
        onSave(newEntry)
    }
}

// MARK: - Preview

#Preview("Dictionary Settings") {
    DictionarySettingsView()
        .frame(width: 500, height: 600)
}
