//
//  SimpleWorkflowLoader.swift
//  Talkie macOS
//
//  Loads simplified workflow JSON files (.json) and converts them to WorkflowDefinition
//  Simplified format: flat step configs, no nested wrappers, IDs generated at runtime
//

import Foundation
import TalkieKit

private let log = Log(.workflow)

// MARK: - Simplified File Format

/// Root structure of a simplified workflow JSON file
struct SimpleWorkflowFile: Codable {
    let name: String
    let description: String
    let icon: String?
    let color: String?
    let maintainer: String?  // e.g., "talkie" for official starter pack
    let steps: [SimpleStep]
}

/// A step in simplified format - flat config, no nested wrappers
struct SimpleStep: Codable {
    // Required
    let type: String  // Matches StepType raw value: "llm", "transcribe", "speak", etc.

    // Optional metadata
    let outputKey: String?
    let isEnabled: Bool?
    let condition: String?

    // LLM config (flat)
    let provider: String?
    let modelId: String?
    let costTier: String?
    let prompt: String?
    let systemPrompt: String?
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?

    // Transcribe config (flat)
    let qualityTier: String?
    let fallbackStrategy: String?
    let overwriteExisting: Bool?
    let saveAsVersion: Bool?

    // Speak config (flat)
    let text: String?
    let voice: String?
    let rate: Float?
    let pitch: Float?
    let playImmediately: Bool?
    let saveToFile: Bool?
    let useCache: Bool?

    // Shell config (flat)
    let executable: String?
    let arguments: [String]?
    let workingDirectory: String?
    let environment: [String: String]?
    let stdin: String?
    let timeout: Int?
    let captureStderr: Bool?

    // Transform config (flat)
    let operation: String?
    let parameters: [String: String]?

    // Notification config (flat)
    let title: String?
    let body: String?
    let sound: Bool?
    let actionLabel: String?

    // Clipboard config (flat)
    let content: String?

    // SaveFile config (flat)
    let filename: String?
    let directory: String?
    // content already defined above
    let appendIfExists: Bool?

    // Trigger config (flat)
    let phrases: [String]?
    let caseSensitive: Bool?
    let searchLocation: String?
    let contextWindowSize: Int?
    let stopIfNoMatch: Bool?

    // Conditional config (flat)
    // condition already defined above
    let thenSteps: [Int]?  // Step indices
    let elseSteps: [Int]?  // Step indices

    // Reminders config (flat)
    let listName: String?
    // title already defined above
    let notes: String?
    let dueDate: String?
    let priority: Int?

    // iOS Push config (flat)
    // title, body, sound already defined
    let includeOutput: Bool?

    // Intent extraction config (flat)
    let inputKey: String?
    let extractionMethod: String?
    let confidenceThreshold: Double?

    // Execute workflows config (flat)
    let intentsKey: String?
    let stopOnError: Bool?
    let parallel: Bool?
}

// MARK: - Simple Workflow Loader

enum SimpleWorkflowLoaderError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String, Error)
    case unknownStepType(String)
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Workflow file not found: \(path)"
        case .parseError(let file, let error):
            return "Failed to parse \(file): \(error.localizedDescription)"
        case .unknownStepType(let type):
            return "Unknown step type: \(type)"
        case .invalidConfig(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

/// Loads simplified workflow JSON files
struct SimpleWorkflowLoader {

    // MARK: - Loading

    /// Load a workflow from a file URL
    static func load(from fileURL: URL) throws -> WorkflowDefinition {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SimpleWorkflowLoaderError.fileNotFound(fileURL.path)
        }

        let data = try Data(contentsOf: fileURL)
        return try load(from: data)
    }

    /// Load a workflow from JSON data
    static func load(from data: Data) throws -> WorkflowDefinition {
        let decoder = JSONDecoder()

        let file: SimpleWorkflowFile
        do {
            file = try decoder.decode(SimpleWorkflowFile.self, from: data)
        } catch {
            throw SimpleWorkflowLoaderError.parseError("workflow", error)
        }

        return try convert(file)
    }

    // MARK: - Conversion

    /// Convert a SimpleWorkflowFile to WorkflowDefinition
    static func convert(_ file: SimpleWorkflowFile) throws -> WorkflowDefinition {
        // Convert steps with fresh UUIDs
        var steps: [WorkflowStep] = []
        var stepUUIDs: [UUID] = []  // Track for conditional step references

        for (index, simpleStep) in file.steps.enumerated() {
            let stepId = UUID()
            stepUUIDs.append(stepId)
            let step = try convertStep(simpleStep, index: index, stepId: stepId, stepUUIDs: stepUUIDs)
            steps.append(step)
        }

        // Parse color
        let color = WorkflowColor(rawValue: file.color ?? "blue") ?? .blue

        return WorkflowDefinition(
            id: UUID(),  // Fresh UUID each time
            name: file.name,
            description: file.description,
            icon: file.icon ?? "wand.and.stars",
            color: color,
            maintainer: file.maintainer,
            steps: steps,
            isEnabled: true,
            isPinned: false,
            autoRun: false,
            autoRunOrder: 0,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    /// Convert a SimpleStep to WorkflowStep
    private static func convertStep(_ step: SimpleStep, index: Int, stepId: UUID, stepUUIDs: [UUID]) throws -> WorkflowStep {
        // StepType raw values now match JSON type names directly
        guard let stepType = WorkflowStep.StepType(rawValue: step.type) else {
            throw SimpleWorkflowLoaderError.unknownStepType(step.type)
        }

        let config = try convertConfig(step, stepType: stepType, stepUUIDs: stepUUIDs)

        // Convert condition string to StepCondition if provided
        let stepCondition: StepCondition? = step.condition.map { StepCondition(expression: $0) }

        return WorkflowStep(
            id: stepId,
            type: stepType,
            config: config,
            outputKey: step.outputKey ?? "step_\(index)",
            isEnabled: step.isEnabled ?? true,
            condition: stepCondition
        )
    }

    /// Convert flat step fields to StepConfig
    private static func convertConfig(_ step: SimpleStep, stepType: WorkflowStep.StepType, stepUUIDs: [UUID]) throws -> StepConfig {
        switch stepType {
        case .llm:
            guard let prompt = step.prompt else {
                throw SimpleWorkflowLoaderError.invalidConfig("LLM step requires 'prompt'")
            }

            var provider: WorkflowLLMProvider? = nil
            if let providerStr = step.provider {
                provider = WorkflowLLMProvider(rawValue: providerStr)
            }

            var costTier: LLMCostTier? = nil
            if let tierStr = step.costTier {
                costTier = LLMCostTier(rawValue: tierStr)
            }

            return .llm(LLMStepConfig(
                provider: provider,
                modelId: step.modelId,
                costTier: costTier,
                autoRoute: provider == nil,
                prompt: prompt,
                systemPrompt: step.systemPrompt,
                temperature: step.temperature ?? 0.7,
                maxTokens: step.maxTokens ?? 1024,
                topP: step.topP ?? 0.9
            ))

        case .transcribe:
            let tier: TranscriptionQualityTier
            switch step.qualityTier ?? "balanced" {
            case "fast": tier = .fast
            case "high": tier = .high
            default: tier = .balanced
            }

            let fallback: TranscriptionFallbackStrategy
            switch step.fallbackStrategy ?? "automatic" {
            case "none": fallback = .none
            case "automatic": fallback = .automatic
            default: fallback = .automatic
            }

            return .transcribe(TranscribeStepConfig(
                qualityTier: tier,
                fallbackStrategy: fallback,
                overwriteExisting: step.overwriteExisting ?? false,
                saveAsVersion: step.saveAsVersion ?? true
            ))

        case .speak:
            let provider: TTSProvider
            if let providerStr = step.provider {
                provider = TTSProvider(rawValue: providerStr) ?? .speakeasy
            } else {
                provider = .speakeasy
            }

            return .speak(SpeakStepConfig(
                text: step.text ?? "{{OUTPUT}}",
                provider: provider,
                voice: step.voice,
                rate: step.rate ?? 0.5,
                pitch: step.pitch ?? 1.0,
                playImmediately: step.playImmediately ?? true,
                saveToFile: step.saveToFile ?? false,
                useCache: step.useCache ?? true
            ))

        case .shell:
            guard let executable = step.executable else {
                throw SimpleWorkflowLoaderError.invalidConfig("Shell step requires 'executable'")
            }

            return .shell(ShellStepConfig(
                executable: executable,
                arguments: step.arguments ?? [],
                workingDirectory: step.workingDirectory,
                environment: step.environment ?? [:],
                stdin: step.stdin,
                promptTemplate: nil,
                timeout: step.timeout ?? 30,
                captureStderr: step.captureStderr ?? true
            ))

        case .transform:
            let operation = TransformStepConfig.TransformOperation(rawValue: step.operation ?? "extractJSON") ?? .extractJSON
            return .transform(TransformStepConfig(
                operation: operation,
                parameters: step.parameters ?? [:]
            ))

        case .conditional:
            guard let condition = step.condition else {
                throw SimpleWorkflowLoaderError.invalidConfig("Conditional step requires 'condition'")
            }

            // Convert step indices to UUIDs using the tracked stepUUIDs
            let thenUUIDs = (step.thenSteps ?? []).compactMap { index in
                index < stepUUIDs.count ? stepUUIDs[index] : nil
            }
            let elseUUIDs = (step.elseSteps ?? []).compactMap { index in
                index < stepUUIDs.count ? stepUUIDs[index] : nil
            }

            return .conditional(ConditionalStepConfig(
                condition: condition,
                thenSteps: thenUUIDs,
                elseSteps: elseUUIDs
            ))

        case .notification:
            return .notification(NotificationStepConfig(
                title: step.title ?? "Talkie",
                body: step.body ?? "{{OUTPUT}}",
                sound: step.sound ?? true,
                actionLabel: step.actionLabel
            ))

        case .iOSPush:
            return .iOSPush(iOSPushStepConfig(
                title: step.title ?? "Talkie",
                body: step.body ?? "{{OUTPUT}}",
                sound: step.sound ?? true,
                includeOutput: step.includeOutput ?? false
            ))

        case .clipboard:
            return .clipboard(ClipboardStepConfig(
                content: step.content ?? "{{OUTPUT}}"
            ))

        case .saveFile:
            return .saveFile(SaveFileStepConfig(
                filename: step.filename ?? "output.txt",
                directory: step.directory,
                content: step.content ?? "{{OUTPUT}}",
                appendIfExists: step.appendIfExists ?? false
            ))

        case .appleReminders:
            let priority: AppleRemindersStepConfig.ReminderPriority
            switch step.priority {
            case 1: priority = .high
            case 5: priority = .medium
            case 9: priority = .low
            default: priority = .none
            }

            return .appleReminders(AppleRemindersStepConfig(
                listName: step.listName,
                title: step.title ?? "{{OUTPUT}}",
                notes: step.notes,
                dueDate: step.dueDate,
                priority: priority
            ))

        case .trigger:
            let searchLocation: TriggerStepConfig.SearchLocation
            switch step.searchLocation {
            case "start": searchLocation = .start
            case "anywhere": searchLocation = .anywhere
            default: searchLocation = .end
            }

            return .trigger(TriggerStepConfig(
                phrases: step.phrases ?? ["hey talkie"],
                caseSensitive: step.caseSensitive ?? false,
                searchLocation: searchLocation,
                contextWindowSize: step.contextWindowSize ?? 200,
                stopIfNoMatch: step.stopIfNoMatch ?? true
            ))

        case .intentExtract:
            let method: IntentExtractStepConfig.ExtractionMethod
            switch step.extractionMethod {
            case "llm": method = .llm
            case "keywords": method = .keywords
            default: method = .hybrid
            }

            return .intentExtract(IntentExtractStepConfig(
                inputKey: step.inputKey ?? "{{PREVIOUS_OUTPUT}}",
                extractionMethod: method,
                recognizedIntents: IntentDefinition.defaults,
                confidenceThreshold: step.confidenceThreshold ?? 0.5
            ))

        case .executeWorkflows:
            return .executeWorkflows(ExecuteWorkflowsStepConfig(
                intentsKey: step.intentsKey ?? "{{PREVIOUS_OUTPUT}}",
                stopOnError: step.stopOnError ?? false,
                parallel: step.parallel ?? false
            ))

        case .webhook, .email, .appleNotes, .appleCalendar:
            // These types use default config
            return StepConfig.defaultConfig(for: stepType)
        }
    }
}
