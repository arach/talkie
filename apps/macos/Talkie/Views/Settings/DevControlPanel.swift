//
//  DevControlPanel.swift
//  Talkie
//
//  Feature flags control panel.
//  Only available in DEBUG builds.
//

import SwiftUI
import TalkieKit

struct DevControlPanelView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "flag.fill",
                title: "FEATURE FLAGS",
                subtitle: "Toggle features on and off during development"
            )
        } content: {
            featureFlagsSection
        }
    }

    // MARK: - Feature Flags

    private var featureFlagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Spacer()

                if FeatureFlags.shared.allFlagKeys.contains(where: { FeatureFlags.shared.isLocalOverride($0) }) {
                    Button(action: {
                        for key in FeatureFlags.shared.allFlagKeys where FeatureFlags.shared.isLocalOverride(key) {
                            FeatureFlags.shared.clearLocalOverride(key)
                        }
                    }) {
                        Text("Reset All")
                            .font(.techLabelSmall)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: Spacing.xs) {
                ForEach(FeatureFlags.shared.allFlagKeys, id: \.self) { key in
                    featureFlagRow(key: key)

                    let children = FeatureFlags.shared.children(of: key)
                    if !children.isEmpty && (FeatureFlags.shared.allFlags[key] ?? false) {
                        ForEach(children, id: \.self) { child in
                            featureFlagRow(key: child)
                                .padding(.leading, Spacing.lg)
                        }
                    }
                }
            }
        }
    }

    private func featureFlagRow(key: String) -> some View {
        let flags = FeatureFlags.shared
        let currentValue = flags.allFlags[key] ?? false
        let source = flags.flagSource(key)
        let isOverridden = source != "default"

        return HStack(spacing: Spacing.sm) {
            // Flag name + inline default
            HStack(spacing: Spacing.xs) {
                Text(key)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Theme.current.foreground)

                Text(flags.defaultValue(key) ? "on" : "off")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            // Source badge (only when overridden)
            if isOverridden {
                HStack(spacing: Spacing.xxs) {
                    Text(source.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(source == "local" ? .orange : .blue)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(
                            (source == "local" ? Color.orange : Color.blue)
                                .opacity(Opacity.light)
                        )
                        .cornerRadius(CornerRadius.xs)

                    if source == "local" {
                        Button(action: {
                            flags.clearLocalOverride(key)
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to default")
                    }
                }
            }

            // Toggle (right side, compact)
            Toggle(isOn: Binding(
                get: { currentValue },
                set: { newValue in
                    flags.setLocalOverride(key, value: newValue)
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.secondary.opacity(Opacity.subtle))
        .cornerRadius(CornerRadius.xs)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    DevControlPanelView()
        .frame(width: 600, height: 400)
}
#endif
