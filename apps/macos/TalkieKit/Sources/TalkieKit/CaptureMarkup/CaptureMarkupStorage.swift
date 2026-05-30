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

    // MARK: - Materialized exports
    //
    // Exports are a *different way to save* — a flat PNG/JPEG copy the user
    // shares out, distinct from the sidecar (the computed doc). They live in a
    // user-visible folder so they're easy to find and hand off; the sidecar
    // and the source capture are never touched by an export.

    /// User-visible exports folder: ~/Pictures/Talkie.
    public static var exportsDirectory: URL {
        let pictures = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Talkie", isDirectory: true)
    }

    /// Base artifact name for a capture at a given scale: `shot` → `shot@2x`
    /// (no suffix at 1×). Extension is appended by the caller from the format.
    public static func exportBaseName(forImageURL imageURL: URL, scale: Int) -> String {
        let base = imageURL.deletingPathExtension().lastPathComponent
        return scale > 1 ? "\(base)@\(scale)x" : base
    }

    /// Write rendered artifact data to the exports folder, returning the URL.
    /// Re-exports don't clobber: a numeric suffix disambiguates collisions, so
    /// each share is a distinct file.
    @discardableResult
    public static func writeExport(
        _ data: Data,
        forImageURL imageURL: URL,
        format: CaptureMarkupExportFormat,
        scale: Int
    ) throws -> URL {
        let dir = exportsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let name = exportBaseName(forImageURL: imageURL, scale: scale)
        let ext = format.fileExtension
        var candidate = dir.appendingPathComponent("\(name).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name)-\(counter).\(ext)")
            counter += 1
        }
        try data.write(to: candidate, options: .atomic)
        return candidate
    }
}
