//
//  RecordingSidecarProcessor.swift
//  Talkie iOS
//
//  Resolves queued sidecar requests once a transcript is available.
//

import Foundation

@MainActor
final class RecordingSidecarProcessor {
    static let shared = RecordingSidecarProcessor()

    private let store = RecordingSidecarStore.shared
    private var activeMemoIds: Set<String> = []

    private init() {}

    func processQueuedRequests(
        memoId: String,
        memoTitle: String,
        transcript: String,
        duration: TimeInterval,
        retryFailed: Bool = false
    ) async {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return }
        guard !activeMemoIds.contains(memoId) else { return }

        let pendingRequests = store.requests(for: memoId).filter { request in
            switch request.status {
            case .queued:
                return true
            case .failed:
                return retryFailed
            case .processing, .completed:
                return false
            }
        }

        guard !pendingRequests.isEmpty else { return }

        await OnDeviceAIService.shared.checkAvailability()
        guard OnDeviceAIService.shared.isAvailable else {
            AppLogger.ai.info("Recording sidecar skipped: on-device AI unavailable")
            return
        }

        activeMemoIds.insert(memoId)
        defer { activeMemoIds.remove(memoId) }

        for request in pendingRequests {
            store.updateRequest(memoId: memoId, requestId: request.id) { current in
                current.status = .processing
                current.failureMessage = nil
            }

            let excerpt = excerptForRequest(
                request,
                transcript: trimmedTranscript,
                duration: duration
            )

            do {
                let output = try await OnDeviceAIService.shared.generateRecordingSidecarOutput(
                    kind: request.kind,
                    memoTitle: memoTitle,
                    transcriptExcerpt: excerpt,
                    note: request.note,
                    queuedAtOffset: request.queuedAtOffset
                )

                store.updateRequest(memoId: memoId, requestId: request.id) { current in
                    current.status = .completed
                    current.output = output
                    current.transcriptExcerpt = excerpt
                    current.failureMessage = nil
                    current.resolvedAt = Date()
                }
            } catch {
                store.updateRequest(memoId: memoId, requestId: request.id) { current in
                    current.status = .failed
                    current.transcriptExcerpt = excerpt
                    current.failureMessage = error.localizedDescription
                    current.resolvedAt = nil
                }
            }
        }
    }

    private func excerptForRequest(
        _ request: RecordingSidecarRequest,
        transcript: String,
        duration: TimeInterval
    ) -> String {
        let words = transcript.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return transcript }
        guard words.count > 80, duration > 0 else { return transcript }

        let clampedRatio = min(max(request.queuedAtOffset / duration, 0), 1)
        let centerIndex = Int((Double(words.count - 1) * clampedRatio).rounded())
        let radius = 70
        let lowerBound = max(0, centerIndex - radius)
        let upperBound = min(words.count, centerIndex + radius)

        let excerptWords = words[lowerBound..<upperBound].map(String.init)
        var excerpt = excerptWords.joined(separator: " ")

        if lowerBound > 0 {
            excerpt = "… " + excerpt
        }

        if upperBound < words.count {
            excerpt += " …"
        }

        return excerpt
    }
}
