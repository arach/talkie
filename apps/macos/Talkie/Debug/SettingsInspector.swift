//
//  SettingsInspector.swift
//  Talkie
//
//  JSON viewer for debugging settings across Talkie apps
//

#if DEBUG
import SwiftUI
import AppKit
import TalkieKit

struct SettingsInspector: View {
    @State private var selectedTab = 0
    @State private var liveSettingsJSON: String = "Loading..."
    @State private var audioLogEntries: [String] = []
    @State private var searchText = ""
    @State private var defaultsItems: [(key: String, value: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker (single segmented control)
            Picker("", selection: $selectedTab) {
                Text("Live Settings").tag(0)
                Text("Audio Log").tag(1)
                Text("Defaults").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content (no TabView - just switch on selectedTab)
            Group {
                switch selectedTab {
                case 0:
                    JSONTextView(json: filteredLiveSettings)
                case 1:
                    AudioLogView(entries: filteredAudioLog)
                case 2:
                    DefaultsListView(items: filteredDefaults)
                default:
                    Text("Unknown tab")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom toolbar
            HStack {
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: revealInFinder) {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear { refresh() }
    }

    private var statusText: String {
        switch selectedTab {
        case 0:
            if liveSettingsJSON.contains("No settings") { return "⚠️ No dump" }
            return "✓ Loaded"
        case 1:
            return "\(audioLogEntries.count) entries"
        case 2:
            return "\(defaultsItems.count) keys"
        default:
            return ""
        }
    }

    private var filteredLiveSettings: String {
        guard !searchText.isEmpty else { return liveSettingsJSON }
        let lines = liveSettingsJSON.components(separatedBy: "\n")
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
        return filtered.isEmpty ? "No matches for '\(searchText)'" : filtered.joined(separator: "\n")
    }

    private var filteredAudioLog: [String] {
        guard !searchText.isEmpty else { return audioLogEntries }
        return audioLogEntries.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredDefaults: [(key: String, value: String)] {
        guard !searchText.isEmpty else { return defaultsItems }
        return defaultsItems.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func refresh() {
        loadLiveSettings()
        loadAudioLog()
        loadDefaults()
    }

    private func loadLiveSettings() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            liveSettingsJSON = "Could not find Application Support directory"
            return
        }

        let settingsPath = appSupport.appendingPathComponent("TalkieAgent/settings_dump.json")

        if fileManager.fileExists(atPath: settingsPath.path),
           let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            liveSettingsJSON = prettyString
        } else {
            liveSettingsJSON = """
            No settings dump found at:
            \(settingsPath.path)

            Tip: Restart TalkieAgent (DEBUG build) to generate the dump.
            The dump is created on launch and whenever settings change.
            """
        }
    }

    private func loadAudioLog() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            audioLogEntries = ["Could not find Application Support directory"]
            return
        }

        let logPath = appSupport.appendingPathComponent("TalkieAgent/AudioInputLog.jsonl")

        if fileManager.fileExists(atPath: logPath.path),
           let content = try? String(contentsOf: logPath, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            audioLogEntries = lines.reversed() // Most recent first
        } else {
            audioLogEntries = []
        }
    }

    private func loadDefaults() {
        var items: [(String, String)] = []

        // Get the correct suite based on environment
        let suiteName = TalkieEnvironment.current.sharedSettingsSuite
        let sharedDefaults = UserDefaults(suiteName: suiteName)

        // All shared defaults (sorted, with prefix showing source)
        if let shared = sharedDefaults?.dictionaryRepresentation() {
            for (key, value) in shared.sorted(by: { $0.key < $1.key }) {
                // Skip Apple/system keys
                if key.hasPrefix("Apple") || key.hasPrefix("NS") || key.hasPrefix("com.apple") { continue }
                if key.hasPrefix("AK") || key.hasPrefix("INNext") { continue }

                let valueStr = formatValue(value)
                items.append(("[\(suiteName.suffix(10))] \(key)", valueStr))
            }
        }

        // Standard defaults (Talkie app-specific)
        let standardDefaults = UserDefaults.standard
        let relevantKeys = ["currentTheme", "accentColor", "sidebarWidth", "lastSelectedMemo",
                           "showSidebar", "selectedNavItem", "windowFrame"]
        for key in relevantKeys {
            if let value = standardDefaults.object(forKey: key) {
                items.append(("[standard] \(key)", formatValue(value)))
            }
        }

        defaultsItems = items
    }

    private func formatValue(_ value: Any) -> String {
        if let data = value as? Data {
            // Try to decode as JSON
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                if let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let str = String(data: pretty, encoding: .utf8) {
                    return str
                }
            }
            return "<Data: \(data.count) bytes>"
        }
        return String(describing: value)
    }

    private func copyToClipboard() {
        let content: String
        switch selectedTab {
        case 0: content = liveSettingsJSON
        case 1: content = audioLogEntries.joined(separator: "\n")
        case 2:
            content = defaultsItems.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        default: content = ""
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func revealInFinder() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        var urls: [URL] = []

        // Collect existing files
        let settingsDump = appSupport.appendingPathComponent("TalkieAgent/settings_dump.json")
        let audioLog = appSupport.appendingPathComponent("TalkieAgent/AudioInputLog.jsonl")
        let liveDB = appSupport.appendingPathComponent("TalkieAgent/live.sqlite")

        if fileManager.fileExists(atPath: settingsDump.path) { urls.append(settingsDump) }
        if fileManager.fileExists(atPath: audioLog.path) { urls.append(audioLog) }
        if fileManager.fileExists(atPath: liveDB.path) { urls.append(liveDB) }

        if urls.isEmpty {
            // Just open the folder
            let folder = appSupport.appendingPathComponent("TalkieAgent")
            if fileManager.fileExists(atPath: folder.path) {
                NSWorkspace.shared.open(folder)
            } else {
                NSWorkspace.shared.open(appSupport)
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

// MARK: - JSON Text View

struct JSONTextView: View {
    let json: String

    var body: some View {
        ScrollView {
            Text(json)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Audio Log View

struct AudioLogView: View {
    let entries: [String]

    var body: some View {
        if entries.isEmpty {
            VStack {
                Image(systemName: "waveform.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No audio log entries")
                    .foregroundColor(.secondary)
                Text("Start a recording in TalkieAgent to generate logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries.indices, id: \.self) { index in
                AudioLogEntryView(jsonString: entries[index])
            }
            .listStyle(.plain)
        }
    }
}

struct AudioLogEntryView: View {
    let jsonString: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let parsed = parseEntry() {
                    Image(systemName: iconForEvent(parsed.event))
                        .foregroundColor(colorForEvent(parsed.event))
                        .frame(width: 20)
                    Text(parsed.event)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Spacer()
                    Text(parsed.timestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Text(String(jsonString.prefix(80)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                Text(prettyJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
    }

    private var prettyJSON: String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let string = String(data: pretty, encoding: .utf8) else {
            return jsonString
        }
        return string
    }

    private func parseEntry() -> (event: String, timestamp: String)? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String,
              let timestamp = json["timestamp"] as? String else {
            return nil
        }
        let shortTimestamp = String(timestamp.prefix(19)).replacingOccurrences(of: "T", with: " ")
        return (event, shortTimestamp)
    }

    private func iconForEvent(_ event: String) -> String {
        switch event {
        case "device_scan": return "antenna.radiowaves.left.and.right"
        case "recording_start": return "record.circle"
        case "recording_stop": return "stop.circle"
        case "device_selected": return "mic"
        default: return "doc.text"
        }
    }

    private func colorForEvent(_ event: String) -> Color {
        switch event {
        case "device_scan": return .blue
        case "recording_start": return .red
        case "recording_stop": return .orange
        case "device_selected": return .green
        default: return .secondary
        }
    }
}

// MARK: - Defaults List View

struct DefaultsListView: View {
    let items: [(key: String, value: String)]

    var body: some View {
        if items.isEmpty {
            VStack {
                Image(systemName: "gearshape.2")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No defaults found")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(items, id: \.key) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.key)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(item.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                }
                .textSelection(.enabled)
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Window Helper

func showSettingsInspector() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = NSHostingView(rootView: SettingsInspector())
    window.title = "Settings Inspector"
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
#endif
