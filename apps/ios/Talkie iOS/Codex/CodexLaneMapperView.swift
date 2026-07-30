//
//  CodexLaneMapperView.swift
//  Talkie iOS
//
//  Browses exact Codex channels and optionally assigns them to numbered lanes.
//

import SwiftUI

struct CodexLaneMapperView: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Lane the user is currently filling. Defaults to the first free lane.
    @State private var targetLane: Int = CodexLane.range.lowerBound
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    laneStrip
                    Divider().overlay(theme.colors.tableDivider)
                    taskList
                }
            }
            .navigationTitle("Codex Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $store.searchQuery, prompt: "Search names, paths, branches, IDs")
        }
        .task {
            targetLane = store.unassignedLaneNumbers.first ?? CodexLane.range.lowerBound
            store.beginCatalogUpdates()
        }
        .onDisappear { store.endCatalogUpdates() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: - Lane assignment

    private var laneStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assign a channel to")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(CodexLane.range), id: \.self) { number in
                        laneChip(number)
                    }
                }
            }

            if let lane = store.lane(targetLane) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lane \(targetLane)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.colors.textTertiary)

                        Text(lane.task.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button("Clear") { store.clearLane(targetLane) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.colors.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
            } else {
                Text("Lane \(targetLane) is open. Choose a channel below.")
                    .font(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(minHeight: 28, alignment: .leading)
            }

            if let failure = store.catalogFailure {
                Text(failure.combined)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func laneChip(_ number: Int) -> some View {
        let isTarget = number == targetLane
        let lane = store.lane(number)

        return Button {
            targetLane = number
        } label: {
            Text("\(number)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isTarget
                              ? theme.colors.accent.opacity(0.18)
                              : theme.colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            isTarget ? theme.colors.accent : theme.colors.tableBorder,
                            lineWidth: isTarget ? 1.5 : 1
                        )
                )
                .foregroundStyle(
                    lane == nil ? theme.colors.textTertiary : theme.colors.textPrimary
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            lane.map { "Lane \(number), \($0.task.title)" } ?? "Lane \(number), empty"
        )
        .accessibilityAddTraits(isTarget ? .isSelected : [])
    }

    // MARK: - Channel list

    @ViewBuilder
    private var taskList: some View {
        let tasks = store.filteredCatalog

        if tasks.isEmpty {
            VStack(spacing: 14) {
                Spacer()

                if store.isLoadingCatalog {
                    ProgressView()
                } else {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                Section {
                    ForEach(tasks) { task in
                        taskRow(task)
                            .listRowBackground(theme.colors.background)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .task { await store.loadNextCatalogPageIfNeeded(after: task) }
                    }

                    if store.isLoadingNextCatalogPage {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(minHeight: 52)
                        .listRowBackground(theme.colors.background)
                    }
                } header: {
                    Text("Channels")
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 72, for: .scrollContent)
            .refreshable { await store.refreshCatalog() }
        }
    }

    private var emptyMessage: String {
        if store.catalogFailure != nil {
            return "Couldn't load Codex tasks from your Mac."
        }
        if !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Codex tasks match that search."
        }
        return "No recent Codex tasks yet."
    }

    private func taskRow(_ task: CodexTaskSummary) -> some View {
        let boundLane = store.sortedLanes.first { $0.task.id == task.id }?.number

        return VStack(spacing: 0) {
            Button {
                store.selectChannel(task)
                dismiss()
            } label: {
                taskDetails(task)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title), \(task.projectName)")
            .accessibilityHint("Selects this channel")
            .accessibilityAddTraits(store.selectedTask?.id == task.id ? .isSelected : [])

            Divider().overlay(theme.colors.tableDivider)

            assignmentButton(task, boundLane: boundLane)
        }
    }

    private func taskDetails(_ task: CodexTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 6)

                if store.selectedTask?.id == task.id {
                    Text("Current")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                }

                Text(task.activityLabel(relativeTo: now))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.colors.textTertiary)
            }

            HStack(spacing: 12) {
                Label(task.projectName, systemImage: "folder")

                if let branch = task.branchName {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.colors.textSecondary)

            HStack(spacing: 8) {
                Text(task.compactPath)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text("Task \(task.shortID)")
                    .monospaced()
            }
            .font(.caption)
            .foregroundStyle(theme.colors.textTertiary)

            if !task.preview.isEmpty && task.preview != task.title {
                Text(task.preview)
                    .font(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assignmentButton(
        _ task: CodexTaskSummary,
        boundLane: Int?
    ) -> some View {
        let isAssignedToTarget = boundLane == targetLane

        return Button {
            if isAssignedToTarget {
                store.clearLane(targetLane)
            } else {
                store.assign(task, to: targetLane)
                if let next = store.unassignedLaneNumbers.first {
                    targetLane = next
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(assignmentTitle(boundLane: boundLane))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(isAssignedToTarget ? "CLEAR" : boundLane == nil ? "ASSIGN" : "MOVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
            }
            .foregroundStyle(isAssignedToTarget ? theme.colors.accent : theme.colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                isAssignedToTarget
                    ? theme.colors.accent.opacity(0.10)
                    : theme.colors.cardBackground.opacity(0.55)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(assignmentAccessibilityLabel(task, boundLane: boundLane))
    }

    private func assignmentTitle(boundLane: Int?) -> String {
        if boundLane == targetLane {
            return "Assigned to Lane \(targetLane)"
        }
        if let boundLane {
            return "Move from Lane \(boundLane) to Lane \(targetLane)"
        }
        if store.lane(targetLane) != nil {
            return "Replace Lane \(targetLane) with this channel"
        }
        return "Assign to Lane \(targetLane)"
    }

    private func assignmentAccessibilityLabel(
        _ task: CodexTaskSummary,
        boundLane: Int?
    ) -> String {
        if boundLane == targetLane {
            return "\(task.title) is assigned to lane \(targetLane). Double tap to clear."
        }
        if let boundLane {
            return "Move \(task.title) from lane \(boundLane) to lane \(targetLane)."
        }
        return "Assign \(task.title) to lane \(targetLane)."
    }
}
