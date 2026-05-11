//
//  WorkflowConfigurationStore.swift
//  Talkie macOS
//
//  Single file-backed source of truth for workflow runtime preferences.
//

import Foundation
import Observation
import TalkieKit

private let workflowConfigLog = Log(.workflow)

@Observable
final class WorkflowConfigurationStore {
    static let shared = WorkflowConfigurationStore()

    private static let legacyControlPlaneEnabledKey = "workflowControlPlaneEnabled"
    private static let legacyControlPlaneIdlePollIntervalKey = "workflowControlPlaneIdlePollInterval"
    private static let legacyControlPlaneDeviceIdKey = "workflowControlPlaneDeviceId"
    private static let legacyCustomAllowedExecutablesKey = "ShellStepCustomAllowedExecutables"
    private static let legacyDefaultOutputDirectoryKey = "TalkieDefaultOutputDirectory"
    private static let legacyPathAliasesKey = "TalkiePathAliases"
    private static let legacyAutomationLastRunTimesKey = "AutomationScheduler.lastRunTimes"

    private(set) var configuration: WorkflowConfiguration
    let fileURL: URL

    private init() {
        let workflowsDirectory = TalkieEnvironment.current.appSupportDirectory
            .appendingPathComponent("workflows", isDirectory: true)

        try? FileManager.default.createDirectory(at: workflowsDirectory, withIntermediateDirectories: true)

        fileURL = workflowsDirectory.appendingPathComponent("config.json")

        if let loaded = Self.loadConfiguration(from: fileURL) {
            configuration = loaded
            save()
        } else {
            configuration = WorkflowConfiguration()
            migrateLegacyControlPlaneSettings()
            migrateLegacyRuntimeSettings()
            save()
        }
    }

    var displayPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return fileURL.path.replacingOccurrences(of: homePath, with: "~")
    }

    func reloadFromDisk() {
        guard let loaded = Self.loadConfiguration(from: fileURL) else { return }
        configuration = loaded
    }

    func updateControlPlane(_ update: (inout WorkflowConfiguration.ControlPlane) -> Void) {
        var next = configuration
        update(&next.controlPlane)
        persist(next.normalized())
    }

    func updateWorkflowPreference(
        for workflowId: UUID,
        defaultingTo fallback: WorkflowConfiguration.WorkflowPreferenceSnapshot = .init(),
        _ update: (inout WorkflowConfiguration.WorkflowPreferenceSnapshot) -> Void
    ) {
        var next = configuration
        var preference = next.workflowPreferences[workflowId.uuidString] ?? fallback
        update(&preference)
        next.workflowPreferences[workflowId.uuidString] = preference
        persist(next)
    }

    func updateRuntime(_ update: (inout WorkflowConfiguration.Runtime) -> Void) {
        var next = configuration
        update(&next.runtime)
        persist(next)
    }

    func removeWorkflowPreference(for workflowId: UUID) {
        var next = configuration
        next.workflowPreferences.removeValue(forKey: workflowId.uuidString)
        persist(next)
    }

    func synchronize(
        loadedWorkflows: [LoadedWorkflow],
        using preferencesRepository: WorkflowPreferencesRepository
    ) throws -> [UUID: WorkflowPreference] {
        let existingPreferences = try preferencesRepository.fetch(for: loadedWorkflows.map(\.id))
        var next = configuration
        var didChangeFile = false
        var resolvedPreferences: [UUID: WorkflowPreference] = [:]

        for loadedWorkflow in loadedWorkflows {
            let workflowId = loadedWorkflow.id
            let key = workflowId.uuidString

            let snapshot: WorkflowConfiguration.WorkflowPreferenceSnapshot
            if let configured = next.workflowPreferences[key] {
                snapshot = configured
            } else if let existing = existingPreferences[workflowId] {
                snapshot = .init(preference: existing)
                next.workflowPreferences[key] = snapshot
                didChangeFile = true
            } else {
                snapshot = .init(workflow: loadedWorkflow.definition)
                next.workflowPreferences[key] = snapshot
                didChangeFile = true
            }

            let desiredPreference = snapshot.materialize(
                workflowId: workflowId,
                existing: existingPreferences[workflowId]
            )

            if existingPreferences[workflowId].map({ !snapshot.matches($0) }) ?? true {
                try preferencesRepository.save(desiredPreference)
            }

            resolvedPreferences[workflowId] = desiredPreference
        }

        if didChangeFile {
            persist(next)
        }

        return resolvedPreferences
    }

    private func migrateLegacyControlPlaneSettings() {
        let defaults = UserDefaults.standard

        let enabled = defaults.object(forKey: Self.legacyControlPlaneEnabledKey) as? Bool ?? configuration.controlPlane.enabled
        let idlePollInterval = (defaults.object(forKey: Self.legacyControlPlaneIdlePollIntervalKey) as? Double) ?? configuration.controlPlane.idlePollInterval
        let deviceId = defaults.string(forKey: Self.legacyControlPlaneDeviceIdKey) ?? configuration.controlPlane.deviceId

        configuration.controlPlane = WorkflowConfiguration.ControlPlane(
            enabled: enabled,
            idlePollInterval: idlePollInterval,
            deviceId: deviceId
        )
    }

    private func migrateLegacyRuntimeSettings() {
        let defaults = UserDefaults.standard

        let customAllowedExecutables = defaults.stringArray(forKey: Self.legacyCustomAllowedExecutablesKey) ?? configuration.runtime.customAllowedExecutables
        let defaultOutputDirectory = defaults.string(forKey: Self.legacyDefaultOutputDirectoryKey) ?? configuration.runtime.defaultOutputDirectory
        let pathAliases = defaults.dictionary(forKey: Self.legacyPathAliasesKey) as? [String: String] ?? configuration.runtime.pathAliases

        var automationLastRunTimes = configuration.runtime.automationLastRunTimes
        if
            let data = defaults.data(forKey: Self.legacyAutomationLastRunTimesKey),
            let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        {
            automationLastRunTimes = decoded.mapValues(\.timeIntervalSince1970)
        }

        configuration.runtime = WorkflowConfiguration.Runtime(
            customAllowedExecutables: customAllowedExecutables,
            defaultOutputDirectory: defaultOutputDirectory,
            pathAliases: pathAliases,
            automationLastRunTimes: automationLastRunTimes
        ).normalized(defaultOutputDirectory: URL.documentsDirectory.appending(path: "Talkie", directoryHint: .isDirectory).path)
    }

    private func persist(_ next: WorkflowConfiguration) {
        configuration = next.normalized()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            workflowConfigLog.error("Failed to save workflow config: \(error.localizedDescription)")
        }
    }

    private static func loadConfiguration(from fileURL: URL) -> WorkflowConfiguration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        do {
            return try JSONDecoder().decode(WorkflowConfiguration.self, from: data).normalized()
        } catch {
            workflowConfigLog.error("Failed to decode workflow config: \(error.localizedDescription)")
            return nil
        }
    }
}
