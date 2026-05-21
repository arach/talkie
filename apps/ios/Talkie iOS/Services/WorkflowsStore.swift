//
//  WorkflowsStore.swift
//  Talkie iOS
//
//  Persistent backing store for workflow templates, schedules, and run history.
//

import Combine
import Foundation

@MainActor
final class WorkflowsStore: ObservableObject {
    static let shared = WorkflowsStore()

    @Published private(set) var templates: [WorkflowTemplate]
    @Published private(set) var schedules: [WorkflowSchedule]
    @Published private(set) var runs: [WorkflowHistoryEntry]

    private let stateURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        templates = Self.builtInTemplates
        schedules = []
        runs = []
        stateURL = URL.documentsDirectory.appending(path: "workflows-state.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadState()
    }

    func run(template: WorkflowTemplate, on target: String?) async {
        try? await Task.sleep(for: .milliseconds(600))

        let newRun = WorkflowHistoryEntry(
            id: UUID().uuidString,
            templateName: template.name,
            target: target,
            timestampLabel: Self.timestampLabel(for: Date()),
            outcome: .success
        )
        runs.insert(newRun, at: 0)
        persistState()
    }

    func schedule(_ template: WorkflowTemplate, cadence: String) -> WorkflowSchedule {
        let normalizedCadence = cadence.trimmingCharacters(in: .whitespacesAndNewlines)
        let schedule = WorkflowSchedule(
            id: UUID().uuidString,
            templateID: template.id,
            templateName: template.name,
            cadence: normalizedCadence.isEmpty ? "On demand" : normalizedCadence,
            nextRunLabel: Self.nextRunLabel(for: normalizedCadence)
        )
        schedules.insert(schedule, at: 0)
        persistState()
        return schedule
    }

    func unschedule(_ scheduleID: String) {
        schedules.removeAll { $0.id == scheduleID }
        persistState()
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        do {
            let state = try decoder.decode(WorkflowStoreState.self, from: data)
            schedules = state.schedules
            runs = state.runs
        } catch {
            AppLogger.persistence.warning("Workflow state decode failed", detail: error.localizedDescription)
        }
    }

    private func persistState() {
        do {
            let directory = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let state = WorkflowStoreState(schedules: schedules, runs: runs)
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            AppLogger.persistence.warning("Workflow state persist failed", detail: error.localizedDescription)
        }
    }

    private static func timestampLabel(for date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDateInToday(date) {
            return "Today · \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday · \(time)"
        }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " · " + time
    }

    private static func nextRunLabel(for cadence: String) -> String {
        let normalizedCadence = cadence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedCadence.contains("daily") {
            return "Tomorrow"
        }
        if normalizedCadence.contains("weekly") {
            return "Next week"
        }
        if normalizedCadence.contains("capture") {
            return "On capture"
        }
        return "Queued"
    }

    private static let builtInTemplates: [WorkflowTemplate] = [
        WorkflowTemplate(id: "summary", name: "Summarize captures", blurb: "Daily digest of new captures", icon: "doc.text.magnifyingglass"),
        WorkflowTemplate(id: "title", name: "Generate memo titles", blurb: "Re-title untitled voice memos", icon: "text.cursor"),
        WorkflowTemplate(id: "outline", name: "Outline from transcript", blurb: "Bullet outline for selected memos", icon: "list.bullet.indent"),
        WorkflowTemplate(id: "translate", name: "Translate to English", blurb: "Translate non-English captures", icon: "globe")
    ]
}

private struct WorkflowStoreState: Codable {
    let schedules: [WorkflowSchedule]
    let runs: [WorkflowHistoryEntry]
}
