//
//  FeedbackReporter.swift
//  Talkie iOS
//
//  Lightweight reporter for iOS — gathers logs from LogStore,
//  system info, and submits to the same API as macOS.
//

import Foundation
import UIKit

/// iOS-adapted reporter that submits feedback to api.usetalkie.com
@MainActor
final class FeedbackReporter {
    static let shared = FeedbackReporter()

    private let endpoint = "https://api.usetalkie.com/api/report"
    private var lastSubmitTime: Date?
    private let minSubmitInterval: TimeInterval = 60

    private init() {}

    /// Submit a feedback report with logs and system info
    func submit(
        description: String,
        contactInfo: String? = nil
    ) async throws -> FeedbackResponse {
        // Rate limiting
        if let lastTime = lastSubmitTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minSubmitInterval {
                throw FeedbackError.rateLimited(retryAfter: minSubmitInterval - elapsed)
            }
        }

        let report = buildReport(description: description, contactInfo: contactInfo)

        guard let url = URL(string: endpoint) else {
            throw FeedbackError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(report)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? JSONDecoder().decode(FeedbackResponse.self, from: data) {
                throw FeedbackError.serverError(errorResponse.error ?? "Unknown error")
            }
            throw FeedbackError.serverError("HTTP \(httpResponse.statusCode)")
        }

        lastSubmitTime = Date()
        return try JSONDecoder().decode(FeedbackResponse.self, from: data)
    }

    /// Gather recent logs with user-authored prompt/transcript content redacted.
    func getRecentLogs(count: Int = 200) -> [String] {
        let entries = LogStore.shared.entries.suffix(count)
        return entries.reversed().map { entry in
            let message = redactForFeedback(entry.message)
            let detail = entry.detail.map { " | \(redactForFeedback($0))" } ?? ""
            return "\(entry.formattedTime) [\(entry.level.rawValue)] \(entry.category): \(message)\(detail)"
        }
    }

    // MARK: - Private

    private func buildReport(description: String, contactInfo: String?) -> FeedbackReport {
        let id = generateShortId()
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let system = FeedbackSystemInfo(
            os: "iOS",
            osVersion: osVersionString,
            chip: UIDevice.modelIdentifier,
            memory: "\(processInfo.physicalMemory / (1024 * 1024 * 1024)) GB",
            locale: Locale.current.identifier
        )

        let apps: [String: FeedbackAppInfo] = [
            "talkie-ios": FeedbackAppInfo(
                running: true,
                pid: processInfo.processIdentifier,
                version: "\(appVersion) (\(buildNumber))"
            )
        ]

        let context = FeedbackContext(
            source: "talkie-ios",
            userDescription: description,
            contactInfo: contactInfo
        )

        return FeedbackReport(
            id: id,
            timestamp: timestamp,
            system: system,
            apps: apps,
            context: context,
            logs: getRecentLogs()
        )
    }

    private func generateShortId() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).compactMap { _ in chars.randomElement() })
    }

    private func redactForFeedback(_ text: String) -> String {
        var redacted = text
        redacted = replaceMatches(
            in: redacted,
            pattern: #"/Users/[^/\s|"']+"#,
            withTemplate: "/Users/***"
        )
        redacted = replaceMatches(
            in: redacted,
            pattern: #"([?&](?:prompt|systemPrompt|userPrompt|llmPrompt|promptTemplate|transcript|transcription|text|content|message|query|q)=)([^&\s]+)"#,
            withTemplate: "$1[redacted]",
            options: [.caseInsensitive]
        )
        redacted = replaceMatches(
            in: redacted,
            pattern: #"(\"(?:prompt|systemPrompt|userPrompt|llmPrompt|promptTemplate|llmPromptTemplate|transcript|transcription|transcriptExcerpt|rawText|inputTranscript|insertedText|selectedText|capturedTranscription|userMessage|message|content|text|title|body)\"\s*:\s*\")((?:\\.|[^\"\\])*)(\")"#,
            withTemplate: "$1[redacted]$3",
            options: [.caseInsensitive]
        )

        let sensitiveLabels = #"(?:(?:system|user|llm)\s*)?prompt(?:\s*template)?|promptTemplate|llmPromptTemplate|transcript(?:ion)?|transcriptExcerpt|transcribed|rawText|inputTranscript|insertedText|selectedText|capturedTranscription|userMessage"#
        redacted = replaceMatches(
            in: redacted,
            pattern: #"\b("# + sensitiveLabels + #")(\s*[:=]\s*)(.+?)(?=(?:[,&]\s*[A-Za-z][A-Za-z0-9_ ]{0,32}\s*[:=])|(?:\s*\(\d+[^)]*\)\s*$)|(?:\.\.\.\s*$)|$)"#,
            withTemplate: "$1$2[redacted]",
            options: [.caseInsensitive]
        )
        redacted = replaceMatches(
            in: redacted,
            pattern: #"\b((?:Apple Speech|Whisper|Parakeet|SpeechAnalyzer)?\s*transcription\s+(?:complete|completed|succeeded|success):\s*)(.+?)(?=(?:\.\.\.\s*$)|(?:,\s*[A-Za-z][A-Za-z0-9_ ]{0,32}\s*[:=])|$)"#,
            withTemplate: "$1[redacted]",
            options: [.caseInsensitive]
        )
        return redacted
    }

    private func replaceMatches(
        in text: String,
        pattern: String,
        withTemplate template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

// MARK: - Models (match macOS TalkieReport structure for API compatibility)

struct FeedbackReport: Codable {
    let id: String
    let timestamp: String
    let system: FeedbackSystemInfo
    let apps: [String: FeedbackAppInfo]
    let context: FeedbackContext
    let logs: [String]
}

struct FeedbackSystemInfo: Codable {
    let os: String
    let osVersion: String
    let chip: String
    let memory: String
    let locale: String?
}

struct FeedbackAppInfo: Codable {
    let running: Bool
    let pid: Int32?
    let version: String?
}

struct FeedbackContext: Codable {
    let source: String
    let userDescription: String?
    let contactInfo: String?
}

struct FeedbackResponse: Codable {
    let success: Bool
    let id: String?
    let key: String?
    let error: String?
}

enum FeedbackError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .serverError(let msg): return msg
        case .rateLimited(let retry): return "Please wait \(Int(retry)) seconds before submitting again."
        }
    }
}
