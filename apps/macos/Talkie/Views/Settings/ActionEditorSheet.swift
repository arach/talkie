//
//  ActionEditorSheet.swift
//  Talkie macOS
//
//  Simplified editor for creating/editing actions (single-step LLM workflows)
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Action Editor Sheet

struct ActionEditorSheet: View {
    let isNew: Bool
    let onSave: (WorkflowDefinition) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var name: String = ""
    @State private var selectedIcon: String = "sparkles"
    @State private var selectedColor: WorkflowColor = .cyan
    @State private var prompt: String = ""
    @State private var showInInterstitial: Bool = true
    @State private var showInDrafts: Bool = false
    @State private var appBundleIDs: [String] = []
    @State private var showingIconPicker: Bool = false

    // LLM Settings
    @State private var selectedProvider: WorkflowLLMProvider = .gemini
    @State private var temperature: Double = 0.7

    // Track the workflow ID for edits
    private let workflowId: UUID

    // MARK: - Init

    init(
        workflow: WorkflowDefinition? = nil,
        isNew: Bool,
        onSave: @escaping (WorkflowDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel

        if let workflow = workflow {
            self.workflowId = workflow.id
            _name = State(initialValue: workflow.name)
            _selectedIcon = State(initialValue: workflow.icon)
            _selectedColor = State(initialValue: workflow.color)

            // Extract LLM config from first step
            if let firstStep = workflow.steps.first,
               case .llm(let config) = firstStep.config {
                _prompt = State(initialValue: config.prompt)
                _selectedProvider = State(initialValue: config.provider ?? .gemini)
                _temperature = State(initialValue: config.temperature)
            }

            // Load context settings from preferences
            let repo = WorkflowPreferencesRepository()
            if let pref = try? repo.fetch(for: workflow.id) {
                _showInInterstitial = State(initialValue: pref.showInInterstitial)
                _showInDrafts = State(initialValue: pref.showInDrafts)
                _appBundleIDs = State(initialValue: pref.appBundleIDs)
            }
        } else {
            self.workflowId = UUID()
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Name and appearance
                    appearanceSection

                    Divider()

                    // Prompt
                    promptSection

                    Divider()

                    // Context settings
                    contextSection

                    Divider()

                    // LLM settings (collapsed by default)
                    llmSettingsSection
                }
                .padding(Spacing.lg)
            }

            Divider()

            // Footer
            footer
        }
        .background(Theme.current.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isNew ? "New Action" : "Edit Action")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("APPEARANCE")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.md) {
                // Icon button
                Button(action: { showingIconPicker = true }) {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 20))
                        .foregroundColor(selectedColor.color)
                        .frame(width: 44, height: 44)
                        .background(selectedColor.color.opacity(0.2))
                        .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingIconPicker) {
                    iconPickerPopover
                }

                // Name field
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("NAME")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    TextField("Action name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.current.fontSM)
                }

                // Color picker
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("COLOR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(spacing: 4) {
                        ForEach(WorkflowColor.allCases.prefix(6), id: \.self) { color in
                            colorButton(color)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func colorButton(_ color: WorkflowColor) -> some View {
        Button(action: { selectedColor = color }) {
            Circle()
                .fill(color.color)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("PROMPT")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("Use {{TRANSCRIPT}} for input text")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
            }

            TextEditor(text: $prompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Theme.current.border, lineWidth: 1)
                )

            // Quick templates
            HStack(spacing: Spacing.xs) {
                Text("Templates:")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                templateButton("Fix Grammar", prompt: "Fix any grammar, spelling, and punctuation errors in the following text. Preserve the original tone and meaning.\n\n{{TRANSCRIPT}}")
                templateButton("Concise", prompt: "Make this text more concise. Remove filler words and redundancy while keeping the core message.\n\n{{TRANSCRIPT}}")
                templateButton("Professional", prompt: "Rewrite this in a professional tone suitable for business communication.\n\n{{TRANSCRIPT}}")
            }
        }
    }

    @ViewBuilder
    private func templateButton(_ label: String, prompt templatePrompt: String) -> some View {
        Button(action: { prompt = templatePrompt }) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("SHOW IN")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.lg) {
                Toggle(isOn: $showInInterstitial) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interstitial")
                                .font(Theme.current.fontSMMedium)
                            Text("After recording")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $showInDrafts) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drafts")
                                .font(Theme.current.fontSMMedium)
                            Text("Quick Edit mode")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                }
                .toggleStyle(.switch)
            }

            // App context (advanced)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Limit this action to specific apps. Leave empty to show for all apps.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Common apps
                    HStack(spacing: Spacing.xs) {
                        appToggle("com.apple.mail", label: "Mail")
                        appToggle("com.tinyspeck.slackmacgap", label: "Slack")
                        appToggle("com.microsoft.VSCode", label: "VS Code")
                        appToggle("com.apple.Notes", label: "Notes")
                    }
                }
                .padding(.top, Spacing.sm)
            } label: {
                Text("App Filter (Optional)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }

    @ViewBuilder
    private func appToggle(_ bundleID: String, label: String) -> some View {
        let isSelected = appBundleIDs.contains(bundleID)
        Button(action: {
            if isSelected {
                appBundleIDs.removeAll { $0 == bundleID }
            } else {
                appBundleIDs.append(bundleID)
            }
        }) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? .white : Theme.current.foregroundSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Theme.current.surface2)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - LLM Settings Section

    private var llmSettingsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Provider
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("PROVIDER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: $selectedProvider) {
                        ForEach(WorkflowLLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                // Temperature
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("TEMPERATURE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Text(String(format: "%.1f", temperature))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Slider(value: $temperature, in: 0...2, step: 0.1)
                }
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "gearshape")
                    .font(Theme.current.fontXS)
                Text("LLM Settings")
                    .font(Theme.current.fontXS)
            }
            .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    // MARK: - Icon Picker

    private var iconPickerPopover: some View {
        let icons = [
            "sparkles", "wand.and.stars", "text.quote", "doc.text",
            "pencil", "highlighter", "list.bullet", "checkmark.circle",
            "envelope", "message", "bubble.left", "quote.bubble",
            "briefcase", "building.2", "person", "person.2",
            "star", "heart", "bolt", "flame",
            "brain", "lightbulb", "eye", "magnifyingglass"
        ]

        return VStack(spacing: Spacing.sm) {
            Text("Choose Icon")
                .font(Theme.current.fontSMMedium)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                ForEach(icons, id: \.self) { icon in
                    Button(action: {
                        selectedIcon = icon
                        showingIconPicker = false
                    }) {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(selectedIcon == icon ? selectedColor.color : Theme.current.foreground)
                            .frame(width: 32, height: 32)
                            .background(selectedIcon == icon ? selectedColor.color.opacity(0.2) : Theme.current.surface1)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: 260)
    }

    // MARK: - Footer

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footer: some View {
        TalkieDecisionBar(
            tertiaryTitle: isNew ? nil : "Delete",
            tertiaryRole: .destructive,
            onTertiary: isNew ? nil : {
                // TODO: Add delete confirmation
            },
            primaryTitle: isNew ? "Create" : "Save",
            helperText: canSubmit ? nil : "Name and prompt are required before saving.",
            isPrimaryEnabled: canSubmit,
            placement: .footer,
            onPrimary: {
                saveAction()
            },
            onSecondary: onCancel
        )
    }

    // MARK: - Save

    private func saveAction() {
        // Create the LLM step config
        let llmConfig = LLMStepConfig(
            provider: selectedProvider,
            prompt: prompt,
            temperature: temperature
        )

        // Create the workflow step
        let step = WorkflowStep(
            type: .llm,
            config: .llm(llmConfig),
            outputKey: "output"
        )

        // Create the workflow definition
        let definition = WorkflowDefinition(
            id: workflowId,
            name: name,
            description: "Custom action",
            icon: selectedIcon,
            color: selectedColor,
            steps: [step],
            isEnabled: true,
            isPinned: false,
            autoRun: false,
            autoRunOrder: 0,
            createdAt: Date(),
            modifiedAt: Date()
        )

        // Save the workflow
        onSave(definition)

        // Update the context preferences
        Task {
            try? await WorkflowService.shared.setActionContext(
                for: workflowId,
                showInInterstitial: showInInterstitial,
                showInDrafts: showInDrafts,
                appBundleIDs: appBundleIDs
            )
        }
    }
}
