//
//  TalkieWorkflowAPIConfiguration.swift
//  Talkie iOS
//
//  Forward-path host resolution for the dedicated live workflow API.
//

import Foundation

enum TalkieWorkflowAPIConfiguration {
    private static let environmentKey = "TALKIE_WORKFLOW_API_BASE_URL"
    private static let infoDictionaryKey = "TalkieWorkflowAPIBaseURL"
    private static let defaultBaseURL = "https://api.talkie.to"

    static var baseURL: String {
        if let override = ProcessInfo.processInfo.environment[environmentKey]?.trimmedForURLOverride {
            return override
        }

        if let override = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
           let trimmed = override.trimmedForURLOverride {
            return trimmed
        }

        return defaultBaseURL
    }
}

private extension String {
    var trimmedForURLOverride: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
