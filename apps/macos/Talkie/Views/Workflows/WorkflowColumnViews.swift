//
//  WorkflowColumnViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import AppKit
import os
import TalkieKit

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "Views")

// MARK: - Workflow Column Views

struct WorkflowListColumn: View {
    @Binding var selectedWorkflowID: UUID?
    @Binding var editingWorkflow: WorkflowDefinition?
    private let workflowService = WorkflowService.shared
    private let fileRepo = WorkflowFileRepository.shared
    private let settings = SettingsManager.shared

    @State private var showingTemplatePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header - aligned with sidebar TALKIE header
            PageHeaderBar {
                TalkieText("Workflows", style: .pageTitle)

                Text("\(workflowService.workflows.count)")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: { showingTemplatePicker = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.current.foreground.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Workflow List
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    ForEach(workflowService.workflows) { workflow in
                        WorkflowListItem(
                            workflow: workflow.definition,
                            isSelected: selectedWorkflowID == workflow.id,
                            isSystem: workflow.isSystem,
                            onSelect: { selectWorkflow(workflow) },
                            onEdit: { selectWorkflow(workflow) }
                        )
                    }
                }
                .padding(Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.current.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.current.border)
                .frame(width: 1)
                .padding(.top, PageLayout.headerHeight)
        }
        .sheet(isPresented: $showingTemplatePicker) {
            WorkflowTemplatePicker(
                templates: fileRepo.loadTemplates(),
                onSelectBlank: {
                    createNewWorkflow(from: nil)
                    showingTemplatePicker = false
                },
                onSelectTemplate: { template in
                    createNewWorkflow(from: template)
                    showingTemplatePicker = false
                },
                onCancel: {
                    showingTemplatePicker = false
                }
            )
        }
    }

    private func createNewWorkflow(from template: WorkflowDefinition?) {
        let newWorkflow: WorkflowDefinition
        if let template = template {
            // Create a copy from template with fresh UUID
            newWorkflow = WorkflowDefinition(
                id: UUID(),
                name: template.name,
                description: template.description,
                icon: template.icon,
                color: template.color,
                maintainer: template.maintainer,
                inputs: template.inputs,
                steps: template.steps.map { step in
                    WorkflowStep(
                        id: UUID(),
                        type: step.type,
                        config: step.config,
                        outputKey: step.outputKey,
                        isEnabled: step.isEnabled,
                        condition: step.condition
                    )
                },
                isEnabled: true,
                isPinned: false,
                autoRun: false,
                autoRunOrder: 0,
                createdAt: Date(),
                modifiedAt: Date()
            )
        } else {
            newWorkflow = WorkflowDefinition(
                name: "Untitled Workflow",
                description: ""
            )
        }
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func selectWorkflow(_ workflow: Workflow) {
        // Only update editingWorkflow if selecting a different workflow
        // This prevents overwriting unsaved edits when clicking the same item
        if selectedWorkflowID != workflow.id {
            selectedWorkflowID = workflow.id
            editingWorkflow = workflow.definition
        }
    }
}

struct WorkflowDetailColumn: View {
    @Environment(\.navigationState) private var navigationState

    @Binding var editingWorkflow: WorkflowDefinition?
    @Binding var selectedWorkflowID: UUID?
    private let workflowService = WorkflowService.shared
    private let fileRepo = WorkflowFileRepository.shared
    private let settings = SettingsManager.shared
    @State private var showingLibrarySelector = false
    @State private var showingTemplatePicker = false
    @State private var queuedTestInput: WorkflowTestInput?
    @State private var agentRunContext = WorkflowAgentRunContext()
    @State private var testPaneWidth: CGFloat = 390

    // Get fresh workflow from service (source of truth)
    private var currentWorkflow: Workflow? {
        guard let id = editingWorkflow?.id else { return nil }
        return workflowService.workflow(byID: id)
    }

    var body: some View {
        Group {
            if let workflow = editingWorkflow {
                if settings.isScopeTheme {
                    // New Scope shell — sourced from design/studio/app/mac-workflows.
                    // Chrome + list, real data; step rows + composer + inspector are
                    // UI-only stubs in this slice (no agent wiring, no run data).
                    ScopeWorkflowDetailShell(
                        workflow: editableWorkflowBinding(fallback: workflow),
                        onBack: clearWorkflowSelection
                    )
                } else {
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                WorkflowInlineEditor(
                                    workflow: editableWorkflowBinding(fallback: workflow),
                                    onSave: saveWorkflow,
                                    onDelete: deleteCurrentWorkflow,
                                    onDuplicate: duplicateCurrentWorkflow,
                                    onRun: { showingLibrarySelector = true },
                                    onBack: clearWorkflowSelection
                                )
                                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

                                WorkflowInspectorResizeHandle(
                                    width: $testPaneWidth,
                                    minWidth: 320,
                                    maxWidth: min(620, max(340, proxy.size.width * 0.48))
                                )

                                WorkflowTestRunPanel(
                                    workflow: editableWorkflowBinding(fallback: workflow),
                                    queuedInput: $queuedTestInput,
                                    agentContext: $agentRunContext,
                                    onChooseInput: { showingLibrarySelector = true }
                                )
                                .frame(width: testPaneWidth)
                            }
                            .frame(height: proxy.size.height * 0.52)

                            Divider()

                            WorkflowAgentTurnsPanel(
                                workflow: editableWorkflowBinding(fallback: workflow),
                                context: agentRunContext
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else if settings.isScopeTheme {
                // Skills landing — the no-selection state in Scope theme.
                // Source of truth: design/studio/app/mac-skills.
                ScopeSkillsLandingView { workflow in
                    selectedWorkflowID = workflow.id
                    editingWorkflow = workflow.definition
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("SELECT OR CREATE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Button(action: { showingTemplatePicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(Theme.current.fontXS)
                            Text("NEW WORKFLOW")
                                .font(Theme.current.fontXSBold)
                        }
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.current.surfaceSelected)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.background)
            }
        }
        .task {
            applyNavigationSelection()
        }
        .onChange(of: navigationState.params) { _, _ in
            applyNavigationSelection()
        }
        .sheet(isPresented: $showingLibrarySelector) {
            if let workflow = editingWorkflow {
                WorkflowLibrarySelectorSheet(
                    workflow: workflow,
                    onSelect: { object in
                        queuedTestInput = WorkflowTestInput(object: object)
                        showingLibrarySelector = false
                    },
                    onCancel: {
                        showingLibrarySelector = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            WorkflowTemplatePicker(
                templates: fileRepo.loadTemplates(),
                onSelectBlank: {
                    createNewWorkflow(from: nil)
                    showingTemplatePicker = false
                },
                onSelectTemplate: { template in
                    createNewWorkflow(from: template)
                    showingTemplatePicker = false
                },
                onCancel: {
                    showingTemplatePicker = false
                }
            )
        }
    }

    private func createNewWorkflow(from template: WorkflowDefinition?) {
        let newWorkflow: WorkflowDefinition
        if let template = template {
            // Create a copy from template with fresh UUID
            newWorkflow = WorkflowDefinition(
                id: UUID(),
                name: template.name,
                description: template.description,
                icon: template.icon,
                color: template.color,
                maintainer: template.maintainer,
                inputs: template.inputs,
                steps: template.steps.map { step in
                    WorkflowStep(
                        id: UUID(),
                        type: step.type,
                        config: step.config,
                        outputKey: step.outputKey,
                        isEnabled: step.isEnabled,
                        condition: step.condition
                    )
                },
                isEnabled: true,
                isPinned: false,
                autoRun: false,
                autoRunOrder: 0,
                createdAt: Date(),
                modifiedAt: Date()
            )
        } else {
            newWorkflow = WorkflowDefinition(
                name: "Untitled Workflow",
                description: ""
            )
        }
        editingWorkflow = newWorkflow
        selectedWorkflowID = newWorkflow.id
    }

    private func saveWorkflow() {
        // Use editingWorkflow binding (contains user's edits)
        guard var definition = editingWorkflow else { return }
        definition.modifiedAt = Date()

        Task {
            do {
                try await workflowService.save(definition)
                // Sync binding from service
                await MainActor.run {
                    editingWorkflow = workflowService.workflow(byID: definition.id)?.definition
                }
            } catch {
                logger.error("Failed to save workflow: \(error)")
            }
        }
    }

    private func deleteCurrentWorkflow() {
        guard let workflow = currentWorkflow else { return }
        let deletedID = workflow.id

        if selectedWorkflowID == deletedID {
            clearWorkflowSelection()
        }

        Task {
            do {
                try await workflowService.delete(workflow)
            } catch {
                logger.error("Failed to delete workflow: \(error)")
            }
        }
    }

    private func clearWorkflowSelection() {
        editingWorkflow = nil
        selectedWorkflowID = nil
    }

    private func editableWorkflowBinding(fallback workflow: WorkflowDefinition) -> Binding<WorkflowDefinition> {
        Binding(
            get: { editingWorkflow ?? workflow },
            set: { updated in
                editingWorkflow = updated
                selectedWorkflowID = updated.id
            }
        )
    }

    private func duplicateCurrentWorkflow() {
        guard let workflow = currentWorkflow else { return }

        Task {
            do {
                let duplicate = try await workflowService.duplicate(workflow)
                await MainActor.run {
                    editingWorkflow = duplicate.definition
                    selectedWorkflowID = duplicate.id
                }
            } catch {
                logger.error("Failed to duplicate workflow: \(error)")
            }
        }
    }

    private var requestedWorkflowID: UUID? {
        if let id = navigationState.params["workflowId"] as? UUID {
            return id
        }
        guard let raw = navigationState.params["workflowId"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private func applyNavigationSelection() {
        guard let id = requestedWorkflowID,
              selectedWorkflowID != id,
              let workflow = workflowService.workflow(byID: id) else {
            return
        }

        selectedWorkflowID = id
        editingWorkflow = workflow.definition
    }
}

private struct WorkflowTestInput: Identifiable, Equatable {
    let id = UUID()
    let object: TalkieObject
}

private struct WorkflowAgentRunContext {
    var run: ActionRunModel?
    var events: [ActionEventModel] = []
    var inputTitle: String?
}

private struct WorkflowInspectorResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var startWidth: CGFloat?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? TalkieTheme.accent.opacity(0.35) : Theme.current.border.opacity(0.75))
            .frame(width: isHovering ? 3 : 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, isHovering ? 5 : 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if startWidth == nil {
                            startWidth = width
                        }
                        let proposed = (startWidth ?? width) - value.translation.width
                        width = min(maxWidth, max(minWidth, proposed))
                    }
                    .onEnded { _ in
                        startWidth = nil
                    }
            )
    }
}

private struct WorkflowLibrarySelectorSheet: View {
    let workflow: WorkflowDefinition
    let onSelect: (TalkieObject) -> Void
    let onCancel: () -> Void

    private let repository = TalkieObjectRepository()

    @State private var objects: [TalkieObject] = []
    @State private var selectedObject: TalkieObject?
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var isVisualWorkflow: Bool {
        workflow.inputs.requiredAssets.contains(.screenshot)
        || workflow.inputs.requiredAssets.contains(.image)
        || workflow.inputs.requiredAssets.contains(.clip)
    }

    private var selectorName: String {
        if isVisualWorkflow { return "Visual Library" }
        if workflow.startsWithTranscribe { return "Audio Library" }
        return "Library"
    }

    private var filteredObjects: [TalkieObject] {
        let eligible = objects.filter(matchesWorkflowInput)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return eligible }

        return eligible.filter { object in
            object.displayTitle.localizedStandardContains(trimmed)
            || (object.text?.localizedStandardContains(trimmed) ?? false)
            || (object.notes?.localizedStandardContains(trimmed) ?? false)
            || object.type.displayName.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .background(Theme.current.surfaceInput)
        .task { await loadObjects() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Run Workflow")
                    .font(Theme.current.fontTitleBold)

                HStack(spacing: 6) {
                    Image(systemName: workflow.icon)
                        .foregroundStyle(workflow.color.color)
                    Text(workflow.name)
                        .font(Theme.current.fontBody)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.current.fontHeadline)
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)

            TextField("Search \(selectorName.lowercased())...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.current.fontBody)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: Spacing.sm) {
                BrailleSpinner(size: 14)
                Text("Loading \(selectorName.lowercased())...")
                    .font(Theme.current.fontSM)
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            emptyState(icon: "exclamationmark.triangle", title: "Library unavailable", detail: errorMessage)
        } else if filteredObjects.isEmpty {
            let title = isVisualWorkflow ? "No visual library items" : "No matching library items"
            let detail = isVisualWorkflow
                ? "Capture or attach an image, then run this workflow against it."
                : "Create a memo, note, dictation, or capture that matches this workflow."
            emptyState(icon: isVisualWorkflow ? "photo.on.rectangle.angled" : "square.stack.3d.up", title: title, detail: detail)
        } else {
            List(selection: $selectedObject) {
                ForEach(filteredObjects) { object in
                    Button {
                        selectedObject = object
                    } label: {
                        WorkflowLibraryObjectRow(object: object, isVisualWorkflow: isVisualWorkflow)
                    }
                    .buttonStyle(.plain)
                    .tag(object)
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(filteredObjects.count) \(filteredObjects.count == 1 ? "item" : "items")")
                .font(Theme.current.fontXS)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Run") {
                if let selectedObject {
                    onSelect(selectedObject)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedObject == nil)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(Spacing.lg)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.current.foregroundMuted.opacity(0.5))

            Text(title)
                .font(Theme.current.fontBodyMedium)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Text(detail)
                .font(Theme.current.fontSM)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.current.foregroundMuted)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadObjects() async {
        do {
            let loaded = try await repository.fetchRecordings(limit: 500)
            let initialSelection = loaded.first(where: matchesWorkflowInput)
            await MainActor.run {
                objects = loaded
                selectedObject = initialSelection
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func matchesWorkflowInput(_ object: TalkieObject) -> Bool {
        guard object.type != .segment else { return false }

        if isVisualWorkflow {
            return workflow.inputs.requiredAssets.allSatisfy { asset in
                switch asset {
                case .screenshot:
                    return !object.screenshots.isEmpty
                case .image:
                    return hasImage(object)
                case .clip:
                    return !object.clips.isEmpty
                case .transcript, .text:
                    return hasText(object)
                case .audio:
                    return object.hasAudio
                }
            }
        }

        if workflow.startsWithTranscribe {
            return object.hasAudio
        }

        if workflow.inputs.requiredAssets.contains(.transcript)
            || workflow.inputs.requiredAssets.contains(.text) {
            return hasText(object)
        }

        guard let recordType = WorkflowRecordType(object.type) else { return false }
        return workflow.inputs.acceptedRecordTypes.contains(recordType)
    }

    private func hasText(_ object: TalkieObject) -> Bool {
        !(object.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        || !(object.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func hasImage(_ object: TalkieObject) -> Bool {
        !object.screenshots.isEmpty
        || object.attachments.contains { $0.kind == .image }
    }
}

private struct WorkflowLibraryObjectRow: View {
    let object: TalkieObject
    let isVisualWorkflow: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: rowIcon)
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(object.displayTitle)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(object.type.displayName)
                    Text("·")
                    Text(object.createdAt, format: .dateTime.month().day().hour().minute())

                    if object.screenshots.count > 0 {
                        Text("·")
                        Text("\(object.screenshots.count) screenshot\(object.screenshots.count == 1 ? "" : "s")")
                    }

                    if imageAttachmentCount > 0 {
                        Text("·")
                        Text("\(imageAttachmentCount) image\(imageAttachmentCount == 1 ? "" : "s")")
                    }
                }
                .font(Theme.current.fontXS)
                .foregroundStyle(Theme.current.foregroundSecondary)

                if let preview = object.transcriptPreview, !isVisualWorkflow {
                    Text(preview)
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private var rowIcon: String {
        if isVisualWorkflow { return "photo.on.rectangle" }
        return object.type.icon
    }

    private var imageAttachmentCount: Int {
        object.attachments.filter { $0.kind == .image }.count
    }
}

private struct WorkflowTestRunPanel: View {
    @Binding var workflow: WorkflowDefinition
    @Binding var queuedInput: WorkflowTestInput?
    @Binding var agentContext: WorkflowAgentRunContext
    let onChooseInput: () -> Void

    private let actionRepository = LocalRepository()
    private let objectRepository = TalkieObjectRepository()
    private let log = Log(.workflow)

    @State private var runs: [ActionRunModel] = []
    @State private var selectedRunId: UUID?
    @State private var selectedEvents: [ActionEventModel] = []
    @State private var selectedSubjects: [ActionSubjectRef] = []
    @State private var selectedInputObject: TalkieObject?
    @State private var selectedInputPackage: ActionInputPackage?
    @State private var isLoading = false
    @State private var isRunning = false

    private var selectedRun: ActionRunModel? {
        guard let selectedRunId else { return nil }
        return runs.first { $0.id == selectedRunId }
    }

    private var selectedInputSubject: ActionSubjectRef? {
        selectedSubjects.first { $0.recordId != nil || $0.assetURLString != nil }
    }

    private var fallbackScreenshotURL: URL? {
        latestScreenshotURL()
    }

    private var canRun: Bool {
        !isRunning && (selectedInputSubject != nil || fallbackScreenshotURL != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            workflowPane
        }
        .background(Theme.current.surfaceBase)
        .task(id: workflow.id) {
            await loadRuns()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await loadRuns(showLoading: false)
            }
        }
        .onChange(of: selectedRunId) { _, _ in
            Task { await loadSelectedRunDetails() }
        }
        .onChange(of: queuedInput?.id) { _, _ in
            guard let input = queuedInput else { return }
            Task {
                await runTest(overrideObject: input.object)
                await MainActor.run {
                    if queuedInput?.id == input.id {
                        queuedInput = nil
                    }
                }
            }
        }
    }

    private var workflowPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                inputBlock
                runBlock
            }
            .padding(Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        PageHeaderBar {
            TalkieText("Test", style: .pageTitle)
            Spacer()
            Button("Run", systemImage: isRunning ? "hourglass" : "play.fill") {
                Task { await runTest() }
            }
            .disabled(!canRun)
            .buttonStyle(.plain)
            .font(Theme.current.fontXS)
        }
    }

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                label("INPUT")
                Spacer()
                Button("Choose", systemImage: "folder") {
                    onChooseInput()
                }
                .buttonStyle(.plain)
                .font(Theme.current.fontXS)
            }

            WorkflowInputPreviewCard(
                icon: selectedInputIcon,
                title: selectedInputTitle,
                subtitle: selectedInputSubtitle,
                imageURL: selectedInputPreviewURL
            )

            if let renderedSnapshot = selectedInputPackage?.renderedSnapshot,
               !renderedSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(renderedSnapshot)
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private var runBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                label("RUNS")
                Spacer()
                if isLoading {
                    BrailleSpinner(size: 10)
                }
            }

            runHistoryStrip

            if let selectedRun {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedRun.title)
                            .font(Theme.current.fontSMBold)
                            .foregroundStyle(Theme.current.foreground)
                            .lineLimit(1)

                        Spacer()

                        WorkflowTestStatusBadge(status: selectedRun.status)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(selectedEvents) { event in
                            WorkflowTestEventRow(
                                event: event,
                                isActive: event.id == activeEventId(for: selectedRun)
                            )
                        }
                    }
                    .clipShape(.rect(cornerRadius: CornerRadius.xs))

                    if let result = selectedRun.primaryResult, !result.isEmpty {
                        outputBlock(title: "RESULT", text: result, tint: TalkieTheme.accent)
                    }

                    if let error = selectedRun.errorMessage, !error.isEmpty {
                        outputBlock(title: "ERROR", text: error, tint: SemanticColor.error)
                    }
                }
            } else {
                inputRow(
                    icon: "play.rectangle",
                    title: "No test run",
                    subtitle: "Pick input and run."
                )
            }
        }
    }

    @ViewBuilder
    private var runHistoryStrip: some View {
        if runs.isEmpty {
            inputRow(
                icon: "play.rectangle",
                title: "No test runs yet",
                subtitle: "Choose input, then run."
            )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(runs.prefix(12).reversed())) { run in
                        Button {
                            selectedRunId = run.id
                        } label: {
                            WorkflowRunChip(
                                run: run,
                                isSelected: selectedRunId == run.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var selectedInputIcon: String {
        if selectedInputPreviewURL != nil { return "photo.on.rectangle" }
        if let selectedInputObject { return selectedInputObject.type.icon }
        if selectedInputSubject?.kind == .screenshot { return "camera.viewfinder" }
        return "square.stack"
    }

    private var selectedInputTitle: String {
        if let selectedInputObject {
            return selectedInputObject.displayTitle
        }
        if let selectedInputSubject {
            return selectedInputSubject.titleSnapshot
                ?? selectedInputSubject.assetURLString
                ?? "Selected input"
        }
        if let fallbackScreenshotURL {
            return fallbackScreenshotURL.lastPathComponent
        }
        return "No input selected"
    }

    private var selectedInputSubtitle: String {
        var parts: [String] = []

        if let selectedInputObject {
            parts.append(selectedInputObject.type.displayName)
            if !selectedInputObject.screenshots.isEmpty {
                parts.append("\(selectedInputObject.screenshots.count) screenshot\(selectedInputObject.screenshots.count == 1 ? "" : "s")")
            }
            let imageCount = selectedInputObject.attachments.filter { $0.kind == .image }.count
            if imageCount > 0 {
                parts.append("\(imageCount) image\(imageCount == 1 ? "" : "s")")
            }
        } else if selectedInputSubject != nil {
            parts.append("Previous run input")
        } else if fallbackScreenshotURL != nil {
            parts.append("Latest screenshot")
        } else {
            parts.append("Use Run or Choose to pick a library item")
        }

        if let selectedRun {
            parts.append(selectedRun.createdAt.formatted(date: .abbreviated, time: .shortened))
        }

        return parts.joined(separator: " · ")
    }

    private var selectedInputPreviewURL: URL? {
        if let selectedInputObject,
           let url = visualURL(for: selectedInputObject) {
            return url
        }

        if selectedInputObject != nil {
            return nil
        }

        if let assetURLString = selectedInputSubject?.assetURLString {
            let url = URL(fileURLWithPath: assetURLString)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if selectedInputSubject != nil {
            return nil
        }

        return fallbackScreenshotURL
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.current.fontXSBold)
            .foregroundStyle(Theme.current.foregroundMuted)
    }

    private func inputRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.current.fontSM)
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }

    private func outputBlock(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.current.fontXSBold)
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foreground)
                .textSelection(.enabled)
                .lineSpacing(2)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }

    private func loadRuns(showLoading: Bool = true, selecting requestedRunId: UUID? = nil) async {
        if showLoading {
            await MainActor.run { isLoading = true }
        }

        do {
            let loadedRuns = try await actionRepository
                .allActionRuns(limit: 100)
                .filter { $0.actionKind == .workflow && $0.actionId == workflow.id.uuidString }

            await MainActor.run {
                runs = loadedRuns
                if let requestedRunId, loadedRuns.contains(where: { $0.id == requestedRunId }) {
                    selectedRunId = requestedRunId
                } else if let selectedRunId, loadedRuns.contains(where: { $0.id == selectedRunId }) {
                    self.selectedRunId = selectedRunId
                } else {
                    selectedRunId = loadedRuns.first?.id
                }
                isLoading = false
            }

            await loadSelectedRunDetails()
        } catch {
            log.error("Failed to load workflow test runs: \(error.localizedDescription)")
            await MainActor.run { isLoading = false }
        }
    }

    private func loadSelectedRunDetails() async {
        guard let selectedRunId else {
            await MainActor.run {
                selectedEvents = []
                selectedSubjects = []
                selectedInputObject = nil
                selectedInputPackage = nil
                agentContext = WorkflowAgentRunContext()
            }
            return
        }

        do {
            async let events = actionRepository.fetchActionEvents(for: selectedRunId)
            async let subjects = actionRepository.fetchActionSubjectRefs(for: selectedRunId)
            async let inputPackage = actionRepository.fetchActionInputPackage(for: selectedRunId)

            let loadedEvents = try await events
            let loadedSubjects = try await subjects
            let loadedInputPackage = try await inputPackage
            let loadedInputObject = try await inputObject(from: loadedSubjects)

            await MainActor.run {
                selectedEvents = loadedEvents
                selectedSubjects = loadedSubjects
                selectedInputObject = loadedInputObject
                selectedInputPackage = loadedInputPackage
                agentContext = WorkflowAgentRunContext(
                    run: selectedRun,
                    events: loadedEvents,
                    inputTitle: loadedInputObject?.displayTitle
                        ?? loadedSubjects.first?.titleSnapshot
                        ?? loadedSubjects.first?.assetURLString
                )
            }
        } catch {
            log.error("Failed to load workflow test detail: \(error.localizedDescription)")
        }
    }

    private func runTest(overrideObject: TalkieObject? = nil) async {
        guard !isRunning else { return }

        let definition = workflow
        let actionRunId = UUID()
        let inputPackageId = UUID()
        let now = Date()

        await MainActor.run { isRunning = true }

        do {
            let subject = try testSubject(
                actionRunId: actionRunId,
                createdAt: now,
                overrideObject: overrideObject
            )
            let inputPackage = ActionInputPackage(
                id: inputPackageId,
                actionRunId: actionRunId,
                parametersJSON: actionJSON([
                    "workflowId": definition.id.uuidString,
                    "workflowName": definition.name,
                    "surface": "workflowTestPanel",
                    "sourceActionRunId": selectedRunId?.uuidString ?? ""
                ]),
                derivedContextRefsJSON: actionJSON([
                    "assetURL": subject.assetURLString ?? "",
                    "recordId": subject.recordId?.uuidString ?? ""
                ]),
                renderedSnapshot: subject.titleSnapshot,
                createdAt: now
            )
            let run = ActionRunModel(
                id: actionRunId,
                actionId: definition.id.uuidString,
                actionKind: .workflow,
                title: definition.name,
                inputPackageId: inputPackageId,
                status: .running,
                createdAt: now,
                updatedAt: now,
                startedAt: now,
                summary: "Running \(definition.name)"
            )

            try await actionRepository.createActionRun(
                run,
                inputPackage: inputPackage,
                subjectRefs: [subject],
                events: [
                    ActionEventModel(actionRunId: actionRunId, kind: .runQueued, message: "\(definition.name) queued"),
                    ActionEventModel(actionRunId: actionRunId, kind: .runStarted, message: "\(definition.name) started")
                ]
            )
            await loadRuns(showLoading: false, selecting: actionRunId)

            try await append(actionRunId, kind: .stepStarted, message: "Resolving input")
            let target = try await targetObject(for: subject, overrideObject: overrideObject)
            try await append(
                actionRunId,
                kind: .inputResolved,
                message: "Input resolved",
                payloadJSON: actionJSON([
                    "recordId": target.id.uuidString,
                    "recordType": target.type.rawValue,
                    "screenshotCount": target.screenshots.count
                ])
            )

            try await append(actionRunId, kind: .stepStarted, message: "Running \(definition.name)")
            let outputs = try await WorkflowExecutor.shared.executeWorkflow(definition, for: target)
            let result = primaryOutput(from: outputs, workflow: definition)
            let summary = actionSummary(from: result, fallback: "\(definition.name) completed")

            try await append(
                actionRunId,
                kind: .artifactCreated,
                message: "Result captured",
                payloadJSON: actionJSON(["kind": "text", "preview": summary])
            )
            try await append(actionRunId, kind: .runCompleted, message: "\(definition.name) completed")
            try await actionRepository.updateActionRun(
                id: actionRunId,
                status: .completed,
                summary: summary,
                primaryResult: result,
                completedAt: Date()
            )
        } catch {
            log.error("Workflow test failed: \(error.localizedDescription)")
            _ = try? await actionRepository.appendActionEvent(
                actionRunId: actionRunId,
                kind: .runFailed,
                level: .error,
                message: error.localizedDescription,
                payloadJSON: actionJSON(["error": error.localizedDescription])
            )
            try? await actionRepository.updateActionRun(
                id: actionRunId,
                status: .failed,
                summary: error.localizedDescription,
                errorMessage: error.localizedDescription,
                errorDetails: String(describing: error),
                completedAt: Date()
            )
        }

        await MainActor.run { isRunning = false }
        await loadRuns(showLoading: false, selecting: actionRunId)
    }

    private func append(
        _ actionRunId: UUID,
        kind: ActionEventModel.Kind,
        level: ActionEventModel.Level = .info,
        message: String,
        payloadJSON: String = "{}"
    ) async throws {
        _ = try await actionRepository.appendActionEvent(
            actionRunId: actionRunId,
            kind: kind,
            level: level,
            message: message,
            payloadJSON: payloadJSON
        )
        await loadRuns(showLoading: false, selecting: actionRunId)
    }

    private func testSubject(
        actionRunId: UUID,
        createdAt: Date,
        overrideObject: TalkieObject? = nil
    ) throws -> ActionSubjectRef {
        if let overrideObject {
            return ActionSubjectRef(
                actionRunId: actionRunId,
                kind: subjectKind(for: overrideObject),
                recordId: overrideObject.id,
                titleSnapshot: overrideObject.displayTitle,
                createdAt: createdAt
            )
        }

        if let selectedInputSubject {
            return ActionSubjectRef(
                actionRunId: actionRunId,
                kind: selectedInputSubject.kind,
                recordId: selectedInputSubject.recordId,
                assetURLString: selectedInputSubject.assetURLString,
                titleSnapshot: selectedInputSubject.titleSnapshot,
                sha256: selectedInputSubject.sha256,
                createdAt: createdAt
            )
        }

        if let fallbackScreenshotURL {
            return ActionSubjectRef(
                actionRunId: actionRunId,
                kind: .screenshot,
                assetURLString: fallbackScreenshotURL.path,
                titleSnapshot: fallbackScreenshotURL.lastPathComponent,
                createdAt: createdAt
            )
        }

        throw WorkflowError.executionFailed("No test input is available.")
    }

    private func targetObject(
        for subject: ActionSubjectRef,
        overrideObject: TalkieObject? = nil
    ) async throws -> TalkieObject {
        if let overrideObject {
            return overrideObject
        }

        if let recordId = subject.recordId,
           let object = try await objectRepository.fetchRecording(id: recordId) {
            return object
        }

        if let assetURLString = subject.assetURLString {
            let url = URL(fileURLWithPath: assetURLString)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw WorkflowError.executionFailed("The selected screenshot is no longer available.")
            }
            return captureObject(for: url, title: subject.titleSnapshot)
        }

        throw WorkflowError.executionFailed("The selected input cannot be resolved.")
    }

    private func inputObject(from subjects: [ActionSubjectRef]) async throws -> TalkieObject? {
        guard let recordId = subjects.first(where: { $0.recordId != nil })?.recordId else {
            return nil
        }
        return try await objectRepository.fetchRecording(id: recordId)
    }

    private func subjectKind(for object: TalkieObject) -> ActionSubjectRef.Kind {
        switch object.type {
        case .memo:
            return .memo
        case .capture:
            return .capture
        case .note:
            return .note
        case .selection:
            return .selection
        case .dictation, .segment:
            return .memo
        }
    }

    private func visualURL(for object: TalkieObject) -> URL? {
        if let screenshot = object.screenshots.first {
            return screenshotURL(for: screenshot)
        }

        if let image = object.attachments.first(where: { $0.kind == .image }) {
            return AttachmentStorage.url(for: image.filename)
        }

        return nil
    }

    private func screenshotURL(for screenshot: RecordingScreenshot) -> URL {
        if screenshot.filename.hasPrefix("/") {
            return URL(fileURLWithPath: screenshot.filename)
        }

        return ScreenshotStorage.screenshotsDirectory.appending(
            path: screenshot.filename,
            directoryHint: .notDirectory
        )
    }

    private func captureObject(for url: URL, title: String?) -> TalkieObject {
        var capture = TalkieObject.newCapture(title: title ?? url.lastPathComponent)
        capture.assetsJSON = TalkieObjectAssets(
            screenshots: [
                RecordingScreenshot(
                    filename: url.path,
                    timestampMs: 0,
                    captureMode: "screenshot"
                )
            ]
        ).toJSON()
        return capture
    }

    private func activeEventId(for run: ActionRunModel) -> UUID? {
        guard run.isRunning else { return nil }

        return selectedEvents.last(where: { event in
            switch event.kind {
            case .stepStarted, .stepLog, .inputResolved, .artifactCreated:
                return event.level != .error
            case .runQueued, .runStarted, .runCompleted, .runFailed, .runCancelled, .stepCompleted, .stepFailed:
                return false
            }
        })?.id ?? selectedEvents.last?.id
    }

    private func primaryOutput(from outputs: [String: String], workflow: WorkflowDefinition) -> String {
        if let outputKey = workflow.steps.last?.outputKey,
           let output = outputs[outputKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }

        for key in ["RESULT", "OUTPUT", "SUMMARY", "SCREENSHOT_DESCRIPTION", "uiDescription"] {
            if let output = outputs[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        }

        return outputs.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func actionSummary(from output: String, fallback: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }
        if cleaned.count <= 220 { return cleaned }
        return "\(cleaned.prefix(220))..."
    }

    private func actionJSON(_ dictionary: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func latestScreenshotURL() -> URL? {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directories = [
            appSupport.appendingPathComponent("Talkie/Tray/screenshots", isDirectory: true),
            ScreenshotStorage.screenshotsDirectory
        ]

        return directories
            .flatMap { directory -> [URL] in
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .max { lhs, rhs in
                modificationDate(for: lhs) < modificationDate(for: rhs)
            }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private struct WorkflowAgentTurnsPanel: View {
    @Binding var workflow: WorkflowDefinition
    let context: WorkflowAgentRunContext

    @State private var prompt = ""
    @State private var localTurns: [WorkflowAgentTurnDraft] = []
    @State private var isDictating = false
    @State private var isTranscribingDictation = false
    @State private var dictationError: String?

    private var run: ActionRunModel? {
        context.run
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                label("TURNS")
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 34)

            Divider()

            turns

            Divider()

            composer
        }
        .background(Theme.current.surfaceBase)
    }

    @ViewBuilder
    private var turns: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(localTurns) { turn in
                    WorkflowAgentTurnRow(turn: turn)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            Button(action: toggleDictation) {
                Image(systemName: isDictating ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDictating ? Color.red : Theme.current.foregroundSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.current.surface1)
                    .clipShape(.rect(cornerRadius: CornerRadius.xs))
            }
            .buttonStyle(.plain)
            .disabled(isTranscribingDictation)
            .help(isDictating ? "Recording — click to stop" : "Dictate into the prompt")

            TextField("Message agent...", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.current.fontBody)
                .foregroundStyle(Theme.current.foreground)
                .lineLimit(1...4)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 8)
                .background(Theme.current.surface1)
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(Theme.current.border.opacity(0.45), lineWidth: 1)
                }
                .clipShape(.rect(cornerRadius: CornerRadius.xs))
                .onSubmit {
                    askAgent()
                }

            Button(action: askAgent) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canSend ? Color.white : Theme.current.foregroundMuted)
                    .frame(width: 32, height: 32)
                    .background(canSend ? TalkieTheme.accent : Theme.current.surface1)
                    .clipShape(.rect(cornerRadius: CornerRadius.xs))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.surfaceBase)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.current.fontXSBold)
            .foregroundStyle(Theme.current.foregroundMuted)
    }

    private func askAgent() {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        localTurns.append(
            WorkflowAgentTurnDraft(
                role: "YOU",
                text: instruction,
                tint: TalkieTheme.accent
            )
        )
        prompt = ""

        NavigationState.shared.navigateToConsole(
            profile: .talkieAgent,
            prompt: agentContextPrompt(instruction: instruction)
        )
    }

    private func toggleDictation() {
        if isDictating {
            Task { await stopDictation() }
        } else if !isTranscribingDictation {
            startDictation()
        }
    }

    private func startDictation() {
        // Optimistic: flip the visual immediately so the user sees feedback
        // before AVAudioEngine spin-up completes. Revert on failure.
        isDictating = true
        dictationError = nil
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .composeDictation)
        } catch {
            isDictating = false
            dictationError = error.localizedDescription
        }
    }

    @MainActor
    private func stopDictation() async {
        guard isDictating else { return }
        isDictating = false
        isTranscribingDictation = true
        do {
            let text = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribingDictation = false
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            // Append to existing draft (with leading space) so dictation augments
            // rather than overwrites whatever the user was typing.
            if prompt.isEmpty {
                prompt = cleaned
            } else {
                prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines) + " " + cleaned
            }
        } catch {
            isTranscribingDictation = false
            dictationError = error.localizedDescription
        }
    }

    private func agentContextPrompt(instruction: String) -> String {
        let result = run?.primaryResult ?? run?.errorMessage ?? "No result yet."
        let logs = context.events
            .map { "#\($0.sequence + 1) [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
        let workflowJSON: String
        if let data = try? JSONEncoder().encode(workflow),
           let json = String(data: data, encoding: .utf8) {
            workflowJSON = json
        } else {
            workflowJSON = workflow.name
        }

        return """
        Improve this Talkie workflow.

        User request:
        \(instruction)

        Workflow:
        \(workflowJSON)

        Latest test input:
        \(context.inputTitle ?? "No input selected.")

        Latest test result:
        \(result)

        Latest test logs:
        \(logs)
        """
    }
}

private struct WorkflowAgentTurnDraft: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    let tint: Color
}

private struct WorkflowAgentTurnRow: View {
    let turn: WorkflowAgentTurnDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(turn.role)
                .font(Theme.current.fontXSBold)
                .foregroundStyle(turn.tint)

            Text(turn.text)
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)
                .textSelection(.enabled)
                .lineLimit(6)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: 720, alignment: .leading)
        .background(Theme.current.surface1.opacity(0.65))
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }
}

private struct WorkflowInputPreviewCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let imageURL: URL?

    private var image: NSImage? {
        guard let imageURL else { return nil }
        return NSImage(contentsOf: imageURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Image(systemName: icon)
                            .font(Theme.current.fontSM)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45))
                            .clipShape(.rect(cornerRadius: CornerRadius.xs))
                            .padding(Spacing.xs)
                    }
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: icon)
                        .font(Theme.current.fontTitle)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .frame(width: 42, height: 42)
                        .background(Theme.current.surface2)
                        .clipShape(.rect(cornerRadius: CornerRadius.xs))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.current.fontSMBold)
                            .foregroundStyle(Theme.current.foreground)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.monoSmall)
                            .foregroundStyle(Theme.current.foregroundMuted)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }

            if image != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.current.fontSMBold)
                        .foregroundStyle(Theme.current.foreground)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.monoSmall)
                        .foregroundStyle(Theme.current.foregroundMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.current.surface1)
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }
}

private struct WorkflowRunChip: View {
    let run: ActionRunModel
    let isSelected: Bool

    private var tint: Color {
        switch run.status {
        case .queued, .running:
            return TalkieTheme.accent
        case .completed:
            return SemanticColor.success
        case .failed:
            return SemanticColor.error
        case .cancelled:
            return Theme.current.foregroundMuted
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(run.createdAt, format: .dateTime.hour().minute())
                .font(.monoSmall)
                .foregroundStyle(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

            Text(run.status.rawValue.prefix(2).uppercased())
                .font(.monoSmall)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
        .background(isSelected ? TalkieTheme.accent.opacity(0.12) : Theme.current.surface1)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(isSelected ? TalkieTheme.accent.opacity(0.5) : Theme.current.border.opacity(0.4), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }
}

private struct WorkflowTestEventRow: View {
    let event: ActionEventModel
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("#\(event.sequence + 1)")
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .frame(width: 28, alignment: .trailing)

                Text(event.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .frame(width: 80, alignment: .leading)

                Text(event.message)
                    .font(Theme.current.fontSM)
                    .foregroundStyle(event.level == .error ? SemanticColor.error : Theme.current.foreground)
                    .textSelection(.enabled)
                    .frame(minWidth: 0, alignment: .leading)

                if isActive {
                    WorkflowTestActiveIndicator(tint: TalkieTheme.accent)
                        .frame(width: 120, height: 18)
                }

                Spacer()
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, isActive ? 8 : 6)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(TalkieTheme.accent)
                    .frame(width: 2)
            }
        }
    }

    private var rowBackground: Color {
        if event.level == .error {
            return SemanticColor.error.opacity(0.08)
        }
        if isActive {
            return TalkieTheme.accent.opacity(0.08)
        }
        return Theme.current.surface2
    }
}

private struct WorkflowTestStatusBadge: View {
    let status: ActionRunModel.Status

    private var tint: Color {
        switch status {
        case .queued, .running:
            return TalkieTheme.accent
        case .completed:
            return SemanticColor.success
        case .failed:
            return SemanticColor.error
        case .cancelled:
            return Theme.current.foregroundMuted
        }
    }

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.monoSmall)
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1))
            .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }
}

private struct WorkflowTestActiveIndicator: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 7) {
                WorkflowTestPulse(tint: tint, size: 7)

                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { index in
                        let phase = (elapsed * 1.35 + Double(index) / 10.0)
                            .truncatingRemainder(dividingBy: 1)
                        let emphasis = phase < 0.28 ? 1 - (phase / 0.28) : 0

                        Capsule()
                            .fill(tint.opacity(0.18 + (emphasis * 0.74)))
                            .frame(width: 4 + (emphasis * 5), height: 3)
                    }
                }
                .frame(width: 88, alignment: .leading)
            }
        }
    }
}

private struct WorkflowTestPulse: View {
    let tint: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.15) / 1.15
            let ringSize = size + (10 * progress)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.24))
                    .frame(width: ringSize, height: ringSize)
                    .opacity(1 - progress)

                Circle()
                    .fill(tint)
                    .frame(width: size, height: size)
                    .opacity(0.74 + ((1 - progress) * 0.26))
            }
            .frame(width: size + 10, height: size + 10)
        }
    }
}

// MARK: - Column Resizer

struct ColumnResizer: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    private let settings = SettingsManager.shared

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? settings.resolvedAccentColor : (isHovering ? Color.secondary.opacity(0.3) : Color.clear))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newWidth = width + value.translation.width
                        width = min(maxWidth, max(minWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}

// MARK: - Scope Workflow Detail Shell
//
// Studio donor: design/studio/app/mac-workflows
// First slice: chrome + list (real data), step rows + composer + inspector
// are UI-only stubs (no agent wiring, no run data). Mutations still flow
// through the existing service when the composer earns a wire-up.
//
// NamesMarginalia:
//   ScopeWorkflowDetailShell    outer composition (productbar + 2-col body)
//   ScopeWorkflowProductBar     top breadcrumb strip (Workflows / talkie / Name)
//   ScopeWorkflowDetailBody     HStack (center column + inspector column)
//   ScopeWorkflowDetailHeader   meta row (steps · rev · updated · actions)
//   ScopeWorkflowTitleBlock     name + description, serif title
//   ScopeWorkflowStepRow        one step (number · name · kind label)
//   ScopeWorkflowComposer       UI-only builder composer at column foot
//   ScopeWorkflowInspectorStub  right column placeholder for v0

struct ScopeWorkflowDetailShell: View {
    @Binding var workflow: WorkflowDefinition
    var onBack: () -> Void

    // Inspector is resizable and mode-aware. Width persists across
    // mode switches. Edit in the detail header flips mode to .data
    // and auto-widens to at least 460 so the JSON has room.
    @State private var inspectorWidth: CGFloat = 360
    @State private var inspectorMode: ScopeInspectorMode = .runs

    // Live run state — fetched per-workflow from the singleton store
    // so a run in workflow A keeps progressing when the user
    // navigates to B (and B's Run button is independently enabled).
    @State private var runState: ScopeWorkflowRunState?
    @State private var showingLibrarySheet = false

    var body: some View {
        Group {
            if let runState {
                content(runState: runState)
            } else {
                Color.clear // brief blank frame while .task swaps in
            }
        }
        .task(id: workflow.id) {
            let state = ScopeWorkflowRunStateStore.shared.state(for: workflow)
            runState = state
            await state.bootstrap(workflow: workflow)
            await state.pollLoop(workflow: workflow)
        }
    }

    @ViewBuilder
    private func content(runState: ScopeWorkflowRunState) -> some View {
        VStack(spacing: 0) {
            ScopeWorkflowProductBar(
                workflowName: workflow.name,
                onBack: onBack
            )

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ScopeWorkflowCenterColumn(
                        workflow: workflow,
                        onEdit: revealDataInspector
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                    ScopeWorkflowResizeHandle(
                        width: $inspectorWidth,
                        halfWidth: proxy.size.width / 2
                    )

                    ScopeWorkflowInspector(
                        workflow: workflow,
                        mode: $inspectorMode,
                        runState: runState,
                        onPickLibrary: { showingLibrarySheet = true }
                    )
                    .frame(width: inspectorWidth)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .background(ScopeCanvas.canvas)
        .sheet(isPresented: $showingLibrarySheet) {
            WorkflowLibrarySelectorSheet(
                workflow: workflow,
                onSelect: { object in
                    runState.selectedRecent = object
                    if !runState.recents.contains(where: { $0.id == object.id }) {
                        runState.recents.insert(object, at: 0)
                    }
                    showingLibrarySheet = false
                },
                onCancel: { showingLibrarySheet = false }
            )
        }
    }

    private func revealDataInspector() {
        inspectorMode = .data
        if inspectorWidth < 460 {
            withAnimation(.easeOut(duration: 0.18)) {
                inspectorWidth = 460
            }
        }
    }
}

enum ScopeInspectorMode {
    case runs, data
}

// Vertical hairline that drags between center column and inspector.
// Soft-snaps on release to 360 / 460 / 600 / half-container-width.
//
// Drag uses a global coordinate space so that translations don't
// jitter when the columns themselves re-layout each frame (which
// they do, because the inspector width changes are what's being
// dragged). Tracking the cursor's global X gives a stable delta.
private struct ScopeWorkflowResizeHandle: View {
    @Binding var width: CGFloat
    let halfWidth: CGFloat
    @State private var startWidth: CGFloat = 0
    @State private var startX: CGFloat? = nil
    @State private var hovering: Bool = false

    private let minWidth: CGFloat = 280
    // Tighter snap to the three fixed widths; the half target is a
    // rough intent so it gets a bigger zone.
    private static let snapRadiusFixed: CGFloat = 14
    private static let snapRadiusHalf:  CGFloat = 28
    private var maxWidth: CGFloat { max(720, halfWidth) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ScopeEdge.faint)
                .frame(width: 1)
            Color.clear
                .frame(width: 11)
                .contentShape(Rectangle())
        }
        .onHover { value in
            if value != hovering {
                hovering = value
                if value { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if startX == nil {
                        startX = value.startLocation.x
                        startWidth = width
                    }
                    let dx = (startX ?? value.location.x) - value.location.x
                    let next = (startWidth + dx).rounded()
                    width = min(maxWidth, max(minWidth, next))
                }
                .onEnded { _ in
                    startX = nil
                    let snapped = snap(width)
                    if snapped != width {
                        withAnimation(.easeOut(duration: 0.14)) { width = snapped }
                    }
                }
        )
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        // Half gets a wider zone — rough intent, not precise width
        if halfWidth > 0, abs(value - halfWidth) <= Self.snapRadiusHalf {
            return halfWidth
        }
        for target in [CGFloat(360), 460, 600] {
            if abs(value - target) <= Self.snapRadiusFixed { return target }
        }
        return value
    }
}

// MARK: ProductBar

private struct ScopeWorkflowProductBar: View {
    let workflowName: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ScopeInk.faint)
                    Text("Workflows")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ScopeInk.faint)
                }
            }
            .buttonStyle(.plain)

            Text("/")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)

            Text("talkie")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ScopeInk.faint)

            Text("/")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)

            Text(workflowName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ScopeInk.primary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            ScopeRule(.row)
        }
    }
}

// MARK: Center column

private struct ScopeWorkflowCenterColumn: View {
    let workflow: WorkflowDefinition
    var onEdit: () -> Void

    // Turns is conversational — owns its own height. Drag the seam
    // above it to grow / shrink; collapse hides it entirely.
    @State private var turnsCollapsed: Bool = false
    @State private var turnsHeight: CGFloat = 220

    // Live turn state for the workflow builder conversation.
    @State private var turns: [ScopeTurn] = []
    @State private var isSending: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScopeWorkflowDetailHeader(workflow: workflow, onEdit: onEdit)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScopeWorkflowTitleBlock(workflow: workflow)
                    ScopeWorkflowStepList(workflow: workflow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !turnsCollapsed {
                ScopeTurnsResizeHandle(height: $turnsHeight)
            }
            ScopeWorkflowTurnsBlock(
                turns: turns,
                isSending: isSending,
                collapsed: turnsCollapsed,
                onToggle: { turnsCollapsed.toggle() },
                height: turnsHeight
            )
            ScopeWorkflowComposer(
                turnCount: turns.count,
                isSending: isSending,
                onSend: handleSend
            )
        }
    }

    private func handleSend(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return }
        let history = Array(turns.suffix(12))
        let now = ScopeTurn.timeLabel(Date())
        turns.append(.init(id: UUID().uuidString, role: .user, time: now, body: body))
        isSending = true
        if !turnsCollapsed == false {
            // ensure turns are visible after sending
            turnsCollapsed = false
        }

        let systemPrompt = builderSystemPrompt()
        let prompt = builderPrompt(history: history, userMessage: body)

        Task { @MainActor in
            defer { isSending = false }

            guard let resolved = await resolveBuilderModel() else {
                appendAgentTurn("No LLM provider configured. Open Settings → API to add a key.")
                return
            }

            var options = GenerationOptions()
            options.temperature = 0.35
            options.topP = 0.9
            options.maxTokens = 700
            options.systemPrompt = systemPrompt

            do {
                try await streamOrGenerateBuilderReply(
                    provider: resolved.provider,
                    modelId: resolved.modelId,
                    prompt: prompt,
                    options: options
                )
            } catch {
                appendAgentTurn("⚠ \(error.localizedDescription)")
            }
        }
    }

    private func resolveBuilderModel() async -> (provider: LLMProvider, modelId: String)? {
        await LLMProviderRegistry.shared.resolveProviderAndModel()
    }

    private func streamOrGenerateBuilderReply(
        provider: LLMProvider,
        modelId: String,
        prompt: String,
        options: GenerationOptions
    ) async throws {
        let replyID = UUID().uuidString
        var insertedStreamingTurn = false

        do {
            let stream = try await provider.streamGenerate(
                prompt: prompt,
                model: modelId,
                options: options
            )
            appendAgentTurn("", id: replyID)
            insertedStreamingTurn = true

            var accumulated = ""
            for try await token in stream {
                accumulated += token
                replaceAgentTurn(id: replyID, body: accumulated)
            }

            if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let generated = try await provider.generate(
                    prompt: prompt,
                    model: modelId,
                    options: options
                )
                replaceAgentTurn(id: replyID, body: generated)
            }
        } catch {
            do {
                let generated = try await provider.generate(
                    prompt: prompt,
                    model: modelId,
                    options: options
                )
                if insertedStreamingTurn {
                    replaceAgentTurn(id: replyID, body: generated)
                } else {
                    appendAgentTurn(generated)
                }
            } catch {
                if insertedStreamingTurn,
                   let index = turns.firstIndex(where: { $0.id == replyID }),
                   turns[index].body.isEmpty {
                    turns.remove(at: index)
                }
                throw error
            }
        }
    }

    private func appendAgentTurn(_ body: String, id: String = UUID().uuidString) {
        turns.append(
            ScopeTurn(
                id: id,
                role: .agent,
                time: ScopeTurn.timeLabel(Date()),
                body: body
            )
        )
    }

    private func replaceAgentTurn(id: String, body: String) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        let existing = turns[index]
        turns[index] = ScopeTurn(
            id: existing.id,
            role: existing.role,
            time: existing.time,
            body: body
        )
    }

    private func builderSystemPrompt() -> String {
        """
        You are the builder agent that helps a dev modify a Talkie workflow document. Reply tersely. Reference step numbers when relevant.

        Current workflow JSON:
        \(scopePrettyJSON(workflow))
        """
    }

    private func builderPrompt(history: [ScopeTurn], userMessage: String) -> String {
        let renderedHistory = history.map { turn in
            let speaker = turn.role == .user ? "you" : "builder"
            return "\(speaker)· \(turn.body)"
        }.joined(separator: "\n\n")

        if renderedHistory.isEmpty {
            return "you· \(userMessage)"
        }

        return """
        Conversation history:
        \(renderedHistory)

        you· \(userMessage)
        """
    }
}

private struct ScopeWorkflowDetailHeader: View {
    let workflow: WorkflowDefinition
    var onEdit: () -> Void

    private var stepsLabel: String {
        let n = workflow.steps.count
        return n == 1 ? "1 step" : "\(n) steps"
    }

    private var updatedLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "updated \(f.string(from: workflow.modifiedAt))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(stepsLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ScopeInk.faint)

            ScopeWorkflowMetaDot()

            Text(updatedLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ScopeInk.faint)

            Spacer()

            ScopeWorkflowSecondaryButton(label: "Edit", action: onEdit)
            ScopeWorkflowSecondaryButton(label: "Duplicate")
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            ScopeRule(.row)
        }
    }
}

private struct ScopeWorkflowTitleBlock: View {
    let workflow: WorkflowDefinition

    private var eyebrowTokens: [String] {
        var tokens: [String] = []
        if workflow.isSystem {
            tokens.append("SYSTEM")
        } else if workflow.isTalkieMaintained {
            tokens.append("TALKIE")
        } else if let m = workflow.maintainer, !m.isEmpty {
            tokens.append(m.uppercased())
        }
        if workflow.autoRun { tokens.append("AUTO-RUN") }
        if workflow.isPinned { tokens.append("PINNED") }
        return tokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !eyebrowTokens.isEmpty {
                HStack(spacing: 8) {
                    ForEach(eyebrowTokens, id: \.self) { token in
                        Text(token)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(ScopeInk.faint)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: workflow.icon.isEmpty ? "wand.and.stars" : workflow.icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(ScopeBrass.solid)
                Text(workflow.name)
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(ScopeInk.primary)
            }

            if !workflow.description.isEmpty {
                Text(workflow.description)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                    .lineSpacing(3)
                    .frame(maxWidth: 640, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
}

// MARK: Step list

private struct ScopeWorkflowStepList: View {
    let workflow: WorkflowDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { idx, step in
                ScopeWorkflowStepRow(index: idx, step: step, first: idx == 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
    }
}

private struct ScopeWorkflowStepRow: View {
    let index: Int
    let step: WorkflowStep
    let first: Bool

    private var stepNumber: String {
        String(format: "%02d", index + 1)
    }

    private var headline: String {
        step.outputKey.isEmpty ? step.type.displayName : step.outputKey
    }

    private var details: ScopeStepDetails { step.scopeDetails }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { ScopeRule(.row) }

            VStack(alignment: .leading, spacing: 10) {
                // Headline row: N° · name · kind · disabled?
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(stepNumber)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                        .frame(width: 20, alignment: .leading)

                    Text(headline)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ScopeInk.primary)

                    Text("·")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)

                    Text(step.type.displayName.lowercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)

                    if !step.isEnabled {
                        Text("disabled")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                    }

                    Spacer()
                }

                // Config summary (provider · model · params)
                if let summary = details.summaryLine {
                    HStack(alignment: .top, spacing: 8) {
                        Spacer().frame(width: 20)
                        Text(summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }

                // WHEN clause
                if let cond = step.condition {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Spacer().frame(width: 20)
                        Text("when")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                        Text(cond.expression)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                // IN bindings
                ForEach(Array(details.inputs.enumerated()), id: \.offset) { _, token in
                    ScopeWorkflowBindingLine(direction: "in", token: token, type: nil, note: nil)
                }

                // OUT binding
                if !step.outputKey.isEmpty {
                    ScopeWorkflowBindingLine(
                        direction: "out",
                        token: step.outputKey,
                        type: details.outputTypeTag,
                        note: nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

private struct ScopeWorkflowBindingLine: View {
    let direction: String   // "in" / "out"
    let token: String
    let type: String?
    let note: String?

    private var arrow: String { direction == "in" ? "←" : "→" }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Spacer().frame(width: 20)
            Text(direction)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
                .frame(width: 22, alignment: .leading)
            Text(arrow)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
            ScopeWorkflowTokenChip(text: token)
            if let type = type {
                ScopeWorkflowTypeTag(text: type)
            }
            if let note = note {
                Text("· \(note)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

// MARK: Composer (UI-only stub)

private struct ScopeWorkflowComposer: View {
    let turnCount: Int
    let isSending: Bool
    let onSend: (String) -> Void

    @State private var draft: String = ""
    @State private var isRecording: Bool = false
    @State private var isTranscribing: Bool = false
    @State private var dictationError: String?
    @State private var showingModelMenu: Bool = false
    @FocusState private var draftFocused: Bool
    private var registry: LLMProviderRegistry { LLMProviderRegistry.shared }

    private var currentModel: LLMModel? {
        if let id = registry.selectedModelId,
           let model = registry.allModels.first(where: { $0.id == id }) {
            return model
        }

        return defaultModelFromProviderOrder()
    }

    private var currentModelLabel: String {
        currentModel?.displayName ?? currentModel?.name ?? "GPT-5.5"
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty && !isSending && !isRecording && !isTranscribing
    }

    private var inputPlaceholder: String {
        if isRecording { return "Listening... click mic again to stop" }
        if isTranscribing { return "Transcribing..." }
        return "Tell the builder what to change..."
    }

    private func performSend() {
        guard canSend else { return }
        let body = trimmedDraft
        draft = ""
        onSend(body)
    }

    private func defaultModelFromProviderOrder() -> LLMModel? {
        var seen = Set<String>()
        for providerId in LLMConfig.shared.preferredProviderOrder + registry.providers.map(\.id) {
            guard seen.insert(providerId).inserted else { continue }
            guard let provider = registry.provider(for: providerId) else { continue }

            let defaultModelId = provider.defaultModelId.isEmpty ? "gpt-5.5" : provider.defaultModelId
            if let defaultModel = registry.allModels.first(where: { $0.provider == providerId && $0.id == defaultModelId }) {
                return defaultModel
            }
            if let firstProviderModel = registry.allModels.first(where: { $0.provider == providerId }) {
                return firstProviderModel
            }
        }

        return registry.allModels.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Compact status row: model picker · turn count · live state
            HStack(spacing: 8) {
                ScopeModelPickerButton(
                    label: currentModelLabel,
                    presented: $showingModelMenu,
                    currentModelId: currentModel?.id,
                    registry: registry,
                    onPick: { picked in
                        registry.selectedProviderId = picked.provider
                        registry.selectedModelId = picked.id
                    }
                )
                ScopeWorkflowMetaDot()
                Text("\(turnCount) turns")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                Spacer()
                if isRecording {
                    Text("listening")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)
                } else if isTranscribing {
                    Text("transcribing")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)
                } else if let dictationError {
                    Text(dictationError)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(red: 0.71, green: 0.21, blue: 0.13))
                        .lineLimit(1)
                } else if isSending {
                    Text("sending")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    inputPlaceholder,
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(2...7)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(ScopeInk.primary)
                .focused($draftFocused)
                .onSubmit { performSend() }
                .disabled(isSending || isRecording || isTranscribing)
                .frame(minHeight: 56, alignment: .topLeading)
                .padding(.top, 3)

                ScopeMicButton(
                    isRecording: isRecording,
                    isTranscribing: isTranscribing,
                    action: toggleDictation
                )

                Button(action: performSend) {
                    Text("send")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(canSend ? ScopeCanvas.canvas : ScopeInk.subtle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(canSend ? ScopeBrass.solid : ScopeBrass.solid.opacity(0.22))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeAmber.tintSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? ScopeBrass.solid : ScopeEdge.normal, lineWidth: 1)
            )

        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .overlay(alignment: .top) {
            ScopeRule(.row)
        }
    }

    private func toggleDictation() {
        if isRecording {
            Task { await stopDictation() }
        } else if !isTranscribing {
            startDictation()
        }
    }

    private func startDictation() {
        isRecording = true
        dictationError = nil
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .skillsChatDictation)
        } catch {
            isRecording = false
            dictationError = error.localizedDescription
        }
    }

    @MainActor
    private func stopDictation() async {
        guard isRecording else { return }
        isRecording = false
        isTranscribing = true
        do {
            let text = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribing = false
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                dictationError = "No speech captured."
                return
            }
            dictationError = nil
            if draft.isEmpty {
                draft = cleaned
            } else {
                draft = draft.trimmingCharacters(in: .whitespacesAndNewlines) + " " + cleaned
            }
            draftFocused = true
        } catch {
            isTranscribing = false
            dictationError = error.localizedDescription
        }
    }
}

// MARK: Inspector
//
// Structure-only for this slice — sections are populated with stub
// data that mirrors the studio mock. Real wiring (input picker
// driving run, runs from WorkflowExecutor, trace from the last run)
// comes in the next slice.

private struct ScopeWorkflowInspector: View {
    let workflow: WorkflowDefinition
    @Binding var mode: ScopeInspectorMode
    @Bindable var runState: ScopeWorkflowRunState
    var onPickLibrary: () -> Void

    @State private var showAllRecents: Bool = false
    @State private var expandedEventId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ScopeWorkflowInspectorTab(label: "Runs", active: mode == .runs) {
                    mode = .runs
                }
                ScopeWorkflowInspectorTab(label: "Data", active: mode == .data) {
                    mode = .data
                }
                Spacer()
                switch mode {
                case .runs:
                    ScopeWorkflowRunButton(
                        small: true,
                        action: { Task { await runState.runTest(workflow: workflow) } },
                        enabled: runState.canRun
                    )
                case .data:
                    HStack(spacing: 12) {
                        Text("read-only")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                        Button {
                            copyWorkflowJSON()
                        } label: {
                            Text("copy")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ScopeInk.subtle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .overlay(alignment: .bottom) { ScopeRule(.row) }

            switch mode {
            case .runs:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        inputSection
                        ScopeRule(.row)
                        runsSection
                        ScopeRule(.row)
                        traceSection
                    }
                }
            case .data:
                ScopeWorkflowDataInspector(workflow: workflow)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ScopeCanvas.canvas)
    }

    private func copyWorkflowJSON() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(scopePrettyJSON(workflow), forType: .string)
    }

    private var inputSection: some View {
        let all = runState.recents
        let selected = runState.selectedRecent
        let visibleCount = ScopeSampleInputs.recentVisible
        let recents = showAllRecents ? all : Array(all.prefix(visibleCount))
        let hiddenCount = max(0, all.count - visibleCount)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Input")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
                if runState.isRunning {
                    Text("running…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)
                }
            }

            // Error pill from last run
            if let error = runState.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("⚠")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(red: 0.71, green: 0.21, blue: 0.13))
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.muted)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 0.71, green: 0.21, blue: 0.13).opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(red: 0.71, green: 0.21, blue: 0.13).opacity(0.20), lineWidth: 1)
                )
            }

            // Selected
            if let selected {
                let preview = ScopeInputDisplay.preview(for: selected)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ScopeSourceGlyph(kind: preview.kind, muted: false)
                    Text(preview.title)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(preview.meta)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }

                // Preview tile — renders the real image for captures,
                // placeholder strip for audio / text until we wire those.
                ScopeWorkflowInputPreviewTile(object: selected, kind: preview.kind)
            } else {
                // No selection yet
                HStack(spacing: 8) {
                    Text("No input selected")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.faint)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeAmber.tintSubtle.opacity(0.5))
                    .frame(height: 60)
                    .overlay(
                        Text("pick a recent or open the library")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ScopeEdge.subtle, lineWidth: 1)
                    )
            }

            // Recent list
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recents, id: \.id) { item in
                        let preview = ScopeInputDisplay.preview(for: item)
                        ScopeInputRecentRow(
                            kind: preview.kind,
                            title: preview.title,
                            meta: preview.meta,
                            isSelected: item.id == selected?.id,
                            onSelect: { runState.selectedRecent = item }
                        )
                    }
                    if hiddenCount > 0 {
                        Button {
                            showAllRecents.toggle()
                        } label: {
                            Text(showAllRecents ? "less" : "+\(hiddenCount) more")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ScopeInk.subtle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }

            // Action chips — filtered by the workflow's input contract.
            // Library is always offered (it's just a navigator); record /
            // text only when the workflow accepts audio / text inputs.
            HStack(spacing: 6) {
                ScopeInputSourceChip(label: "library", action: onPickLibrary)
                if workflow.inputs.acceptedRecordTypes.contains(.memo)
                    || workflow.inputs.acceptedRecordTypes.contains(.dictation) {
                    ScopeInputSourceChip(label: "record")
                }
                if workflow.inputs.acceptedRecordTypes.contains(.note)
                    || workflow.inputs.acceptedRecordTypes.contains(.selection) {
                    ScopeInputSourceChip(label: "text")
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Runs")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
                if !runState.runs.isEmpty {
                    Text("live")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)
                }
            }

            if runState.runs.isEmpty {
                Text("No runs yet. Pick an input and hit Run.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(runState.runs.prefix(12).enumerated()), id: \.element.id) { idx, run in
                        ScopeWorkflowRunsRow(
                            number: idx + 1,
                            run: run,
                            isSelected: run.id == runState.selectedRunId,
                            onSelect: { runState.selectedRunId = run.id }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var traceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(runState.selectedRunId == nil ? "Trace" : "Trace · run")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
                if !runState.selectedEvents.isEmpty {
                    Text("\(runState.selectedEvents.count) events")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
            if runState.selectedEvents.isEmpty {
                Text(runState.selectedRunId == nil
                     ? "Select a run to see its trace."
                     : "Loading events…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(runState.selectedEvents, id: \.id) { event in
                        ScopeTraceEventRow(
                            event: event,
                            isExpanded: expandedEventId == event.id,
                            onToggle: {
                                expandedEventId = (expandedEventId == event.id) ? nil : event.id
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct ScopeTraceEventRow: View {
    let event: ActionEventModel
    let isExpanded: Bool
    let onToggle: () -> Void

    private var levelColor: Color {
        switch event.level {
        case .error:   return Color(red: 0.71, green: 0.21, blue: 0.13)
        case .warning: return ScopeBrass.solid
        case .debug:   return ScopeInk.subtle
        case .info:    return ScopeInk.muted
        }
    }

    private var kindColor: Color {
        switch event.kind {
        case .runFailed, .stepFailed:  return Color(red: 0.71, green: 0.21, blue: 0.13)
        case .runQueued, .runStarted:  return ScopeInk.subtle
        case .runCompleted:            return ScopeBrass.solid
        default:                        return ScopeBrass.solid
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: event.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(ScopeInk.subtle)
                        .frame(width: 10, alignment: .leading)
                    Text(scopeEventKindLabel(event.kind))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(kindColor)
                        .frame(width: 70, alignment: .leading)
                    Text(event.message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(levelColor)
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScopeTraceEventDetail(event: event, timeString: timeString)
            }
        }
    }
}

private struct ScopeTraceEventDetail: View {
    let event: ActionEventModel
    let timeString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                detailField("time", value: timeString)
                detailField("seq",  value: "\(event.sequence)")
                detailField("level", value: event.level.rawValue)
            }
            if let pretty = scopePrettyPayload(event.payloadJSON), !pretty.isEmpty, pretty != "{}" {
                Text("payload")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(ScopeInk.subtle)
                    .padding(.top, 2)
                Text(pretty)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ScopeAmber.tintSubtle.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeEdge.subtle, lineWidth: 1)
        )
        .padding(.leading, 18)
        .padding(.bottom, 4)
    }

    private func detailField(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(ScopeInk.subtle)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ScopeInk.muted)
        }
    }
}

// Pretty-print payloadJSON if it parses as JSON; otherwise return
// the raw string. Empty / "{}" payloads return nil so the detail
// block can suppress the section.
private func scopePrettyPayload(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "{}" { return nil }
    if let data = trimmed.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(
           withJSONObject: obj,
           options: [.prettyPrinted, .sortedKeys]
       ),
       let str = String(data: pretty, encoding: .utf8) {
        return str
    }
    return trimmed
}

private struct ScopeWorkflowRunsRow: View {
    let number: Int
    let run: ActionRunModel
    let isSelected: Bool
    let onSelect: () -> Void

    private var time: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: run.startedAt ?? run.createdAt)
    }

    private var statusColor: Color {
        switch run.status {
        case .running, .queued: return ScopeBrass.solid
        case .failed:           return Color(red: 0.71, green: 0.21, blue: 0.13)
        default:                return ScopeInk.faint
        }
    }

    private var statusLabel: String {
        switch run.status {
        case .running:   return "running"
        case .queued:    return "queued"
        case .completed: return "ok"
        case .failed:    return "failed"
        case .cancelled: return "cancel"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                    .frame(width: 16, alignment: .leading)
                Text(time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 60, alignment: .leading)
                Text(run.summary ?? run.title)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? ScopeAmber.tintSubtle : Color.clear)
                    .padding(.horizontal, -6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func scopeEventKindLabel(_ kind: ActionEventModel.Kind) -> String {
    switch kind {
    case .runQueued:        return "queued"
    case .runStarted:       return "started"
    case .stepStarted:      return "step"
    case .stepCompleted:    return "step ✓"
    case .inputResolved:    return "input"
    case .artifactCreated:  return "artifact"
    case .runCompleted:     return "complete"
    case .runFailed:        return "failed"
    default:                return "\(kind)"
    }
}

// MARK: Atoms

private struct ScopeWorkflowRunButton: View {
    var small: Bool = false
    var action: (() -> Void)? = nil
    var enabled: Bool = true

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: small ? 8 : 9))
                Text("Run")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(enabled ? ScopeCanvas.canvas : ScopeInk.subtle)
            .padding(.horizontal, small ? 10 : 12)
            .padding(.vertical, small ? 5 : 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(enabled ? ScopeBrass.solid : ScopeBrass.solid.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil || !enabled)
    }
}

private struct ScopeWorkflowSecondaryButton: View {
    let label: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ScopeInk.faint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(ScopeEdge.normal, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

private struct ScopeWorkflowMetaDot: View {
    var body: some View {
        Circle()
            .fill(ScopeInk.subtle)
            .frame(width: 3, height: 3)
    }
}

private struct ScopeWorkflowTokenChip: View {
    let text: String

    var body: some View {
        Text("{\(text)}")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(ScopeBrass.solid)
    }
}

private struct ScopeWorkflowTypeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(ScopeInk.subtle)
    }
}

// MARK: - Step detail extraction
//
// Pulls a one-line summary, template-input tokens, and an output
// type tag out of a WorkflowStep's config. This is enough for the
// step row to render with the same density as the studio donor
// without modelling per-kind detail panes yet.

private struct ScopeStepDetails {
    let summaryLine: String?
    let inputs: [String]
    let outputTypeTag: String
}

private extension WorkflowStep {
    var scopeDetails: ScopeStepDetails {
        switch config {
        case .llm(let c):
            let provider = c.provider?.displayName ?? (c.autoRoute ? "auto" : "—")
            let model: String = {
                if let id = c.modelId, !id.isEmpty { return id }
                if let tier = c.costTier { return tier.displayName }
                return "auto"
            }()
            let summary = "\(provider) · \(model) · temp \(formatNum(c.temperature)) · max \(c.maxTokens)"
            var sources = [c.prompt]
            if let s = c.systemPrompt { sources.append(s) }
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: sources),
                outputTypeTag: "TXT"
            )

        case .shell(let c):
            let exe = (c.executable as NSString).lastPathComponent
            let summary = "\(exe) · timeout \(c.timeout)s\(c.captureStderr ? " · +stderr" : "")"
            var sources = c.arguments
            if let s = c.stdin { sources.append(s) }
            if let p = c.promptTemplate { sources.append(p) }
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: sources),
                outputTypeTag: "TXT"
            )

        case .transcribe(let c):
            let summary = "\(c.qualityTier.displayName) · \(c.primaryModel)"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: ["AUDIO"],
                outputTypeTag: "TXT"
            )

        case .speak(let c):
            let voice = c.voice ?? "default"
            let summary = "\(c.provider.displayName) · voice \(voice) · rate \(formatNum(Double(c.rate)))"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: [c.text]),
                outputTypeTag: "AUDIO"
            )

        case .trigger(let c):
            let head = c.phrases.first ?? ""
            let summary = "phrases [\(c.phrases.count)] · '\(head)' · \(c.searchLocation.displayName)"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: ["TRANSCRIPT"],
                outputTypeTag: "EVT"
            )

        case .intentExtract(let c):
            let summary = "input '\(c.inputKey)'"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: [c.inputKey],
                outputTypeTag: "JSON"
            )

        case .webhook(let c):
            let summary = "\(c.method.rawValue) \(c.url)"
            return ScopeStepDetails(
                summaryLine: summary,
                inputs: scopeTemplateTokens(from: [c.url, c.bodyTemplate ?? ""]),
                outputTypeTag: "JSON"
            )

        case .conditional(let c):
            return ScopeStepDetails(
                summaryLine: "if \(c.condition)",
                inputs: scopeTemplateTokens(from: [c.condition]),
                outputTypeTag: "BOOL"
            )

        case .transform(let c):
            return ScopeStepDetails(
                summaryLine: "transform · \(c.operation.rawValue)",
                inputs: scopeTemplateTokens(from: Array(c.parameters.values)),
                outputTypeTag: "TXT"
            )

        default:
            return ScopeStepDetails(
                summaryLine: nil,
                inputs: [],
                outputTypeTag: scopeDefaultOutputTag(for: type)
            )
        }
    }
}

private func formatNum(_ value: Double) -> String {
    if value == value.rounded() { return String(format: "%.0f", value) }
    return String(format: "%.2f", value).trimmingCharacters(in: ["0"])
}

private func scopeTemplateTokens(from sources: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    let pattern = try? NSRegularExpression(pattern: "\\{\\{\\s*([A-Za-z0-9_.]+)\\s*\\}\\}")
    for src in sources where !src.isEmpty {
        let range = NSRange(src.startIndex..., in: src)
        pattern?.enumerateMatches(in: src, range: range) { match, _, _ in
            guard let m = match,
                  let r = Range(m.range(at: 1), in: src) else { return }
            let token = String(src[r])
            if !seen.contains(token) {
                seen.insert(token)
                ordered.append(token)
            }
        }
    }
    return ordered
}

private func scopeDefaultOutputTag(for type: WorkflowStep.StepType) -> String {
    switch type {
    case .transcribe, .speak: return "TXT"
    case .clipboard, .saveFile: return "TXT"
    case .webhook, .intentExtract, .conditional: return "JSON"
    case .notification, .iOSPush, .email, .appleNotes, .appleReminders, .appleCalendar: return "EVT"
    case .cloudUpload: return "URL"
    default: return "TXT"
    }
}

// MARK: - Inspector tab atom

private struct ScopeWorkflowInspectorTab: View {
    let label: String
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(active ? ScopeInk.primary : ScopeInk.faint)
                Rectangle()
                    .fill(active ? ScopeBrass.solid : Color.clear)
                    .frame(height: 1.5)
            }
            .frame(width: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
    }
}

// MARK: - Data Inspector
//
// Read-only JSON of the workflow definition. Lightweight syntax
// tinting (keys neutral, strings in brass, numbers ink, bool/null
// faint, punctuation subtle) and a gutter for line numbers — gives
// the dev something to point at when describing a section.

private struct ScopeWorkflowDataInspector: View {
    let workflow: WorkflowDefinition

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                let lines = scopePrettyJSON(workflow).components(separatedBy: "\n")
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                            .frame(width: 32, alignment: .trailing)
                            .lineLimit(1)
                        scopeColoredLine(line)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

// Regex tokenizer matching the studio's JsonLine — keys, strings,
// numbers, bools, null, punctuation.
private func scopeColoredLine(_ line: String) -> Text {
    let pattern = try? NSRegularExpression(
        pattern: #"("(?:[^"\\]|\\.)*"\s*:)|("(?:[^"\\]|\\.)*")|(\b-?\d+(?:\.\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)|([{}\[\],])|(\s+)"#
    )
    guard let pattern = pattern else {
        return Text(line).foregroundStyle(ScopeInk.primary)
    }
    var result = Text("")
    var cursor = line.startIndex
    let nsLine = line as NSString
    let range = NSRange(location: 0, length: nsLine.length)
    pattern.enumerateMatches(in: line, range: range) { match, _, _ in
        guard let m = match else { return }
        // Emit any unmatched ink between cursor and match start
        if let matchStart = Range(m.range, in: line), cursor < matchStart.lowerBound {
            let gap = String(line[cursor..<matchStart.lowerBound])
            result = result + Text(gap).foregroundStyle(ScopeInk.primary)
        }
        let groupColor: (Int, Color)? = {
            if m.range(at: 1).location != NSNotFound { return (1, ScopeInk.primary) }
            if m.range(at: 2).location != NSNotFound { return (2, ScopeBrass.solid) }
            if m.range(at: 3).location != NSNotFound { return (3, ScopeInk.primary) }
            if m.range(at: 4).location != NSNotFound { return (4, ScopeInk.faint) }
            if m.range(at: 5).location != NSNotFound { return (5, ScopeInk.subtle) }
            if m.range(at: 6).location != NSNotFound { return (6, ScopeInk.primary) }
            return nil
        }()
        if let (g, color) = groupColor, let r = Range(m.range(at: g), in: line) {
            result = result + Text(String(line[r])).foregroundStyle(color)
            cursor = r.upperBound
        }
    }
    if cursor < line.endIndex {
        result = result + Text(String(line[cursor...])).foregroundStyle(ScopeInk.primary)
    }
    return result
}

private func scopePrettyJSON(_ workflow: WorkflowDefinition) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
        let data = try encoder.encode(workflow)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{\n  \"_encodingError\": \"\(error)\"\n}"
    }
}

// MARK: - Run state (Scope inspector live model)
//
// Owns the picker recents, the runs feed, and the currently-running
// test. Mirrors the legacy WorkflowTestRunPanel's flow — create an
// ActionRunModel, fire events through LocalRepository, hand off to
// WorkflowExecutor.shared.executeWorkflow, mark complete on success
// / failed on error. The runs feed polls every 1s for live updates.

// Singleton holder so each workflow has its own run state and runs
// can be queued / in flight across workflows. Switching workflows
// in the sidebar pulls up that workflow's state — the prior run
// keeps progressing in the background. Each ScopeWorkflowRunState
// gates its own button (so double-clicks are still blocked), but
// nothing is global.
@MainActor
@Observable
final class ScopeWorkflowRunStateStore {
    static let shared = ScopeWorkflowRunStateStore()
    private var states: [UUID: ScopeWorkflowRunState] = [:]

    func state(for workflow: WorkflowDefinition) -> ScopeWorkflowRunState {
        if let s = states[workflow.id] { return s }
        let s = ScopeWorkflowRunState()
        states[workflow.id] = s
        return s
    }
}

@MainActor
@Observable
final class ScopeWorkflowRunState {
    var recents: [TalkieObject] = []
    var selectedRecent: TalkieObject?
    var runs: [ActionRunModel] = []
    var selectedRunId: UUID?
    var selectedEvents: [ActionEventModel] = []
    var isRunning: Bool = false
    var errorMessage: String?

    private let objectRepository = TalkieObjectRepository()
    private let actionRepository = LocalRepository()
    private let log = Log(.workflow)
    private var hasBootstrapped = false

    var canRun: Bool {
        !isRunning && selectedRecent != nil
    }

    func bootstrap(workflow: WorkflowDefinition) async {
        hasBootstrapped = false
        await loadRecents(workflow: workflow)
        await loadRuns(workflow: workflow)
        hasBootstrapped = true
    }

    func pollLoop(workflow: WorkflowDefinition) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            await loadRuns(workflow: workflow, showSpinner: false)
        }
    }

    func loadRecents(workflow: WorkflowDefinition) async {
        do {
            let all = try await objectRepository.fetchRecordings(limit: 200)
            let eligible = all.filter { scopeMatchesWorkflowInput($0, workflow: workflow) }
            recents = Array(eligible.prefix(20))
            if selectedRecent == nil {
                selectedRecent = recents.first
            }
        } catch {
            log.error("Failed to load Scope workflow recents: \(error.localizedDescription)")
        }
    }

    func loadRuns(workflow: WorkflowDefinition, showSpinner: Bool = true) async {
        do {
            let loaded = try await actionRepository
                .allActionRuns(limit: 50)
                .filter { $0.actionKind == .workflow && $0.actionId == workflow.id.uuidString }
            runs = loaded
            if selectedRunId == nil {
                selectedRunId = loaded.first?.id
            }
            await loadSelectedRunDetails()
        } catch {
            log.error("Failed to load Scope workflow runs: \(error.localizedDescription)")
        }
    }

    func loadSelectedRunDetails() async {
        guard let id = selectedRunId else {
            selectedEvents = []
            return
        }
        do {
            selectedEvents = try await actionRepository.fetchActionEvents(for: id)
        } catch {
            log.error("Failed to load Scope run events: \(error.localizedDescription)")
        }
    }

    func runTest(workflow: WorkflowDefinition) async {
        guard !isRunning else { return }
        guard let target = selectedRecent else {
            errorMessage = "Pick an input first."
            return
        }

        isRunning = true
        errorMessage = nil
        let runId = UUID()
        let inputPackageId = UUID()
        let now = Date()

        do {
            let subject = ActionSubjectRef(
                actionRunId: runId,
                kind: scopeSubjectKind(for: target),
                recordId: target.id,
                titleSnapshot: target.displayTitle,
                createdAt: now
            )
            let inputPackage = ActionInputPackage(
                id: inputPackageId,
                actionRunId: runId,
                renderedSnapshot: target.displayTitle,
                createdAt: now
            )
            let run = ActionRunModel(
                id: runId,
                actionId: workflow.id.uuidString,
                actionKind: .workflow,
                title: workflow.name,
                inputPackageId: inputPackageId,
                status: .running,
                createdAt: now,
                updatedAt: now,
                startedAt: now,
                summary: "Running \(workflow.name)"
            )

            try await actionRepository.createActionRun(
                run,
                inputPackage: inputPackage,
                subjectRefs: [subject],
                events: [
                    ActionEventModel(actionRunId: runId, kind: .runQueued, message: "\(workflow.name) queued"),
                    ActionEventModel(actionRunId: runId, kind: .runStarted, message: "\(workflow.name) started")
                ]
            )
            selectedRunId = runId
            await loadRuns(workflow: workflow, showSpinner: false)

            // Per-step trace breadcrumbs — match the legacy run-test pattern
            _ = try await actionRepository.appendActionEvent(
                actionRunId: runId,
                kind: .stepStarted,
                level: .info,
                message: "Resolving input",
                payloadJSON: "{}"
            )
            _ = try await actionRepository.appendActionEvent(
                actionRunId: runId,
                kind: .inputResolved,
                level: .info,
                message: "Input: \(target.displayTitle)",
                payloadJSON: scopeInputPayload(target)
            )
            _ = try await actionRepository.appendActionEvent(
                actionRunId: runId,
                kind: .stepStarted,
                level: .info,
                message: "Running \(workflow.name)",
                payloadJSON: "{}"
            )

            let outputs = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: target)
            let summary = scopePrimaryOutput(outputs: outputs, workflow: workflow)

            _ = try await actionRepository.appendActionEvent(
                actionRunId: runId,
                kind: .artifactCreated,
                level: .info,
                message: "Result captured (\(outputs.count) outputs)",
                payloadJSON: scopeOutputsPayload(outputs)
            )
            _ = try await actionRepository.appendActionEvent(
                actionRunId: runId,
                kind: .runCompleted,
                level: .info,
                message: "\(workflow.name) completed",
                payloadJSON: "{}"
            )
            try await actionRepository.updateActionRun(
                id: runId,
                status: .completed,
                summary: summary,
                primaryResult: summary,
                completedAt: Date()
            )
        } catch {
            errorMessage = error.localizedDescription
            log.error("Scope workflow run failed: \(error.localizedDescription)")
            _ = try? await actionRepository.appendActionEvent(
                actionRunId: runId,
                kind: .runFailed,
                level: .error,
                message: error.localizedDescription,
                payloadJSON: "{}"
            )
            try? await actionRepository.updateActionRun(
                id: runId,
                status: .failed,
                summary: error.localizedDescription,
                errorMessage: error.localizedDescription,
                errorDetails: String(describing: error),
                completedAt: Date()
            )
        }

        isRunning = false
        await loadRuns(workflow: workflow, showSpinner: false)
    }
}

private func scopeMatchesWorkflowInput(_ object: TalkieObject, workflow: WorkflowDefinition) -> Bool {
    guard object.type != .segment else { return false }
    let assets = workflow.inputs.requiredAssets
    let isVisual = assets.contains(.screenshot) || assets.contains(.image) || assets.contains(.clip)
    if isVisual {
        return assets.allSatisfy { asset in
            switch asset {
            case .screenshot: return !object.screenshots.isEmpty
            case .image:      return object.attachments.contains { $0.kind == .image }
            case .clip:       return !object.clips.isEmpty
            case .transcript, .text:
                return (object.text?.isEmpty == false)
            case .audio:      return object.hasAudio
            }
        }
    }
    if workflow.startsWithTranscribe { return object.hasAudio }

    // A trigger or intentExtract step (without a transcribe ahead of it)
    // needs a real transcript in the input — they pattern-match on text.
    let hasTranscribeFirst = workflow.steps.first?.type == .transcribe
    let needsTranscript =
        !hasTranscribeFirst &&
        (workflow.steps.contains { $0.type == .trigger || $0.type == .intentExtract }
         || assets.contains(.transcript)
         || assets.contains(.text))

    if needsTranscript {
        guard let text = object.text, !text.isEmpty else { return false }

        // Trigger-gated workflows refuse to fire without a matching
        // phrase — surface only memos that will actually trigger.
        // Scans every trigger step in the workflow; matches any
        // phrase from any of them. Case-insensitive when the step
        // is configured that way (the default).
        let gatedPhrases = workflow.steps.compactMap { step -> TriggerStepConfig? in
            guard case .trigger(let cfg) = step.config, cfg.stopIfNoMatch else { return nil }
            return cfg
        }
        if !gatedPhrases.isEmpty {
            let matched = gatedPhrases.contains { cfg in
                let haystack = cfg.caseSensitive ? text : text.lowercased()
                return cfg.phrases.contains { phrase in
                    let needle = cfg.caseSensitive ? phrase : phrase.lowercased()
                    return haystack.contains(needle)
                }
            }
            if !matched { return false }
        }
        return true
    }

    guard let recordType = WorkflowRecordType(object.type) else { return false }
    return workflow.inputs.acceptedRecordTypes.contains(recordType)
}

private func scopeSubjectKind(for object: TalkieObject) -> ActionSubjectRef.Kind {
    switch object.type {
    case .memo, .dictation, .segment: return .memo
    case .capture:                     return .capture
    case .note:                        return .note
    case .selection:                   return .selection
    }
}

// MARK: - Turns + Model picker (composer atoms)

private struct ScopeTurn: Identifiable, Hashable {
    enum Role { case user, agent }
    let id: String
    let role: Role
    let time: String
    let body: String

    static func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// Provider id → display name. Falls back to the id if the registry
// doesn't know about that provider.
@MainActor
private func scopeProviderDisplayName(_ providerId: String) -> String {
    LLMProviderRegistry.shared.providers
        .first { $0.id == providerId }?
        .name ?? providerId
}

private struct ScopeWorkflowTurnsBlock: View {
    let turns: [ScopeTurn]
    let isSending: Bool
    let collapsed: Bool
    let onToggle: () -> Void
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("TURNS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(ScopeInk.subtle)
                Text("· \(turns.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                if isSending {
                    Text("· builder is thinking")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ScopeBrass.solid)
                }
                Spacer()
                Button(action: onToggle) {
                    Text(collapsed ? "show" : "collapse")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if !collapsed {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(turns) { turn in
                                ScopeWorkflowTurnRow(turn: turn)
                                    .id(turn.id)
                            }
                            if isSending {
                                ScopeAgentThinkingRow()
                                    .id("thinking-row")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: turns.count) { _, _ in
                        if let last = turns.last {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("thinking-row", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: collapsed ? nil : height)
        .background(ScopeCanvas.canvas)
    }
}

private struct ScopeAgentThinkingRow: View {
    @State private var animating: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ScopeBrass.solid.opacity(animating ? 1.0 : 0.35))
                .frame(width: 5, height: 5)
            Text("builder")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ScopeBrass.solid)
            Text("typing…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ScopeInk.faint)
                .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

private struct ScopeWorkflowTurnRow: View {
    let turn: ScopeTurn

    private var isAgent: Bool { turn.role == .agent }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isAgent ? ScopeBrass.solid : ScopeInk.subtle)
                    .frame(width: 5, height: 5)
                Text(isAgent ? "builder" : "you")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isAgent ? ScopeBrass.solid : ScopeInk.faint)
                Circle()
                    .fill(ScopeInk.subtle)
                    .frame(width: 3, height: 3)
                Text(turn.time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                Spacer(minLength: 0)
            }
            Text(turn.body)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isAgent ? ScopeInk.primary : ScopeInk.faint)
                .lineSpacing(2)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if !isAgent {
                        Rectangle()
                            .fill(ScopeEdge.subtle)
                            .frame(width: 1)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScopeTurnsResizeHandle: View {
    @Binding var height: CGFloat
    @State private var startHeight: CGFloat = 0
    @State private var startY: CGFloat? = nil
    @State private var hovering: Bool = false

    private let minHeight: CGFloat = 80
    private let maxHeight: CGFloat = 560

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ScopeEdge.faint)
                .frame(height: 1)
            Color.clear
                .frame(height: 11)
                .contentShape(Rectangle())
        }
        .onHover { value in
            if value != hovering {
                hovering = value
                if value { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if startY == nil {
                        startY = value.startLocation.y
                        startHeight = height
                    }
                    let dy = (startY ?? value.location.y) - value.location.y
                    let next = (startHeight + dy).rounded()
                    height = min(maxHeight, max(minHeight, next))
                }
                .onEnded { _ in
                    startY = nil
                }
        )
    }
}

private struct ScopeMicButton: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let action: () -> Void

    private var iconName: String {
        if isTranscribing { return "waveform" }
        return isRecording ? "stop.fill" : "mic"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isRecording ? ScopeCanvas.canvas : ScopeBrass.solid)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isRecording ? ScopeBrass.solid : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? ScopeBrass.solid : ScopeEdge.normal, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(isRecording ? "Stop dictation" : isTranscribing ? "Transcribing..." : "Start dictation")
    }
}

private struct ScopeModelPickerButton: View {
    let label: String
    @Binding var presented: Bool
    let currentModelId: String?
    let registry: LLMProviderRegistry
    let onPick: (LLMModel) -> Void

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(ScopeInk.subtle)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            ScopeModelMenu(
                currentModelId: currentModelId,
                registry: registry
            ) { picked in
                onPick(picked)
                presented = false
            }
        }
    }
}

private struct ScopeModelMenu: View {
    let currentModelId: String?
    let registry: LLMProviderRegistry
    let onPick: (LLMModel) -> Void

    @State private var showAll: Bool = false

    // For each provider, surface the recommended subset by default.
    // Anything beyond that is locked behind 'show all'. Providers
    // with zero installed models are skipped entirely.
    private var providerSections: [(providerId: String, providerName: String, models: [LLMModel])] {
        var sections: [(String, String, [LLMModel])] = []
        for provider in registry.providers {
            let providerModels = registry.allModels.filter { $0.provider == provider.id }
            guard !providerModels.isEmpty else { continue }

            if showAll {
                sections.append((provider.id, provider.name, providerModels))
            } else {
                let recommended = registry.recommendedModels(for: provider.id)
                // recommendedModels falls back to all when nothing is
                // marked recommended — clamp to a sensible default of
                // the top 3 in that case so we don't dump 30 models.
                let curated: [LLMModel] =
                    (recommended.count < providerModels.count)
                    ? recommended
                    : Array(providerModels.prefix(3))
                if !curated.isEmpty {
                    sections.append((provider.id, provider.name, curated))
                }
            }
        }
        return sections
    }

    private var hiddenCount: Int {
        let visible = providerSections.reduce(0) { $0 + $1.models.count }
        return max(0, registry.allModels.count - visible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if providerSections.isEmpty {
                Text("No models installed.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                    .padding(12)
            } else {
                ForEach(providerSections, id: \.providerId) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(section.providerName.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(ScopeInk.subtle)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        ForEach(section.models) { m in
                            Button(action: { onPick(m) }) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(m.id == currentModelId ? ScopeBrass.solid : Color.clear)
                                        .overlay(
                                            Circle()
                                                .stroke(m.id == currentModelId ? Color.clear : ScopeInk.subtle, lineWidth: 1)
                                        )
                                        .frame(width: 5, height: 5)
                                    Text(m.displayName.isEmpty ? m.name : m.displayName)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(m.id == currentModelId ? ScopeBrass.solid : ScopeInk.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    if !m.size.isEmpty && m.size != "0" {
                                        Text(m.size)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(ScopeInk.subtle)
                                    } else if m.type == .local {
                                        Text("local")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(ScopeInk.subtle)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    m.id == currentModelId
                                    ? ScopeAmber.tintSubtle
                                    : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if hiddenCount > 0 || showAll {
                    Divider()
                        .padding(.top, 6)
                    Button {
                        showAll.toggle()
                    } label: {
                        Text(showAll ? "show fewer" : "show all (+\(hiddenCount))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 240)
        .background(ScopeCanvas.canvas)
    }
}

private func scopePrimaryOutput(outputs: [String: String], workflow: WorkflowDefinition) -> String {
    // Walk steps in order, take the last filled outputKey
    for step in workflow.steps.reversed() {
        if let v = outputs[step.outputKey], !v.isEmpty { return v }
    }
    return outputs.first?.value ?? "\(workflow.name) completed"
}

private func scopeInputPayload(_ object: TalkieObject) -> String {
    let preview = (object.text ?? "").prefix(140)
    let payload: [String: String] = [
        "id": object.id.uuidString,
        "type": object.type.rawValue,
        "hasText": object.text?.isEmpty == false ? "true" : "false",
        "preview": String(preview)
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{}"
}

private func scopeOutputsPayload(_ outputs: [String: String]) -> String {
    let trimmed = outputs.mapValues { String($0.prefix(80)) }
    if let data = try? JSONSerialization.data(withJSONObject: trimmed),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{}"
}

// MARK: - Input picker model & atoms
//
// Sources that can drive a workflow test run. Real wiring to memos /
// captures / notes happens in the next slice — for now, sample data
// shows the picker shape.

private enum ScopeSourceKind {
    case capture, memo, note, text, recording

    var glyph: String {
        switch self {
        case .capture:   return "▣"
        case .memo:      return "≋"
        case .note:      return "¶"
        case .text:      return "T"
        case .recording: return "●"
        }
    }

    var previewLabel: String {
        switch self {
        case .capture:   return "image preview"
        case .memo:      return "audio waveform"
        case .note:      return "text preview"
        case .text:      return "text preview"
        case .recording: return "live recording"
        }
    }
}

private enum ScopeSampleInputs {
    static let recentVisible = 3
}

// MARK: - App-wide lightbox utility
//
// `.scopeExpandable(imageURL:)` makes any view click-to-expand into a
// full-bleed image preview. Lives here for now because the inspector
// tile is the first adopter; lift to a shared file once a second
// surface (memo detail, capture row, etc.) wires it up.
//
// Wiring: `ScopeLightboxHost()` must be installed once at the app
// root (already done in TalkieApp.swift) so the overlay can paint
// over the whole window when triggered.

@Observable
@MainActor
final class ScopeLightboxPresenter {
    static let shared = ScopeLightboxPresenter()
    private init() {}

    var currentURL: URL? = nil

    func present(_ url: URL) { currentURL = url }
    func dismiss() { currentURL = nil }
}

struct ScopeLightboxHost: View {
    @Bindable private var presenter = ScopeLightboxPresenter.shared

    var body: some View {
        ZStack {
            if let url = presenter.currentURL {
                ScopeLightboxView(imageURL: url) { presenter.dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: presenter.currentURL)
    }
}

private struct ScopeLightboxView: View {
    let imageURL: URL
    let onDismiss: () -> Void

    private var image: NSImage? {
        NSImage(contentsOf: imageURL)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(40)
            } else {
                Text("Couldn't load preview")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding(12)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Adds click-to-expand behavior to any view that displays an image
    /// (or could). When `imageURL` is non-nil, hover shows the pointing-
    /// hand cursor and a click promotes the image into the app-wide
    /// lightbox overlay. No-op when nil.
    func scopeExpandable(imageURL: URL?) -> some View {
        modifier(ScopeExpandableModifier(imageURL: imageURL))
    }
}

private struct ScopeExpandableModifier: ViewModifier {
    let imageURL: URL?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                guard imageURL != nil else { return }
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                guard let url = imageURL else { return }
                ScopeLightboxPresenter.shared.present(url)
            }
    }
}

// Real input preview for the inspector. Captures render the actual
// screenshot; text/note types show a snippet; audio still falls back
// to a label until a real waveform lands.
private struct ScopeWorkflowInputPreviewTile: View {
    let object: TalkieObject
    let kind: ScopeSourceKind

    private var screenshotURL: URL? {
        guard let shot = object.screenshots.first else { return nil }
        if shot.filename.hasPrefix("/") {
            return URL(fileURLWithPath: shot.filename)
        }
        return ScreenshotStorage.screenshotsDirectory.appending(
            path: shot.filename,
            directoryHint: .notDirectory
        )
    }

    private var image: NSImage? {
        guard let url = screenshotURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var textSnippet: String? {
        guard let text = object.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(280))
    }

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: 6)

        Group {
            if let image {
                // Letterbox the image — never crop. Tall portrait
                // screenshots and wide landscapes both stay legible
                // against a soft canvas mat at a fixed tile height.
                // Click to expand into the app-wide lightbox.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(ScopeAmber.tintSubtle)
                    .scopeExpandable(imageURL: screenshotURL)
            } else if let snippet = textSnippet, (kind == .note || kind == .text || kind == .memo) {
                Text(snippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.muted)
                    .lineLimit(6)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
                    .frame(height: 96)
                    .background(ScopeAmber.tintSubtle)
            } else {
                Text(kind.previewLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(ScopeAmber.tintSubtle)
            }
        }
        .clipShape(frame)
        .overlay(frame.stroke(ScopeEdge.subtle, lineWidth: 1))
    }
}

// Display shim — maps TalkieObject to the small bundle the picker rows need.
private enum ScopeInputDisplay {
    struct Preview {
        let kind: ScopeSourceKind
        let title: String
        let meta: String
    }

    static func preview(for object: TalkieObject) -> Preview {
        Preview(
            kind: kind(for: object),
            title: title(for: object),
            meta: meta(for: object)
        )
    }

    private static func kind(for object: TalkieObject) -> ScopeSourceKind {
        switch object.type {
        case .memo, .dictation: return .memo
        case .capture:           return .capture
        case .note:              return .note
        case .selection:         return .text
        case .segment:           return .memo
        }
    }

    private static func title(for object: TalkieObject) -> String {
        let candidate = object.displayTitle
        return candidate.isEmpty ? object.type.rawValue.capitalized : candidate
    }

    private static func meta(for object: TalkieObject) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        let when = f.string(from: object.createdAt)
        switch object.type {
        case .memo, .dictation:
            if object.duration > 0 {
                return "\(when) · \(scopeFormatDuration(object.duration))"
            }
            return when
        case .capture:
            if let shot = object.screenshots.first {
                return "\(when) · \(shot.width)×\(shot.height)"
            }
            return when
        case .note, .selection, .segment:
            let words = (object.text ?? "")
                .split(whereSeparator: \.isWhitespace)
                .count
            return words > 0 ? "\(when) · \(words) words" : when
        }
    }
}

private func scopeFormatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let mins = total / 60
    let secs = total % 60
    return mins > 0 ? "\(mins)m \(String(format: "%02d", secs))s" : "\(secs)s"
}

private struct ScopeSourceGlyph: View {
    let kind: ScopeSourceKind
    let muted: Bool

    var body: some View {
        Text(kind.glyph)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(muted ? ScopeInk.subtle : ScopeBrass.solid)
            .frame(width: 12, alignment: .center)
    }
}

private struct ScopeInputRecentRow: View {
    let kind: ScopeSourceKind
    let title: String
    let meta: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .stroke(isSelected ? Color.clear : ScopeInk.subtle, lineWidth: 1)
                    .background(
                        Circle().fill(isSelected ? ScopeBrass.solid : Color.clear)
                    )
                    .frame(width: 5, height: 5)
                ScopeSourceGlyph(kind: kind, muted: !isSelected)
                Text(title)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.faint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(meta)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? ScopeAmber.tintSubtle : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ScopeInputSourceChip: View {
    let label: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Text("+ \(label)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(action == nil ? ScopeInk.subtle : ScopeInk.faint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.normal, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
