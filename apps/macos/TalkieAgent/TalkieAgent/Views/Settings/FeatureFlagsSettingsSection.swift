//
//  FeatureFlagsSettingsSection.swift
//  TalkieAgent
//
//  Read-only runtime feature flag diagnostics.
//

import SwiftUI
import AppKit
import TalkieKit

struct FeatureFlagsSettingsSection: View {
    @StateObject private var model = AgentFeatureFlagsModel()

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "flag.fill",
                title: "FEATURE FLAGS",
                subtitle: "Runtime rollout state and remote fetch status."
            )
        } content: {
            SettingsCard(title: "DELIVERY") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    AboutInfoRow(label: "Environment", value: TalkieEnvironment.current.displayName)
                    AboutInfoRow(label: "Endpoint", value: RuntimeFeatureFlags.endpoint, isMonospaced: true, canCopy: true)
                    AboutInfoRow(label: "Cache", value: model.cacheDurationLabel)
                    AboutInfoRow(label: "Last Fetch", value: model.lastFetchLabel)
                    AboutInfoRow(label: "Next Automatic Fetch", value: model.nextFetchLabel)
                    AboutInfoRow(label: "Remote Flags", value: model.remoteCountLabel, isMonospaced: true)

                    if let lastError = model.lastErrorMessage {
                        AboutInfoRow(label: "Last Error", value: lastError, valueColor: SemanticColor.error)
                    }

                    Divider()
                        .background(TalkieTheme.border.opacity(0.5))

                    HStack(spacing: Spacing.sm) {
                        Button(action: {
                            Task { await model.fetchNow() }
                        }) {
                            HStack(spacing: 6) {
                                if model.isFetching {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.55)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                }

                                Text(model.isFetching ? "Fetching" : "Fetch Now")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(.rect(cornerRadius: CornerRadius.xs))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isFetching)

                        Button(action: model.copySnapshot) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Copy Snapshot")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(TalkieTheme.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(TalkieTheme.textMuted.opacity(0.12))
                            .clipShape(.rect(cornerRadius: CornerRadius.xs))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
            }

            SettingsCard(title: "FLAGS") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visibleDefinitions) { definition in
                        FeatureFlagReadOnlyRow(
                            definition: definition,
                            value: model.value(for: definition),
                            source: model.source(for: definition)
                        )

                        if definition.id != model.visibleDefinitions.last?.id {
                            Divider()
                                .background(TalkieTheme.border.opacity(0.35))
                        }
                    }
                }
            }
        }
        .onAppear {
            model.loadSnapshot()
        }
    }
}

private struct FeatureFlagReadOnlyRow: View {
    let definition: RuntimeFeatureFlagDefinition
    let value: Bool
    let source: AgentFeatureFlagSource

    private var valueColor: Color {
        value ? SemanticColor.success : TalkieTheme.textTertiary
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Circle()
                .fill(valueColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(definition.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TalkieTheme.textPrimary)

                    Text(definition.key)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)
                }

                Text(definition.detail)
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.md)

            HStack(spacing: 6) {
                Text(source.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(source.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(source.color.opacity(0.16))
                    .clipShape(.rect(cornerRadius: 4))

                Text(value ? "ON" : "OFF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(valueColor)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

enum AgentFeatureFlagSource {
    case production
    case remote
    case shared
    case `default`

    var label: String {
        switch self {
        case .production: return "PROD"
        case .remote: return "REMOTE"
        case .shared: return "SHARED"
        case .default: return "DEFAULT"
        }
    }

    var color: Color {
        switch self {
        case .production: return OpsTint.amber.color
        case .remote: return .blue
        case .shared: return .purple
        case .default: return TalkieTheme.textMuted
        }
    }
}

@MainActor
final class AgentFeatureFlagsModel: ObservableObject {
    @Published private(set) var remoteFlags: [String: Bool] = [:]
    @Published private(set) var lastFetchDate: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isFetching = false

    var visibleDefinitions: [RuntimeFeatureFlagDefinition] {
        RuntimeFeatureFlags.definitions
    }

    var cacheDurationLabel: String {
        Self.durationLabel(RuntimeFeatureFlags.cacheDuration)
    }

    var lastFetchLabel: String {
        guard let lastFetchDate else { return "Never" }
        return lastFetchDate.formatted(date: .abbreviated, time: .standard)
    }

    var nextFetchLabel: String {
        guard let lastFetchDate else { return "On next launch" }
        let nextFetch = lastFetchDate.addingTimeInterval(RuntimeFeatureFlags.cacheDuration)
        if nextFetch <= Date() { return "Now" }
        return nextFetch.formatted(date: .abbreviated, time: .standard)
    }

    var remoteCountLabel: String {
        "\(remoteFlags.count)"
    }

    func loadSnapshot() {
        if let data = TalkieSharedSettings.data(forKey: AgentSettingsKey.featureFlagsRemotePayload),
           let flags = try? JSONDecoder().decode([String: Bool].self, from: data) {
            remoteFlags = flags
        }
        lastFetchDate = TalkieSharedSettings.object(forKey: AgentSettingsKey.featureFlagsLastFetch) as? Date
        lastErrorMessage = TalkieSharedSettings.string(forKey: AgentSettingsKey.featureFlagsLastError)
    }

    func fetchNow() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let flags = try await RuntimeFeatureFlags.fetchRemoteFlags()
            remoteFlags = flags
            lastFetchDate = Date()
            lastErrorMessage = nil
            persistSnapshot()
            syncSharedFlags()
        } catch {
            lastErrorMessage = error.localizedDescription
            TalkieSharedSettings.set(error.localizedDescription, forKey: AgentSettingsKey.featureFlagsLastError)
        }
    }

    func value(for definition: RuntimeFeatureFlagDefinition) -> Bool {
        if definition.key == "enableCapture", TalkieEnvironment.current == .production {
            return true
        }
        if let remote = remoteFlags[definition.key] {
            return remote
        }
        if let sharedSettingsKey = definition.sharedSettingsKey,
           let sharedValue = Self.boolObject(forKey: sharedSettingsKey) {
            return sharedValue
        }
        return definition.defaultValue
    }

    func source(for definition: RuntimeFeatureFlagDefinition) -> AgentFeatureFlagSource {
        if definition.key == "enableCapture", TalkieEnvironment.current == .production {
            return .production
        }
        if remoteFlags[definition.key] != nil {
            return .remote
        }
        if let sharedSettingsKey = definition.sharedSettingsKey,
           Self.boolObject(forKey: sharedSettingsKey) != nil {
            return .shared
        }
        return .default
    }

    func copySnapshot() {
        let snapshot = AgentFeatureFlagSnapshot(
            environment: TalkieEnvironment.current.displayName,
            endpoint: RuntimeFeatureFlags.endpoint,
            cacheDurationSeconds: Int(RuntimeFeatureFlags.cacheDuration),
            lastFetch: lastFetchDate,
            lastError: lastErrorMessage,
            flags: Dictionary(
                uniqueKeysWithValues: RuntimeFeatureFlags.definitions.map { definition in
                    (definition.key, value(for: definition))
                }
            )
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

    private func persistSnapshot() {
        if let data = try? JSONEncoder().encode(remoteFlags) {
            TalkieSharedSettings.set(data, forKey: AgentSettingsKey.featureFlagsRemotePayload)
        }
        if let lastFetchDate {
            TalkieSharedSettings.set(lastFetchDate, forKey: AgentSettingsKey.featureFlagsLastFetch)
        }
        TalkieSharedSettings.set(remoteFlags.count, forKey: AgentSettingsKey.featureFlagsRemoteCount)
        TalkieSharedSettings.removeObject(forKey: AgentSettingsKey.featureFlagsLastError)
    }

    private func syncSharedFlags() {
        for definition in RuntimeFeatureFlags.definitions {
            guard let sharedSettingsKey = definition.sharedSettingsKey else { continue }
            let nextValue = value(for: definition)
            let previousValue = Self.boolObject(forKey: sharedSettingsKey)
            TalkieSharedSettings.set(nextValue, forKey: sharedSettingsKey)

            guard previousValue != nextValue,
                  sharedSettingsKey == AgentSettingsKey.featureCaptureEnabled else {
                continue
            }

            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.agentHotkeysDidChange"),
                object: "featureCaptureEnabled",
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    private static func boolObject(forKey key: String) -> Bool? {
        let object = TalkieSharedSettings.object(forKey: key)
        return (object as? Bool) ?? (object as? NSNumber)?.boolValue
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

private struct AgentFeatureFlagSnapshot: Encodable {
    let environment: String
    let endpoint: String
    let cacheDurationSeconds: Int
    let lastFetch: Date?
    let lastError: String?
    let flags: [String: Bool]
}
