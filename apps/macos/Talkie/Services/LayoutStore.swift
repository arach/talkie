//
//  LayoutStore.swift
//  Talkie
//
//  Single source of truth for all UI layout state.
//  Persists to ~/Library/Application Support/Talkie/layout.json
//  Human-readable, agent-friendly, per-type split ratios.
//

import Foundation
import SwiftUI
import TalkieKit

// MARK: - Layout Schema

struct TalkieLayout: Codable {
    var window: WindowLayout
    var splits: [String: Double]  // Keyed by TalkieObjectType rawValue
    var sidebar: SidebarState
    var listView: ListViewLayout

    static let defaultLayout = TalkieLayout(
        window: WindowLayout(),
        splits: [
            "all": 0.5,
            "memos": 0.5,
            "dictations": 0.5,
            "readouts": 0.5,
            "notes": 0.45
        ],
        sidebar: SidebarState(),
        listView: ListViewLayout()
    )
}

struct WindowLayout: Codable {
    var width: Double = 1200
    var height: Double = 800
}

struct SidebarState: Codable {
    var iconsOnly: Bool = false
    var collapsed: Bool = false
}

struct ListViewLayout: Codable {
    var detailed: Bool = false
    var collapsed: Bool = false
}

// MARK: - Layout Store

@MainActor
@Observable
final class LayoutStore {
    static let shared = LayoutStore()

    private(set) var layout: TalkieLayout
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Talkie")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        self.fileURL = appSupport.appendingPathComponent("layout.json")
        self.layout = TalkieLayout.defaultLayout

        // Load from disk
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(TalkieLayout.self, from: data) {
            self.layout = saved
            Log(.ui).info("Loaded layout from \(fileURL.lastPathComponent)")
        }
    }

    // MARK: - Split Ratios

    func splitRatio(for type: String) -> Double {
        layout.splits[type] ?? 0.5
    }

    func setSplitRatio(_ ratio: Double, for type: String) {
        let clamped = min(max(ratio, 0.2), 0.8)
        layout.splits[type] = clamped
        scheduleSave()
    }

    // MARK: - Sidebar

    var sidebarIconsOnly: Bool {
        get { layout.sidebar.iconsOnly }
        set { layout.sidebar.iconsOnly = newValue; scheduleSave() }
    }

    var sidebarCollapsed: Bool {
        get { layout.sidebar.collapsed }
        set { layout.sidebar.collapsed = newValue; scheduleSave() }
    }

    // MARK: - List View

    var listDetailed: Bool {
        get { layout.listView.detailed }
        set { layout.listView.detailed = newValue; scheduleSave() }
    }

    var listCollapsed: Bool {
        get { layout.listView.collapsed }
        set { layout.listView.collapsed = newValue; scheduleSave() }
    }

    // MARK: - Window

    var windowWidth: Double {
        get { layout.window.width }
        set { layout.window.width = newValue; scheduleSave() }
    }

    var windowHeight: Double {
        get { layout.window.height }
        set { layout.window.height = newValue; scheduleSave() }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layout) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log(.ui).error("Failed to save layout: \(error)")
        }
    }

    /// Force an immediate save (e.g., on app quit)
    func saveNow() {
        saveTask?.cancel()
        save()
    }
}
