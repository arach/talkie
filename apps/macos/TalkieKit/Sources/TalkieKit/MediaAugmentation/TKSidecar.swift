//
//  TKSidecar.swift
//  TalkieKit
//
//  Shape of the per-asset sidecar file written to `<asset-dir>/.tk/<basename>.json`.
//
//  Holds machine-derived data about a primary asset (audio or image). The
//  primary asset, the user-state sidecars (e.g. `.markup.json` for
//  screenshots), and the future on-disk transcript file (for audio) live
//  visibly next to the asset. This sidecar is hidden — `.tk/` — because
//  its contents are reproducible from the primary asset and shouldn't
//  clutter the user-facing directory.
//
//  Writes happen via `MediaAugmentationService`, never on the critical
//  capture or transcription-insertion paths.
//

import Foundation

/// Kinds of augmentation that can contribute a payload to a TKSidecar.
/// Adding a kind is a forward-compat operation: older readers see an
/// unknown raw value and skip it.
public enum TKAugmenterKind: String, Codable, Sendable {
    /// OCR results with text + per-observation bounding boxes.
    case ocr

    /// macOS Accessibility (AX) tree at the time of capture — roles,
    /// labels, frames, hierarchy.
    case axTree = "ax-tree"

    /// Window metadata at capture time — title, bundleID, frame in
    /// screen coords, backing scale.
    case windowMeta = "window-meta"

    /// VLM-generated textual descriptions of image UI state, keyed by
    /// the downstream target surface they were prepared for.
    case visionDescription = "vision-description"

    /// Voice-activity detection regions — `[start, end]` pairs.
    case vad

    /// Higher-quality re-transcription (the live transcription that the
    /// user waited on is the canonical product; this is an opportunistic
    /// upgrade or alternative-model pass).
    case transcript

    /// Speaker diarization — turn-taking with speaker labels.
    case diarization

    /// Embedding vector for semantic search / clustering.
    case embedding
}

/// One augmenter's contribution to the sidecar.
///
/// `Decodable` is implemented explicitly so we can throw a specific
/// `UnknownKind` error when the raw `kind` value isn't recognized —
/// `TKSidecar`'s decoder catches that one error and drops the entry,
/// achieving forward compatibility (a future build with a new kind
/// can write sidecars that today's build still reads).
public struct TKAugmentation: Codable, Sendable {
    public let kind: TKAugmenterKind
    /// Free-form version string identifying the augmenter that produced
    /// this entry (e.g. `"vision-v1"`, `"whisper-large-v3"`). Used by
    /// the catch-up sweep to decide if an entry should be re-run after
    /// the augmenter ships a new version.
    public let version: String
    /// When the augmenter ran. NOT the same as the asset's `capturedAt`.
    public let ranAt: Date
    /// Augmenter-specific JSON payload. Typed as `AnyCodable` so the
    /// envelope shape is stable while each augmenter owns its data
    /// schema in its own file.
    public let data: TKAugmentationData

    public init(kind: TKAugmenterKind, version: String, ranAt: Date = Date(), data: TKAugmentationData) {
        self.kind = kind
        self.version = version
        self.ranAt = ranAt
        self.data = data
    }

    /// Thrown when a stored augmentation has a `kind` raw value not
    /// recognized by the current `TKAugmenterKind` enum. Internal to
    /// the kit — `TKSidecar`'s decoder catches it and skips the entry.
    struct UnknownKind: Error {
        let rawKind: String
    }

    enum CodingKeys: String, CodingKey {
        case kind, version, ranAt, data
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try c.decode(String.self, forKey: .kind)
        guard let kind = TKAugmenterKind(rawValue: rawKind) else {
            throw UnknownKind(rawKind: rawKind)
        }
        self.kind = kind
        self.version = try c.decode(String.self, forKey: .version)
        self.ranAt = try c.decode(Date.self, forKey: .ranAt)
        self.data = try c.decode(TKAugmentationData.self, forKey: .data)
    }
}

/// Type-erased JSON payload — encodes whatever the augmenter wants
/// without forcing every augmenter to thread a concrete generic through
/// `TKSidecar`. Augmenter implementations build a typed model, encode
/// it into this, and decoders that care about the kind decode back.
public struct TKAugmentationData: Codable, Sendable {
    public let jsonData: Data

    public init(jsonData: Data) {
        self.jsonData = jsonData
    }

    public init<T: Encodable>(encoding value: T, encoder: JSONEncoder = .init()) throws {
        self.jsonData = try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = .init()) throws -> T {
        try decoder.decode(type, from: jsonData)
    }

    // MARK: Codable — passes through the inner JSON
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        self.jsonData = try JSONEncoder().encode(value)
    }

    public func encode(to encoder: Encoder) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// The kind of primary asset the sidecar is describing.
public enum TKSidecarAssetKind: String, Codable, Sendable {
    case audio
    case image
}

/// Identifies the primary asset the sidecar belongs to. The sidecar
/// stores enough to detect drift (filename mismatch, hash mismatch) on
/// load, so consumers can flag stale sidecars.
public struct TKSidecarAsset: Codable, Sendable {
    public let kind: TKSidecarAssetKind
    /// Basename of the primary asset (no directory, with extension).
    public let filename: String
    /// SHA-256 of the primary asset bytes at the time the sidecar was
    /// written. Optional because hashing a multi-GB file is expensive;
    /// augmenters may skip it.
    public let sha256: String?

    public init(kind: TKSidecarAssetKind, filename: String, sha256: String? = nil) {
        self.kind = kind
        self.filename = filename
        self.sha256 = sha256
    }
}

/// One sidecar file. Lives at `<asset-dir>/.tk/<basename>.json`.
public struct TKSidecar: Codable, Sendable {
    /// Bump when the envelope shape changes. Augmenter payload schemas
    /// version independently via `TKAugmentation.version`.
    public static let currentSchema: Int = 1

    public let schema: Int
    public let asset: TKSidecarAsset
    public var augmentations: [TKAugmentation]

    public init(asset: TKSidecarAsset, augmentations: [TKAugmentation] = []) {
        self.schema = Self.currentSchema
        self.asset = asset
        self.augmentations = augmentations
    }

    /// Returns the entry of the given kind, if present. Latest wins if
    /// multiple are stored (which shouldn't happen — `upsert` replaces).
    public func entry(of kind: TKAugmenterKind) -> TKAugmentation? {
        augmentations.last { $0.kind == kind }
    }

    public mutating func upsert(_ augmentation: TKAugmentation) {
        augmentations.removeAll { $0.kind == augmentation.kind }
        augmentations.append(augmentation)
    }

    // MARK: - Codable
    //
    // Custom `init(from:)` does lossy decoding of the `augmentations`
    // array — entries with unknown `kind` raw values are dropped,
    // not thrown. Forward compatibility: a future build can write a
    // sidecar with new kinds, today's build still reads the file.

    enum CodingKeys: String, CodingKey {
        case schema, asset, augmentations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = try c.decode(Int.self, forKey: .schema)
        self.asset = try c.decode(TKSidecarAsset.self, forKey: .asset)

        // Decode the augmentations array as raw `JSONValue`s first,
        // then re-encode + decode each individually into a typed
        // `TKAugmentation`. Entries with unknown `kind` (or any other
        // schema mismatch on a new payload) are silently dropped.
        // Going through `[JSONValue]` avoids relying on JSONDecoder's
        // cursor-advance behavior when a sub-decode throws mid-array.
        let raws = try c.decode([JSONValue].self, forKey: .augmentations)
        let encoder = JSONEncoder()
        let inner = JSONDecoder()
        inner.dateDecodingStrategy = .iso8601
        var collected: [TKAugmentation] = []
        for raw in raws {
            guard let data = try? encoder.encode(raw),
                  let entry = try? inner.decode(TKAugmentation.self, from: data) else {
                continue
            }
            collected.append(entry)
        }
        self.augmentations = collected
    }
}

// MARK: - JSONValue (round-trips arbitrary JSON through Codable)

/// Minimal JSON AST used so `TKAugmentationData` can round-trip
/// arbitrary augmenter payloads through Codable without forcing every
/// augmenter to share a single concrete schema. Public because consumers
/// of the kit may want to introspect a sidecar without decoding to a
/// concrete payload type.
public enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self)   { self = .bool(b); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:        try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
