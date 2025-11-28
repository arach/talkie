//
//  TranscriptionService.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import Foundation
import Speech
import CoreData
import AVFoundation

class TranscriptionService {

    static let shared = TranscriptionService()

    private init() {}

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func transcribe(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let recognizer = SFSpeechRecognizer() else {
            completion(.failure(TranscriptionError.recognizerNotAvailable))
            return
        }

        guard recognizer.isAvailable else {
            completion(.failure(TranscriptionError.recognizerNotAvailable))
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let result = result else {
                completion(.failure(TranscriptionError.noResult))
                return
            }

            if result.isFinal {
                completion(.success(result.bestTranscription.formattedString))
            }
        }
    }

    func transcribeVoiceMemo(_ memo: VoiceMemo, context: NSManagedObjectContext) {
        guard let filename = memo.fileURL else {
            AppLogger.transcription.warning("No filename for transcription")
            return
        }

        // Build full path from filename
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsPath.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.transcription.warning("Audio file doesn't exist at \(url.path)")
            return
        }

        // Store the objectID to fetch in the background context
        let memoObjectID = memo.objectID

        // Set transcribing flag on main context
        context.perform {
            guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else { return }
            memo.isTranscribing = true
            try? context.save()
            AppLogger.transcription.info("Starting transcription for: \(filename)")
        }

        // Do transcription work
        transcribe(audioURL: url) { [weak context] result in
            guard let context = context else { return }

            // Save transcription on main context
            context.perform {
                // Fetch the memo in this context using objectID
                guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else {
                    AppLogger.transcription.error("Failed to fetch memo in background context")
                    return
                }

                switch result {
                case .success(let transcription):
                    AppLogger.transcription.info("Transcription succeeded: \(transcription.prefix(50))...")
                    // Create versioned transcript (also sets legacy field for compatibility)
                    memo.addSystemTranscript(
                        content: transcription,
                        fromMacOS: false,
                        engine: TranscriptEngines.appleSpeech
                    )
                    memo.isTranscribing = false

                case .failure(let error):
                    AppLogger.transcription.error("Transcription failed: \(error.localizedDescription)")
                    memo.isTranscribing = false
                }

                do {
                    try context.save()
                    AppLogger.persistence.info("Transcription saved successfully to Core Data")
                } catch {
                    AppLogger.persistence.error("Failed to save transcription: \(error.localizedDescription)")
                }
            }
        }
    }
}

enum TranscriptionError: Error {
    case recognizerNotAvailable
    case noResult

    var localizedDescription: String {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .noResult:
            return "No transcription result"
        }
    }
}
