//
//  MediaAugmentationService.swift
//  TalkieKit
//
//  Fire-and-forget pipeline that runs zero or more `Augmenter`s against
//  a primary asset (audio or image) and writes the results into
//  `<asset-dir>/.tk/<basename>.json`. Runs off the critical capture and
//  transcription-insertion paths — callers `enqueue(...)` and walk
//  away; the service never returns a result.
//
//  Design notes (matching the user's framing 2026-05-25):
//   - Two protected paths must stay untouched:
//       1. screenshot → drag handle ready
//       2. screenshot → insertion into a transcription
//     Augmentation hooks fire AFTER each of those has done its work.
//   - Outputs are purely additive. Augmenters that fail leave the
//     sidecar partially populated; absence of a kind is graceful for
//     all consumers.
//   - Serial queue, `.utility` priority — burst captures don't pin the
//     machine doing OCR + AX walks in parallel.
//   - Catch-up sweep (TODO follow-up): on app startup, scan asset
//     directories for primary files whose sidecars are missing the
//     expected augmenter kinds and enqueue them.
//

import Foundation

/// Identifies the asset being augmented + its on-disk URL. Augmenters
/// receive this so they can read the primary asset, but they MUST NOT
/// mutate it.
public struct AugmentationTask: Sendable {
    public let assetURL: URL
    public let assetKind: TKSidecarAssetKind
    /// Optional context the caller hands in at enqueue time — e.g. the
    /// AX reference of the captured window, the recording ID this asset
    /// belongs to, the screen backing scale. Augmenters read what they
    /// need and ignore the rest.
    public let context: TKAugmentationContext

    public init(assetURL: URL, assetKind: TKSidecarAssetKind, context: TKAugmentationContext = .init()) {
        self.assetURL = assetURL
        self.assetKind = assetKind
        self.context = context
    }
}

/// Free-form context bag passed from the enqueue site to each augmenter.
/// Augmenter-specific keys are namespaced (e.g. `window.title`,
/// `screen.backingScale`); a missing key means the augmenter should
/// either skip or fall back to its own discovery.
public struct TKAugmentationContext: Sendable {
    public var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

/// A single augmenter — produces one `TKAugmentation` from an asset.
/// Returning nil means "I had nothing to contribute" (e.g. OCR found no
/// text). Throwing means "I tried and failed" — the service logs and
/// moves on; the sidecar simply doesn't get an entry for this kind.
public protocol Augmenter: Sendable {
    var kind: TKAugmenterKind { get }
    var version: String { get }
    /// Asset kinds this augmenter supports. The service filters before
    /// invoking, so OCR doesn't get audio files etc.
    var supportedAssetKinds: Set<TKSidecarAssetKind> { get }
    func run(_ task: AugmentationTask) async throws -> TKAugmentation?
}

private let log = Log(.system)

/// Fire-and-forget orchestrator. Holds a serial actor-isolated queue so
/// a burst of enqueues doesn't fan out into parallel CPU-heavy work.
public actor MediaAugmentationService {
    public static let shared = MediaAugmentationService()

    private var augmenters: [Augmenter] = []
    private var pending: [AugmentationTask] = []
    private var draining = false

    private init() {}

    /// Register an `Augmenter`. Idempotent on `(kind, version)`. Call
    /// once at app launch from the consumer (the augmenter
    /// implementations live in the main app — OCR uses AppKit, AX uses
    /// the Accessibility API, both outside TalkieKit).
    public func register(_ augmenter: Augmenter) {
        augmenters.removeAll { $0.kind == augmenter.kind && $0.version == augmenter.version }
        augmenters.append(augmenter)
    }

    /// Enqueue a task. Returns immediately. The service runs the task
    /// in the background at utility priority; the caller never awaits
    /// the result. Safe to call from any actor / context.
    nonisolated public func enqueue(_ task: AugmentationTask) {
        Task {
            await self._enqueue(task)
        }
    }

    private func _enqueue(_ task: AugmentationTask) {
        pending.append(task)
        if !draining {
            draining = true
            Task.detached(priority: .utility) { [weak self] in
                await self?.drain()
            }
        }
    }

    private func drain() async {
        // Loop until the actor-isolated `popNextOrFinish` returns nil,
        // which also flips `draining = false` in the same isolation
        // step. This closes the race where a late `_enqueue` could
        // append after the empty check but before we mark the drainer
        // gone — appending while `draining == true` is fine because
        // the loop iterates again; appending while `draining == false`
        // starts a fresh detached drainer. There is no window between.
        while let task = await popNextOrFinish() {
            await runTask(task)
        }
    }

    /// Atomically (under actor isolation) either pop the next pending
    /// task OR mark the drainer as finished and return nil. Never both.
    private func popNextOrFinish() -> AugmentationTask? {
        if pending.isEmpty {
            draining = false
            return nil
        }
        return pending.removeFirst()
    }

    private func runTask(_ task: AugmentationTask) async {
        // Guard: if the primary asset is gone by the time we get here
        // (deleted from the tray while queued, hard-deleted recording,
        // etc.), there's nothing to augment. Without this an augmenter
        // like WindowMetaAugmenter — which reads only from context, not
        // the file — would still write an orphan sidecar for a missing
        // asset.
        guard FileManager.default.fileExists(atPath: task.assetURL.path) else {
            // Also clean up any pre-existing sidecar so we don't leave
            // an orphan after a slow-running augmenter finally exits.
            TKSidecarStore.delete(forAsset: task.assetURL)
            return
        }

        let applicable = augmenters.filter { $0.supportedAssetKinds.contains(task.assetKind) }
        guard !applicable.isEmpty else { return }

        // Skip augmenters whose (kind, version) is already in the
        // sidecar — keeps the catch-up sweep idempotent and makes
        // re-enqueues from accidental double-calls a no-op. To force
        // re-running an augmenter, bump its `version` string.
        let existing = (try? TKSidecarStore.read(forAsset: task.assetURL))?.augmentations ?? []
        let havePairs = Set(existing.map { "\($0.kind.rawValue):\($0.version)" })

        for augmenter in applicable {
            let pair = "\(augmenter.kind.rawValue):\(augmenter.version)"
            if havePairs.contains(pair) { continue }

            do {
                guard let result = try await augmenter.run(task) else { continue }
                // Re-check existence after the augmenter ran — closes
                // the window where the asset was deleted while a slow
                // augmenter (OCR on a large image, future audio
                // transcript pass) was in flight. Without this we'd
                // recreate the sidecar for a primary asset that's no
                // longer on disk.
                guard FileManager.default.fileExists(atPath: task.assetURL.path) else {
                    TKSidecarStore.delete(forAsset: task.assetURL)
                    return
                }
                try TKSidecarStore.upsertAugmentation(
                    result,
                    forAsset: task.assetURL,
                    assetKind: task.assetKind
                )
            } catch {
                log.error("augmenter failed", detail: "\(augmenter.kind.rawValue): \(error.localizedDescription)")
            }
        }
    }
}
