//
//  ManagedAgentLabSection.swift
//  Talkie
//
//  Starter agent harness runner for Talkie's processing settings.
//

import SwiftUI

struct ManagedAgentLabSection: View {
    @State private var model = ManagedAgentConsoleModel()

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.green)
                    .frame(width: 3, height: 14)

                Text("AGENT LAB")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text(model.statusLabel.uppercased())
                    .font(.techLabelSmall)
                    .foregroundColor(statusColor.opacity(Opacity.prominent))
            }

            Text("Boot a managed harness inside a prepared Talkie workspace. This is phase one of the in-app agent loop: workspace bootstrap and streamed output first, PTY relay next.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    controls(model)
                    editors(model)
                }
                .frame(maxWidth: 420, alignment: .topLeading)

                outputPanel(model)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var statusColor: Color {
        switch model.status {
        case .idle, .preparing:
            .orange
        case .running:
            .green
        case .finished(let code):
            code == 0 ? .green : .orange
        case .failed:
            .orange
        }
    }

    private func controls(_ model: ManagedAgentConsoleModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HARNESS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: Binding(
                        get: { model.selectedProfile },
                        set: { model.selectedProfile = $0 }
                    )) {
                        ForEach(AgentHarnessProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Spacer()

                Button("Reveal", systemImage: "folder") {
                    model.revealWorkspace()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.workspace == nil)

                if model.isRunning {
                    Button("Stop", systemImage: "stop.fill") {
                        model.stop()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Run", systemImage: "play.fill") {
                    model.run()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canRun)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(model.selectedProfile.summary)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foreground)

                if let availabilityNote = model.selectedProfile.availabilityNote {
                    Text(availabilityNote)
                        .font(Theme.current.fontXS)
                        .foregroundColor(.orange)
                }

                Text(model.statusDetail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)

            if let workspace = model.workspace {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("WORKSPACE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(workspace.rootURL.path())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                        .textSelection(.enabled)

                    if let startedAt = model.lastStartedAt {
                        Text("Last run: \(startedAt.formatted(date: .omitted, time: .standard))")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.sm)
            }
        }
    }

    private func editors(_ model: ManagedAgentConsoleModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            editorCard(
                title: "PROMPT",
                caption: "This is sent to the selected harness.",
                text: Binding(
                    get: { model.prompt },
                    set: { model.prompt = $0 }
                ),
                minHeight: 110
            )

            editorCard(
                title: "CONTEXT NOTES",
                caption: "Written to `CONTEXT.md` in the generated workspace before each run.",
                text: Binding(
                    get: { model.notes },
                    set: { model.notes = $0 }
                ),
                minHeight: 140
            )
        }
    }

    private func outputPanel(_ model: ManagedAgentConsoleModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("OUTPUT")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if let finishedAt = model.lastFinishedAt {
                    Text(finishedAt, format: .dateTime.hour().minute().second())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            ScrollView {
                Text(model.output.isEmpty ? "Run the harness to generate a Talkie agent workspace and stream its output here." : model.output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(model.output.isEmpty ? Theme.current.foregroundSecondary : Theme.current.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
            }
            .frame(minHeight: 360)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Theme.current.divider, lineWidth: 1)
            )
        }
    }

    private func editorCard(
        title: String,
        caption: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(caption)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            TextEditor(text: text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: minHeight)
                .padding(Spacing.xs)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.sm)
        }
    }
}
