//
//  DictionaryURLExtractModal.swift
//  Talkie
//
//  Modal for extracting dictionary entries from a URL
//

import SwiftUI
import TalkieKit

struct DictionaryURLExtractModal: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var extractor = DictionaryURLExtractor.shared
    @ObservedObject private var dictionaryManager = DictionaryManager.shared
    private var registry: LLMProviderRegistry { LLMProviderRegistry.shared }

    @State private var urlString: String = ""
    @State private var selectedProviderId: String = ""
    @State private var selectedModelId: String = ""
    @State private var newDictionaryName: String = ""
    @State private var selectedEntries: Set<UUID> = []
    @State private var isCreatingDictionary: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            header

            // URL Input
            urlInputSection

            // LLM Configuration
            llmConfigSection

            // Extract button
            extractButton

            // Error display
            if let error = extractor.lastError {
                errorBanner(error)
            }

            // Results section
            if !extractor.extractedEntries.isEmpty {
                resultsSection
            }

            Spacer()

            // Footer actions
            footerActions
        }
        .padding(Spacing.lg)
        .frame(width: 550, height: 500)
        .onAppear {
            setupDefaults()
        }
        .onDisappear {
            extractor.clearResults()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("EXTRACT FROM URL")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Extract domain terminology from a web page to create a specialized dictionary")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    // MARK: - URL Input

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Web Page URL")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)

            TextField("https://docs.example.com/api-reference", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .font(Theme.current.fontSM)
        }
    }

    // MARK: - LLM Configuration

    private var llmConfigSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("LLM Provider")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $selectedProviderId) {
                    Text("Select provider...").tag("")
                    ForEach(registry.providers, id: \.id) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedProviderId) { _, newValue in
                    updateModelSelection(for: newValue)
                }
            }

            if !selectedProviderId.isEmpty {
                HStack {
                    Text("Model")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .frame(width: 100, alignment: .leading)

                    Picker("", selection: $selectedModelId) {
                        Text("Select model...").tag("")
                        ForEach(modelsForProvider, id: \.id) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Extract Button

    private var extractButton: some View {
        HStack {
            Spacer()

            Button(action: runExtraction) {
                HStack(spacing: Spacing.xs) {
                    if extractor.isExtracting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 12))
                    }
                    Text(extractor.isExtracting ? "Extracting..." : "Extract Terminology")
                        .font(Theme.current.fontSMMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(canExtract ? Theme.current.accent : Theme.current.foregroundMuted)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(!canExtract || extractor.isExtracting)

            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foreground)
            Spacer()
        }
        .padding(Spacing.sm)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extracted Entries (\(extractor.extractedEntries.count))")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    if let title = extractor.pageTitle {
                        Text("From: \(title)")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(selectedEntries.count == extractor.extractedEntries.count ? "Deselect All" : "Select All") {
                    if selectedEntries.count == extractor.extractedEntries.count {
                        selectedEntries.removeAll()
                    } else {
                        selectedEntries = Set(extractor.extractedEntries.map { $0.id })
                    }
                }
                .font(Theme.current.fontXS)
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.accent)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(extractor.extractedEntries) { entry in
                        ExtractedEntryRow(
                            entry: entry,
                            isSelected: selectedEntries.contains(entry.id),
                            onToggle: {
                                if selectedEntries.contains(entry.id) {
                                    selectedEntries.remove(entry.id)
                                } else {
                                    selectedEntries.insert(entry.id)
                                }
                            }
                        )

                        if entry.id != extractor.extractedEntries.last?.id {
                            Divider().background(Theme.current.border)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.md)

            // New dictionary name
            HStack {
                Text("Dictionary Name")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)

                TextField("e.g., Medical Terms", text: $newDictionaryName)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.current.fontSM)
            }
        }
    }

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Spacer()

            if !extractor.extractedEntries.isEmpty {
                Button(action: createDictionary) {
                    HStack(spacing: Spacing.xs) {
                        if isCreatingDictionary {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Create Dictionary (\(selectedEntries.count) entries)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedEntries.isEmpty || newDictionaryName.isEmpty || isCreatingDictionary)
            }
        }
    }

    // MARK: - Helpers

    private var modelsForProvider: [LLMModel] {
        registry.allModels.filter { $0.provider == selectedProviderId }
    }

    private var canExtract: Bool {
        !urlString.isEmpty && !selectedProviderId.isEmpty && !selectedModelId.isEmpty
    }

    private func setupDefaults() {
        // Set default provider if available
        Task {
            if let (provider, modelId) = await registry.firstAvailableProvider() {
                selectedProviderId = provider.id
                selectedModelId = modelId
            }
        }

        // Initialize all entries as selected
        selectedEntries = Set(extractor.extractedEntries.map { $0.id })
    }

    private func updateModelSelection(for providerId: String) {
        if let defaultModel = LLMConfig.shared.defaultModel(for: providerId) {
            selectedModelId = defaultModel
        } else if let firstModel = modelsForProvider.first {
            selectedModelId = firstModel.id
        }
    }

    private func runExtraction() {
        Task {
            await extractor.extractFromURL(
                urlString,
                providerId: selectedProviderId,
                modelId: selectedModelId
            )

            // Auto-select all entries
            selectedEntries = Set(extractor.extractedEntries.map { $0.id })

            // Auto-generate dictionary name from page title
            if newDictionaryName.isEmpty, let title = extractor.pageTitle {
                newDictionaryName = title.prefix(30).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func createDictionary() {
        isCreatingDictionary = true

        Task {
            // Create new dictionary
            await dictionaryManager.createDictionary(name: newDictionaryName)

            // Find the newly created dictionary
            if let newDict = dictionaryManager.dictionaries.last(where: { $0.name == newDictionaryName }) {
                // Add selected entries
                let entriesToAdd = extractor.extractedEntries.filter { selectedEntries.contains($0.id) }
                for entry in entriesToAdd {
                    await dictionaryManager.addEntry(to: newDict.id, entry: entry)
                }
            }

            isCreatingDictionary = false
            dismiss()
        }
    }
}

// MARK: - Extracted Entry Row

struct ExtractedEntryRow: View {
    let entry: DictionaryEntry
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Toggle("", isOn: .init(get: { isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()

            Text(entry.trigger)
                .font(Theme.current.fontSM.monospaced())
                .foregroundColor(Theme.current.foregroundMuted)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundMuted)

            Text(entry.replacement)
                .font(Theme.current.fontSM.monospaced())
                .foregroundColor(Theme.current.accent)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(isSelected ? Theme.current.accent.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Preview

#Preview("URL Extract Modal") {
    DictionaryURLExtractModal()
}
