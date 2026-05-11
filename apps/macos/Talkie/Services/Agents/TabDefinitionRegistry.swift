//
//  TabDefinitionRegistry.swift
//  Talkie
//
//  Reads, watches, and manages .talkierc tab definitions.
//  Single source of truth for the tab rail.
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.system)

@MainActor
@Observable
final class TabDefinitionRegistry {
    static let shared = TabDefinitionRegistry()

    private(set) var tabs: [TabDefinition] = []
    private(set) var errors: [String: String] = [:]
    private(set) var globalConfig = GlobalRCConfig(tabsDir: nil, secretsFiles: [], env: [:], defaults: [:])

    var activeTabId: String {
        didSet {
            UserDefaults.standard.set(activeTabId, forKey: "console.activeTabId")
        }
    }

    var activeTab: TabDefinition? {
        tabs.first { $0.id == activeTabId }
    }

    private var fsEventStream: FSEventStreamRef?
    private var globalFSEventStream: FSEventStreamRef?
    private let fileManager = FileManager.default

    private static let defaultTabsDir = "~/.talkie/tabs"
    private static let globalRCPath = "~/.talkierc"

    var tabsDirectoryURL: URL {
        let dir = globalConfig.tabsDir ?? Self.defaultTabsDir
        return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
    }

    private var globalRCURL: URL {
        URL(fileURLWithPath: (Self.globalRCPath as NSString).expandingTildeInPath)
    }

    private init() {
        self.activeTabId = UserDefaults.standard.string(forKey: "console.activeTabId") ?? "claude"
    }

    func bootstrap() {
        seedIfNeeded()
        prepareForAppLaunch()
        loadAllTabs()
        startWatching()

        if activeTab == nil, let first = tabs.first {
            activeTabId = first.id
        }

        log.info("TabDefinitionRegistry bootstrapped", detail: "\(tabs.count) tabs loaded")
    }

    func reload() {
        prepareForAppLaunch()
        loadAllTabs()
    }

    func prepareForAppLaunch() {
        loadGlobalConfig()
        migrateLegacyClaudeAuthBridgeIfNeeded()
    }

    func tab(for id: String) -> TabDefinition? {
        tabs.first { $0.id == id }
    }

    func create(_ definition: TabDefinition) {
        let url = tabsDirectoryURL.appending(path: "\(definition.id).talkierc")
        let content = TalkieRCParser.serialize(definition)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            loadAllTabs()
            log.info("Created tab definition", detail: definition.id)
        } catch {
            log.error("Failed to create tab definition", error: error)
        }
    }

    func update(_ id: String, _ definition: TabDefinition) {
        let url = tabsDirectoryURL.appending(path: "\(id).talkierc")
        let content = TalkieRCParser.serialize(definition)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            loadAllTabs()
            log.info("Updated tab definition", detail: id)
        } catch {
            log.error("Failed to update tab definition", error: error)
        }
    }

    func delete(_ id: String) {
        let url = tabsDirectoryURL.appending(path: "\(id).talkierc")
        do {
            try fileManager.removeItem(at: url)
            loadAllTabs()
            if activeTabId == id, let first = tabs.first {
                activeTabId = first.id
            }
            log.info("Deleted tab definition", detail: id)
        } catch {
            log.error("Failed to delete tab definition", error: error)
        }
    }

    func duplicate(_ id: String) -> TabDefinition? {
        guard let original = tab(for: id) else { return nil }

        let newId = "\(id)-copy-\(Int(Date().timeIntervalSince1970))"
        var copy = original
        copy = TabDefinition(
            id: newId,
            label: "\(original.label) Copy",
            icon: original.icon,
            order: original.order + 1,
            harness: original.harness,
            model: original.model,
            systemPrompt: original.systemPrompt,
            cwd: original.cwd,
            launchArgs: original.launchArgs,
            readOnly: false,
            useTmux: original.useTmux,
            tmuxSessionName: original.tmuxSessionName,
            env: original.env,
            shell: original.shell,
            sourceURL: nil
        )

        create(copy)
        return copy
    }

    func resolveEnv(for tab: TabDefinition) -> TabEnvResolver.ResolutionResult {
        TabEnvResolver.resolve(
            tabEnv: tab.env,
            globalEnv: globalConfig.env,
            secretsFiles: globalConfig.secretsFiles
        )
    }

    // MARK: - Private

    private func loadGlobalConfig() {
        let url = globalRCURL
        guard fileManager.fileExists(atPath: url.path) else {
            globalConfig = GlobalRCConfig(tabsDir: nil, secretsFiles: [], env: [:], defaults: [:])
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            globalConfig = try TalkieRCParser.parseGlobalRC(content)
        } catch {
            log.warning("Failed to parse ~/.talkierc", detail: error.localizedDescription)
            globalConfig = GlobalRCConfig(tabsDir: nil, secretsFiles: [], env: [:], defaults: [:])
        }
    }

    private func loadAllTabs() {
        let dir = tabsDirectoryURL
        var loaded: [TabDefinition] = []
        var newErrors: [String: String] = [:]

        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            tabs = []
            errors = [:]
            return
        }

        for entry in entries where entry.pathExtension == "talkierc" {
            let fileID = entry.deletingPathExtension().lastPathComponent
            do {
                let content = try String(contentsOf: entry, encoding: .utf8)
                var tab = try TalkieRCParser.parseTabDefinition(from: content, sourceURL: entry)
                if tab.id != fileID {
                    tab = TabDefinition(
                        id: fileID,
                        label: tab.label,
                        icon: tab.icon,
                        order: tab.order,
                        harness: tab.harness,
                        model: tab.model,
                        systemPrompt: tab.systemPrompt,
                        cwd: tab.cwd,
                        launchArgs: tab.launchArgs,
                        readOnly: tab.readOnly,
                        useTmux: tab.useTmux,
                        tmuxSessionName: tab.tmuxSessionName,
                        env: tab.env,
                        shell: tab.shell,
                        sourceURL: tab.sourceURL
                    )
                }
                loaded.append(tab)
            } catch {
                newErrors[fileID] = error.localizedDescription
                log.warning("Failed to parse tab", detail: "\(fileID): \(error.localizedDescription)")
            }
        }

        loaded.sort { $0.order < $1.order }
        tabs = loaded
        errors = newErrors
    }

    private func migrateLegacyClaudeAuthBridgeIfNeeded() {
        let url = tabsDirectoryURL.appending(path: "claude.talkierc")
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let tab = try TalkieRCParser.parseTabDefinition(from: content, sourceURL: url)
            guard tab.id == "claude",
                  tab.harness == .claudeCode,
                  tab.env == TabPresets.legacyClaudeAuthBridgeEnv else {
                return
            }

            var migrated = tab
            migrated.env = [:]

            let updatedContent = TalkieRCParser.serialize(migrated)
            guard updatedContent != content else { return }

            try updatedContent.write(to: url, atomically: true, encoding: .utf8)
            log.info("Migrated Claude console tab to CLI auth", detail: url.path)
        } catch {
            log.warning("Failed to migrate Claude console auth bridge", detail: error.localizedDescription)
        }
    }

    // MARK: - First-run seeding

    private func seedIfNeeded() {
        let dir = tabsDirectoryURL

        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                log.error("Failed to create tabs directory", error: error)
                return
            }
        }

        let existing = (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "talkierc" } ?? []

        guard existing.isEmpty else { return }

        for preset in TabPresets.bundled {
            let content = TalkieRCParser.serialize(preset)
            let url = dir.appending(path: "\(preset.id).talkierc")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }

        seedGlobalRCIfNeeded()
        seedShellInitIfNeeded()

        log.info("Seeded starter tab presets", detail: "\(TabPresets.bundled.count) tabs")
    }

    private func seedGlobalRCIfNeeded() {
        let url = globalRCURL
        guard !fileManager.fileExists(atPath: url.path) else { return }

        let content = """
        # ~/.talkierc — Talkie global console configuration
        #
        # Shared defaults applied across all console tabs.
        # Tab-specific config lives in ~/.talkie/tabs/<id>.talkierc

        # tabs_dir = "~/.talkie/tabs"
        # secrets_files = ["~/.talkie/.env.local"]

        # [env]
        # TALKIE_WORKSPACE = "~/dev/talkie"

        # [defaults.claude-code]
        # model = "claude-sonnet-4-6"
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func seedShellInitIfNeeded() {
        let dir = tabsDirectoryURL
        let initURL = dir.appending(path: "talkie-shell.init.zsh")
        guard !fileManager.fileExists(atPath: initURL.path) else { return }

        let content = """
        #!/bin/zsh
        # talkie-shell.init.zsh — Talkie Shell session initialization
        # Sourced when the Talkie Shell tab starts a new session.

        # Add talkie-dev to PATH
        export PATH="$HOME/dev/talkie/packages/npm/cli/bin:$PATH"

        # iOS simulator aliases
        alias sim-list='xcrun simctl list devices available'
        alias sim-boot='xcrun simctl boot'
        alias sim-open='open -a Simulator'
        alias sim-install='xcrun simctl install booted'
        alias sim-launch='xcrun simctl launch booted'

        # Talkie workspace
        cd "${TALKIE_WORKSPACE:-$HOME/dev/talkie}" 2>/dev/null || true

        exec /bin/zsh -i
        """
        try? content.write(to: initURL, atomically: true, encoding: .utf8)
    }

    // MARK: - FSEvents watching

    private func startWatching() {
        stopWatching()

        let tabsPath = tabsDirectoryURL.path as CFString
        let globalPath = globalRCURL.deletingLastPathComponent().path as CFString

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        if let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let registry = Unmanaged<TabDefinitionRegistry>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    registry.reload()
                }
            },
            &context,
            [tabsPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
            fsEventStream = stream
        }

        if let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let registry = Unmanaged<TabDefinitionRegistry>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    registry.loadGlobalConfig()
                }
            },
            &context,
            [globalPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
            globalFSEventStream = stream
        }
    }

    private func stopWatching() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
        if let stream = globalFSEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            globalFSEventStream = nil
        }
    }
}
