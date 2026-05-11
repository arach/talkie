//
//  ActionsSettingsView.swift
//  Talkie macOS
//
//  Context-aware actions that appear in interstitial and drafts
//  Now delegates to ActionsSettingsContent in ContextSettingsView.swift
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Actions Settings View (Legacy wrapper)

struct ActionsSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "sparkles",
                title: "ACTIONS",
                subtitle: "Quick transformations for your transcriptions."
            )
        } content: {
            ActionsSettingsContent()
        }
    }
}

// MARK: - Context Toggle Style

struct ContextToggleStyle: ToggleStyle {
    let label: String
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(configuration.isOn ? color : Theme.current.foregroundSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(configuration.isOn ? color.opacity(0.2) : Theme.current.surface2)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
