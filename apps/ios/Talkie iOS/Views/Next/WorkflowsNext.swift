//
//  WorkflowsNext.swift
//  Talkie iOS
//
//  Workflow templates · scheduled runs · history, backed by WorkflowsStore.
//
//  Distinct from CaptureAICommandsSheet (per-capture AI run): this
//  surface is the standalone workflows hub — templates the user can
//  attach to any capture / memo, schedule on a recurring cadence, or
//  inspect after the fact.
//

import SwiftUI

struct WorkflowsNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var store = WorkflowsStore.shared
    @State private var runningTemplateID: String?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        templatesSection
                        schedulesSection
                        historySection
                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · WORKFLOWS")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { AppShellRouter.shared.openSettings() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close workflows")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Templates

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("· TEMPLATES", count: store.templates.count)

            VStack(spacing: 0) {
                ForEach(store.templates) { template in
                    templateRow(template)
                }
            }
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
    }

    private func templateRow(_ template: WorkflowTemplate) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.currentTheme.chrome.accent.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: template.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(template.blurb)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer(minLength: 8)

            Button(action: { run(template) }) {
                Text(runningTemplateID == template.id ? "RUNNING" : "RUN")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.55),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
            .disabled(runningTemplateID != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if template.id != store.templates.last?.id {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
                    .padding(.leading, 54)
            }
        }
    }

    // MARK: - Schedules

    private var schedulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("· SCHEDULED", count: store.schedules.count)

            if store.schedules.isEmpty {
                emptyTile(
                    icon: "calendar",
                    title: "No scheduled runs",
                    body: "Add a recurring schedule to run a template on a cadence (daily, weekly, on capture)."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(store.schedules) { schedule in
                        scheduleRow(schedule)
                    }
                }
                .background(theme.colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func scheduleRow(_ schedule: WorkflowSchedule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.templateName)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(schedule.cadence)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer()
            Text(schedule.nextRunLabel)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.currentTheme.chrome.accent)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("· HISTORY", count: store.runs.count)

            if store.runs.isEmpty {
                emptyTile(
                    icon: "clock.arrow.circlepath",
                    title: "No runs yet",
                    body: "Workflow runs you fire show up here with status + timestamp."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(store.runs) { run in
                        historyRow(run)
                    }
                }
                .background(theme.colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            }
        }
    }

    private func historyRow(_ run: WorkflowHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            outcomeMarker(run.outcome)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(run.templateName)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                    if let target = run.target {
                        Text("· \(target)")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if case .failure(let reason) = run.outcome {
                    Text(reason)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
                }
            }

            Spacer(minLength: 8)

            Text(run.timestampLabel)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if run.id != store.runs.last?.id {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
                    .padding(.leading, 26)
            }
        }
    }

    private func outcomeMarker(_ outcome: WorkflowHistoryEntry.Outcome) -> some View {
        let color: Color = {
            switch outcome {
            case .success: return Color(red: 0.36, green: 0.74, blue: 0.50)
            case .failure: return Color(red: 0.85, green: 0.46, blue: 0.34)
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .strokeBorder(color.opacity(0.4),
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    .frame(width: 10, height: 10)
            )
    }

    // MARK: - Primitives

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
            Text("\(count)")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func emptyTile(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.4))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(body)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            style: StrokeStyle(
                                lineWidth: theme.currentTheme.chrome.hairlineWidth,
                                dash: [5, 3]
                            )
                        )
                )
        )
    }

    // MARK: - Run handler

    private func run(_ template: WorkflowTemplate) {
        guard runningTemplateID == nil else { return }
        runningTemplateID = template.id
        Task { @MainActor in
            await store.run(template: template, on: nil)
            runningTemplateID = nil
        }
    }
}
