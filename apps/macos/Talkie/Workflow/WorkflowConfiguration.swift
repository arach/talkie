//
//  WorkflowConfiguration.swift
//  Talkie macOS
//
//  Human-editable workflow runtime configuration persisted to disk.
//

import Foundation

struct WorkflowConfiguration: Codable {
    struct ControlPlane: Codable, Equatable {
        var enabled: Bool
        var idlePollInterval: TimeInterval
        var deviceId: String

        init(
            enabled: Bool = false,
            idlePollInterval: TimeInterval = 300,
            deviceId: String = Self.generatedDeviceId()
        ) {
            self.enabled = enabled
            self.idlePollInterval = max(60, idlePollInterval)
            self.deviceId = deviceId.isEmpty ? Self.generatedDeviceId() : deviceId
        }

        func normalized() -> ControlPlane {
            ControlPlane(
                enabled: enabled,
                idlePollInterval: max(60, idlePollInterval),
                deviceId: deviceId.isEmpty ? Self.generatedDeviceId() : deviceId
            )
        }

        static func generatedDeviceId() -> String {
            "mac-\(UUID().uuidString.lowercased())"
        }
    }

    struct WorkflowPreferenceSnapshot: Codable, Equatable {
        var isEnabled: Bool
        var isPinned: Bool
        var autoRun: Bool
        var autoRunOrder: Int
        var sortOrder: Int
        var showInInterstitial: Bool
        var showInDrafts: Bool
        var appBundleIDs: [String]

        init(
            isEnabled: Bool = true,
            isPinned: Bool = false,
            autoRun: Bool = false,
            autoRunOrder: Int = 0,
            sortOrder: Int = 0,
            showInInterstitial: Bool = false,
            showInDrafts: Bool = false,
            appBundleIDs: [String] = []
        ) {
            self.isEnabled = isEnabled
            self.isPinned = isPinned
            self.autoRun = autoRun
            self.autoRunOrder = autoRunOrder
            self.sortOrder = sortOrder
            self.showInInterstitial = showInInterstitial
            self.showInDrafts = showInDrafts
            self.appBundleIDs = appBundleIDs
        }

        init(preference: WorkflowPreference) {
            self.init(
                isEnabled: preference.isEnabled,
                isPinned: preference.isPinned,
                autoRun: preference.autoRun,
                autoRunOrder: preference.autoRunOrder,
                sortOrder: preference.sortOrder,
                showInInterstitial: preference.showInInterstitial,
                showInDrafts: preference.showInDrafts,
                appBundleIDs: preference.appBundleIDs
            )
        }

        init(workflow: WorkflowDefinition) {
            self.init(
                isEnabled: workflow.isEnabled,
                isPinned: workflow.isPinned,
                autoRun: workflow.autoRun,
                autoRunOrder: workflow.autoRunOrder
            )
        }

        func materialize(workflowId: UUID, existing: WorkflowPreference?) -> WorkflowPreference {
            WorkflowPreference(
                workflowId: workflowId.uuidString,
                isEnabled: isEnabled,
                isPinned: isPinned,
                autoRun: autoRun,
                autoRunOrder: autoRunOrder,
                sortOrder: sortOrder,
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date(),
                showInInterstitial: showInInterstitial,
                showInDrafts: showInDrafts,
                appBundleIDsJSON: Self.encode(appBundleIDs)
            )
        }

        func matches(_ preference: WorkflowPreference) -> Bool {
            isEnabled == preference.isEnabled &&
            isPinned == preference.isPinned &&
            autoRun == preference.autoRun &&
            autoRunOrder == preference.autoRunOrder &&
            sortOrder == preference.sortOrder &&
            showInInterstitial == preference.showInInterstitial &&
            showInDrafts == preference.showInDrafts &&
            appBundleIDs == preference.appBundleIDs
        }

        private static func encode(_ appBundleIDs: [String]) -> String {
            (try? String(data: JSONEncoder().encode(appBundleIDs), encoding: .utf8)) ?? "[]"
        }
    }

    struct Runtime: Codable, Equatable {
        var customAllowedExecutables: [String]
        var defaultOutputDirectory: String
        var pathAliases: [String: String]
        var automationLastRunTimes: [String: TimeInterval]

        init(
            customAllowedExecutables: [String] = [],
            defaultOutputDirectory: String = "",
            pathAliases: [String: String] = [:],
            automationLastRunTimes: [String: TimeInterval] = [:]
        ) {
            self.customAllowedExecutables = customAllowedExecutables
            self.defaultOutputDirectory = defaultOutputDirectory
            self.pathAliases = pathAliases
            self.automationLastRunTimes = automationLastRunTimes
        }

        func normalized(defaultOutputDirectory fallbackOutputDirectory: String) -> Runtime {
            Runtime(
                customAllowedExecutables: Array(Set(customAllowedExecutables)).sorted(),
                defaultOutputDirectory: defaultOutputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackOutputDirectory : defaultOutputDirectory,
                pathAliases: pathAliases,
                automationLastRunTimes: automationLastRunTimes
            )
        }
    }

    var version: Int
    var controlPlane: ControlPlane
    var workflowPreferences: [String: WorkflowPreferenceSnapshot]
    var runtime: Runtime

    init(
        version: Int = 2,
        controlPlane: ControlPlane = .init(),
        workflowPreferences: [String: WorkflowPreferenceSnapshot] = [:],
        runtime: Runtime = .init()
    ) {
        self.version = version
        self.controlPlane = controlPlane.normalized()
        self.workflowPreferences = workflowPreferences
        self.runtime = runtime.normalized(defaultOutputDirectory: Self.defaultOutputDirectoryPath())
    }

    func normalized() -> WorkflowConfiguration {
        WorkflowConfiguration(
            version: max(1, version),
            controlPlane: controlPlane.normalized(),
            workflowPreferences: workflowPreferences,
            runtime: runtime.normalized(defaultOutputDirectory: Self.defaultOutputDirectoryPath())
        )
    }

    private static func defaultOutputDirectoryPath() -> String {
        let documentsDirectory = URL.documentsDirectory
        return documentsDirectory.appending(path: "Talkie", directoryHint: .isDirectory).path
    }
}
