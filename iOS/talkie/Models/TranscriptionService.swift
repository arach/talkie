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
            print("No filename for transcription")
            return
        }

        // Build full path from filename
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsPath.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Audio file doesn't exist at \(url.path)")
            return
        }

        // Store the objectID to fetch in the background context
        let memoObjectID = memo.objectID

        // Set transcribing flag on main context
        context.perform {
            guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else { return }
            memo.isTranscribing = true
            try? context.save()
            print("Starting transcription for: \(filename)")
        }

        // Do transcription work
        transcribe(audioURL: url) { [weak context] result in
            guard let context = context else { return }

            // Save transcription on main context
            context.perform {
                // Fetch the memo in this context using objectID
                guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else {
                    print("Failed to fetch memo in background context")
                    return
                }

                switch result {
                case .success(let transcription):
                    print("Transcription succeeded: \(transcription.prefix(50))...")
                    memo.transcription = transcription
                    memo.isTranscribing = false

                case .failure(let error):
                    print("Transcription failed: \(error.localizedDescription)")
                    memo.isTranscribing = false
                }

                do {
                    try context.save()
                    print("Transcription saved successfully to Core Data")
                } catch {
                    print("Failed to save transcription: \(error.localizedDescription)")
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
