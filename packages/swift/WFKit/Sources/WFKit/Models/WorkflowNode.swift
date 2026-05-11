import Foundation
import SwiftUI

// MARK: - Color Extension for Hex Support

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Node Types

public enum NodeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case trigger = "Trigger"
    case llm = "LLM"
    case transform = "Transform"
    case condition = "Condition"
    case action = "Action"
    case notification = "Notification"
    case output = "Output"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .trigger: return "bolt.fill"
        case .llm: return "brain"
        case .transform: return "wand.and.rays"
        case .condition: return "arrow.triangle.branch"
        case .action: return "play.fill"
        case .notification: return "bell.fill"
        case .output: return "square.and.arrow.up"
        }
    }

    public var color: Color {
        switch self {
        case .trigger: return Color(hex: "#FF9F0A") // Tactical orange
        case .llm: return Color(hex: "#BF5AF2") // Tactical purple
        case .transform: return Color(hex: "#0A84FF") // Tactical blue
        case .condition: return Color(hex: "#FFD60A") // Tactical yellow
        case .action: return Color(hex: "#30D158") // Tactical green
        case .notification: return Color(hex: "#64D2FF") // Tactical cyan
        case .output: return Color(hex: "#FF375F") // Tactical pink/red
        }
    }

    public var defaultTitle: String {
        switch self {
        case .trigger: return "Start"
        case .llm: return "AI Process"
        case .transform: return "Transform"
        case .condition: return "If/Else"
        case .action: return "Action"
        case .notification: return "Notify"
        case .output: return "Output"
        }
    }
}

// MARK: - Port (Connection Point)

public struct Port: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var label: String
    public var isInput: Bool

    public init(id: UUID = UUID(), label: String, isInput: Bool) {
        self.id = id
        self.label = label
        self.isInput = isInput
    }

    public static func input(_ label: String = "In") -> Port {
        Port(label: label, isInput: true)
    }

    public static func output(_ label: String = "Out") -> Port {
        Port(label: label, isInput: false)
    }
}

// MARK: - Workflow Node

public struct WorkflowNode: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var type: NodeType
    public var title: String
    public var position: CGPoint
    public var size: CGSize
    public var inputs: [Port]
    public var outputs: [Port]
    public var configuration: NodeConfiguration
    public var isCollapsed: Bool
    public var customColor: String? // Store as hex string for Codable support

    // Computed property for getting the effective color
    public var effectiveColor: Color {
        if let hexColor = customColor {
            return Color(hex: hexColor)
        }
        return type.color
    }

    public init(
        id: UUID = UUID(),
        type: NodeType,
        title: String? = nil,
        position: CGPoint = .zero,
        size: CGSize = CGSize(width: 200, height: 120),
        inputs: [Port]? = nil,
        outputs: [Port]? = nil,
        configuration: NodeConfiguration = NodeConfiguration(),
        isCollapsed: Bool = false,
        customColor: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title ?? type.defaultTitle
        self.position = position
        self.size = size
        self.inputs = inputs ?? Self.defaultInputs(for: type)
        self.outputs = outputs ?? Self.defaultOutputs(for: type)
        self.configuration = configuration
        self.isCollapsed = isCollapsed
        self.customColor = customColor
    }

    public static func defaultInputs(for type: NodeType) -> [Port] {
        switch type {
        case .trigger:
            return [] // Triggers have no inputs
        case .condition:
            return [.input("In")]
        default:
            return [.input("In")]
        }
    }

    public static func defaultOutputs(for type: NodeType) -> [Port] {
        switch type {
        case .output:
            return [] // Output nodes have no outputs
        case .condition:
            return [.output("True"), .output("False")]
        default:
            return [.output("Out")]
        }
    }

    // Hashable conformance
    public static func == (lhs: WorkflowNode, rhs: WorkflowNode) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Node Configuration

// MARK: - Notification Channel

public enum NotificationChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case push = "Push"
    case email = "Email"
    case sms = "SMS"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .push: return "bell.badge"
        case .email: return "envelope"
        case .sms: return "message"
        }
    }
}

public struct NodeConfiguration: Codable, Hashable, Sendable {
    // LLM settings
    public var prompt: String?
    public var systemPrompt: String?
    public var model: String?
    public var temperature: Double?
    public var maxTokens: Int?

    // Transform settings
    public var transformType: String?
    public var expression: String?

    // Condition settings
    public var condition: String?

    // Action settings
    public var actionType: String?
    public var actionConfig: [String: String]?

    // Notification settings
    public var notificationChannel: NotificationChannel?
    public var notificationTitle: String?
    public var notificationBody: String?
    public var notificationRecipient: String?  // email/phone for email/sms

    // Generic key-value for extensibility
    public var customFields: [String: String]?

    public init(
        prompt: String? = nil,
        systemPrompt: String? = nil,
        model: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        transformType: String? = nil,
        expression: String? = nil,
        condition: String? = nil,
        actionType: String? = nil,
        actionConfig: [String: String]? = nil,
        notificationChannel: NotificationChannel? = nil,
        notificationTitle: String? = nil,
        notificationBody: String? = nil,
        notificationRecipient: String? = nil,
        customFields: [String: String]? = nil
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.transformType = transformType
        self.expression = expression
        self.condition = condition
        self.actionType = actionType
        self.actionConfig = actionConfig
        self.notificationChannel = notificationChannel
        self.notificationTitle = notificationTitle
        self.notificationBody = notificationBody
        self.notificationRecipient = notificationRecipient
        self.customFields = customFields
    }
}
