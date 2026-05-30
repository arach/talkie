//
//  TKSidecarStore.swift
//  TalkieKit
//
//  Disk read / write / delete for `<asset-dir>/.tk/<basename>.json`
//  sidecars. URL math + atomic JSON serialization.
//

import Foundation

public extension URL {
    /// Sidecar path for the primary asset at this URL. Does NOT check
    /// existence — callers ask the store if they need that.
    ///
    /// Layout: a `.tk/` subdirectory inside the asset's parent directory.
    /// The basename mirrors the asset, with the extension swapped for
    /// `.json`. Hidden (dot-prefixed) so Finder / `ls` keep the asset
    /// directory clean.
    func tkSidecarURL() -> URL {
        deletingLastPathComponent()
            .appendingPathComponent(".tk", isDirectory: true)
            .appendingPathComponent(deletingPathExtension().lastPathComponent + ".json")
    }
}

public enum TKSidecarStore {
    /// Read the sidecar for `assetURL`, or nil if no sidecar exists.
    /// Returns nil (not an error) for absent files because absence is
    /// the expected steady state before augmentation has run.
    public static func read(forAsset assetURL: URL) throws -> TKSidecar? {
        let sidecarURL = assetURL.tkSidecarURL()
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: sidecarURL)
        return try JSONDecoder.tkDecoder().decode(TKSidecar.self, from: data)
    }

    /// Write `sidecar` to disk for `assetURL`, creating `.tk/` if
    /// needed. Atomic: writes to a temp file and renames, so a crash
    /// mid-write can't leave a torn JSON file readable.
    public static func write(_ sidecar: TKSidecar, forAsset assetURL: URL) throws {
        let sidecarURL = assetURL.tkSidecarURL()
        let dir = sidecarURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try JSONEncoder.tkEncoder().encode(sidecar)
        try data.write(to: sidecarURL, options: [.atomic])
    }

    /// Delete the sidecar for `assetURL` if one exists. No-op when
    /// absent — callers hooking this up to asset-delete sites don't
    /// need to check existence first.
    public static func delete(forAsset assetURL: URL) {
        let sidecarURL = assetURL.tkSidecarURL()
        try? FileManager.default.removeItem(at: sidecarURL)
    }

    /// Whether a sidecar exists on disk for `assetURL`.
    public static func exists(forAsset assetURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: assetURL.tkSidecarURL().path)
    }

    /// Adds (or replaces) `augmentation` in the sidecar for
    /// `assetURL`, creating the sidecar if it doesn't exist yet.
    /// Convenience for augmenter implementations that produce one kind.
    public static func upsertAugmentation(
        _ augmentation: TKAugmentation,
        forAsset assetURL: URL,
        assetKind: TKSidecarAssetKind
    ) throws {
        var sidecar = try read(forAsset: assetURL) ?? TKSidecar(
            asset: TKSidecarAsset(
                kind: assetKind,
                filename: assetURL.lastPathComponent,
                sha256: nil
            )
        )
        sidecar.upsert(augmentation)
        try write(sidecar, forAsset: assetURL)
    }
}

private extension JSONEncoder {
    static func tkEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static func tkDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
