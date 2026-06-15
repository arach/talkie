//
//  WorkflowTemplatePicker.swift
//  Talkie macOS
//

import SwiftUI
import TalkieKit

// MARK: - Workflow Template Picker

struct WorkflowTemplatePicker: View {
    let templates: [WorkflowDefinition]
    let onSelectBlank: () -> Void
    let onSelectTemplate: (WorkflowDefinition) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Workflow")
                    .font(Theme.current.fontTitleBold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Blank option
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("START FRESH")
                            .font(Theme.current.fontXSBold)
                            .foregroundStyle(Theme.current.foregroundSecondary)

                        Button(action: onSelectBlank) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.1))
                                    Image(systemName: "plus")
                                        .font(Theme.current.fontTitle)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Blank Workflow")
                                        .font(Theme.current.fontBodyMedium)
                                        .foregroundStyle(Theme.current.foreground)
                                    Text("Start from scratch")
                                        .font(Theme.current.fontXS)
                                        .foregroundStyle(Theme.current.foregroundSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(Theme.current.fontSM)
                                    .foregroundStyle(Theme.current.foregroundMuted)
                            }
                            .padding(Spacing.md)
                            .background(Theme.current.surface1)
                            .clipShape(.rect(cornerRadius: CornerRadius.sm))
                        }
                        .buttonStyle(.plain)
                    }

                    // Templates section
                    if !templates.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("TEMPLATES")
                                .font(Theme.current.fontXSBold)
                                .foregroundStyle(Theme.current.foregroundSecondary)

                            ForEach(templates) { template in
                                Button(action: { onSelectTemplate(template) }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(template.color.color.opacity(0.15))
                                            Image(systemName: template.icon)
                                                .font(Theme.current.fontBody)
                                                .foregroundStyle(template.color.color)
                                        }
                                        .frame(width: 44, height: 44)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name)
                                                .font(Theme.current.fontBodyMedium)
                                                .foregroundStyle(Theme.current.foreground)
                                            Text(template.description)
                                                .font(Theme.current.fontXS)
                                                .foregroundStyle(Theme.current.foregroundSecondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text("\(template.steps.count) step\(template.steps.count == 1 ? "" : "s")")
                                            .font(Theme.current.fontXS)
                                            .foregroundStyle(Theme.current.foregroundMuted)

                                        Image(systemName: "chevron.right")
                                            .font(Theme.current.fontSM)
                                            .foregroundStyle(Theme.current.foregroundMuted)
                                    }
                                    .padding(Spacing.md)
                                    .background(Theme.current.surface1)
                                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 500, height: 450)
        .background(Theme.current.surfaceInput)
    }
}
