//
//  CodexNewTaskView.swift
//  Talkie iOS
//
//  THESIS: New-task creation is a short signal path, not a configuration form.
//  OWN WORLD: Talkie's paper-and-instrument Command Deck, with one lit trace.
//  STORY: Choose the project, enter NEW mode, then land ready to talk.
//  FIRST VIEWPORT: The path, the reason for the choice, and lane projects fit before scrolling.
//  FORM: Flat native rows, quiet metadata, one bottom action, and no lane mutation.
//

import SwiftUI

struct CodexNewTaskView: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProjectID: String?
    @State private var projectSearch = ""
    @State private var creationID = UUID()
    @State private var createdTaskID: String?
    @State private var stage: CodexTaskCreationStage = .project

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CodexNewTaskHeader(isLocked: isLocked, onCancel: { dismiss() })

                        CodexTaskSignalRail(stage: stage)

                        CodexTaskCreationIntroduction()

                        CodexProjectPicker(
                            assignedProjects: assignedProjects,
                            recentProjects: recentProjects,
                            laneNumbersByProjectID: laneNumbersByProjectID,
                            selectedProjectID: selectedProjectID,
                            isLoading: store.isLoadingCatalog,
                            hasSearchQuery: hasSearchQuery,
                            catalogFailure: store.catalogFailure,
                            onSelect: selectProject,
                            onRefresh: refreshCatalog
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .disabled(isLocked)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if let project = selectedProject {
                    CodexTaskCreateDock(
                        project: project,
                        stage: stage,
                        failure: store.creationFailure,
                        onCreate: { createTask(in: project) }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .searchable(text: $projectSearch, prompt: "Search projects")
        }
        .interactiveDismissDisabled(isLocked)
        .task {
            store.clearCreationFailure()
            store.beginCatalogUpdates()
        }
        .onDisappear { store.endCatalogUpdates() }
        .onChange(of: selectedProjectID) {
            creationID = UUID()
            store.clearCreationFailure()
        }
        .sensoryFeedback(.selection, trigger: selectedProjectID)
        .sensoryFeedback(.success, trigger: createdTaskID)
        .animation(selectionAnimation, value: selectedProjectID)
        .animation(stageAnimation, value: stage)
    }

    private var filteredProjects: [CodexProjectSummary] {
        let query = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.name.localizedStandardContains(query)
                || $0.cwd.localizedStandardContains(query)
        }
    }

    private var assignedProjects: [CodexProjectSummary] {
        filteredProjects.filter(\.isAssignedToLane)
    }

    private var recentProjects: [CodexProjectSummary] {
        filteredProjects.filter { !$0.isAssignedToLane }
    }

    private var selectedProject: CodexProjectSummary? {
        store.projects.first { $0.id == selectedProjectID }
    }

    private var hasSearchQuery: Bool {
        !projectSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var laneNumbersByProjectID: [String: [Int]] {
        Dictionary(uniqueKeysWithValues: filteredProjects.map { project in
            (project.id, lanes(for: project))
        })
    }

    private var isLocked: Bool {
        store.isCreatingTask || createdTaskID != nil
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.32, dampingFraction: 0.84)
    }

    private var stageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.8)
    }

    private func lanes(for project: CodexProjectSummary) -> [Int] {
        store.sortedLanes.compactMap { lane in
            lane.task.canonicalWorkingDirectory == project.cwd ? lane.number : nil
        }
    }

    private func selectProject(_ project: CodexProjectSummary) {
        guard !isLocked else { return }
        selectedProjectID = project.id
        stage = .project
    }

    private func refreshCatalog() {
        Task { await store.refreshCatalog() }
    }

    private func createTask(in project: CodexProjectSummary) {
        guard stage == .project, !store.isCreatingTask else { return }
        stage = .task

        Task {
            guard store.enterNewTaskMode(in: project, submissionID: creationID) else {
                stage = .project
                return
            }

            createdTaskID = creationID.uuidString
            stage = .talk
            try? await Task.sleep(for: reduceMotion ? .milliseconds(260) : .milliseconds(680))
            dismiss()
        }
    }
}

private struct CodexNewTaskHeader: View {
    let isLocked: Bool
    let onCancel: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.chrome.accent)
                .frame(width: 76, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .disabled(isLocked)

            Spacer(minLength: 0)

            Text("New Codex Task")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 76, height: 44)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
    }
}

private enum CodexTaskCreationStage: Int, CaseIterable {
    case project
    case task
    case talk

    var title: String {
        switch self {
        case .project: "Project"
        case .task: "Task"
        case .talk: "Talk"
        }
    }

    var systemImage: String {
        switch self {
        case .project: "folder"
        case .task: "rectangle.badge.plus"
        case .talk: "waveform"
        }
    }

    var progressDescription: String {
        switch self {
        case .project: "Choose a project. Task and talk are next."
        case .task: "Project chosen. Preparing new task mode."
        case .talk: "New task mode ready. Hold to talk."
        }
    }
}

private struct CodexTaskSignalRail: View {
    let stage: CodexTaskCreationStage

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: dynamicTypeSize.isAccessibilitySize ? 6 : 10) {
            ForEach(CodexTaskCreationStage.allCases, id: \.self) { item in
                CodexTaskSignalStageView(item: item, currentStage: stage)

                if item != .talk {
                    Rectangle()
                        .fill(
                            stage.rawValue > item.rawValue
                                ? theme.chrome.trace
                                : theme.colors.textTertiary.opacity(0.28)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: theme.chrome.hairlineWidth)
                        .padding(.top, 14)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Creation progress")
        .accessibilityValue(stage.progressDescription)
    }
}

private struct CodexTaskSignalStageView: View {
    let item: CodexTaskCreationStage
    let currentStage: CodexTaskCreationStage

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 28, height: 28)
                .background(symbolBackground, in: .circle)
                .overlay {
                    Circle()
                        .strokeBorder(symbolBorder, lineWidth: currentStage == item ? 1 : 0.5)
                }

            Text(item.title.uppercased())
                .font(.caption2.weight(.medium).monospaced())
                .tracking(0.9)
                .foregroundStyle(currentStage == item ? theme.chrome.accent : theme.colors.textTertiary)
                .lineLimit(1)
        }
        .frame(minWidth: 48)
    }

    private var isReached: Bool {
        currentStage.rawValue >= item.rawValue
    }

    private var symbolName: String {
        currentStage.rawValue > item.rawValue ? "checkmark" : item.systemImage
    }

    private var symbolColor: Color {
        isReached ? theme.chrome.accent : theme.colors.textTertiary
    }

    private var symbolBackground: Color {
        currentStage == item ? theme.chrome.accentTint : theme.chrome.actionTint
    }

    private var symbolBorder: Color {
        isReached ? theme.chrome.accent.opacity(0.55) : theme.chrome.edgeFaint
    }
}

private struct CodexTaskCreationIntroduction: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Text("Choose a project")
            .font(.headline.weight(.semibold))
            .foregroundStyle(theme.colors.textPrimary)
    }
}

private struct CodexProjectPicker: View {
    let assignedProjects: [CodexProjectSummary]
    let recentProjects: [CodexProjectSummary]
    let laneNumbersByProjectID: [String: [Int]]
    let selectedProjectID: String?
    let isLoading: Bool
    let hasSearchQuery: Bool
    let catalogFailure: CodexLaneFailure?
    let onSelect: (CodexProjectSummary) -> Void
    let onRefresh: () -> Void

    var body: some View {
        if assignedProjects.isEmpty && recentProjects.isEmpty {
            CodexProjectEmptyState(
                isLoading: isLoading,
                hasSearchQuery: hasSearchQuery,
                catalogFailure: catalogFailure,
                onRefresh: onRefresh
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                CodexLaneProjectStrip(
                    projects: assignedProjects,
                    laneNumbersByProjectID: laneNumbersByProjectID,
                    selectedProjectID: selectedProjectID,
                    onSelect: onSelect
                )

                CodexProjectSection(
                    title: "Recent projects",
                    projects: recentProjects,
                    laneNumbersByProjectID: laneNumbersByProjectID,
                    selectedProjectID: selectedProjectID,
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct CodexLaneProjectStrip: View {
    let projects: [CodexProjectSummary]
    let laneNumbersByProjectID: [String: [Int]]
    let selectedProjectID: String?
    let onSelect: (CodexProjectSummary) -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("IN YOUR LANES")
                    .font(.caption2.weight(.medium).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.textTertiary)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        TalkieDivider()

                        ForEach(projects) { project in
                            CodexProjectSelectionRow(
                                project: project,
                                laneNumbers: laneNumbersByProjectID[project.id, default: []],
                                isSelected: selectedProjectID == project.id,
                                onSelect: { onSelect(project) }
                            )

                            if project.id != projects.last?.id {
                                TalkieDivider()
                                    .padding(.leading, 40)
                            }
                        }

                        TalkieDivider()
                    }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 18) {
                            ForEach(projects) { project in
                                CodexLaneProjectButton(
                                    project: project,
                                    laneNumbers: laneNumbersByProjectID[project.id, default: []],
                                    isSelected: selectedProjectID == project.id,
                                    onSelect: { onSelect(project) }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    TalkieDivider()
                }
            }
        }
    }
}

private struct CodexLaneProjectButton: View {
    let project: CodexProjectSummary
    let laneNumbers: [Int]
    let isSelected: Bool
    let onSelect: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption.weight(.semibold))

                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .foregroundStyle(isSelected ? theme.chrome.accent : theme.colors.textPrimary)

                CodexProjectLaneLabels(laneNumbers: laneNumbers, isSelected: isSelected)
            }
            .padding(.horizontal, 2)
            .frame(minWidth: 104, minHeight: 46, alignment: .leading)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(theme.chrome.trace)
                        .frame(height: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Creates a new task in this project without changing lane assignments.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let lanes = laneNumbers.map(String.init).joined(separator: ", ")
        let laneDescription = lanes.isEmpty ? "" : ", in lanes \(lanes)"
        return "\(project.name), \(project.compactPath)\(laneDescription)"
    }
}

private struct CodexProjectSection: View {
    let title: String
    let projects: [CodexProjectSummary]
    let laneNumbersByProjectID: [String: [Int]]
    let selectedProjectID: String?
    let onSelect: (CodexProjectSummary) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.medium).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.textTertiary)

                VStack(spacing: 0) {
                    TalkieDivider()

                    ForEach(projects) { project in
                        CodexProjectSelectionRow(
                            project: project,
                            laneNumbers: laneNumbersByProjectID[project.id, default: []],
                            isSelected: selectedProjectID == project.id,
                            onSelect: { onSelect(project) }
                        )

                        if project.id != projects.last?.id {
                            TalkieDivider()
                                .padding(.leading, 40)
                        }
                    }

                    TalkieDivider()
                }
            }
        }
    }
}

private struct CodexProjectSelectionRow: View {
    let project: CodexProjectSummary
    let laneNumbers: [Int]
    let isSelected: Bool
    let onSelect: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? theme.chrome.accent : theme.colors.textSecondary)
                    .frame(width: 28, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(project.compactPath)
                        .font(.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                CodexProjectLaneLabels(laneNumbers: laneNumbers, isSelected: isSelected)

                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.chrome.accent)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Color.clear
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(size: 19, weight: .medium))
                .frame(width: 22, height: 44)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 52)
            .background(isSelected ? theme.chrome.accentTint : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(theme.chrome.trace)
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Creates a new task in this project without changing lane assignments.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        guard !laneNumbers.isEmpty else {
            return "\(project.name), \(project.compactPath)"
        }
        let lanes = laneNumbers.map(String.init).joined(separator: ", ")
        return "\(project.name), \(project.compactPath), in lanes \(lanes)"
    }
}

private struct CodexProjectLaneLabels: View {
    let laneNumbers: [Int]
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(laneNumbers.prefix(2), id: \.self) { laneNumber in
                CodexProjectLaneLabel(code: "L\(laneNumber)", isActive: isSelected)
            }

            if laneNumbers.count > 2 {
                CodexProjectLaneLabel(code: "+\(laneNumbers.count - 2)", isActive: isSelected)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CodexProjectLaneLabel: View {
    let code: String
    let isActive: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Text(code.uppercased())
            .font(.caption2.weight(.medium).monospaced())
            .tracking(0.8)
            .foregroundStyle(isActive ? theme.chrome.accent : theme.colors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                isActive ? theme.chrome.accentTint : Color.clear,
                in: .rect(cornerRadius: theme.chrome.chromeCorner)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.chrome.chromeCorner, style: .continuous)
                    .strokeBorder(
                        isActive ? theme.chrome.accent.opacity(0.4) : theme.chrome.edgeFaint,
                        lineWidth: 0.5
                    )
            }
    }
}

private struct CodexProjectEmptyState: View {
    let isLoading: Bool
    let hasSearchQuery: Bool
    let catalogFailure: CodexLaneFailure?
    let onRefresh: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading projects from your Mac…")
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            } else if hasSearchQuery {
                Label("No projects match that search.", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: catalogFailure == nil ? "folder.badge.questionmark" : "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(theme.chrome.accent)

                    Text(catalogFailure == nil ? "No Codex projects yet" : "Projects are unavailable")
                        .font(.headline)
                        .foregroundStyle(theme.colors.textPrimary)

                    Text(catalogFailure?.combined ?? "Open a project in Codex on your Mac, then refresh this view.")
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                        .buttonStyle(.bordered)
                        .tint(theme.chrome.action)
                        .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }
}

private struct CodexTaskCreateDock: View {
    let project: CodexProjectSummary
    let stage: CodexTaskCreationStage
    let failure: CodexLaneFailure?
    let onCreate: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textTertiary)

                Text("DEFAULT MODEL · MAC CODEX SETTINGS")
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if let failure {
                Label(failure.combined, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onCreate) {
                HStack(spacing: 9) {
                    if stage == .task {
                        ProgressView()
                            .tint(theme.colors.background)
                    } else {
                        Image(systemName: stage == .talk ? "checkmark" : "rectangle.badge.plus")
                    }

                    Text(buttonTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.accent)
            .disabled(stage != .project)
            .accessibilityLabel(buttonAccessibilityLabel)
            .accessibilityHint("Selects new task mode. Codex creates the task with your first message.")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(theme.colors.background)
        .overlay(alignment: .top) { TalkieDivider() }
    }

    private var buttonTitle: String {
        switch stage {
        case .project: "Create Task in \(project.name)"
        case .task: "Preparing \(project.name)…"
        case .talk: "Ready to talk"
        }
    }

    private var buttonAccessibilityLabel: String {
        switch stage {
        case .project: "Create task in \(project.name)"
        case .task: "Preparing new task mode in \(project.name)"
        case .talk: "New task mode ready to talk"
        }
    }
}
