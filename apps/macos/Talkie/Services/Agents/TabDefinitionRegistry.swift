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
    nonisolated private static let globalRCPath = "~/.talkierc"

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
        seedConsoleSupportScriptsIfNeeded()
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
            if activeTabId == id {
                // Reassign — falling back to "" when the registry is
                // now empty, so a phantom id doesn't linger in
                // UserDefaults and the starter shows correctly on
                // next launch.
                activeTabId = tabs.first?.id ?? ""
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
            setGlobalConfig(GlobalRCConfig(tabsDir: nil, secretsFiles: [], env: [:], defaults: [:]))
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            setGlobalConfig(try TalkieRCParser.parseGlobalRC(content))
        } catch {
            log.warning("Failed to parse ~/.talkierc", detail: error.localizedDescription)
            setGlobalConfig(GlobalRCConfig(tabsDir: nil, secretsFiles: [], env: [:], defaults: [:]))
        }
    }

    private func setGlobalConfig(_ config: GlobalRCConfig) {
        guard globalConfig != config else { return }
        globalConfig = config
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

        guard ensureTabsDirectory() else { return }

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
        seedConsoleSupportScriptsIfNeeded()

        log.info("Seeded starter tab presets", detail: "\(TabPresets.bundled.count) tabs")
    }

    private func ensureTabsDirectory() -> Bool {
        let dir = tabsDirectoryURL

        if fileManager.fileExists(atPath: dir.path) {
            return true
        }

        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return true
        } catch {
            log.error("Failed to create tabs directory", error: error)
            return false
        }
    }

    private func seedConsoleSupportScriptsIfNeeded() {
        seedShellInitIfNeeded()
        seedBridgeLogsInitIfNeeded()
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
        # model = "opus"
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func seedShellInitIfNeeded() {
        guard ensureTabsDirectory() else { return }
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

    private func seedBridgeLogsInitIfNeeded() {
        guard ensureTabsDirectory() else { return }
        let initURL = URL(fileURLWithPath: (TabPresets.bridgeLogsInitScriptPath as NSString).expandingTildeInPath)
        guard !fileManager.fileExists(atPath: initURL.path) else { return }

        let content = """
        #!/bin/zsh
        # bridge-logs.init.zsh - Tail Mac Bridge + TalkieAgent logs in Console.

        export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        clear
        printf '[Talkie] Bridge + agent log tail\\n'
        printf 'Press Ctrl-C to stop.\\n\\n'

        today="$(date +%F)"
        log_candidates=(
          "/tmp/talkie-bridge-hyper-scan.log"
          "/tmp/talkie-bridge-dev.log"
          "/tmp/talkie-bridge.log"
          "$HOME/Library/Logs/TalkieBridge/bridge-dev.log"
          "$HOME/Library/Logs/TalkieBridge/bridge.log"
          "$HOME/Library/Application Support/Talkie/Bridge/bridge.log"
          "$HOME/Library/Application Support/Talkie/Bridge/bridge.dev.log"
          "$HOME/Library/Application Support/Talkie/logs/talkie-$today.log"
          "$HOME/Library/Application Support/TalkieAgent/logs/talkie-$today.log"
          "/tmp/talkie-agent-debug.log"
          "/tmp/to.talkie.app.agent.dev.stdout.log"
          "/tmp/to.talkie.app.agent.dev.stderr.log"
          "/tmp/to.talkie.app.agent.xpc.dev.stdout.log"
          "/tmp/to.talkie.app.agent.xpc.dev.stderr.log"
        )

        existing=()
        for file in "${log_candidates[@]}"; do
          [[ -f "$file" ]] && existing+=("$file")
        done

        if (( ${#existing[@]} > 0 )); then
          printf 'Tailing logs:\\n'
          printf '  %s\\n' "${existing[@]}"
          printf '\\n'
          exec tail -n 100 -F "${existing[@]}"
        fi

        printf 'No Talkie bridge or agent log found yet. Waiting...\\n'
        while true; do
          for file in "${log_candidates[@]}"; do
            if [[ -f "$file" ]]; then
              printf '\\nTailing %s\\n\\n' "$file"
              exec tail -n 120 -F "$file"
            fi
          done
          sleep 2
        done
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
                guard TabDefinitionRegistry.eventPathsIncludeGlobalRC(eventPaths) else { return }
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

    nonisolated private static func eventPathsIncludeGlobalRC(_ eventPaths: UnsafeMutableRawPointer?) -> Bool {
        guard let eventPaths else { return false }

        let targetPath = URL(fileURLWithPath: (globalRCPath as NSString).expandingTildeInPath)
            .standardizedFileURL
            .path
        let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        for case let path as String in paths {
            if URL(fileURLWithPath: path).standardizedFileURL.path == targetPath {
                return true
            }
        }

        return false
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
