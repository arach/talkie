//
//  ContextRulesSettingsView.swift
//  Talkie macOS
//
//  Settings for context rules: app-aware post-transcription prompting
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Context Rules Settings View

struct ContextRulesSettingsView: View {
    @State private var rules: [ContextRule] = []
    @State private var isEnabled: Bool = ContextRuleStore.shared.isEnabled
    @State private var showingAddSheet = false
    @State private var editingRule: ContextRule?

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "app.badge.checkmark",
                title: "CONTEXT RULES",
                subtitle: "Auto-refine dictations based on which app you're in."
            )
        } content: {
            // Master toggle
            masterToggle

            if isEnabled {
                // Rules list
                if rules.isEmpty {
                    emptyState
                } else {
                    rulesList
                }

                // Add button
                addButton

                // Preset templates
                presetSection
            }
        }
        .onAppear { loadRules() }
        .sheet(isPresented: $showingAddSheet) {
            ContextRuleEditorSheet(rule: nil) { newRule in
                ContextRuleStore.shared.add(newRule)
                loadRules()
            }
        }
        .sheet(item: $editingRule) { rule in
            ContextRuleEditorSheet(rule: rule) { updatedRule in
                ContextRuleStore.shared.update(updatedRule)
                loadRules()
            }
        }
    }

    // MARK: - Components

    private var masterToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Enable Context Rules")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text("Automatically apply LLM prompts based on the target app")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    ContextRuleStore.shared.isEnabled = newValue
                }
        }
        .padding(Spacing.md)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 24))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))

            Text("No rules yet")
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Create a rule to auto-refine dictations for specific apps.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private var rulesList: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(rules) { rule in
                contextRuleRow(rule)
            }
        }
    }

    private func contextRuleRow(_ rule: ContextRule) -> some View {
        HStack(spacing: Spacing.sm) {
            // App icon cluster
            rowIconCluster(for: rule.appBundleIDs)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                HStack(spacing: Spacing.xs) {
                    // Behavior badge
                    Text(rule.behavior == .autoRefine ? "REFINE" : "EDIT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(rule.behavior == .autoRefine ? .green : .blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (rule.behavior == .autoRefine ? Color.green : Color.blue)
                                .opacity(0.15)
                        )
                        .cornerRadius(3)

                    Text(rule.appSummary)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    var updated = rule
                    updated.isEnabled = newValue
                    ContextRuleStore.shared.update(updated)
                    loadRules()
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            // Edit button
            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                ContextRuleStore.shared.delete(id: rule.id)
                loadRules()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    @ViewBuilder
    private func rowIconCluster(for bundleIDs: [String]) -> some View {
        if bundleIDs.isEmpty {
            Image(systemName: "app")
                .font(.system(size: 20))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if bundleIDs.count == 1 {
            rowAppIcon(bundleIDs[0])
        } else {
            ZStack {
                rowAppIcon(bundleIDs[0])
                    .frame(width: 22, height: 22)
                    .offset(x: -3, y: -2)

                rowAppIcon(bundleIDs[1])
                    .frame(width: 18, height: 18)
                    .offset(x: 4, y: 3)
            }
        }
    }

    @ViewBuilder
    private func rowAppIcon(_ bundleID: String) -> some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
        } else {
            Image(systemName: "app")
                .font(.system(size: 16))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                Text("Add Rule")
                    .font(Theme.current.fontSMMedium)
            }
        }
        .buttonStyle(.bordered)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.purple)
                    .frame(width: 3, height: 14)

                Text("PROMPT TEMPLATES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Text("Suggested prompts for common app categories. Tap to create a rule with this prompt.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))

            VStack(spacing: Spacing.xs) {
                ForEach(ContextRulePreset.allCases, id: \.name) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: ContextRulePreset) -> some View {
        Button {
            showingAddSheet = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(preset.prompt)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.sm)
            .background(Theme.current.backgroundSecondary.opacity(0.5))
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadRules() {
        rules = ContextRuleStore.shared.rules
    }
}

// MARK: - Rule Editor Sheet

private struct ContextRuleEditorSheet: View {
    let existingRule: ContextRule?
    let onSave: (ContextRule) -> Void
    @Environment(\.dismiss) private var dismiss

    private var registry: LLMProviderRegistry { LLMProviderRegistry.shared }

    @State private var name: String
    @State private var appBundleIDs: [String]
    @State private var behavior: ContextRuleBehavior
    @State private var prompt: String
    @State private var llmProviderId: String
    @State private var llmModelId: String

    init(rule: ContextRule?, onSave: @escaping (ContextRule) -> Void) {
        self.existingRule = rule
        self.onSave = onSave
        _name = State(initialValue: rule?.name ?? "")
        _appBundleIDs = State(initialValue: rule?.appBundleIDs ?? [])
        _behavior = State(initialValue: rule?.behavior ?? .autoRefine)
        _prompt = State(initialValue: rule?.prompt ?? "")
        _llmProviderId = State(initialValue: rule?.llmProviderId ?? "")
        _llmModelId = State(initialValue: rule?.llmModelId ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !appBundleIDs.isEmpty
            && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var modelsForProvider: [LLMModel] {
        registry.allModels.filter { $0.provider == llmProviderId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            Text(existingRule == nil ? "NEW CONTEXT RULE" : "EDIT CONTEXT RULE")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Theme.current.foreground)

            // Rule name
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Name")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                TextField("e.g. Slack - Casual", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // App selection
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Apps")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Running apps as clickable icons
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: Spacing.xs) {
                    ForEach(runningApps(), id: \.bundleIdentifier) { app in
                        sheetAppButton(app)
                    }
                }

                if !appBundleIDs.isEmpty {
                    Text(appBundleIDs.count == 1 ? appBundleIDs[0] : "\(appBundleIDs.count) apps selected")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            // Behavior toggle
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Behavior")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Picker("", selection: $behavior) {
                    Text("Auto-refine (paste refined text)").tag(ContextRuleBehavior.autoRefine)
                    Text("Auto-interstitial (open scratchpad)").tag(ContextRuleBehavior.autoInterstitial)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(behavior == .autoRefine
                    ? "Silently refines text via LLM before pasting. Falls back to raw text on timeout (5s)."
                    : "Opens the scratchpad with the prompt pre-applied. You can review and edit before pasting."
                )
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
            }

            // Prompt editor
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Prompt")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Menu("Templates") {
                        ForEach(ContextRulePreset.allCases, id: \.name) { preset in
                            Button(preset.name) {
                                prompt = preset.prompt
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(Theme.current.fontXS)
                }

                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 80)
                    .padding(4)
                    .background(Theme.current.backgroundSecondary)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )
            }

            // LLM Provider / Model override
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("LLM Override")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Leave as \"Default\" to use your global LLM settings.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))

                HStack {
                    Text("Provider")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 60, alignment: .leading)

                    Picker("", selection: $llmProviderId) {
                        Text("Default").tag("")
                        ForEach(registry.providers, id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: llmProviderId) { _, newValue in
                        if newValue.isEmpty {
                            llmModelId = ""
                        } else if let defaultModel = LLMConfig.shared.defaultModel(for: newValue) {
                            llmModelId = defaultModel
                        } else if let first = modelsForProvider.first {
                            llmModelId = first.id
                        }
                    }
                }

                if !llmProviderId.isEmpty {
                    HStack {
                        Text("Model")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(width: 60, alignment: .leading)

                        Picker("", selection: $llmModelId) {
                            Text("Select model...").tag("")
                            ForEach(modelsForProvider, id: \.id) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.sm)

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(existingRule == nil ? "Create" : "Save") {
                    let rule = ContextRule(
                        id: existingRule?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        appBundleIDs: appBundleIDs,
                        isEnabled: existingRule?.isEnabled ?? true,
                        behavior: behavior,
                        prompt: prompt.trimmingCharacters(in: .whitespaces),
                        llmProviderId: llmProviderId.isEmpty ? nil : llmProviderId,
                        llmModelId: llmModelId.isEmpty ? nil : llmModelId,
                        createdAt: existingRule?.createdAt ?? Date(),
                        updatedAt: Date()
                    )
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 480, height: 620)
    }

    private func sheetAppButton(_ app: NSRunningApplication) -> some View {
        let bid = app.bundleIdentifier ?? ""
        let isActive = appBundleIDs.contains(bid)

        return Button {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            if modifiers.contains(.option) {
                // Toggle
                if let idx = appBundleIDs.firstIndex(of: bid) {
                    appBundleIDs.remove(at: idx)
                } else {
                    appBundleIDs.append(bid)
                }
            } else {
                // Replace
                appBundleIDs = [bid]
                if name.isEmpty {
                    name = app.localizedName ?? bid
                }
            }
        } label: {
            VStack(spacing: 2) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(4)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
        .help(app.localizedName ?? bid)
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
