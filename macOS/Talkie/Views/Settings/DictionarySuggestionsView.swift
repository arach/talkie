//
//  DictionarySuggestionsView.swift
//  Talkie
//
//  AI-powered dictionary suggestions - analyze transcriptions to find corrections
//

import SwiftUI
import TalkieKit

struct DictionarySuggestionsView: View {
    @ObservedObject private var service = DictionarySuggestionService.shared
    @ObservedObject private var dictionaryManager = DictionaryManager.shared
    private var registry: LLMProviderRegistry { LLMProviderRegistry.shared }

    @State private var selectedProviderId: String = ""
    @State private var selectedModelId: String = ""
    @State private var selectedTimeRange: SuggestionTimeRange = .sevenDays
    @State private var targetDictionaryId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            header

            // Configuration section
            configurationSection

            // Analyze button
            analyzeButton

            // Error display
            if let error = service.lastError {
                errorBanner(error)
            }

            // Results section
            if !service.pendingSuggestions.isEmpty {
                suggestionsList
            } else if !service.isAnalyzing {
                emptyState
            }

            Spacer()
        }
        .padding(Spacing.lg)
        .onAppear {
            setupDefaults()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("AI SUGGESTIONS")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Analyze your transcriptions to find words that need dictionary entries")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            if let lastAnalyzed = service.lastAnalyzedAt {
                Text("Last analyzed: \(lastAnalyzed.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // LLM Provider picker
            HStack {
                Text("LLM Provider")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $selectedProviderId) {
                    Text("Select provider...").tag("")
                    ForEach(availableProviders, id: \.id) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedProviderId) { _, newValue in
                    updateModelSelection(for: newValue)
                }
            }

            // Model picker
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

            // Time range picker
            HStack {
                Text("Time Range")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $selectedTimeRange) {
                    ForEach(SuggestionTimeRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            // Target dictionary picker
            HStack {
                Text("Add to")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                    .frame(width: 100, alignment: .leading)

                Picker("", selection: $targetDictionaryId) {
                    Text("Select dictionary...").tag(nil as UUID?)
                    ForEach(dictionaryManager.dictionaries) { dict in
                        Text(dict.name).tag(dict.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        HStack {
            Spacer()

            Button(action: runAnalysis) {
                HStack(spacing: Spacing.xs) {
                    if service.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                    }
                    Text(service.isAnalyzing ? "Analyzing..." : "Analyze Transcriptions")
                        .font(Theme.current.fontSMMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(canAnalyze ? Theme.current.accent : Theme.current.foregroundMuted)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(!canAnalyze || service.isAnalyzing)

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

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Suggestions (\(service.pendingSuggestions.count))")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Button("Clear All") {
                    service.clearAllSuggestions()
                }
                .font(Theme.current.fontXS)
                .foregroundColor(.red)
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(service.pendingSuggestions) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            onAccept: {
                                if let dictId = targetDictionaryId {
                                    Task {
                                        await service.acceptSuggestion(suggestion, toDictionaryId: dictId)
                                    }
                                }
                            },
                            onDismiss: {
                                service.dismissSuggestion(suggestion)
                            },
                            canAccept: targetDictionaryId != nil
                        )

                        if suggestion.id != service.pendingSuggestions.last?.id {
                            Divider().background(Theme.current.border)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("No suggestions yet")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundMuted)

            Text("Click 'Analyze Transcriptions' to find potential dictionary entries")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background(Theme.current.backgroundSecondary.opacity(0.5))
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Helpers

    private var availableProviders: [LLMProvider] {
        registry.providers
    }

    private var modelsForProvider: [LLMModel] {
        registry.allModels.filter { $0.provider == selectedProviderId }
    }

    private var canAnalyze: Bool {
        !selectedProviderId.isEmpty && !selectedModelId.isEmpty
    }

    private func setupDefaults() {
        // Set default provider if available
        if selectedProviderId.isEmpty {
            Task {
                if let (provider, modelId) = await registry.firstAvailableProvider() {
                    selectedProviderId = provider.id
                    selectedModelId = modelId
                }
            }
        }

        // Set default target dictionary
        if targetDictionaryId == nil, let firstDict = dictionaryManager.dictionaries.first {
            targetDictionaryId = firstDict.id
        }
    }

    private func updateModelSelection(for providerId: String) {
        // Select default model for provider
        if let defaultModel = LLMConfig.shared.defaultModel(for: providerId) {
            selectedModelId = defaultModel
        } else if let firstModel = modelsForProvider.first {
            selectedModelId = firstModel.id
        }
    }

    private func runAnalysis() {
        Task {
            await service.generateSuggestions(
                providerId: selectedProviderId,
                modelId: selectedModelId,
                timeRange: selectedTimeRange
            )
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let suggestion: DictionarySuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let canAccept: Bool

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // From -> To
            HStack(spacing: Spacing.xs) {
                Text(suggestion.from)
                    .font(Theme.current.fontSM.monospaced())
                    .foregroundColor(Theme.current.foregroundMuted)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.current.foregroundMuted)

                Text(suggestion.to)
                    .font(Theme.current.fontSM.monospaced())
                    .foregroundColor(Theme.current.accent)
            }

            // Confidence badge
            Text("\(Int(suggestion.confidence * 100))%")
                .font(.system(size: 10))
                .foregroundColor(confidenceColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(confidenceColor.opacity(0.1))
                .cornerRadius(4)

            Spacer()

            // Actions
            if isHovered {
                HStack(spacing: Spacing.sm) {
                    Button(action: onAccept) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(canAccept ? Theme.current.accent : Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAccept)
                    .help(canAccept ? "Add to dictionary" : "Select a dictionary first")

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss suggestion")
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(isHovered ? Theme.current.backgroundTertiary : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var confidenceColor: Color {
        switch suggestion.confidence {
        case 0.9...1.0: return .green
        case 0.8..<0.9: return .blue
        case 0.7..<0.8: return .orange
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview("Dictionary Suggestions") {
    DictionarySuggestionsView()
        .frame(width: 500, height: 600)
}
