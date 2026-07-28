//
//  CodexLaneMapperView.swift
//  Talkie iOS
//
//  Maps live Codex Desktop tasks onto numbered deck lanes.
//
//  The mapper is deliberately an *editing* surface: picking a task here binds
//  it to a lane and nothing else. It never changes which lane is live, because
//  going live requires the Mac to confirm ownership, and that belongs to the
//  deck's activation path rather than to a picker.
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
            .navigationTitle("Codex Lanes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $store.searchQuery, prompt: "Search tasks, projects, IDs")
        }
        .task {
            targetLane = store.unassignedLaneNumbers.first ?? CodexLane.range.lowerBound
            store.beginCatalogUpdates()
        }
        .onDisappear { store.endCatalogUpdates() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: - Lane strip

    private var laneStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign to lane")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(CodexLane.range), id: \.self) { number in
                        laneChip(number)
                    }
                }
            }

            if let lane = store.lane(targetLane) {
                HStack(spacing: 6) {
                    Text(lane.task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button("Clear") { store.clearLane(targetLane) }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.accent)
                }
            } else {
                Text("Lane \(targetLane) is empty — pick a task below.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
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
        let isAssigned = store.lane(number) != nil

        return Button {
            targetLane = number
        } label: {
            Text("\(number)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isTarget
                              ? theme.colors.accent.opacity(0.18)
                              : theme.colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            isTarget ? theme.colors.accent : theme.colors.tableBorder,
                            lineWidth: isTarget ? 1.5 : 1
                        )
                )
                .foregroundStyle(
                    isAssigned ? theme.colors.textPrimary : theme.colors.textTertiary
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task list

    @ViewBuilder
    private var taskList: some View {
        let tasks = store.filteredCatalog

        if tasks.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                if store.isLoadingCatalog {
                    ProgressView()
                } else {
                    Text(emptyMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(tasks) { task in
                    taskRow(task)
                        .listRowBackground(theme.colors.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        return "No recent Codex Desktop tasks yet."
    }

    private func taskRow(_ task: CodexTaskSummary) -> some View {
        let boundLane = store.sortedLanes.first { $0.task.id == task.id }?.number

        return Button {
            store.assign(task, to: targetLane)
            // Advance to the next empty lane so mapping several tasks in a row
            // doesn't quietly overwrite the one just assigned.
            if let next = store.unassignedLaneNumbers.first {
                targetLane = next
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if let boundLane {
                        Text("Lane \(boundLane)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(theme.colors.accent.opacity(0.16))
                            )
                            .foregroundStyle(theme.colors.accent)
                    }

                    Text(task.activityLabel(relativeTo: now))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                }

                Text(task.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)

                if !task.preview.isEmpty {
                    Text(task.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
