//
//  NotchSettingsSection.swift
//  TalkieAgent
//
//  Settings for the agent-owned capture island — the draggable preview that
//  drops in at the top of the screen after a screenshot/clip. Heavy actions
//  (markup, full tray) deliberately defer to launching Talkie; the island
//  stays minimal: preview + drag-out.
//

import SwiftUI
import TalkieKit

struct NotchSettingsSection: View {
    @AppStorage(CaptureIslandDefaults.enabled) private var enabled = true
    @AppStorage(CaptureIslandDefaults.dismissSeconds) private var dismissSeconds = 6.0

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.topthird.inset.filled",
                title: "ISLAND",
                subtitle: "A draggable preview drops in at the top when you capture. Drag it straight into any app."
            )
        } content: {
            SettingsCard(title: "CAPTURE ISLAND") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsToggleRow(
                        icon: "rectangle.topthird.inset.filled",
                        title: "Show capture island",
                        description: "Surface a draggable preview at the top after each screenshot or clip",
                        isOn: $enabled
                    )

                    Rectangle().fill(Design.divider).frame(height: 0.5)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-dismiss")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Hover the preview to keep it open")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Picker("", selection: $dismissSeconds) {
                            Text("4s").tag(4.0)
                            Text("6s").tag(6.0)
                            Text("10s").tag(10.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .disabled(!enabled)
                    }
                    .opacity(enabled ? 1 : 0.45)
                }
            }

            SettingsCard {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Markup & tray live in Talkie")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TalkieTheme.textSecondary)
                        Text("The island stays intentionally minimal — preview and drag-out. To annotate a capture or browse the full tray, open Talkie. This replaces the old Talkie notch island, which is now retired.")
                            .font(.system(size: 9))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
