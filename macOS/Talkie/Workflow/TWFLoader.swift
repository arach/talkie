//
//  TWFLoader.swift
//  Talkie macOS
//
//  Loads Talkie Workflow Format (.twf.json) files and converts them to WorkflowDefinition
//  TWF uses human-readable slug-based IDs; UUIDs are generated deterministically at runtime
//

import Foundation
import CryptoKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Workflow")
// MARK: - TWF Format Structures

/// Root structure of a .twf.json file
struct TWFWorkflow: Codable {
    let slug: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let isEnabled: Bool
    let isPinned: Bool
    let autoRun: Bool
    let steps: [TWFStep]
}

/// A step in the TWF workflow
struct TWFStep: Codable {
    let id: String  // Slug-based ID (e.g., "transcribe-hq", "polish")
    let type: String  // Human-readable type (e.g., "LLM Generation", "Transcribe Audio")
    let config: TWFStepConfig
}

/// Step configuration - wraps all possible config types
struct TWFStepConfig: Codable {
    // Each step type has its config under a specific key
    let llm: TWFLLMConfig?
    let transcribe: TWFTranscribeConfig?
    let transform: TWFTransformConfig?
    let conditional: TWFConditionalConfig?
    let notification: TWFNotificationConfig?
    let iOSPush: TWFiOSPushConfig?
    let clipboard: TWFClipboardConfig?
    let saveFile: TWFSaveFileConfig?
    let appleReminders: TWFAppleRemindersConfig?
    let shell: TWFShellConfig?
    let trigger: TWFTriggerConfig?
    let intentExtract: TWFIntentExtractConfig?
    let executeWorkflows: TWFExecuteWorkflowsConfig?
    let speak: TWFSpeakConfig?  // Walkie-Talkie mode!
}

// MARK: - TWF Config Types

struct TWFLLMConfig: Codable {
    let costTier: String?  // "budget", "balanced", "capable"
    let provider: String?  // "gemini", "openai", "anthropic", "groq", "mlx"
    let modelId: String?
    let prompt: String
    let systemPrompt: String?
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
}

struct TWFTranscribeConfig: Codable {
    let model: String?  // e.g., "openai_whisper-small", "distil-whisper_distil-large-v3"
    let overwriteExisting: Bool?
    let saveAsVersion: Bool?
}

struct TWFSpeakConfig: Codable {
    let text: String?               // Text to speak (supports variables like {{OUTPUT}})
    let provider: String?           // TTS provider: system, speakeasy, openai, elevenlabs
    let voice: String?              // Voice name/ID (depends on provider)
    let voiceIdentifier: String?    // Legacy: same as voice
    let rate: Float?                // Speech rate (0.0 - 1.0)
    let pitch: Float?               // Voice pitch (0.5 - 2.0)
    let playImmediately: Bool?      // Play now vs just generate audio
    let saveToFile: Bool?           // Also save as audio file
    let uploadToWalkie: Bool?       // Upload to CloudKit for iOS playback
    let useCache: Bool?             // Use SpeakEasy's caching
}

struct TWFTransformConfig: Codable {
    let operation: String  // "Extract JSON", "Extract List", etc.
    let parameters: [String: String]?
}

struct TWFConditionalConfig: Codable {
    let condition: String
    let thenSteps: [String]?  // Step IDs (slugs)
    let elseSteps: [String]?  // Step IDs (slugs)
}

struct TWFNotificationConfig: Codable {
    let title: String
    let body: String
    let sound: Bool?
    let actionLabel: String?
}

struct TWFiOSPushConfig: Codable {
    let title: String
    let body: String
    let sound: Bool?
    let includeOutput: Bool?
}

struct TWFClipboardConfig: Codable {
    let content: String
}

struct TWFSaveFileConfig: Codable {
    let filename: String
    let directory: String?
    let content: String
    let appendIfExists: Bool?
}

struct TWFAppleRemindersConfig: Codable {
    let listName: String?
    let title: String
    let notes: String?
    let dueDate: String?
    let priority: Int?
}

struct TWFShellConfig: Codable {
    let executable: String
    let arguments: [String]?
    let workingDirectory: String?
    let environment: [String: String]?
    let stdin: String?
    let timeout: Int?
    let captureStderr: Bool?
}

struct TWFTriggerConfig: Codable {
    let phrases: [String]?
    let caseSensitive: Bool?
    let searchLocation: String?
    let contextWindowSize: Int?
    let stopIfNoMatch: Bool?
}

struct TWFIntentExtractConfig: Codable {
    let inputKey: String?
    let extractionMethod: String?
    let confidenceThreshold: Double?
}

struct TWFExecuteWorkflowsConfig: Codable {
    let intentsKey: String?
    let stopOnError: Bool?
    let parallel: Bool?
}

// MARK: - TWF Loader

enum TWFLoaderError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String, Error)
    case unknownStepType(String)
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "TWF file not found: \(path)"
        case .parseError(let file, let error):
            return "Failed to parse \(file): \(error.localizedDescription)"
        case .unknownStepType(let type):
            return "Unknown step type: \(type)"
        case .invalidConfig(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

/// Loads and converts TWF (Talkie Workflow Format) files
struct TWFLoader {

    // MARK: - UUID Generation

    /// Generate a deterministic UUID from a slug
    /// Uses SHA256 hash to create a stable UUID namespace
    static func uuidFromSlug(_ slug: String, namespace: String = "talkie.twf") -> UUID {
        let input = "\(namespace):\(slug)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(hash)

        // Use first 16 bytes of hash to create UUID
        // Set version (4) and variant (RFC 4122) bits
        var uuidBytes = Array(bytes.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x40  // Version 4
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80  // Variant RFC 4122

        let uuid = NSUUID(uuidBytes: uuidBytes) as UUID
        return uuid
    }

    /// Generate a UUID for a step within a workflow
    static func uuidForStep(_ stepSlug: String, workflowSlug: String) -> UUID {
        return uuidFromSlug("\(workflowSlug)/\(stepSlug)")
    }

    // MARK: - Loading

    /// Load all TWF files from the StarterWorkflows bundle directory
    static func loadStarterWorkflows() -> [WorkflowDefinition] {
        guard let resourcePath = Bundle.main.resourcePath else {
            logger.debug("[TWFLoader] No resource path found")
            return []
        }

        let starterPath = (resourcePath as NSString).appendingPathComponent("StarterWorkflows")
        return loadWorkflows(from: starterPath)
    }

    /// Load all TWF files from a directory
    static func loadWorkflows(from directoryPath: String) -> [WorkflowDefinition] {
        let fileManager = FileManager.default
        var workflows: [WorkflowDefinition] = []

        do {
            let files = try fileManager.contentsOfDirectory(atPath: directoryPath)
            let twfFiles = files.filter { $0.hasSuffix(".twf.json") }

            for filename in twfFiles {
                let filePath = (directoryPath as NSString).appendingPathComponent(filename)
                do {
                    let workflow = try loadWorkflow(from: filePath)
                    workflows.append(workflow)
                    logger.debug("[TWFLoader] Loaded: \(workflow.name) (\(workflow.steps.count) steps)")
                } catch {
                    logger.debug("[TWFLoader] Failed to load \(filename): \(error)")
                }
            }
        } catch {
            logger.debug("[TWFLoader] Failed to read directory \(directoryPath): \(error)")
        }

        return workflows
    }

    /// Load a single TWF file and convert to WorkflowDefinition
    static func loadWorkflow(from filePath: String) throws -> WorkflowDefinition {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw TWFLoaderError.fileNotFound(filePath)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let filename = (filePath as NSString).lastPathComponent

        let twf: TWFWorkflow
        do {
            let decoder = JSONDecoder()
            twf = try decoder.decode(TWFWorkflow.self, from: data)
        } catch {
            throw TWFLoaderError.parseError(filename, error)
        }

        return try convert(twf)
    }

    /// Load TWF from raw JSON data
    static func loadWorkflow(from data: Data) throws -> WorkflowDefinition {
        let decoder = JSONDecoder()
        let twf = try decoder.decode(TWFWorkflow.self, from: data)
        return try convert(twf)
    }

    // MARK: - Conversion

    /// Convert a TWFWorkflow to WorkflowDefinition
    static func convert(_ twf: TWFWorkflow) throws -> WorkflowDefinition {
        let workflowId = uuidFromSlug(twf.slug)

        // Build step ID lookup for conditional references
        var stepIdMap: [String: UUID] = [:]
        for step in twf.steps {
            stepIdMap[step.id] = uuidForStep(step.id, workflowSlug: twf.slug)
        }

        // Convert steps
        var steps: [WorkflowStep] = []
        for twfStep in twf.steps {
            let step = try convertStep(twfStep, workflowSlug: twf.slug, stepIdMap: stepIdMap)
            steps.append(step)
        }

        // Parse color
        let color = WorkflowColor(rawValue: twf.color) ?? .blue

        return WorkflowDefinition(
            id: workflowId,
            name: twf.name,
            description: twf.description,
            icon: twf.icon,
            color: color,
            steps: steps,
            isEnabled: twf.isEnabled,
            isPinned: twf.isPinned,
            autoRun: twf.autoRun,
            autoRunOrder: 0,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    /// Convert a TWFStep to WorkflowStep
    private static func convertStep(_ twfStep: TWFStep, workflowSlug: String, stepIdMap: [String: UUID]) throws -> WorkflowStep {
        let stepId = uuidForStep(twfStep.id, workflowSlug: workflowSlug)

        guard let stepType = mapStepType(twfStep.type) else {
            throw TWFLoaderError.unknownStepType(twfStep.type)
        }

        let config = try convertConfig(twfStep.config, stepType: stepType, stepIdMap: stepIdMap)

        return WorkflowStep(
            id: stepId,
            type: stepType,
            config: config,
            outputKey: twfStep.id,  // Use step slug as output key
            isEnabled: true,
            condition: nil
        )
    }

    /// Map TWF type string to WorkflowStep.StepType
    private static func mapStepType(_ typeString: String) -> WorkflowStep.StepType? {
        // Direct mapping from TWF type strings
        switch typeString {
        case "LLM Generation": return .llm
        case "Run Shell Command": return .shell
        case "Webhook": return .webhook
        case "Send Email": return .email
        case "Send Notification": return .notification
        case "Notify iPhone": return .iOSPush
        case "Add to Apple Notes": return .appleNotes
        case "Create Reminder": return .appleReminders
        case "Create Calendar Event": return .appleCalendar
        case "Copy to Clipboard": return .clipboard
        case "Save to File": return .saveFile
        case "Conditional Branch": return .conditional
        case "Transform Data": return .transform
        case "Transcribe Audio": return .transcribe
        case "Trigger Detection": return .trigger
        case "Extract Intents": return .intentExtract
        case "Execute Workflows": return .executeWorkflows
        default: return nil
        }
    }

    /// Convert TWFStepConfig to StepConfig
    private static func convertConfig(_ twfConfig: TWFStepConfig, stepType: WorkflowStep.StepType, stepIdMap: [String: UUID]) throws -> StepConfig {
        switch stepType {
        case .llm:
            guard let llm = twfConfig.llm else {
                throw TWFLoaderError.invalidConfig("LLM step missing 'llm' config")
            }
            return .llm(convertLLMConfig(llm))

        case .transcribe:
            let transcribe = twfConfig.transcribe ?? TWFTranscribeConfig(model: nil, overwriteExisting: nil, saveAsVersion: nil)
            return .transcribe(convertTranscribeConfig(transcribe))

        case .transform:
            guard let transform = twfConfig.transform else {
                throw TWFLoaderError.invalidConfig("Transform step missing 'transform' config")
            }
            return .transform(convertTransformConfig(transform))

        case .conditional:
            guard let conditional = twfConfig.conditional else {
                throw TWFLoaderError.invalidConfig("Conditional step missing 'conditional' config")
            }
            return .conditional(convertConditionalConfig(conditional, stepIdMap: stepIdMap))

        case .notification:
            guard let notification = twfConfig.notification else {
                throw TWFLoaderError.invalidConfig("Notification step missing 'notification' config")
            }
            return .notification(convertNotificationConfig(notification))

        case .iOSPush:
            guard let iosPush = twfConfig.iOSPush else {
                throw TWFLoaderError.invalidConfig("iOS Push step missing 'iOSPush' config")
            }
            return .iOSPush(convertiOSPushConfig(iosPush))

        case .clipboard:
            guard let clipboard = twfConfig.clipboard else {
                throw TWFLoaderError.invalidConfig("Clipboard step missing 'clipboard' config")
            }
            return .clipboard(ClipboardStepConfig(content: clipboard.content))

        case .saveFile:
            guard let saveFile = twfConfig.saveFile else {
                throw TWFLoaderError.invalidConfig("Save File step missing 'saveFile' config")
            }
            return .saveFile(convertSaveFileConfig(saveFile))

        case .appleReminders:
            guard let reminders = twfConfig.appleReminders else {
                throw TWFLoaderError.invalidConfig("Apple Reminders step missing 'appleReminders' config")
            }
            return .appleReminders(convertAppleRemindersConfig(reminders))

        case .shell:
            guard let shell = twfConfig.shell else {
                throw TWFLoaderError.invalidConfig("Shell step missing 'shell' config")
            }
            return .shell(convertShellConfig(shell))

        case .trigger:
            let trigger = twfConfig.trigger ?? TWFTriggerConfig(phrases: nil, caseSensitive: nil, searchLocation: nil, contextWindowSize: nil, stopIfNoMatch: nil)
            return .trigger(convertTriggerConfig(trigger))

        case .intentExtract:
            let intentExtract = twfConfig.intentExtract ?? TWFIntentExtractConfig(inputKey: nil, extractionMethod: nil, confidenceThreshold: nil)
            return .intentExtract(convertIntentExtractConfig(intentExtract))

        case .executeWorkflows:
            let executeWorkflows = twfConfig.executeWorkflows ?? TWFExecuteWorkflowsConfig(intentsKey: nil, stopOnError: nil, parallel: nil)
            return .executeWorkflows(convertExecuteWorkflowsConfig(executeWorkflows))

        case .speak:
            // Speak config from TWF (or use defaults)
            let speak = twfConfig.speak
            // Map TWF provider string to TTSProvider
            let provider: TTSProvider
            if let providerStr = speak?.provider {
                provider = TTSProvider(rawValue: providerStr) ?? .speakeasy
            } else {
                provider = .speakeasy  // Default to SpeakEasy
            }
            return .speak(SpeakStepConfig(
                text: speak?.text ?? "{{OUTPUT}}",
                provider: provider,
                voice: speak?.voiceIdentifier ?? speak?.voice,
                rate: speak?.rate ?? 0.5,
                pitch: speak?.pitch ?? 1.0,
                playImmediately: speak?.playImmediately ?? true,
                saveToFile: speak?.saveToFile ?? false,
                uploadToWalkie: speak?.uploadToWalkie ?? true,
                useCache: speak?.useCache ?? true
            ))

        case .webhook, .email, .appleNotes, .appleCalendar:
            // These types need their configs implemented
            return StepConfig.defaultConfig(for: stepType)
        }
    }

    // MARK: - Config Converters

    private static func convertLLMConfig(_ twf: TWFLLMConfig) -> LLMStepConfig {
        var provider: WorkflowLLMProvider? = nil
        if let providerStr = twf.provider {
            provider = WorkflowLLMProvider(rawValue: providerStr)
        }

        var costTier: LLMCostTier? = nil
        if let tierStr = twf.costTier {
            costTier = LLMCostTier(rawValue: tierStr)
        }

        return LLMStepConfig(
            provider: provider,
            modelId: twf.modelId,
            costTier: costTier,
            autoRoute: provider == nil,  // Auto-route if no explicit provider
            prompt: twf.prompt,
            systemPrompt: twf.systemPrompt,
            temperature: twf.temperature ?? 0.7,
            maxTokens: twf.maxTokens ?? 1024,
            topP: twf.topP ?? 0.9
        )
    }

    private static func convertTranscribeConfig(_ twf: TWFTranscribeConfig) -> TranscribeStepConfig {
        return TranscribeStepConfig(
            model: twf.model ?? "openai_whisper-small",
            overwriteExisting: twf.overwriteExisting ?? false,
            saveAsVersion: twf.saveAsVersion ?? true
        )
    }

    private static func convertTransformConfig(_ twf: TWFTransformConfig) -> TransformStepConfig {
        let operation = TransformStepConfig.TransformOperation(rawValue: twf.operation) ?? .extractJSON
        return TransformStepConfig(
            operation: operation,
            parameters: twf.parameters ?? [:]
        )
    }

    private static func convertConditionalConfig(_ twf: TWFConditionalConfig, stepIdMap: [String: UUID]) -> ConditionalStepConfig {
        // Convert step slug references to UUIDs
        let thenUUIDs = (twf.thenSteps ?? []).compactMap { stepIdMap[$0] }
        let elseUUIDs = (twf.elseSteps ?? []).compactMap { stepIdMap[$0] }

        return ConditionalStepConfig(
            condition: twf.condition,
            thenSteps: thenUUIDs,
            elseSteps: elseUUIDs
        )
    }

    private static func convertNotificationConfig(_ twf: TWFNotificationConfig) -> NotificationStepConfig {
        return NotificationStepConfig(
            title: twf.title,
            body: twf.body,
            sound: twf.sound ?? true,
            actionLabel: twf.actionLabel
        )
    }

    private static func convertiOSPushConfig(_ twf: TWFiOSPushConfig) -> iOSPushStepConfig {
        return iOSPushStepConfig(
            title: twf.title,
            body: twf.body,
            sound: twf.sound ?? true,
            includeOutput: twf.includeOutput ?? false
        )
    }

    private static func convertSaveFileConfig(_ twf: TWFSaveFileConfig) -> SaveFileStepConfig {
        return SaveFileStepConfig(
            filename: twf.filename,
            directory: twf.directory,
            content: twf.content,
            appendIfExists: twf.appendIfExists ?? false
        )
    }

    private static func convertAppleRemindersConfig(_ twf: TWFAppleRemindersConfig) -> AppleRemindersStepConfig {
        let priority: AppleRemindersStepConfig.ReminderPriority
        switch twf.priority {
        case 1: priority = .high
        case 5: priority = .medium
        case 9: priority = .low
        default: priority = .none
        }

        return AppleRemindersStepConfig(
            listName: twf.listName,
            title: twf.title,
            notes: twf.notes,
            dueDate: twf.dueDate,
            priority: priority
        )
    }

    private static func convertShellConfig(_ twf: TWFShellConfig) -> ShellStepConfig {
        return ShellStepConfig(
            executable: twf.executable,
            arguments: twf.arguments ?? [],
            workingDirectory: twf.workingDirectory,
            environment: twf.environment ?? [:],
            stdin: twf.stdin,
            promptTemplate: nil,
            timeout: twf.timeout ?? 30,
            captureStderr: twf.captureStderr ?? true
        )
    }

    private static func convertTriggerConfig(_ twf: TWFTriggerConfig) -> TriggerStepConfig {
        let searchLocation: TriggerStepConfig.SearchLocation
        switch twf.searchLocation {
        case "Start": searchLocation = .start
        case "Anywhere": searchLocation = .anywhere
        default: searchLocation = .end
        }

        return TriggerStepConfig(
            phrases: twf.phrases ?? ["hey talkie"],
            caseSensitive: twf.caseSensitive ?? false,
            searchLocation: searchLocation,
            contextWindowSize: twf.contextWindowSize ?? 200,
            stopIfNoMatch: twf.stopIfNoMatch ?? true
        )
    }

    private static func convertIntentExtractConfig(_ twf: TWFIntentExtractConfig) -> IntentExtractStepConfig {
        let method: IntentExtractStepConfig.ExtractionMethod
        switch twf.extractionMethod {
        case "LLM": method = .llm
        case "Keywords": method = .keywords
        default: method = .hybrid
        }

        return IntentExtractStepConfig(
            inputKey: twf.inputKey ?? "{{PREVIOUS_OUTPUT}}",
            extractionMethod: method,
            recognizedIntents: IntentDefinition.defaults,
            confidenceThreshold: twf.confidenceThreshold ?? 0.5
        )
    }

    private static func convertExecuteWorkflowsConfig(_ twf: TWFExecuteWorkflowsConfig) -> ExecuteWorkflowsStepConfig {
        return ExecuteWorkflowsStepConfig(
            intentsKey: twf.intentsKey ?? "{{PREVIOUS_OUTPUT}}",
            stopOnError: twf.stopOnError ?? false,
            parallel: twf.parallel ?? false
        )
    }
}

