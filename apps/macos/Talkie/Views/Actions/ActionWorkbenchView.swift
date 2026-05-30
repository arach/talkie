//
//  ActionWorkbenchView.swift
//  Talkie macOS
//
//  Console-first surface for action runs.
//

import SwiftUI
import TalkieKit

private let actionWorkbenchLog = Log(.ui)

struct ActionWorkbenchView: View {
    private let repository = LocalRepository()

    @State private var runs: [ActionRunModel] = []
    @State private var selectedRunId: UUID?
    @State private var selectedEvents: [ActionEventModel] = []
    @State private var selectedSubjects: [ActionSubjectRef] = []
    @State private var selectedInputPackage: ActionInputPackage?
    @State private var isLoading = true

    private var selectedRun: ActionRunModel? {
        guard let selectedRunId else { return nil }
        return runs.first { $0.id == selectedRunId }
    }

    private var requestedRunId: UUID? {
        guard let raw = NavigationState.shared.params["actionRunId"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    /// Scope paints all structural surfaces with the single light canvas
    /// token so the left side matches every other Scope screen (the
    /// Theme.current surface ladder read as a slightly heavier, different
    /// tone). Other themes keep their own surface ladder.
    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    var body: some View {
        VStack(spacing: 0) {
            // Scope renders the shared top band (title · count · refresh);
            // Pro/Light keep the legacy PageHeaderBar until the band is
            // brought onto those themes. Same `refreshButton` either way.
            if SettingsManager.shared.isScopeTheme {
                ScopeTopBand(
                    title: "Actions",
                    chrome: runs.isEmpty ? nil : "\(runs.count) RUNS",
                    trailing: { refreshButton }
                )
            } else {
                PageHeaderBar {
                    TalkieText("Actions", style: .pageTitle)
                    Spacer()
                    refreshButton
                }
            }

            Divider()

            if isLoading {
                VStack {
                    Spacer()
                    BrailleSpinner()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runs.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.current.foregroundMuted)
                    Text("NO ACTIONS YET")
                        .font(Theme.current.fontXSBold)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                workbenchLayout
            }
        }
        .background(isScope ? ScopeCanvas.canvas : Theme.current.surfaceBase)
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await load(showLoading: false)
            }
        }
        .onChange(of: NavigationState.shared.params) { _, _ in
            Task { await applyNavigationSelection() }
        }
    }

    private var refreshButton: some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await load(showLoading: false) }
        }
        .buttonStyle(.plain)
        .font(Theme.current.fontXS)
    }

    private var workbenchLayout: some View {
        HStack(spacing: 0) {
            runRail
                .frame(width: 304)

            Divider()

            selectedRunPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isScope ? ScopeCanvas.canvas : Theme.current.surfaceInput)
    }

    private var runRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("RUNS")
                    .font(Theme.current.fontXSBold)
                    .foregroundStyle(Theme.current.foregroundMuted)

                Text("\(runs.count)")
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(runs) { run in
                        Button {
                            selectedRunId = run.id
                            Task { await loadSelectedRunDetails() }
                        } label: {
                            ActionRunRow(run: run, isSelected: run.id == selectedRunId)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.xs)
            }
        }
        .background(Theme.current.surfaceBase)
    }

    @ViewBuilder
    private var selectedRunPane: some View {
        if let selectedRun {
            ScrollView {
                ActionRunConsole(
                    run: selectedRun,
                    events: selectedEvents,
                    subjects: selectedSubjects,
                    inputPackage: selectedInputPackage
                )
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: Spacing.sm) {
                Spacer()
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.current.foregroundMuted)
                Text("SELECT A RUN")
                    .font(Theme.current.fontXSBold)
                    .foregroundStyle(Theme.current.foregroundSecondary)
                Spacer()
            }
        }
    }

    private func load(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }

        do {
            let loadedRuns = try await repository.allActionRuns(limit: 100)
            let targetId = requestedRunId ?? selectedRunId ?? loadedRuns.first?.id

            await MainActor.run {
                runs = loadedRuns
                if let targetId, loadedRuns.contains(where: { $0.id == targetId }) {
                    selectedRunId = targetId
                } else {
                    selectedRunId = loadedRuns.first?.id
                }
                isLoading = false
            }

            await loadSelectedRunDetails()
        } catch {
            actionWorkbenchLog.error("Failed to load action runs: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func applyNavigationSelection() async {
        guard let requestedRunId else { return }
        selectedRunId = requestedRunId
        await load(showLoading: false)
    }

    private func loadSelectedRunDetails() async {
        guard let selectedRunId else {
            await MainActor.run {
                selectedEvents = []
                selectedSubjects = []
                selectedInputPackage = nil
            }
            return
        }

        do {
            async let events = repository.fetchActionEvents(for: selectedRunId)
            async let subjects = repository.fetchActionSubjectRefs(for: selectedRunId)
            async let inputPackage = repository.fetchActionInputPackage(for: selectedRunId)

            let loadedEvents = try await events
            let loadedSubjects = try await subjects
            let loadedInputPackage = try await inputPackage

            await MainActor.run {
                selectedEvents = loadedEvents
                selectedSubjects = loadedSubjects
                selectedInputPackage = loadedInputPackage
            }
        } catch {
            actionWorkbenchLog.error("Failed to load action run detail: \(error.localizedDescription)")
        }
    }
}

private struct ActionRunRow: View {
    let run: ActionRunModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if run.isRunning {
                ActionRunPulse(tint: statusColor, size: 7)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(run.title)
                    .font(Theme.current.fontSMBold)
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                Text("\(run.actionKind.rawValue) - \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.current.fontXS)
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()

            Text(statusLabel)
                .font(.monoSmall)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Theme.current.surfaceHover : Color.clear)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 2)
                    .padding(.vertical, 7)
            }
        }
        .contentShape(.rect)
    }

    private var statusColor: Color {
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

    private var statusLabel: String {
        switch run.status {
        case .queued:
            return "WAIT"
        case .running:
            return "RUN"
        case .completed:
            return "OK"
        case .failed:
            return "FAIL"
        case .cancelled:
            return "STOP"
        }
    }
}

private struct ActionRunConsole: View {
    let run: ActionRunModel
    let events: [ActionEventModel]
    let subjects: [ActionSubjectRef]
    let inputPackage: ActionInputPackage?

    @State private var showRawPayloads = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            if !subjects.isEmpty {
                subjectsView
            }

            if let inputPackage {
                Text("render \(inputPackage.renderLogicVersion)")
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
            }

            VStack(alignment: .leading, spacing: 1) {
                ForEach(events) { event in
                    ActionEventLine(
                        event: event,
                        showPayload: showRawPayloads,
                        isActive: event.id == activeEventId
                    )
                }
            }
            .clipShape(.rect(cornerRadius: CornerRadius.xs))

            if let primaryResult = run.primaryResult, !primaryResult.isEmpty {
                outputBlock(title: "RESULT", text: primaryResult, tint: TalkieTheme.accent)
            }

            if let errorMessage = run.errorMessage, !errorMessage.isEmpty {
                outputBlock(title: "ERROR", text: errorMessage, tint: SemanticColor.error)
            }

            HStack {
                Button(showRawPayloads ? "Hide raw logs" : "Show raw logs", systemImage: "doc.text.magnifyingglass") {
                    showRawPayloads.toggle()
                }
                .buttonStyle(.plain)
                .font(Theme.current.fontXS)

                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(Theme.current.divider, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.title)
                    .font(Theme.current.fontTitleBold)
                    .foregroundStyle(Theme.current.foreground)

                Text("\(run.id.uuidString.prefix(8).uppercased()) - \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
            }

            Spacer()

            if let workflowId {
                Button("Edit", systemImage: "slider.horizontal.3") {
                    NavigationState.shared.navigate(
                        to: .workflows,
                        params: ["workflowId": workflowId.uuidString]
                    )
                }
                .buttonStyle(.plain)
                .font(Theme.current.fontXS)
            }

            ActionRunStatusBadge(status: run.status, tint: statusColor)
        }
    }

    private var workflowId: UUID? {
        guard run.actionKind == .workflow else { return nil }
        return UUID(uuidString: run.actionId)
    }

    private var activeEventId: UUID? {
        guard run.isRunning else { return nil }

        return events.last(where: { event in
            switch event.kind {
            case .stepStarted, .stepLog, .inputResolved, .artifactCreated:
                return event.level != .error
            case .runQueued, .runStarted, .runCompleted, .runFailed, .runCancelled, .stepCompleted, .stepFailed:
                return false
            }
        })?.id ?? events.last?.id
    }

    private var subjectsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INPUT")
                .font(Theme.current.fontXSBold)
                .foregroundStyle(Theme.current.foregroundMuted)

            ForEach(subjects) { subject in
                HStack(spacing: Spacing.xs) {
                    Image(systemName: subject.kind == .screenshot ? "camera.viewfinder" : "square.stack")
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                    Text(subject.titleSnapshot ?? subject.assetURLString ?? subject.recordId?.uuidString ?? subject.kind.rawValue)
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
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

    private var statusColor: Color {
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
}

private struct ActionEventLine: View {
    let event: ActionEventModel
    let showPayload: Bool
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Text(formatSequence(event.sequence))
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .frame(width: 34, alignment: .trailing)

                Text(event.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .frame(width: 86, alignment: .leading)

                Text(event.message)
                    .font(Theme.current.fontSM)
                    .foregroundStyle(event.level == .error ? SemanticColor.error : Theme.current.foreground)
                    .textSelection(.enabled)
                    .frame(minWidth: 0, alignment: .leading)

                if isActive {
                    ActiveStepIndicator(tint: TalkieTheme.accent)
                        .frame(width: 150, height: 18)
                        .padding(.leading, Spacing.sm)
                }

                Spacer()
            }

            if showPayload, event.payloadJSON != "{}" {
                Text(event.payloadJSON)
                    .font(.monoSmall)
                    .foregroundStyle(Theme.current.foregroundSecondary)
                    .textSelection(.enabled)
                    .padding(.leading, 128)
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

    private func formatSequence(_ sequence: Int) -> String {
        "#\(sequence + 1)"
    }
}

private struct ActiveStepIndicator: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 7) {
                ActionRunPulse(tint: tint, size: 7)

                HStack(spacing: 3) {
                    ForEach(0..<14, id: \.self) { index in
                        let phase = (elapsed * 1.35 + Double(index) / 14.0)
                            .truncatingRemainder(dividingBy: 1)
                        let emphasis = phase < 0.28 ? 1 - (phase / 0.28) : 0

                        Capsule()
                            .fill(tint.opacity(0.18 + (emphasis * 0.74)))
                            .frame(width: 4 + (emphasis * 5), height: 3)
                    }
                }
                .frame(width: 118, alignment: .leading)
            }
        }
    }
}

private struct ActionRunStatusBadge: View {
    let status: ActionRunModel.Status
    let tint: Color

    private var isActive: Bool {
        status == .queued || status == .running
    }

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.monoSmall)
            .foregroundStyle(tint)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(isActive ? 0.14 : 0.1))
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
    }
}

private struct ActionRunPulse: View {
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
