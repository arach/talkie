//
//  OnDeviceAIService.swift
//  Talkie
//
//  On-device AI processing using Apple Foundation Models (iOS 26+)
//  Falls back gracefully when not available
//

import Foundation
import CoreData
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for on-device AI processing using Apple Intelligence
@MainActor
class OnDeviceAIService: ObservableObject {

    static let shared = OnDeviceAIService()

    @Published var isProcessing = false
    @Published var isAvailable = false

    private init() {
        Task {
            await checkAvailability()
        }
    }

    /// Check if on-device AI is available
    func checkAvailability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let availability = LanguageModelSession.availability
            isAvailable = availability == .available
            AppLogger.ai.info("On-device AI availability: \(String(describing: availability))")
        } else {
            isAvailable = false
            AppLogger.ai.info("On-device AI: Requires iOS 26+")
        }
        #else
        isAvailable = false
        AppLogger.ai.info("On-device AI: FoundationModels not available on this platform")
        #endif
    }

    /// Generate a smart title for a voice memo based on its transcript
    func generateSmartTitle(for transcript: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        guard #available(iOS 26.0, *) else {
            throw OnDeviceAIError.notAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

        let prompt = """
        Generate a short, descriptive title (3-6 words) for this voice memo transcript. \
        The title should capture the main topic or purpose. \
        Return ONLY the title, no quotes or extra text.

        Transcript:
        \(transcript.prefix(2000))
        """

        let response = try await session.respond(to: prompt)
        let title = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        AppLogger.ai.info("Generated smart title: \(title)")
        return title
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Generate a brief summary of a voice memo
    func generateSummary(for transcript: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        guard #available(iOS 26.0, *) else {
            throw OnDeviceAIError.notAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

        let prompt = """
        Summarize this voice memo in 2-3 sentences. Focus on the key points and action items.

        Transcript:
        \(transcript.prefix(4000))
        """

        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Extract action items/tasks from a voice memo
    func extractTasks(from transcript: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else {
            throw OnDeviceAIError.notAvailable
        }

        guard #available(iOS 26.0, *) else {
            throw OnDeviceAIError.notAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        let session = LanguageModelSession()

        let prompt = """
        Extract any action items or tasks mentioned in this voice memo. \
        List them as bullet points. If no tasks are found, say "No tasks identified."

        Transcript:
        \(transcript.prefix(4000))
        """

        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw OnDeviceAIError.notAvailable
        #endif
    }

    /// Apply smart title to a VoiceMemo
    func applySmartTitle(to memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        let title = try await generateSmartTitle(for: transcript)

        await MainActor.run {
            memo.title = title
            try? context.save()
            AppLogger.ai.info("Applied smart title to memo: \(title)")
        }
    }

    /// Generate and save summary for a VoiceMemo
    func applySummary(to memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        await MainActor.run {
            memo.isProcessingSummary = true
            try? context.save()
        }

        defer {
            Task { @MainActor in
                memo.isProcessingSummary = false
                try? context.save()
            }
        }

        let summary = try await generateSummary(for: transcript)

        await MainActor.run {
            memo.summary = summary
            try? context.save()
            AppLogger.ai.info("Applied summary to memo")
        }
    }

    /// Generate and save tasks for a VoiceMemo
    func applyTasks(to memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw OnDeviceAIError.noTranscript
        }

        await MainActor.run {
            memo.isProcessingTasks = true
            try? context.save()
        }

        defer {
            Task { @MainActor in
                memo.isProcessingTasks = false
                try? context.save()
            }
        }

        let tasks = try await extractTasks(from: transcript)

        await MainActor.run {
            memo.tasks = tasks
            try? context.save()
            AppLogger.ai.info("Applied tasks to memo")
        }
    }
}

enum OnDeviceAIError: LocalizedError {
    case notAvailable
    case noTranscript
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "On-device AI is not available. Requires iOS 26+ with Apple Intelligence enabled."
        case .noTranscript:
            return "No transcript available. Please wait for transcription to complete."
        case .generationFailed(let reason):
            return "AI generation failed: \(reason)"
        }
    }
}
