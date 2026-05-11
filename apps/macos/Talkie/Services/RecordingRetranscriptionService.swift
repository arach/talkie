//
//  RecordingRetranscriptionService.swift
//  Talkie
//
//  Shared retranscription workflow for memos and dictations.
//

import Foundation
import TalkieKit

private let retranscriptionLog = Log(.transcription)

actor RecordingRetranscriptionService {
    static let shared = RecordingRetranscriptionService()

    enum RetranscriptionError: LocalizedError {
        case memoNotFound(UUID)
        case noAudio(UUID)
        case audioFileMissing(String)

        var errorDescription: String? {
            switch self {
            case .memoNotFound(let id):
                return "Memo not found: \(id.uuidString)"
            case .noAudio(let id):
                return "No audio file available for \(id.uuidString)"
            case .audioFileMissing(let path):
                return "Audio file not found at \(path)"
            }
        }
    }

    private let memoRepository: LocalRepository
    private let recordingRepository: TalkieObjectRepository

    init(
        memoRepository: LocalRepository = LocalRepository(),
        recordingRepository: TalkieObjectRepository = TalkieObjectRepository()
    ) {
        self.memoRepository = memoRepository
        self.recordingRepository = recordingRepository
    }

    func retranscribe(
        _ recording: TalkieObject,
        modelId: String,
        priority: TranscriptionPriority = .medium
    ) async throws -> String {
        guard let audioURL = recording.audioURL else {
            throw RetranscriptionError.noAudio(recording.id)
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw RetranscriptionError.audioFileMissing(audioURL.path)
        }

        let newTranscript = try await EngineClient.shared.transcribe(
            audioPath: audioURL.path,
            modelId: modelId,
            priority: priority,
            postProcess: .inverseTextNormalization
        )

        if recording.isMemo {
            try await persistMemoRetranscription(
                id: recording.id,
                transcript: newTranscript,
                modelId: modelId
            )
        } else {
            try await persistRecordingRetranscription(
                recording: recording,
                transcript: newTranscript,
                modelId: modelId
            )
        }

        retranscriptionLog.info("Retranscribed recording \(recording.id) with \(modelId)")
        return newTranscript
    }

    func retranscribeMemo(
        id: UUID,
        modelId: String,
        priority: TranscriptionPriority = .medium
    ) async throws -> String {
        guard let memo = try await memoRepository.fetchMemo(id: id)?.memo else {
            throw RetranscriptionError.memoNotFound(id)
        }

        return try await retranscribe(
            TalkieObject(from: memo),
            modelId: modelId,
            priority: priority
        )
    }

    func persistFailureState(for recording: TalkieObject, errorMessage: String) async {
        let existingText = recording.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existingText.isEmpty else { return }

        if recording.isMemo {
            do {
                _ = try await recordingRepository.refreshMemoRecordingsMirrorFields()
            } catch {
                retranscriptionLog.error("Failed to refresh memo mirror after retranscription failure: \(error)")
            }
            return
        }

        do {
            var updated = recording
            updated.transcriptionStatus = .failed
            updated.transcriptionError = errorMessage
            updated.lastModified = Date()
            try await recordingRepository.saveRecording(updated)
        } catch {
            retranscriptionLog.error("Failed to persist retranscription failure state: \(error)")
        }
    }

    private func persistMemoRetranscription(
        id: UUID,
        transcript: String,
        modelId: String
    ) async throws {
        guard let memoData = try await memoRepository.fetchMemo(id: id) else {
            throw RetranscriptionError.memoNotFound(id)
        }

        var memo = memoData.memo
        memo.transcription = transcript
        memo.isTranscribing = false
        memo.lastModified = Date()

        try await memoRepository.saveMemo(memo)
        try await saveSupplementalArtifacts(
            recordingId: id,
            title: memo.title,
            transcript: transcript,
            modelId: modelId
        )
        _ = try await recordingRepository.refreshMemoRecordingsMirrorFields()
    }

    private func persistRecordingRetranscription(
        recording: TalkieObject,
        transcript: String,
        modelId: String
    ) async throws {
        var updated = recording
        updated.text = transcript
        updated.transcriptionModel = modelId
        updated.transcriptionStatus = .success
        updated.transcriptionError = nil
        updated.lastModified = Date()

        try await recordingRepository.saveRecording(updated)
        try await saveSupplementalArtifacts(
            recordingId: recording.id,
            title: updated.title,
            transcript: transcript,
            modelId: modelId
        )
    }

    private func saveSupplementalArtifacts(
        recordingId: UUID,
        title: String?,
        transcript: String,
        modelId: String
    ) async throws {
        let engine = engineName(from: modelId)
        try await recordingRepository.saveTranscriptVersion(
            for: recordingId,
            content: transcript,
            sourceType: .systemMacOS,
            engine: engine
        )
        try await recordingRepository.appendContentSnapshot(
            recordingId: recordingId,
            title: title,
            text: transcript,
            source: .transcription
        )
    }

    private func engineName(from modelId: String) -> String {
        modelId.split(separator: ":", maxSplits: 1).last.map(String.init) ?? modelId
    }
}
