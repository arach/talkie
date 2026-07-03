//
//  DevControlPanel.swift
//  Talkie
//
//  Feature flags control panel.
//  Only available in DEBUG builds.
//

import SwiftUI
import TalkieKit

struct FeatureFlagsSettingsView: View {
    @State private var flags = FeatureFlags.shared
    @State private var isManualFetchInFlight = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "flag.fill",
                title: "FEATURE FLAGS",
                subtitle: "Runtime rollout state and remote fetch status."
            )
        } content: {
            deliverySection
            readOnlyFlagsSection
        }
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            featureFlagsHeader(title: "DELIVERY", subtitle: flags.lastFetchDate == nil ? "NO FETCH YET" : "REMOTE CACHE")

            VStack(spacing: Spacing.sm) {
                featureInfoRow("Environment", value: TalkieEnvironment.current.displayName)
                featureInfoRow("Endpoint", value: RuntimeFeatureFlags.endpoint, monospaced: true)
                featureInfoRow("Cache", value: Self.durationLabel(RuntimeFeatureFlags.cacheDuration))
                featureInfoRow("Last Fetch", value: lastFetchLabel)
                featureInfoRow("Next Automatic Fetch", value: nextFetchLabel)
                featureInfoRow("Remote Flags", value: "\(flags.remoteFlagCount)", monospaced: true)
                featureInfoRow("Local Overrides", value: "\(flags.localOverrideCount)", monospaced: true)

                if let lastError = flags.lastError {
                    featureInfoRow("Last Error", value: lastError.localizedDescription, valueColor: .red)
                }
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    Task { await fetchNow() }
                } label: {
                    Label(isManualFetchInFlight ? "Fetching" : "Fetch Now", systemImage: "arrow.clockwise")
                        .font(Theme.current.fontXSMedium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isManualFetchInFlight || flags.isFetching)

                Button {
                    copySnapshot()
                } label: {
                    Label("Copy Snapshot", systemImage: "doc.on.clipboard")
                        .font(Theme.current.fontXSMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var readOnlyFlagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            featureFlagsHeader(title: "FLAGS", subtitle: "READ ONLY")

            VStack(spacing: Spacing.xs) {
                ForEach(flags.allFlagKeys, id: \.self) { key in
                    readOnlyFlagRow(key: key)

                    let children = flags.children(of: key)
                    if !children.isEmpty && (flags.allFlags[key] ?? false) {
                        ForEach(children, id: \.self) { child in
                            readOnlyFlagRow(key: child)
                                .padding(.leading, Spacing.lg)
                        }
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var lastFetchLabel: String {
        guard let lastFetchDate = flags.lastFetchDate else { return "Never" }
        return lastFetchDate.formatted(date: .abbreviated, time: .standard)
    }

    private var nextFetchLabel: String {
        guard let lastFetchDate = flags.lastFetchDate else { return "On next launch" }
        let nextFetch = lastFetchDate.addingTimeInterval(RuntimeFeatureFlags.cacheDuration)
        if nextFetch <= Date() { return "Now" }
        return nextFetch.formatted(date: .abbreviated, time: .standard)
    }

    private func fetchNow() async {
        guard !isManualFetchInFlight else { return }
        isManualFetchInFlight = true
        defer { isManualFetchInFlight = false }
        await flags.refresh(force: true)
    }

    private func readOnlyFlagRow(key: String) -> some View {
        let currentValue = flags.allFlags[key] ?? false
        let source = flags.flagSource(key)
        let definition = RuntimeFeatureFlags.definition(for: key)

        return HStack(spacing: Spacing.sm) {
            Circle()
                .fill(currentValue ? Color.green : Theme.current.foregroundMuted)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(definition?.title ?? key)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                if let detail = definition?.detail {
                    Text(detail)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            Spacer()

            Text(source.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color(for: source))
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(color(for: source).opacity(0.16))
                .cornerRadius(CornerRadius.xs)

            Text(currentValue ? "ON" : "OFF")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(currentValue ? .green : Theme.current.foregroundMuted)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.secondary.opacity(Opacity.subtle))
        .cornerRadius(CornerRadius.xs)
    }

    private func featureFlagsHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.blue)
                .frame(width: 3, height: 14)

            Text(title)
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            Text(subtitle)
                .font(.techLabelSmall)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    private func featureInfoRow(
        _ label: String,
        value: String,
        valueColor: Color? = nil,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundColor(valueColor ?? Theme.current.foreground)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func copySnapshot() {
        let snapshot = TalkieFeatureFlagSnapshot(
            environment: TalkieEnvironment.current.displayName,
            endpoint: RuntimeFeatureFlags.endpoint,
            cacheDurationSeconds: Int(RuntimeFeatureFlags.cacheDuration),
            lastFetch: flags.lastFetchDate,
            lastError: flags.lastError?.localizedDescription,
            flags: flags.allFlags,
            sources: Dictionary(uniqueKeysWithValues: flags.allFlags.keys.map { ($0, flags.flagSource($0)) })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private func color(for source: String) -> Color {
        switch source {
        case "local": return .orange
        case "remote": return .blue
        default: return Theme.current.foregroundMuted
        }
    }

    private static func durationLabel(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86_400)
        if days >= 1 {
            return days == 1 ? "1 day" : "\(days) days"
        }
        let hours = Int(interval / 3_600)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

private struct TalkieFeatureFlagSnapshot: Encodable {
    let environment: String
    let endpoint: String
    let cacheDurationSeconds: Int
    let lastFetch: Date?
    let lastError: String?
    let flags: [String: Bool]
    let sources: [String: String]
}

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
