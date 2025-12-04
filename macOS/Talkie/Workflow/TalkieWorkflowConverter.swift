//
//  TalkieWorkflowConverter.swift
//  Talkie macOS
//
//  Converts Talkie WorkflowDefinition to WFKit CanvasState for visualization
//

import Foundation
import SwiftUI
import WFKit

/// Converts Talkie's linear workflow model to WFKit's node graph model
struct TalkieWorkflowConverter {

    // MARK: - Type Mapping

    /// Map Talkie step types to WFKit node types
    static func mapStepType(_ stepType: WorkflowStep.StepType) -> NodeType {
        switch stepType {
        case .trigger, .intentExtract, .executeWorkflows:
            return .trigger
        case .llm, .transcribe:
            return .llm
        case .transform:
            return .transform
        case .conditional:
            return .condition
        case .shell, .webhook:
            return .action
        case .notification, .iOSPush, .email:
            return .notification
        case .appleNotes, .appleReminders, .appleCalendar, .clipboard, .saveFile:
            return .output
        }
    }

    /// Get a color hex string for the step type
    static func colorForStepType(_ stepType: WorkflowStep.StepType) -> String? {
        switch stepType.category {
        case .ai:
            return "#BF5AF2"  // Purple
        case .communication:
            return "#64D2FF"  // Cyan
        case .apple:
            return "#FF375F"  // Pink
        case .integration:
            return "#FF9F0A"  // Orange
        case .output:
            return "#30D158"  // Green
        case .logic:
            return "#FFD60A"  // Yellow
        case .trigger:
            return "#0A84FF"  // Blue
        }
    }

    // MARK: - Conversion

    /// Convert a Talkie WorkflowDefinition to a WFKit CanvasState
    static func convert(workflow: WorkflowDefinition) -> CanvasState {
        var nodes: [WorkflowNode] = []
        var connections: [WorkflowConnection] = []

        // Layout constants
        let horizontalSpacing: CGFloat = 280
        let startX: CGFloat = 100
        let startY: CGFloat = 150

        // Create nodes for each step
        for (index, step) in workflow.steps.enumerated() {
            let nodeType = mapStepType(step.type)
            let position = CGPoint(
                x: startX + CGFloat(index) * horizontalSpacing,
                y: startY
            )

            // Build node configuration dynamically from step
            let nodeConfig = buildNodeConfiguration(from: step)

            let node = WorkflowNode(
                id: step.id,
                type: nodeType,
                title: step.type.displayName,
                position: position,
                size: CGSize(width: 200, height: 120),
                inputs: index == 0 ? [] : [.input("In")],
                outputs: index == workflow.steps.count - 1 && nodeType == .output ? [] : [.output("Out")],
                configuration: nodeConfig,
                isCollapsed: false,
                customColor: colorForStepType(step.type)
            )
            nodes.append(node)

            // Create connection from previous node
            if index > 0 {
                let previousNode = nodes[index - 1]
                if let sourcePort = previousNode.outputs.first,
                   let targetPort = node.inputs.first {
                    let connection = WorkflowConnection(
                        sourceNodeId: previousNode.id,
                        sourcePortId: sourcePort.id,
                        targetNodeId: node.id,
                        targetPortId: targetPort.id
                    )
                    connections.append(connection)
                }
            }
        }

        // Create canvas state with raw input and metadata for debugging
        let state = CanvasState()
        state.nodes = nodes
        state.connections = connections

        // Store raw workflow data for WFKit capture feature
        if let workflowJSON = encodeWorkflowToJSON(workflow) {
            state.rawInput = workflowJSON
        }
        state.clientMetadata = [
            "workflowId": workflow.id.uuidString,
            "workflowName": workflow.name,
            "stepCount": String(workflow.steps.count),
            "source": "Talkie macOS"
        ]

        return state
    }

    /// Encode the workflow definition to JSON data for WFKit raw input storage
    private static func encodeWorkflowToJSON(_ workflow: WorkflowDefinition) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(workflow)
    }

    // MARK: - Dynamic Configuration Builder

    /// Build WFKit NodeConfiguration dynamically by encoding step config to JSON
    private static func buildNodeConfiguration(from step: WorkflowStep) -> NodeConfiguration {
        var customFields: [String: String] = [:]

        // Add step metadata
        customFields["outputKey"] = step.outputKey
        customFields["isEnabled"] = step.isEnabled ? "true" : "false"
        customFields["stepType"] = step.type.rawValue
        customFields["category"] = step.type.category.rawValue

        // Add condition if present
        if let condition = step.condition {
            customFields["condition"] = condition.expression
            customFields["skipOnFail"] = condition.skipOnFail ? "true" : "false"
        }

        // Dynamically encode the step config to JSON, then flatten to customFields
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        do {
            let jsonData = try encoder.encode(step.config)
            if let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // The config is wrapped in a key like "llm", "shell", etc. - extract the inner object
                if let (configKey, configValue) = jsonDict.first,
                   let innerDict = configValue as? [String: Any] {
                    customFields["configType"] = configKey
                    flattenDictionary(innerDict, prefix: "", into: &customFields)
                }
            }
        } catch {
            customFields["encodingError"] = error.localizedDescription
        }

        // Build NodeConfiguration with well-known fields extracted for better display
        return NodeConfiguration(
            prompt: customFields["prompt"],
            systemPrompt: customFields["systemPrompt"],
            model: customFields["modelId"] ?? customFields["model"],
            temperature: Double(customFields["temperature"] ?? ""),
            maxTokens: Int(customFields["maxTokens"] ?? ""),
            transformType: customFields["operation"],
            expression: customFields["pattern"] ?? customFields["expression"],
            condition: customFields["condition"],
            actionType: customFields["configType"],
            actionConfig: extractActionConfig(from: customFields),
            notificationChannel: parseNotificationChannel(customFields["configType"]),
            notificationTitle: customFields["title"] ?? customFields["subject"],
            notificationBody: customFields["body"],
            notificationRecipient: customFields["to"],
            customFields: customFields
        )
    }

    /// Recursively flatten a dictionary into string key-value pairs
    private static func flattenDictionary(_ dict: [String: Any], prefix: String, into result: inout [String: String]) {
        for (key, value) in dict {
            // Skip Swift enum encoding artifacts like "_0" but still process their contents
            let isEnumArtifact = key.hasPrefix("_") && key.count <= 2
            let fullKey: String
            if isEnumArtifact {
                fullKey = prefix // Use parent prefix, don't append "_0"
            } else if prefix.isEmpty {
                fullKey = key
            } else {
                fullKey = "\(prefix).\(key)"
            }

            switch value {
            case let stringValue as String:
                if !fullKey.isEmpty {
                    result[fullKey] = stringValue
                }
            case let intValue as Int:
                if !fullKey.isEmpty {
                    result[fullKey] = String(intValue)
                }
            case let doubleValue as Double:
                if !fullKey.isEmpty {
                    result[fullKey] = String(format: "%.4g", doubleValue)
                }
            case let boolValue as Bool:
                if !fullKey.isEmpty {
                    result[fullKey] = boolValue ? "true" : "false"
                }
            case let arrayValue as [Any]:
                if !fullKey.isEmpty {
                    result[fullKey] = formatArray(arrayValue)
                }
            case let nestedDict as [String: Any]:
                // For nested objects, flatten with dot notation
                flattenDictionary(nestedDict, prefix: fullKey, into: &result)
            case is NSNull:
                // Skip null values
                break
            default:
                if !fullKey.isEmpty {
                    result[fullKey] = String(describing: value)
                }
            }
        }
    }

    /// Format an array as a readable string
    private static func formatArray(_ array: [Any]) -> String {
        let items = array.compactMap { item -> String? in
            switch item {
            case let string as String:
                return string
            case let dict as [String: Any]:
                // For objects in arrays, show a summary
                if let name = dict["name"] as? String {
                    return name
                }
                return dict.keys.sorted().prefix(3).joined(separator: ", ")
            default:
                return String(describing: item)
            }
        }
        return items.joined(separator: ", ")
    }

    /// Extract action config for shell/webhook/etc
    private static func extractActionConfig(from fields: [String: String]) -> [String: String]? {
        var config: [String: String] = [:]

        // Common action fields
        if let executable = fields["executable"] { config["executable"] = executable }
        if let url = fields["url"] { config["url"] = url }
        if let method = fields["method"] { config["method"] = method }
        if let filename = fields["filename"] { config["filename"] = filename }
        if let title = fields["title"] { config["title"] = title }

        return config.isEmpty ? nil : config
    }

    /// Parse notification channel from config type
    private static func parseNotificationChannel(_ configType: String?) -> NotificationChannel? {
        switch configType {
        case "notification", "iOSPush":
            return .push
        case "email":
            return .email
        default:
            return nil
        }
    }
}
