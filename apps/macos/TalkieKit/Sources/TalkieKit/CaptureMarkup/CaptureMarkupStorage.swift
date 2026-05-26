//
//  CaptureMarkupStorage.swift
//  TalkieKit
//

import Foundation

public enum CaptureMarkupStorage {
    public static let sidecarSuffix = ".markup.json"

    public static func sidecarURL(forImageURL imageURL: URL) -> URL {
        let base = imageURL.deletingPathExtension().lastPathComponent
        return imageURL.deletingLastPathComponent()
            .appendingPathComponent(base + sidecarSuffix)
    }

    public static func load(forImageURL imageURL: URL) -> CaptureMarkupDocument? {
        let url = sidecarURL(forImageURL: imageURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    }

    public static func save(_ document: CaptureMarkupDocument, forImageURL imageURL: URL) throws {
        let url = sidecarURL(forImageURL: imageURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    public static func deleteSidecar(forImageURL imageURL: URL) {
        let url = sidecarURL(forImageURL: imageURL)
        try? FileManager.default.removeItem(at: url)
    }
}
