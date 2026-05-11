//
//  CaptureSyncService.swift
//  Talkie iOS
//
//  Opportunistic sync of captures to Mac via bridge.
//  After sync, requests TTS audio from Mac's OpenAI key.
//  Triggered on: new capture, app foreground, bridge reconnect.
//

import Foundation
import TalkieMobileKit

@MainActor
final class CaptureSyncService {
    static let shared = CaptureSyncService()

    private var isSyncing = false
    private var observer: NSObjectProtocol?

    private init() {
        // Auto-sync when bridge connects
        observer = NotificationCenter.default.addObserver(
            forName: .bridgeDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncIfConnected()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Try to send all unsynced captures to Mac, then fetch TTS audio
    func syncIfConnected() {
        guard !isSyncing else {
            AppLogger.app.debug("CaptureSyncService: skipped — already syncing")
            return
        }

        let bridgeStatus = BridgeManager.shared.status
        guard bridgeStatus == .connected else {
            AppLogger.app.info("CaptureSyncService: bridge not connected (status: \(bridgeStatus.rawValue))")
            return
        }

        let unsynced = CaptureStore.shared.unsyncedCaptures()
        guard !unsynced.isEmpty else {
            // Even if all synced, check for missing audio
            Task { await fetchMissingAudio() }
            return
        }

        isSyncing = true
        AppLogger.app.info("CaptureSyncService: syncing \(unsynced.count) captures")

        Task {
            defer { isSyncing = false }

            for capture in unsynced {
                do {
                    // Load image data if this is a photo capture
                    var imageBase64: String?
                    if let filename = capture.imageFilename,
                       let imageData = CaptureStore.shared.loadImageData(filename: filename) {
                        imageBase64 = imageData.base64EncodedString()
                    }

                    let request = IngestRequest(
                        sourceType: capture.sourceType == "photo" ? "ocr" : capture.sourceType,
                        text: capture.text,
                        title: capture.title,
                        sourceURL: capture.sourceURL,
                        imageBase64: imageBase64,
                        imageFilename: capture.imageFilename,
                        bookmarkCanonicalURL: capture.bookmark?.canonicalURL,
                        bookmarkHost: capture.bookmark?.host,
                        bookmarkSiteName: capture.bookmark?.siteName,
                        bookmarkSummary: capture.bookmark?.summary,
                        bookmarkImageURL: capture.bookmark?.imageURL,
                        sourceApplicationBundleID: capture.bookmark?.sourceApplicationBundleID,
                        sourceApplicationName: capture.bookmark?.sourceApplicationName,
                        sourceDevice: capture.bookmark?.sourceDevice,
                        ingestMethod: capture.bookmark?.ingestionMethod
                    )

                    let response = try await BridgeManager.shared.client.ingestContent(body: request)
                    if response.ok {
                        CaptureStore.shared.markSynced(capture.id)
                        AppLogger.app.info("Capture synced: \(capture.id) → \(response.objectId ?? "?")")
                    } else {
                        AppLogger.app.warning("Capture sync failed: \(response.error ?? "unknown")")
                    }
                } catch {
                    AppLogger.app.warning("Capture sync error for \(capture.id): \(error.localizedDescription)")
                }
            }

            // After sync, fetch TTS audio for captures that don't have it yet
            await fetchMissingAudio()
        }
    }

    // MARK: - TTS Audio Fetching

    /// Request TTS audio from Mac for captures that don't have cached audio
    private func fetchMissingAudio() async {
        guard BridgeManager.shared.status == .connected else { return }

        let captures = CaptureStore.shared.all()
        let needsAudio = captures.filter { capture in
            !capture.text.isEmpty &&
            capture.syncedToMac &&
            CaptureStore.shared.audioURL(for: capture.id) == nil
        }

        guard !needsAudio.isEmpty else { return }
        AppLogger.app.info("CaptureSyncService: fetching TTS for \(needsAudio.count) captures")

        for capture in needsAudio {
            do {
                let audioData = try await TTSService.synthesizeConfigured(text: capture.text)
                if let url = CaptureStore.shared.saveAudio(audioData, id: capture.id) {
                    AppLogger.app.info("TTS audio cached: \(capture.id) (\(audioData.count) bytes)")
                    NotificationCenter.default.post(name: .capturesDidChange, object: nil)
                }
            } catch {
                AppLogger.app.warning("TTS fetch error for \(capture.id): \(error.localizedDescription)")
            }
        }
    }
}
