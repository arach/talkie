//
//  VoiceIntentBenchmark.swift
//  TalkieKit
//
//  Benchmark tests for VoiceIntentRecognizer.
//  Tests diverse natural language inputs against expected intents.
//

import Foundation

// MARK: - Benchmark Test Case

public struct VoiceIntentTestCase: Codable {
    public let input: String
    public let expected: String

    public init(input: String, expected: String) {
        self.input = input
        self.expected = expected
    }
}

// MARK: - Benchmark Result

public struct VoiceIntentBenchmarkResult {
    public let totalCases: Int
    public let passed: Int
    public let failed: Int
    public let accuracy: Double
    public let failures: [(input: String, expected: String, actual: String, confidence: Float)]
    public let lowConfidence: [(input: String, intent: String, confidence: Float)]

    public var passRate: String {
        String(format: "%.1f%%", accuracy * 100)
    }
}

// MARK: - Voice Intent Benchmark

@MainActor
public final class VoiceIntentBenchmark {
    public static let shared = VoiceIntentBenchmark()

    private init() {}

    /// Run benchmark with all built-in test cases
    public func runFullBenchmark() async -> VoiceIntentBenchmarkResult {
        await run(testCases: Self.testCases)
    }

    /// Run benchmark with custom test cases
    public func run(testCases: [VoiceIntentTestCase]) async -> VoiceIntentBenchmarkResult {
        let recognizer = VoiceIntentRecognizer.shared

        var passed = 0
        var failures: [(String, String, String, Float)] = []
        var lowConfidence: [(String, String, Float)] = []

        for testCase in testCases {
            let result = await recognizer.recognize(testCase.input)
            let actualIntent = result.intent.rawValue

            if actualIntent == testCase.expected {
                passed += 1
                // Track low confidence matches
                if result.confidence < 0.7 {
                    lowConfidence.append((testCase.input, actualIntent, result.confidence))
                }
            } else {
                failures.append((testCase.input, testCase.expected, actualIntent, result.confidence))
            }
        }

        let total = testCases.count
        let accuracy = total > 0 ? Double(passed) / Double(total) : 0

        return VoiceIntentBenchmarkResult(
            totalCases: total,
            passed: passed,
            failed: failures.count,
            accuracy: accuracy,
            failures: failures,
            lowConfidence: lowConfidence
        )
    }

    /// Print benchmark results to console
    public func printResults(_ result: VoiceIntentBenchmarkResult) {
        TalkieLogger.info(.system, "\n" + String(repeating: "=", count: 60))
        TalkieLogger.info(.system, "VOICE INTENT RECOGNITION BENCHMARK")
        TalkieLogger.info(.system, String(repeating: "=", count: 60))
        TalkieLogger.info(.system, "Total: \(result.totalCases) | Passed: \(result.passed) | Failed: \(result.failed)")
        TalkieLogger.info(.system, "Accuracy: \(result.passRate)")
        TalkieLogger.info(.system, String(repeating: "-", count: 60))

        if !result.failures.isEmpty {
            TalkieLogger.info(.system, "\nFAILURES (\(result.failures.count)):")
            for (input, expected, actual, confidence) in result.failures.prefix(20) {
                TalkieLogger.info(.system, "  \"\(input)\"")
                TalkieLogger.info(.system, "    Expected: \(expected) | Got: \(actual) (conf: \(String(format: "%.2f", confidence)))")
            }
            if result.failures.count > 20 {
                TalkieLogger.info(.system, "  ... and \(result.failures.count - 20) more failures")
            }
        }

        if !result.lowConfidence.isEmpty {
            TalkieLogger.info(.system, "\nLOW CONFIDENCE MATCHES (\(result.lowConfidence.count)):")
            for (input, intent, confidence) in result.lowConfidence.prefix(10) {
                TalkieLogger.info(.system, "  \"\(input)\" -> \(intent) (conf: \(String(format: "%.2f", confidence)))")
            }
            if result.lowConfidence.count > 10 {
                TalkieLogger.info(.system, "  ... and \(result.lowConfidence.count - 10) more")
            }
        }

        TalkieLogger.info(.system, String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Built-in Test Cases

    public static let testCases: [VoiceIntentTestCase] = [
        // Home Navigation
        VoiceIntentTestCase(input: "go home", expected: "navigateHome"),
        VoiceIntentTestCase(input: "take me home", expected: "navigateHome"),
        VoiceIntentTestCase(input: "show me the main screen", expected: "navigateHome"),
        VoiceIntentTestCase(input: "back to dashboard", expected: "navigateHome"),
        VoiceIntentTestCase(input: "open the home page", expected: "navigateHome"),
        VoiceIntentTestCase(input: "return to home", expected: "navigateHome"),
        VoiceIntentTestCase(input: "uhh home please", expected: "navigateHome"),
        VoiceIntentTestCase(input: "lemme go to the main screen", expected: "navigateHome"),
        VoiceIntentTestCase(input: "could you show me the dashboard", expected: "navigateHome"),
        VoiceIntentTestCase(input: "I want to see the home screen", expected: "navigateHome"),
        VoiceIntentTestCase(input: "um go to like the home screen", expected: "navigateHome"),
        VoiceIntentTestCase(input: "take me to the main page", expected: "navigateHome"),
        VoiceIntentTestCase(input: "I'd like to go home", expected: "navigateHome"),
        VoiceIntentTestCase(input: "can you show the dashboard", expected: "navigateHome"),
        VoiceIntentTestCase(input: "let's go back to the beginning", expected: "navigateHome"),

        // Recordings
        VoiceIntentTestCase(input: "show recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "open my recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "let me see my recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "where are my voice memos", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "show me saved recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "I want to see my memos", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "open recordings list", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "go to recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "show my voice notes", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "where did I save that memo", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "open recordigns", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "show me the recs", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "um open recordings please", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "open ze recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "take me to my voice memos", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "lemme see my saved memos", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "could you show me the recordings please", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "uhh show me the... recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "how do I access my recordings", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "where are my saved voice notes", expected: "navigateRecordings"),
        VoiceIntentTestCase(input: "I want to see what I recorded yesterday", expected: "navigateRecordings"),

        // Dictations
        VoiceIntentTestCase(input: "show dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "open dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "show me my dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "where are my transcriptions", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "show transcription history", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "open dictation list", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "go to dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "show live dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "I want to see my dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "show me the dicts", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "um show dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "lemme see dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "where's my transcription history", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "where can I find my dictations", expected: "navigateDictations"),
        VoiceIntentTestCase(input: "show me all my transcriptions", expected: "navigateDictations"),

        // Settings
        VoiceIntentTestCase(input: "open settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "show settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "go to settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "I need to change settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "open preferences", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "show me the settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "take me to settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "open setings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "how do I get to settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "could you please open settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "um open settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "I want to configure something", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "show me preferences", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "open ze settings", expected: "navigateSettings"),
        VoiceIntentTestCase(input: "can you open the settings for me", expected: "navigateSettings"),

        // Workflows
        VoiceIntentTestCase(input: "open workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "show workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "go to workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "show me the workflow editor", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "I want to edit workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "open workflow editor", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "take me to workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "show my workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "um workflows please", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "lemme edit workflows", expected: "navigateWorkflows"),
        VoiceIntentTestCase(input: "could you take me to the workflows", expected: "navigateWorkflows"),

        // Models
        VoiceIntentTestCase(input: "open models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "show models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "show me AI models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "go to models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "open AI models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "show model manager", expected: "navigateModels"),
        VoiceIntentTestCase(input: "I want to manage models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "take me to models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "where are the AI models", expected: "navigateModels"),
        VoiceIntentTestCase(input: "um show models", expected: "navigateModels"),

        // Drafts
        VoiceIntentTestCase(input: "open drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "show drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "go to drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "show me my drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "open compose area", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "I want to write something", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "take me to drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "show compose", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "where are my drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "um open drafts", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "lemme write something", expected: "navigateDrafts"),
        VoiceIntentTestCase(input: "please show me my drafts", expected: "navigateDrafts"),

        // Stats
        VoiceIntentTestCase(input: "show statistics", expected: "navigateStats"),
        VoiceIntentTestCase(input: "open stats", expected: "navigateStats"),
        VoiceIntentTestCase(input: "show me statistics", expected: "navigateStats"),
        VoiceIntentTestCase(input: "go to statistics", expected: "navigateStats"),
        VoiceIntentTestCase(input: "show analytics", expected: "navigateStats"),
        VoiceIntentTestCase(input: "I want to see my stats", expected: "navigateStats"),
        VoiceIntentTestCase(input: "open analytics", expected: "navigateStats"),
        VoiceIntentTestCase(input: "show me the stats", expected: "navigateStats"),
        VoiceIntentTestCase(input: "take me to statistics", expected: "navigateStats"),
        VoiceIntentTestCase(input: "um show stats", expected: "navigateStats"),
        VoiceIntentTestCase(input: "I'd like to see the statistics", expected: "navigateStats"),

        // Activity Log
        VoiceIntentTestCase(input: "open activity log", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "show activity log", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "show me the activity log", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "go to activity", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "show history", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "I want to see the log", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "open history", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "show me activity history", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "take me to activity log", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "um show activity", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "I need to see my activity", expected: "navigateActivityLog"),
        VoiceIntentTestCase(input: "show me what I did today", expected: "navigateActivityLog"),

        // System Console
        VoiceIntentTestCase(input: "open system console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "show console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "show me the console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "go to console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "show system logs", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "open logs", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "I want to see the logs", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "show me system console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "take me to console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "um open console", expected: "navigateSystemConsole"),
        VoiceIntentTestCase(input: "I want to check the logs", expected: "navigateSystemConsole"),

        // Pending Actions
        VoiceIntentTestCase(input: "show pending actions", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "open pending actions", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "show me pending actions", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "go to pending", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "show action queue", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "I want to see pending actions", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "open queue", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "show me the queue", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "take me to pending actions", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "um show pending", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "what's in the queue", expected: "navigatePendingActions"),
        VoiceIntentTestCase(input: "show me what's pending", expected: "navigatePendingActions"),

        // AI Results
        VoiceIntentTestCase(input: "show AI results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "open AI results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "show me AI outputs", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "go to results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "show AI outputs", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "I want to see AI results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "open results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "show me the AI results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "take me to AI results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "um show results", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "I want to see the AI output", expected: "navigateAIResults"),
        VoiceIntentTestCase(input: "what did the AI generate", expected: "navigateAIResults"),

        // Settings - Appearance
        VoiceIntentTestCase(input: "open appearance settings", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "show appearance", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "go to appearance settings", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "I want to change the theme", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "show me theme settings", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "open theme settings", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "change appearance", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "um appearance settings", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "lemme change the theme", expected: "settingsAppearance"),
        VoiceIntentTestCase(input: "how do I change the appearance", expected: "settingsAppearance"),

        // Settings - Voice IO
        VoiceIntentTestCase(input: "open microphone settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "show microphone settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "go to mic settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "I want to configure the microphone", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "show me voice settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "open voice settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "change mic settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "um microphone settings", expected: "settingsVoiceIO"),
        VoiceIntentTestCase(input: "I need to change my microphone", expected: "settingsVoiceIO"),

        // Settings - Sync
        VoiceIntentTestCase(input: "open sync settings", expected: "settingsSync"),
        VoiceIntentTestCase(input: "show sync settings", expected: "settingsSync"),
        VoiceIntentTestCase(input: "go to sync", expected: "settingsSync"),
        VoiceIntentTestCase(input: "I want to configure sync", expected: "settingsSync"),
        VoiceIntentTestCase(input: "show me sync settings", expected: "settingsSync"),
        VoiceIntentTestCase(input: "change sync settings", expected: "settingsSync"),
        VoiceIntentTestCase(input: "um sync settings", expected: "settingsSync"),

        // Settings - Storage
        VoiceIntentTestCase(input: "open storage settings", expected: "settingsStorage"),
        VoiceIntentTestCase(input: "show storage settings", expected: "settingsStorage"),
        VoiceIntentTestCase(input: "go to storage", expected: "settingsStorage"),
        VoiceIntentTestCase(input: "I want to manage storage", expected: "settingsStorage"),
        VoiceIntentTestCase(input: "show me storage settings", expected: "settingsStorage"),
        VoiceIntentTestCase(input: "change storage settings", expected: "settingsStorage"),
        VoiceIntentTestCase(input: "um storage settings", expected: "settingsStorage"),

        // Settings - AI Providers
        VoiceIntentTestCase(input: "open API key settings", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "show API keys", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "go to API settings", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "I want to add API keys", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "show me API key settings", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "change API keys", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "um API settings", expected: "settingsAIProviders"),
        VoiceIntentTestCase(input: "I need to add an API key", expected: "settingsAIProviders"),

        // Settings - Models
        VoiceIntentTestCase(input: "open model settings", expected: "settingsModels"),
        VoiceIntentTestCase(input: "show model settings", expected: "settingsModels"),
        VoiceIntentTestCase(input: "go to model configuration", expected: "settingsModels"),
        VoiceIntentTestCase(input: "I want to configure models", expected: "settingsModels"),
        VoiceIntentTestCase(input: "show me model settings", expected: "settingsModels"),
        VoiceIntentTestCase(input: "change model settings", expected: "settingsModels"),
        VoiceIntentTestCase(input: "um model settings", expected: "settingsModels"),

        // Settings - Dictionary
        VoiceIntentTestCase(input: "open dictionary settings", expected: "settingsDictionary"),
        VoiceIntentTestCase(input: "show dictionary", expected: "settingsDictionary"),
        VoiceIntentTestCase(input: "go to dictionary settings", expected: "settingsDictionary"),
        VoiceIntentTestCase(input: "I want to edit the dictionary", expected: "settingsDictionary"),
        VoiceIntentTestCase(input: "show me dictionary settings", expected: "settingsDictionary"),
        VoiceIntentTestCase(input: "change dictionary settings", expected: "settingsDictionary"),
        VoiceIntentTestCase(input: "um dictionary settings", expected: "settingsDictionary"),

        // Settings - Permissions
        VoiceIntentTestCase(input: "open permissions settings", expected: "settingsPermissions"),
        VoiceIntentTestCase(input: "show permissions", expected: "settingsPermissions"),
        VoiceIntentTestCase(input: "go to permissions", expected: "settingsPermissions"),
        VoiceIntentTestCase(input: "I want to manage permissions", expected: "settingsPermissions"),
        VoiceIntentTestCase(input: "show me permissions settings", expected: "settingsPermissions"),
        VoiceIntentTestCase(input: "change permissions", expected: "settingsPermissions"),
        VoiceIntentTestCase(input: "um permissions settings", expected: "settingsPermissions"),

        // Settings - Automations
        VoiceIntentTestCase(input: "open automations settings", expected: "settingsAutomations"),
        VoiceIntentTestCase(input: "show automations", expected: "settingsAutomations"),
        VoiceIntentTestCase(input: "go to automations", expected: "settingsAutomations"),
        VoiceIntentTestCase(input: "I want to configure automations", expected: "settingsAutomations"),
        VoiceIntentTestCase(input: "show me automation settings", expected: "settingsAutomations"),
        VoiceIntentTestCase(input: "change automations", expected: "settingsAutomations"),
        VoiceIntentTestCase(input: "um automations settings", expected: "settingsAutomations"),

        // Settings - Extensions
        VoiceIntentTestCase(input: "open extensions settings", expected: "settingsExtensions"),
        VoiceIntentTestCase(input: "show extensions", expected: "settingsExtensions"),
        VoiceIntentTestCase(input: "go to extensions", expected: "settingsExtensions"),
        VoiceIntentTestCase(input: "I want to manage extensions", expected: "settingsExtensions"),
        VoiceIntentTestCase(input: "show me extensions settings", expected: "settingsExtensions"),
        VoiceIntentTestCase(input: "change extensions", expected: "settingsExtensions"),
        VoiceIntentTestCase(input: "um extensions settings", expected: "settingsExtensions"),

        // Settings - Debug
        VoiceIntentTestCase(input: "open debug settings", expected: "settingsDebug"),
        VoiceIntentTestCase(input: "show debug settings", expected: "settingsDebug"),
        VoiceIntentTestCase(input: "go to debug", expected: "settingsDebug"),
        VoiceIntentTestCase(input: "I want to see debug settings", expected: "settingsDebug"),
        VoiceIntentTestCase(input: "show me debug settings", expected: "settingsDebug"),
        VoiceIntentTestCase(input: "change debug settings", expected: "settingsDebug"),
        VoiceIntentTestCase(input: "um debug settings", expected: "settingsDebug"),

        // Search
        VoiceIntentTestCase(input: "open search", expected: "openSearch"),
        VoiceIntentTestCase(input: "search", expected: "openSearch"),
        VoiceIntentTestCase(input: "I want to search", expected: "openSearch"),
        VoiceIntentTestCase(input: "show search", expected: "openSearch"),
        VoiceIntentTestCase(input: "find something", expected: "openSearch"),
        VoiceIntentTestCase(input: "um search please", expected: "openSearch"),
        VoiceIntentTestCase(input: "lemme search", expected: "openSearch"),
        VoiceIntentTestCase(input: "I need to find something", expected: "openSearch"),
        VoiceIntentTestCase(input: "help me search for something", expected: "openSearch"),

        // Command Palette
        VoiceIntentTestCase(input: "open command palette", expected: "openCommandPalette"),
        VoiceIntentTestCase(input: "show command palette", expected: "openCommandPalette"),
        VoiceIntentTestCase(input: "open commands", expected: "openCommandPalette"),
        VoiceIntentTestCase(input: "show commands", expected: "openCommandPalette"),
        VoiceIntentTestCase(input: "I want to run a command", expected: "openCommandPalette"),
        VoiceIntentTestCase(input: "um command palette", expected: "openCommandPalette"),

        // Go Back
        VoiceIntentTestCase(input: "go back", expected: "goBack"),
        VoiceIntentTestCase(input: "back", expected: "goBack"),
        VoiceIntentTestCase(input: "previous screen", expected: "goBack"),
        VoiceIntentTestCase(input: "go to previous", expected: "goBack"),
        VoiceIntentTestCase(input: "um go back", expected: "goBack"),
        VoiceIntentTestCase(input: "take me back", expected: "goBack"),

        // Start Dictation
        VoiceIntentTestCase(input: "start dictation", expected: "startDictation"),
        VoiceIntentTestCase(input: "begin dictation", expected: "startDictation"),
        VoiceIntentTestCase(input: "start recording", expected: "startDictation"),
        VoiceIntentTestCase(input: "I want to record something", expected: "startDictation"),
        VoiceIntentTestCase(input: "start listening", expected: "startDictation"),
        VoiceIntentTestCase(input: "um start dictation", expected: "startDictation"),
        VoiceIntentTestCase(input: "lemme record", expected: "startDictation"),
        // Memo-related phrases
        VoiceIntentTestCase(input: "start a memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "record a memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "take a memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "new memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "I want to take a memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "capture a thought", expected: "startDictation"),
        VoiceIntentTestCase(input: "jot this down", expected: "startDictation"),
        VoiceIntentTestCase(input: "start a voice memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "record a voice memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "I need to capture a memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "take a note please", expected: "startDictation"),
        VoiceIntentTestCase(input: "new voice recording", expected: "startDictation"),
        VoiceIntentTestCase(input: "um let me take a memo", expected: "startDictation"),
        VoiceIntentTestCase(input: "can I record a memo", expected: "startDictation"),

        // Stop Dictation
        VoiceIntentTestCase(input: "stop dictation", expected: "stopDictation"),
        VoiceIntentTestCase(input: "end dictation", expected: "stopDictation"),
        VoiceIntentTestCase(input: "stop recording", expected: "stopDictation"),
        VoiceIntentTestCase(input: "stop listening", expected: "stopDictation"),
        VoiceIntentTestCase(input: "um stop dictation", expected: "stopDictation"),

        // Sync Now
        VoiceIntentTestCase(input: "sync now", expected: "syncNow"),
        VoiceIntentTestCase(input: "sync data", expected: "syncNow"),
        VoiceIntentTestCase(input: "synchronize", expected: "syncNow"),
        VoiceIntentTestCase(input: "I want to sync", expected: "syncNow"),
        VoiceIntentTestCase(input: "um sync please", expected: "syncNow"),
        VoiceIntentTestCase(input: "start sync", expected: "syncNow"),
    ]
}
