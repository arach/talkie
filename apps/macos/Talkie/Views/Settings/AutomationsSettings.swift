//
//  AutomationsSettings.swift
//  Talkie macOS
//
//  Settings view for automations - event-triggered and scheduled workflow execution.
//  Includes both the new Automations system and legacy Quick Auto-Run workflows.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Automations Settings View

struct AutomationsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    private let workflowService = WorkflowService.shared
    private let automationService = AutomationService.shared

    @State private var showAddSheet = false
    @State private var editingAutomation: Automation?

    private var autoRunWorkflows: [Workflow] {
        workflowService.autoRunWorkflows
    }

    private var availableWorkflows: [Workflow] {
        workflowService.workflows.filter { !$0.autoRun }
    }

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt.circle",
                title: "AUTOMATIONS",
                subtitle: "Configure event-triggered and scheduled workflow automation."
            )
        } content: {
            // MARK: - Master Toggle Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(settingsManager.autoRunWorkflowsEnabled ? Color.green : Theme.current.foregroundSecondary)
                        .frame(width: 3, height: 14)

                    Text("AUTOMATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(settingsManager.autoRunWorkflowsEnabled ? Color.green : Theme.current.foregroundSecondary)
                            .frame(width: 6, height: 6)
                        Text(settingsManager.autoRunWorkflowsEnabled ? "ENABLED" : "DISABLED")
                            .font(.techLabelSmall)
                            .foregroundColor(settingsManager.autoRunWorkflowsEnabled ? .green : Theme.current.foregroundSecondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(settingsManager.autoRunWorkflowsEnabled ? .green : Theme.current.foregroundSecondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Enable Automations")
                            .font(Theme.current.fontSMMedium)
                        Text("Run workflows automatically based on events or schedules.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.autoRunWorkflowsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            if settingsManager.autoRunWorkflowsEnabled {
                // MARK: - Automations Section (New)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.orange)
                            .frame(width: 3, height: 14)

                        Text("AUTOMATIONS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        let enabledCount = automationService.enabledAutomations.count
                        if enabledCount > 0 {
                            Text("\(enabledCount) ACTIVE")
                                .font(.techLabelSmall)
                                .foregroundColor(.orange.opacity(Opacity.prominent))
                        }

                        Button(action: { showAddSheet = true }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "plus")
                                Text("Add")
                            }
                            .font(Theme.current.fontXSMedium)
                        }
                    }

                    if automationService.automations.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Text("No Automations")
                                .font(Theme.current.fontSMBold)

                            Text("Create automations to run workflows when events occur or on a schedule.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .multilineTextAlignment(.center)

                            Button(action: { showAddSheet = true }) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Automation")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                    } else {
                        VStack(spacing: Spacing.sm) {
                            ForEach(automationService.automations) { automation in
                                AutomationRow(
                                    automation: automation,
                                    onToggle: { enabled in
                                        Task {
                                            try? await automationService.setEnabled(enabled, for: automation.id)
                                        }
                                    },
                                    onEdit: { editingAutomation = automation },
                                    onDelete: {
                                        Task {
                                            try? await automationService.delete(automation)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .settingsSectionCard(padding: Spacing.md)

                // MARK: - Quick Auto-Run Section (Legacy)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Workflows that run on every synced memo. Use Automations above for more control.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        if autoRunWorkflows.isEmpty {
                            // Default Hey Talkie workflow info
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "waveform.badge.mic")
                                    .font(Theme.current.fontHeadline)
                                    .foregroundColor(.purple)
                                    .frame(width: 32, height: 32)
                                    .background(Color.purple.opacity(Opacity.medium))
                                    .cornerRadius(CornerRadius.xs)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text("Hey Talkie (Default)")
                                        .font(Theme.current.fontSMMedium)
                                    Text("Detects \"Hey Talkie\" voice commands and routes to workflows")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                Spacer()

                                Text("ACTIVE")
                                    .font(.techLabelSmall)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(SemanticColor.success.opacity(Opacity.medium))
                                    .foregroundColor(SemanticColor.success)
                                    .cornerRadius(CornerRadius.xs)
                            }
                            .padding(Spacing.sm)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)
                        } else {
                            VStack(spacing: Spacing.sm) {
                                ForEach(autoRunWorkflows) { workflow in
                                    AutoRunWorkflowRow(
                                        workflow: workflow,
                                        onDisable: { disableAutoRun(workflow) },
                                        onMoveUp: autoRunWorkflows.first?.id == workflow.id ? nil : { moveWorkflowUp(workflow) },
                                        onMoveDown: autoRunWorkflows.last?.id == workflow.id ? nil : { moveWorkflowDown(workflow) }
                                    )
                                }
                            }
                        }

                        // Add workflow button
                        if !availableWorkflows.isEmpty {
                            Menu {
                                ForEach(availableWorkflows) { workflow in
                                    Button(action: { enableAutoRun(workflow) }) {
                                        Label(workflow.name, systemImage: workflow.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Workflow")
                                }
                                .font(Theme.current.fontXSMedium)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.purple)
                            .frame(width: 3, height: 14)

                        Text("QUICK AUTO-RUN")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text("LEGACY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)

                        Spacer()

                        if !autoRunWorkflows.isEmpty {
                            Text("\(autoRunWorkflows.count) ACTIVE")
                                .font(.techLabelSmall)
                                .foregroundColor(.purple.opacity(Opacity.prominent))
                        }
                    }
                }
                .accentColor(Theme.current.foregroundSecondary)
                .settingsSectionCard(padding: Spacing.md)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddAutomationSheet(isPresented: $showAddSheet)
        }
        .sheet(item: $editingAutomation) { automation in
            EditAutomationSheet(automation: automation, isPresented: Binding(
                get: { editingAutomation != nil },
                set: { if !$0 { editingAutomation = nil } }
            ))
        }
    }

    // MARK: - Actions

    private func enableAutoRun(_ workflow: Workflow) {
        let nextOrder = (autoRunWorkflows.map { $0.autoRunOrder }.max() ?? -1) + 1
        Task {
            try? await workflowService.setAutoRun(true, for: workflow.id, order: nextOrder)
        }
    }

    private func disableAutoRun(_ workflow: Workflow) {
        Task {
            try? await workflowService.setAutoRun(false, for: workflow.id, order: 0)
        }
    }

    private func moveWorkflowUp(_ workflow: Workflow) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index > 0 else { return }
        let previous = autoRunWorkflows[index - 1]

        let tempOrder = workflow.autoRunOrder
        Task {
            try? await workflowService.setAutoRun(true, for: workflow.id, order: previous.autoRunOrder)
            try? await workflowService.setAutoRun(true, for: previous.id, order: tempOrder)
        }
    }

    private func moveWorkflowDown(_ workflow: Workflow) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index < autoRunWorkflows.count - 1 else { return }
        let next = autoRunWorkflows[index + 1]

        let tempOrder = workflow.autoRunOrder
        Task {
            try? await workflowService.setAutoRun(true, for: workflow.id, order: next.autoRunOrder)
            try? await workflowService.setAutoRun(true, for: next.id, order: tempOrder)
        }
    }
}

// MARK: - Automation Row

struct AutomationRow: View {
    let automation: Automation
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var workflowName: String {
        WorkflowService.shared.workflow(byID: automation.workflowId)?.name ?? "Unknown Workflow"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Trigger icon
            Image(systemName: automation.trigger.icon)
                .font(Theme.current.fontBody)
                .foregroundColor(.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.xs)

            // Automation info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(automation.name)
                    .font(Theme.current.fontSMBold)

                HStack(spacing: Spacing.xs) {
                    Text(automation.trigger.displayDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("→")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text(workflowName)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { automation.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .alert("Delete Automation?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This will permanently delete the automation \"\(automation.name)\".")
        }
    }
}

// MARK: - Auto-Run Workflow Row (Legacy)

struct AutoRunWorkflowRow: View {
    let workflow: Workflow
    let onDisable: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Reorder buttons
            VStack(spacing: Spacing.xs) {
                if let moveUp = onMoveUp {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
                if let moveDown = onMoveDown {
                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
            .frame(width: 16)

            // Workflow icon
            Image(systemName: workflow.icon)
                .font(Theme.current.fontBody)
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.xs)

            // Workflow info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workflow.name)
                    .font(Theme.current.fontSMBold)
                Text(workflow.description.isEmpty ? "\(workflow.steps.count) step(s)" : workflow.description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            if workflow.isEnabled {
                Text("ACTIVE")
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(SemanticColor.success.opacity(Opacity.medium))
                    .foregroundColor(SemanticColor.success)
                    .cornerRadius(CornerRadius.xs)
            } else {
                Text("DISABLED")
                    .font(.techLabelSmall)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.foregroundSecondary.opacity(Opacity.medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .cornerRadius(CornerRadius.xs)
            }

            // Remove button
            Button(action: onDisable) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove from automations")
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }
}

// MARK: - Add Automation Sheet

struct AddAutomationSheet: View {
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var triggerType: TriggerTypeOption = .event
    @State private var selectedEvent: EventTrigger = .memoSynced
    @State private var scheduleInterval: ScheduleInterval = .daily
    @State private var scheduleTime = Date()
    @State private var scheduleWeekday = 2  // Monday
    @State private var selectedWorkflowId: UUID?

    private let automationService = AutomationService.shared
    private let workflowService = WorkflowService.shared

    enum TriggerTypeOption: String, CaseIterable {
        case event = "Event"
        case schedule = "Schedule"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Automation")
                    .font(Theme.current.fontHeadline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Name") {
                    TextField("Automation name", text: $name)
                }

                Section("Trigger") {
                    Picker("Type", selection: $triggerType) {
                        ForEach(TriggerTypeOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if triggerType == .event {
                        Picker("Event", selection: $selectedEvent) {
                            ForEach(EventTrigger.allCases, id: \.self) { event in
                                HStack {
                                    Image(systemName: event.icon)
                                    Text(event.displayName)
                                }
                                .tag(event)
                            }
                        }
                    } else {
                        Picker("Interval", selection: $scheduleInterval) {
                            ForEach(ScheduleInterval.allCases, id: \.self) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }

                        if scheduleInterval != .hourly {
                            DatePicker("Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                        }

                        if scheduleInterval == .weekly {
                            Picker("Day", selection: $scheduleWeekday) {
                                Text("Sunday").tag(1)
                                Text("Monday").tag(2)
                                Text("Tuesday").tag(3)
                                Text("Wednesday").tag(4)
                                Text("Thursday").tag(5)
                                Text("Friday").tag(6)
                                Text("Saturday").tag(7)
                            }
                        }
                    }
                }

                Section("Workflow") {
                    Picker("Run Workflow", selection: $selectedWorkflowId) {
                        Text("Select a workflow...").tag(nil as UUID?)
                        ForEach(workflowService.enabledWorkflows) { workflow in
                            HStack {
                                Image(systemName: workflow.icon)
                                Text(workflow.name)
                            }
                            .tag(workflow.id as UUID?)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save Automation") {
                    saveAutomation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || selectedWorkflowId == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }

    private func saveAutomation() {
        guard let workflowId = selectedWorkflowId else { return }

        let trigger: AutomationTrigger
        if triggerType == .event {
            trigger = .event(selectedEvent)
        } else {
            let time = TimeOfDay(from: scheduleTime)
            let schedule = ScheduleTrigger(
                interval: scheduleInterval,
                time: scheduleInterval == .hourly ? nil : time,
                weekday: scheduleInterval == .weekly ? scheduleWeekday : nil
            )
            trigger = .schedule(schedule)
        }

        let automation = Automation(
            name: name,
            trigger: trigger,
            workflowId: workflowId
        )

        Task {
            try? await automationService.create(automation)
            await MainActor.run {
                isPresented = false
            }
        }
    }
}

// MARK: - Edit Automation Sheet

struct EditAutomationSheet: View {
    let automation: Automation
    @Binding var isPresented: Bool

    @State private var name: String
    @State private var triggerType: AddAutomationSheet.TriggerTypeOption
    @State private var selectedEvent: EventTrigger
    @State private var scheduleInterval: ScheduleInterval
    @State private var scheduleTime: Date
    @State private var scheduleWeekday: Int
    @State private var selectedWorkflowId: UUID?

    private let automationService = AutomationService.shared
    private let workflowService = WorkflowService.shared

    init(automation: Automation, isPresented: Binding<Bool>) {
        self.automation = automation
        self._isPresented = isPresented
        self._name = State(initialValue: automation.name)
        self._selectedWorkflowId = State(initialValue: automation.workflowId)

        switch automation.trigger {
        case .event(let event):
            self._triggerType = State(initialValue: .event)
            self._selectedEvent = State(initialValue: event)
            self._scheduleInterval = State(initialValue: .daily)
            self._scheduleTime = State(initialValue: Date())
            self._scheduleWeekday = State(initialValue: 2)
        case .schedule(let schedule):
            self._triggerType = State(initialValue: .schedule)
            self._selectedEvent = State(initialValue: .memoSynced)
            self._scheduleInterval = State(initialValue: schedule.interval)
            if let time = schedule.time {
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                self._scheduleTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
            } else {
                self._scheduleTime = State(initialValue: Date())
            }
            self._scheduleWeekday = State(initialValue: schedule.weekday ?? 2)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Automation")
                    .font(Theme.current.fontHeadline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Name") {
                    TextField("Automation name", text: $name)
                }

                Section("Trigger") {
                    Picker("Type", selection: $triggerType) {
                        ForEach(AddAutomationSheet.TriggerTypeOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if triggerType == .event {
                        Picker("Event", selection: $selectedEvent) {
                            ForEach(EventTrigger.allCases, id: \.self) { event in
                                HStack {
                                    Image(systemName: event.icon)
                                    Text(event.displayName)
                                }
                                .tag(event)
                            }
                        }
                    } else {
                        Picker("Interval", selection: $scheduleInterval) {
                            ForEach(ScheduleInterval.allCases, id: \.self) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }

                        if scheduleInterval != .hourly {
                            DatePicker("Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                        }

                        if scheduleInterval == .weekly {
                            Picker("Day", selection: $scheduleWeekday) {
                                Text("Sunday").tag(1)
                                Text("Monday").tag(2)
                                Text("Tuesday").tag(3)
                                Text("Wednesday").tag(4)
                                Text("Thursday").tag(5)
                                Text("Friday").tag(6)
                                Text("Saturday").tag(7)
                            }
                        }
                    }
                }

                Section("Workflow") {
                    Picker("Run Workflow", selection: $selectedWorkflowId) {
                        Text("Select a workflow...").tag(nil as UUID?)
                        ForEach(workflowService.enabledWorkflows) { workflow in
                            HStack {
                                Image(systemName: workflow.icon)
                                Text(workflow.name)
                            }
                            .tag(workflow.id as UUID?)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || selectedWorkflowId == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }

    private func saveChanges() {
        guard let workflowId = selectedWorkflowId else { return }

        let trigger: AutomationTrigger
        if triggerType == .event {
            trigger = .event(selectedEvent)
        } else {
            let time = TimeOfDay(from: scheduleTime)
            let schedule = ScheduleTrigger(
                interval: scheduleInterval,
                time: scheduleInterval == .hourly ? nil : time,
                weekday: scheduleInterval == .weekly ? scheduleWeekday : nil
            )
            trigger = .schedule(schedule)
        }

        var updated = automation
        updated.name = name
        updated.trigger = trigger
        updated.workflowId = workflowId

        Task {
            try? await automationService.update(updated)
            await MainActor.run {
                isPresented = false
            }
        }
    }
}
