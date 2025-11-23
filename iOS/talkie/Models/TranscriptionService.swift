//
//  TranscriptionService.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import Foundation
import Speech
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
        guard let urlString = memo.fileURL,
              let url = URL(string: urlString) else { return }

        memo.isTranscribing = true
        try? context.save()

        transcribe(audioURL: url) { result in
            context.perform {
                switch result {
                case .success(let transcription):
                    memo.transcription = transcription
                    memo.isTranscribing = false

                case .failure(let error):
                    print("Transcription failed: \(error.localizedDescription)")
                    memo.isTranscribing = false
                }

                try? context.save()
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
