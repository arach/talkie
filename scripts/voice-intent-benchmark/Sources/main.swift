//
//  Voice Intent Benchmark CLI
//
//  Standalone tool for testing voice intent recognition accuracy.
//  NOT part of production builds - for development/QA use only.
//
//  Usage:
//    swift run voice-intent-benchmark [--json] [--output <file>] [--verbose]
//
//  Examples:
//    swift run voice-intent-benchmark
//    swift run voice-intent-benchmark --json --output results.json
//    swift run voice-intent-benchmark --verbose > full-report.txt
//

import Foundation
import TalkieKit

// MARK: - CLI Arguments

struct CLIArguments {
    var jsonOutput = false
    var outputFile: String?
    var verbose = false

    init(arguments: [String]) {
        var args = Array(arguments.dropFirst()) // Skip executable name
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--json", "-j":
                jsonOutput = true
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputFile = args[i]
                }
            case "--verbose", "-v":
                verbose = true
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                if arg.hasPrefix("-") {
                    print("Unknown option: \(arg)")
                    printUsage()
                    exit(1)
                }
            }
            i += 1
        }
    }

    func printUsage() {
        print("""
        Voice Intent Benchmark CLI

        Tests voice intent recognition against a corpus of natural language inputs.
        Reports accuracy, failures, and low-confidence matches.

        Usage:
          swift run voice-intent-benchmark [options]

        Options:
          --json, -j       Output results as JSON
          --output, -o     Write results to file (default: stdout)
          --verbose, -v    Show all test cases, not just failures
          --help, -h       Show this help message

        Examples:
          swift run voice-intent-benchmark
          swift run voice-intent-benchmark --json --output results.json
          swift run voice-intent-benchmark --verbose > full-report.txt
        """)
    }
}

// MARK: - JSON Output Structures

struct JSONBenchmarkResult: Codable {
    let summary: JSONSummary
    let failures: [JSONTestFailure]
    let lowConfidence: [JSONLowConfidence]
    let allResults: [JSONTestResult]?
}

struct JSONSummary: Codable {
    let totalCases: Int
    let passed: Int
    let failed: Int
    let accuracy: Double
    let passRate: String
    let timestamp: String
}

struct JSONTestFailure: Codable {
    let input: String
    let expected: String
    let actual: String
    let confidence: Float
}

struct JSONLowConfidence: Codable {
    let input: String
    let intent: String
    let confidence: Float
}

struct JSONTestResult: Codable {
    let input: String
    let expected: String
    let actual: String
    let confidence: Float
    let passed: Bool
    let matchedPhrase: String?
}

// MARK: - Main

@main
struct VoiceIntentBenchmarkCLI {
    static func main() async {
        let args = CLIArguments(arguments: CommandLine.arguments)
        let startTime = Date()

        print("╔══════════════════════════════════════════════════════════════════════╗")
        print("║           VOICE INTENT RECOGNITION BENCHMARK                         ║")
        print("╚══════════════════════════════════════════════════════════════════════╝")
        print("")
        print("Running \(VoiceIntentBenchmark.testCases.count) test cases...")
        print("")

        // Run benchmark
        let recognizer = await VoiceIntentRecognizer.shared
        var allResults: [JSONTestResult] = []
        var passed = 0
        var failures: [(String, String, String, Float)] = []
        var lowConfidence: [(String, String, Float)] = []

        for (index, testCase) in VoiceIntentBenchmark.testCases.enumerated() {
            let result = await recognizer.recognize(testCase.input)
            let actualIntent = result.intent.rawValue
            let didPass = actualIntent == testCase.expected

            if didPass {
                passed += 1
                if result.confidence < 0.7 {
                    lowConfidence.append((testCase.input, actualIntent, result.confidence))
                }
            } else {
                failures.append((testCase.input, testCase.expected, actualIntent, result.confidence))
            }

            allResults.append(JSONTestResult(
                input: testCase.input,
                expected: testCase.expected,
                actual: actualIntent,
                confidence: result.confidence,
                passed: didPass,
                matchedPhrase: result.matchedPhrase
            ))

            // Progress indicator
            if (index + 1) % 50 == 0 {
                print("  Processed \(index + 1)/\(VoiceIntentBenchmark.testCases.count)...")
            }
        }

        let total = VoiceIntentBenchmark.testCases.count
        let accuracy = total > 0 ? Double(passed) / Double(total) : 0
        let passRate = String(format: "%.1f%%", accuracy * 100)
        let duration = Date().timeIntervalSince(startTime)

        print("")
        print("Completed in \(String(format: "%.2f", duration))s")
        print("")

        // Generate output
        var output = ""
        let timestamp = ISO8601DateFormatter().string(from: Date())

        if args.jsonOutput {
            let jsonResult = JSONBenchmarkResult(
                summary: JSONSummary(
                    totalCases: total,
                    passed: passed,
                    failed: failures.count,
                    accuracy: accuracy,
                    passRate: passRate,
                    timestamp: timestamp
                ),
                failures: failures.map { JSONTestFailure(input: $0.0, expected: $0.1, actual: $0.2, confidence: $0.3) },
                lowConfidence: lowConfidence.map { JSONLowConfidence(input: $0.0, intent: $0.1, confidence: $0.2) },
                allResults: args.verbose ? allResults : nil
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let jsonData = try? encoder.encode(jsonResult),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                output = jsonString
            }
        } else {
            // Text output
            output += "══════════════════════════════════════════════════════════════════════\n"
            output += "                    BENCHMARK RESULTS\n"
            output += "══════════════════════════════════════════════════════════════════════\n"
            output += "\n"
            output += "Timestamp:        \(timestamp)\n"
            output += "Total Test Cases: \(total)\n"
            output += "Passed:           \(passed) ✓\n"
            output += "Failed:           \(failures.count) ✗\n"
            output += "Accuracy:         \(passRate)\n"
            output += "\n"

            // Breakdown by intent category
            output += "──────────────────────────────────────────────────────────────────────\n"
            output += "ACCURACY BY CATEGORY\n"
            output += "──────────────────────────────────────────────────────────────────────\n"

            let categories: [(String, [String])] = [
                ("Navigation", ["navigateHome", "navigateRecordings", "navigateDictations", "navigateSettings",
                               "navigateWorkflows", "navigateModels", "navigateDrafts", "navigateStats",
                               "navigateActivityLog", "navigateSystemConsole", "navigatePendingActions", "navigateAIResults"]),
                ("Settings", ["settingsAppearance", "settingsHelpers", "settingsVoiceIO", "settingsDictionary",
                             "settingsAIProviders", "settingsModels", "settingsStorage", "settingsSync",
                             "settingsActions", "settingsAutomations", "settingsExtensions", "settingsPermissions", "settingsDebug"]),
                ("Actions", ["openSearch", "openCommandPalette", "goBack", "startDictation", "stopDictation", "syncNow"])
            ]

            for (categoryName, intents) in categories {
                let categoryResults = allResults.filter { intents.contains($0.expected) }
                let categoryPassed = categoryResults.filter { $0.passed }.count
                let categoryTotal = categoryResults.count
                let categoryRate = categoryTotal > 0 ? Double(categoryPassed) / Double(categoryTotal) * 100 : 0
                output += String(format: "  %-15s %3d/%3d (%.1f%%)\n", categoryName, categoryPassed, categoryTotal, categoryRate)
            }
            output += "\n"

            if !failures.isEmpty {
                output += "══════════════════════════════════════════════════════════════════════\n"
                output += "FAILURES (\(failures.count))\n"
                output += "══════════════════════════════════════════════════════════════════════\n"

                // Group failures by expected intent
                let failuresByIntent = Dictionary(grouping: failures) { $0.1 }
                for (expected, cases) in failuresByIntent.sorted(by: { $0.key < $1.key }) {
                    output += "\n[\(expected)] - \(cases.count) failures:\n"
                    for (input, _, actual, confidence) in cases {
                        output += "  • \"\(input)\"\n"
                        output += "    → Got: \(actual) (conf: \(String(format: "%.2f", confidence)))\n"
                    }
                }
                output += "\n"
            }

            if !lowConfidence.isEmpty {
                output += "══════════════════════════════════════════════════════════════════════\n"
                output += "LOW CONFIDENCE MATCHES (\(lowConfidence.count)) - passed but conf < 0.70\n"
                output += "══════════════════════════════════════════════════════════════════════\n"
                for (input, intent, confidence) in lowConfidence.sorted(by: { $0.2 < $1.2 }) {
                    output += "  \(String(format: "%.2f", confidence)) │ \"\(input)\" → \(intent)\n"
                }
                output += "\n"
            }

            if args.verbose {
                output += "══════════════════════════════════════════════════════════════════════\n"
                output += "ALL RESULTS (\(allResults.count))\n"
                output += "══════════════════════════════════════════════════════════════════════\n"
                for result in allResults {
                    let status = result.passed ? "✓" : "✗"
                    let confStr = String(format: "%.2f", result.confidence)
                    output += "\(status) [\(confStr)] \"\(result.input)\"\n"
                    if !result.passed {
                        output += "         Expected: \(result.expected) │ Got: \(result.actual)\n"
                    }
                }
                output += "\n"
            }

            output += "══════════════════════════════════════════════════════════════════════\n"
        }

        // Write output
        if let outputFile = args.outputFile {
            do {
                try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
                print("Results written to: \(outputFile)")
            } catch {
                print("Error writing to file: \(error.localizedDescription)")
                exit(1)
            }
        } else {
            print(output)
        }

        // Summary
        print("")
        if failures.isEmpty {
            print("🎉 All tests passed!")
        } else {
            print("📊 Summary: \(passRate) accuracy (\(passed)/\(total) passed, \(failures.count) failed)")
        }
    }
}
