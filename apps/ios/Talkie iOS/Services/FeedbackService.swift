//
//  FeedbackService.swift
//  Talkie iOS
//
//  Network-backed feedback submission for the Next feedback surface.
//

import Foundation
import UIKit

@MainActor
enum FeedbackService {
    private static let endpoint = URL(string: "https://api.usetalkie.com/api/report")!

    static func submit(description: String, contact: String?) async throws -> String {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            throw FeedbackServiceError.emptyDescription
        }

        let trimmedContact = contact?.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = FeedbackReportPayload(
            id: generateLocalReportID(),
            timestamp: ISO8601DateFormatter().string(from: Date()),
            system: systemInfo(),
            apps: appInfo(),
            context: FeedbackContextPayload(
                source: "talkie-ios",
                userDescription: trimmedDescription,
                contactInfo: trimmedContact?.isEmpty == false ? trimmedContact : nil,
                appVersion: appVersion,
                iosVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.modelIdentifier
            ),
            logs: recentLogLines(limit: 50)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(report)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let serverResponse = try? JSONDecoder().decode(FeedbackSubmissionResponse.self, from: data),
               let message = serverResponse.error,
               !message.isEmpty {
                throw FeedbackServiceError.server(message)
            }
            throw FeedbackServiceError.server("Feedback failed with HTTP \(httpResponse.statusCode).")
        }

        let decoded = try JSONDecoder().decode(FeedbackSubmissionResponse.self, from: data)
        guard decoded.success != false else {
            throw FeedbackServiceError.server(decoded.error ?? "Feedback submission failed.")
        }

        if let id = decoded.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        if let key = decoded.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }

        throw FeedbackServiceError.missingReportID
    }

    private static var appVersion: String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
        return "\(shortVersion) (\(buildNumber))"
    }

    private static func systemInfo() -> FeedbackSystemPayload {
        FeedbackSystemPayload(
            os: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.modelIdentifier,
            deviceName: UIDevice.current.name,
            locale: Locale.current.identifier
        )
    }

    private static func appInfo() -> [String: FeedbackAppPayload] {
        [
            "talkie-ios": FeedbackAppPayload(
                running: true,
                pid: ProcessInfo.processInfo.processIdentifier,
                version: appVersion
            )
        ]
    }

    /// LogStore is available in the iOS target; include the newest entries only.
    private static func recentLogLines(limit: Int) -> [String] {
        LogStore.shared.entries.prefix(limit).map { entry in
            let detail = entry.detail.map { " | \(redactForFeedback($0))" } ?? ""
            return "\(entry.formattedTime) [\(entry.level.rawValue)] \(entry.category): \(redactForFeedback(entry.message))\(detail)"
        }
    }

    private static func generateLocalReportID() -> String {
        "IOS-" + String(UUID().uuidString.prefix(8)).uppercased()
    }

    private static func redactForFeedback(_ text: String) -> String {
        var redacted = text
        redacted = replaceMatches(
            in: redacted,
            pattern: #"/Users/[^/\s|\"']+"#,
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
        return redacted
    }

    private static func replaceMatches(
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

private struct FeedbackReportPayload: Codable {
    let id: String
    let timestamp: String
    let system: FeedbackSystemPayload
    let apps: [String: FeedbackAppPayload]
    let context: FeedbackContextPayload
    let logs: [String]
}

private struct FeedbackSystemPayload: Codable {
    let os: String
    let osVersion: String
    let deviceModel: String
    let deviceName: String
    let locale: String?
}

private struct FeedbackAppPayload: Codable {
    let running: Bool
    let pid: Int32?
    let version: String?
}

private struct FeedbackContextPayload: Codable {
    let source: String
    let userDescription: String?
    let contactInfo: String?
    let appVersion: String
    let iosVersion: String
    let deviceModel: String
}

private struct FeedbackSubmissionResponse: Codable {
    let success: Bool?
    let id: String?
    let key: String?
    let error: String?
}

enum FeedbackServiceError: LocalizedError {
    case emptyDescription
    case invalidResponse
    case missingReportID
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyDescription:
            return "Describe what happened before sending feedback."
        case .invalidResponse:
            return "Talkie received an invalid feedback response."
        case .missingReportID:
            return "Talkie submitted feedback but did not receive a report ID."
        case .server(let message):
            return message
        }
    }
}
