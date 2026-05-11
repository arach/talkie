//
//  ContextRulesDetailColumn.swift
//  Talkie macOS
//
//  Right column: inline context rule editor or empty state
//  Follows WorkflowDetailColumn pattern for 3-column NavigationSplitView
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct ContextRulesDetailColumn: View {
    @Binding var selectedRuleID: UUID?
    @Binding var editingRule: ContextRule?

    var body: some View {
        Group {
            if editingRule != nil {
                ContextRuleInlineEditor(
                    editingRule: $editingRule,
                    selectedRuleID: $selectedRuleID
                )
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("SELECT OR CREATE")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Select a rule from the list,\nor create a new one.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
    }
}

// MARK: - Inline Editor

private struct ContextRuleInlineEditor: View {
    @Binding var editingRule: ContextRule?
    @Binding var selectedRuleID: UUID?

    private var registry: LLMProviderRegistry { LLMProviderRegistry.shared }

    @State private var name: String = ""
    @State private var appBundleIDs: [String] = []
    @State private var behavior: ContextRuleBehavior = .autoRefine
    @State private var prompt: String = ""
    @State private var isEnabled: Bool = true
    @State private var llmProviderId: String = ""
    @State private var llmModelId: String = ""
    @State private var llmOverrideExpanded: Bool = false
    @State private var selectionRoutineEnabled: Bool = false
    @State private var selectionProcessMode: SelectionMode = .auto
    @State private var selectionDelivery: SelectionDelivery = .speak
    @State private var selectionVoiceOverride: String? = nil
    @State private var selectedRange: NSRange?
    @State private var lastClickedIndex: Int?

    // Track the rule ID we're editing to detect changes
    @State private var currentEditID: UUID?

    private var isNew: Bool {
        guard let rule = editingRule else { return true }
        return !ContextRuleStore.shared.rules.contains(where: { $0.id == rule.id })
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Visual header — app icon(s) + editable name
                    ruleHeader

                    // Enabled toggle
                    enabledToggle

                    // Running apps picker — wrapping grid
                    appPickerSection

                    // Behavior — segmented control + tinted card
                    behaviorSection

                    // Prompt — TalkieTextEditor
                    promptSection

                    // LLM Override — collapsible
                    llmOverrideSection

                    // Selection Routine — frozen workflow for selections
                    selectionRoutineSection
                }
                .padding(Spacing.lg)
            }

            // Sticky action bar
            actionBar
        }
        .background(Theme.current.background)
        .onAppear { syncFromRule() }
        .onChange(of: editingRule?.id) { _, _ in syncFromRule() }
    }

    // MARK: - Visual Header

    private var ruleHeader: some View {
        HStack(spacing: Spacing.md) {
            // App icon display adapts to selection count
            headerIconCluster
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                // Editable rule name
                TextField("Rule name", text: $name)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
                    .textFieldStyle(.plain)

                // Subtitle adapts to selection
                if appBundleIDs.count == 1 {
                    Text(appBundleIDs[0])
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                } else if appBundleIDs.count > 1 {
                    Text("\(appBundleIDs.count) apps selected")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    Text("No app selected")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var headerIconCluster: some View {
        if appBundleIDs.count == 1, let bid = appBundleIDs.first {
            singleAppIcon(bid)
        } else if appBundleIDs.count >= 2 {
            // Overlapping mini icons
            ZStack {
                appIconImage(appBundleIDs[0])
                    .frame(width: 32, height: 32)
                    .offset(x: -6, y: -4)

                appIconImage(appBundleIDs[1])
                    .frame(width: 28, height: 28)
                    .offset(x: 8, y: 6)

                if appBundleIDs.count > 2 {
                    Text("+\(appBundleIDs.count - 2)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.current.foreground.opacity(0.12))
                        .cornerRadius(6)
                        .offset(x: 16, y: -8)
                }
            }
        } else {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.foreground.opacity(0.04))
                .cornerRadius(CornerRadius.sm)
        }
    }

    @ViewBuilder
    private func singleAppIcon(_ bundleID: String) -> some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
        } else {
            Image(systemName: "app")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func appIconImage(_ bundleID: String) -> some View {
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

    // MARK: - Enabled Toggle

    private var enabledToggle: some View {
        HStack(spacing: Spacing.sm) {
            Text("Enabled")
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    // MARK: - App Picker (Wrapping Grid, Multi-Select)

    private var appPickerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Apps")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            // Wrapping grid of running app icons
            let apps = runningApps()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: Spacing.xs) {
                ForEach(Array(apps.enumerated()), id: \.element.bundleIdentifier) { index, app in
                    runningAppButton(app, index: index, apps: apps)
                }
            }

            Text("Click to select \u{00B7} \u{2325} toggle \u{00B7} \u{21E7} range")
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))
        }
    }

    private func runningAppButton(_ app: NSRunningApplication, index: Int, apps: [NSRunningApplication]) -> some View {
        let bid = app.bundleIdentifier ?? ""
        let isActive = appBundleIDs.contains(bid)

        return Button {
            handleAppClick(bid: bid, index: index, apps: apps, appName: app.localizedName ?? bid)
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

    private func handleAppClick(bid: String, index: Int, apps: [NSRunningApplication], appName: String) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []

        if modifiers.contains(.option) {
            // Option-click: toggle this app in/out
            if let existingIndex = appBundleIDs.firstIndex(of: bid) {
                appBundleIDs.remove(at: existingIndex)
            } else {
                appBundleIDs.append(bid)
            }
            lastClickedIndex = index
        } else if modifiers.contains(.shift), let lastIndex = lastClickedIndex {
            // Shift-click: range select
            let range = min(lastIndex, index)...max(lastIndex, index)
            for i in range {
                guard i < apps.count else { continue }
                let rangeBid = apps[i].bundleIdentifier ?? ""
                if !appBundleIDs.contains(rangeBid) {
                    appBundleIDs.append(rangeBid)
                }
            }
            // Don't update lastClickedIndex for shift-click
        } else {
            // Plain click: replace selection
            appBundleIDs = [bid]
            lastClickedIndex = index
            if name.isEmpty {
                name = appName
            }
        }
    }

    // MARK: - Behavior (Segmented + Tinted Card)

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Behavior")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Picker("", selection: $behavior) {
                Text("Refine").tag(ContextRuleBehavior.autoRefine)
                Text("Edit").tag(ContextRuleBehavior.autoInterstitial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            behaviorCard
        }
    }

    private var behaviorCard: some View {
        let isRefine = behavior == .autoRefine
        let tint: Color = isRefine ? .green : .blue
        let icon = isRefine ? "bolt.fill" : "pencil.and.outline"
        let description = isRefine
            ? "Silently refines text via LLM before pasting. Falls back to raw text on timeout (5s)."
            : "Opens the scratchpad with the prompt pre-applied. You can review and edit before pasting."

        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 20)
                .padding(.top, 1)

            Text(description)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foreground.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(tint.opacity(0.15), lineWidth: 0.5)
        )
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Prompt (TalkieTextEditor)

    private var promptSection: some View {
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

            TalkieTextEditor(
                text: $prompt,
                selectedRange: $selectedRange,
                font: .systemFont(ofSize: 14),
                textColor: NSColor(Theme.current.foreground),
                insertionPointColor: .controlAccentColor
            )
            .frame(minHeight: 120, maxHeight: 200)
            .padding(12)
            .background(Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Theme.current.divider, lineWidth: 0.5)
            )
        }
    }

    // MARK: - LLM Override (Collapsible)

    private var llmOverrideSection: some View {
        DisclosureGroup(isExpanded: $llmOverrideExpanded) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
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
            .padding(.top, Spacing.xs)
        } label: {
            Text("LLM Override")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Selection Routine

    private var selectionRoutineSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.teal)
                    .frame(width: 3, height: 14)

                Text("Selection")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Toggle("", isOn: $selectionRoutineEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }

            if selectionRoutineEnabled {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("When text is selected in this app, process and deliver it.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))

                    // Process mode
                    HStack {
                        Text("Process")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(width: 60, alignment: .leading)

                        Picker("", selection: $selectionProcessMode) {
                            ForEach(SelectionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Delivery
                    HStack {
                        Text("Deliver")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(width: 60, alignment: .leading)

                        Picker("", selection: $selectionDelivery) {
                            ForEach(SelectionDelivery.allCases) { delivery in
                                Label(delivery.displayName, systemImage: delivery.icon).tag(delivery)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Voice override (only for speak delivery)
                    if selectionDelivery == .speak {
                        HStack {
                            Text("Voice")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .frame(width: 60, alignment: .leading)

                            Picker("", selection: Binding(
                                get: { selectionVoiceOverride ?? "" },
                                set: { selectionVoiceOverride = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("Default").tag("")
                                Section("OpenAI") {
                                    ForEach(TTSVoiceCatalog.openAIVoices, id: \.id) { voice in
                                        Text(voice.displayName).tag(voice.id)
                                    }
                                }
                                Section("ElevenLabs Free") {
                                    ForEach(TTSVoiceCatalog.elevenLabsFreeVoices, id: \.id) { voice in
                                        Text(voice.displayName).tag(voice.id)
                                    }
                                }
                                Section("ElevenLabs Premium") {
                                    ForEach(TTSVoiceCatalog.elevenLabsPremiumVoices, id: \.id) { voice in
                                        Text(voice.displayName).tag(voice.id)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Color.teal.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.teal.opacity(0.12), lineWidth: 0.5)
                )
                .cornerRadius(CornerRadius.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
        .animation(.easeInOut(duration: 0.2), value: selectionRoutineEnabled)
    }

    // MARK: - Sticky Action Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.current.divider)
                .frame(height: 1)

            HStack {
                Button("Cancel") {
                    editingRule = nil
                    selectedRuleID = nil
                }

                Spacer()

                if !isNew {
                    Button(role: .destructive) {
                        deleteRule()
                    } label: {
                        Text("Delete")
                            .foregroundColor(.red)
                    }
                }

                Button(isNew ? "Create" : "Save") {
                    saveRule()
                }
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .background(Theme.current.background)
    }

    // MARK: - Logic

    private func syncFromRule() {
        guard let rule = editingRule, rule.id != currentEditID else { return }
        currentEditID = rule.id
        name = rule.name
        appBundleIDs = rule.appBundleIDs
        behavior = rule.behavior
        prompt = rule.prompt
        isEnabled = rule.isEnabled
        llmProviderId = rule.llmProviderId ?? ""
        llmModelId = rule.llmModelId ?? ""
        llmOverrideExpanded = rule.llmProviderId != nil
        selectionRoutineEnabled = rule.selectionRoutine?.enabled ?? false
        selectionProcessMode = rule.selectionRoutine?.processMode ?? .auto
        selectionDelivery = rule.selectionRoutine?.delivery ?? .speak
        selectionVoiceOverride = rule.selectionRoutine?.voiceOverride
        lastClickedIndex = nil
    }

    private func saveRule() {
        let selRoutine: SelectionRoutine? = selectionRoutineEnabled
            ? SelectionRoutine(
                enabled: true,
                processMode: selectionProcessMode,
                prompt: nil,
                delivery: selectionDelivery,
                voiceOverride: selectionVoiceOverride
            )
            : nil

        let rule = ContextRule(
            id: editingRule?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            appBundleIDs: appBundleIDs,
            isEnabled: isEnabled,
            behavior: behavior,
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            llmProviderId: llmProviderId.isEmpty ? nil : llmProviderId,
            llmModelId: llmModelId.isEmpty ? nil : llmModelId,
            selectionRoutine: selRoutine,
            createdAt: editingRule?.createdAt ?? Date(),
            updatedAt: Date()
        )

        if isNew {
            ContextRuleStore.shared.add(rule)
        } else {
            ContextRuleStore.shared.update(rule)
        }

        // Notify list to reload
        NotificationCenter.default.post(name: .contextRulesDidChange, object: nil)

        editingRule = rule
        selectedRuleID = rule.id
    }

    private func deleteRule() {
        guard let rule = editingRule else { return }
        ContextRuleStore.shared.delete(id: rule.id)
        NotificationCenter.default.post(name: .contextRulesDidChange, object: nil)
        editingRule = nil
        selectedRuleID = nil
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let contextRulesDidChange = Notification.Name("contextRulesDidChange")
}
