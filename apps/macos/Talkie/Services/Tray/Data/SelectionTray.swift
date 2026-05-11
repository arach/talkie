//
//  SelectionTray.swift
//  Talkie
//
//  Staging area for text selections captured via Hyper+S.
//  Persists selection text and lightweight app metadata so selection context
//  can participate in the same tray surfaces as screenshots and clips.
//

import AppKit
import TalkieKit

private let selectionTrayDir: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Talkie/Tray/selections", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

struct TraySelectionText: Identifiable, Codable {
    let id: UUID
    let capturedAt: Date
    let filename: String
    let textPreview: String
    let characterCount: Int
    let appName: String?
    let bundleID: String?
    let windowTitle: String?
    let displayName: String?
    var pinned: Bool

    var tempURL: URL {
        selectionTrayDir.appendingPathComponent(filename)
    }

    var text: String? {
        try? String(contentsOf: tempURL, encoding: .utf8)
    }
}

@MainActor
@Observable
final class SelectionTray {
    static let shared = SelectionTray()

    private(set) var items: [TraySelectionText] = []

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var isNotEmpty: Bool { !items.isEmpty }
    var unpinnedItems: [TraySelectionText] { items.filter { !$0.pinned } }
    var unpinnedCount: Int { items.filter { !$0.pinned }.count }
    var pinnedCount: Int { items.filter(\.pinned).count }
    var hasUnpinnedItems: Bool { items.contains { !$0.pinned } }

    private static var manifestURL: URL {
        selectionTrayDir.appendingPathComponent("manifest.json")
    }

    private init() {
        restoreFromDisk()
    }

    func add(
        text: String,
        appName: String?,
        bundleID: String?,
        windowTitle: String?,
        displayName: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let id = UUID()
        let filename = "\(id.uuidString).txt"
        let url = selectionTrayDir.appendingPathComponent(filename)

        do {
            try trimmed.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log(.system).error("Failed to write tray selection: \(error)")
            return
        }

        let item = TraySelectionText(
            id: id,
            capturedAt: Date(),
            filename: filename,
            textPreview: Self.preview(for: trimmed),
            characterCount: trimmed.count,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            displayName: displayName,
            pinned: false
        )

        items.append(item)
        saveManifest()
        Log(.system).info("Selection added to tray (\(items.count) total), \(trimmed.count) chars")
    }

    func togglePinned(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        saveManifest()
    }

    func clearItems(ids: Set<UUID>) {
        let toRemove = items.filter { ids.contains($0.id) }
        for item in toRemove {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
        items.removeAll { ids.contains($0.id) }
        saveManifest()
        Log(.system).info("Cleared \(toRemove.count) tray selections, \(items.count) remaining")
    }

    func clear() {
        clearItems(ids: Set(items.map(\.id)))
    }

    func clearUnpinned() {
        clearItems(ids: Set(unpinnedItems.map(\.id)))
    }

    private func saveManifest() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: Self.manifestURL, options: .atomic)
        } catch {
            Log(.system).error("Failed to save selection tray manifest: \(error)")
        }
    }

    private func restoreFromDisk() {
        guard let data = try? Data(contentsOf: Self.manifestURL) else { return }
        do {
            let restored = try JSONDecoder().decode([TraySelectionText].self, from: data)
            items = restored.filter { FileManager.default.fileExists(atPath: $0.tempURL.path) }
        } catch {
            Log(.system).error("Failed to restore selection tray manifest: \(error)")
        }
    }

    private static func preview(for text: String) -> String {
        let collapsed = text
            .replacing("\n", with: " ")
            .replacing("\t", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if collapsed.count <= 140 {
            return collapsed
        }
        return String(collapsed.prefix(137)) + "..."
    }
}
