//
//  TOWorkflowRunsSection.swift
//  Talkie
//
//  Recent workflow runs section.
//  Self-gates: renders nothing if no runs.
//

import SwiftUI
import TalkieKit

struct TOWorkflowRunsSection: View {
    let slot: SectionSlot
    let settings: SettingsManager
    let cachedWorkflowRuns: [WorkflowRunModel]

    var body: some View {
        if !cachedWorkflowRuns.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("RECENT RUNS")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if cachedWorkflowRuns.count > 3 {
                        Text("\(cachedWorkflowRuns.count) runs")
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.current.foreground.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                VStack(spacing: Spacing.xs) {
                    ForEach(Array(cachedWorkflowRuns.prefix(3)), id: \.id) { run in
                        WorkflowRunRow(run: run)
                    }
                }
            }
        }
    }
}
