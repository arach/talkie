import Foundation

// MARK: - Schema Protocol

/// Protocol for host apps to provide workflow schema information.
/// The schema defines node types, their fields, and display metadata.
public protocol WFSchemaProvider {
    /// All available node types in this schema
    var nodeTypes: [WFNodeTypeSchema] { get }

    /// Lookup a node type schema by its identifier
    func schema(for nodeType: String) -> WFNodeTypeSchema?
}

// MARK: - Default Implementation

extension WFSchemaProvider {
    public func schema(for nodeType: String) -> WFNodeTypeSchema? {
        nodeTypes.first { $0.id == nodeType }
    }
}

// MARK: - Node Type Schema

/// Describes a type of node in the workflow (e.g., "LLM", "Notification")
public struct WFNodeTypeSchema: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let category: String
    public let iconName: String?
    public let defaultColor: String?
    public let fields: [WFFieldSchema]

    public init(
        id: String,
        displayName: String,
        category: String,
        iconName: String? = nil,
        defaultColor: String? = nil,
        fields: [WFFieldSchema] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.iconName = iconName
        self.defaultColor = defaultColor
        self.fields = fields
    }
}

// MARK: - Field Schema

/// Describes a field within a node type
public struct WFFieldSchema: Identifiable, Sendable {
    public let id: String           // Key in customFields (e.g., "_0.modelId")
    public let displayName: String  // Human-readable label (e.g., "Model ID")
    public let type: WFFieldType
    public let placeholder: String?
    public let helpText: String?
    public let isRequired: Bool
    public let group: String?       // Optional grouping (e.g., "Model Settings")
    public let order: Int           // Display order within the inspector

    public init(
        id: String,
        displayName: String,
        type: WFFieldType,
        placeholder: String? = nil,
        helpText: String? = nil,
        isRequired: Bool = false,
        group: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.placeholder = placeholder
        self.helpText = helpText
        self.isRequired = isRequired
        self.group = group
        self.order = order
    }
}

// MARK: - Field Types

/// The type of a field, which determines how it's displayed and edited
public enum WFFieldType: Sendable {
    case string
    case text          // Multi-line text
    case number
    case boolean
    case picker([WFPickerOption])
    case slider(min: Double, max: Double, step: Double)
    case color
    case hidden        // Not shown in inspector
    case objectArray(WFObjectSchema)  // Array of objects with a defined schema
    case stringArray(WFStringArrayOptions)  // Simple array of strings
    case keyValueArray(WFKeyValueOptions)   // Array of key-value pairs

    /// Picker option for enum-like fields
    public struct WFPickerOption: Sendable {
        public let value: String
        public let label: String
        public let iconName: String?

        public init(value: String, label: String, iconName: String? = nil) {
            self.value = value
            self.label = label
            self.iconName = iconName
        }
    }
}

// MARK: - Object Schema (for objectArray fields)

/// Describes the schema for objects within an objectArray field
public struct WFObjectSchema: Sendable {
    /// Fields that each object in the array contains
    public let fields: [WFFieldSchema]

    /// Which field's value to show in the collapsed list view (e.g., "name")
    public let displayField: String

    /// Label for the "Add" button (e.g., "Add Intent")
    public let addLabel: String

    /// Optional icon for list items
    public let itemIcon: String?

    public init(
        fields: [WFFieldSchema],
        displayField: String,
        addLabel: String = "Add Item",
        itemIcon: String? = nil
    ) {
        self.fields = fields
        self.displayField = displayField
        self.addLabel = addLabel
        self.itemIcon = itemIcon
    }
}

// MARK: - String Array Options (for stringArray fields)

/// Options for displaying a simple array of strings
public struct WFStringArrayOptions: Sendable {
    /// Placeholder text for new items
    public let placeholder: String

    /// Label for the "Add" button
    public let addLabel: String

    /// Optional icon for list items
    public let itemIcon: String?

    /// Whether items can be reordered
    public let allowReorder: Bool

    public init(
        placeholder: String = "Enter value...",
        addLabel: String = "Add Item",
        itemIcon: String? = nil,
        allowReorder: Bool = true
    ) {
        self.placeholder = placeholder
        self.addLabel = addLabel
        self.itemIcon = itemIcon
        self.allowReorder = allowReorder
    }
}

// MARK: - Key-Value Options (for keyValueArray fields)

/// Options for displaying an array of key-value pairs
public struct WFKeyValueOptions: Sendable {
    /// Placeholder text for keys
    public let keyPlaceholder: String

    /// Placeholder text for values
    public let valuePlaceholder: String

    /// Label for the "Add" button
    public let addLabel: String

    /// Whether keys should be validated as unique
    public let uniqueKeys: Bool

    public init(
        keyPlaceholder: String = "Key",
        valuePlaceholder: String = "Value",
        addLabel: String = "Add Entry",
        uniqueKeys: Bool = true
    ) {
        self.keyPlaceholder = keyPlaceholder
        self.valuePlaceholder = valuePlaceholder
        self.addLabel = addLabel
        self.uniqueKeys = uniqueKeys
    }
}

// MARK: - Empty Schema (Default)

/// Default empty schema when no schema is provided
public struct WFEmptySchema: WFSchemaProvider {
    public let nodeTypes: [WFNodeTypeSchema] = []

    public init() {}
}

// MARK: - Schema Environment Key

import SwiftUI

private struct WFSchemaKey: EnvironmentKey {
    static let defaultValue: (any WFSchemaProvider)? = nil
}

extension EnvironmentValues {
    public var wfSchema: (any WFSchemaProvider)? {
        get { self[WFSchemaKey.self] }
        set { self[WFSchemaKey.self] = newValue }
    }
}
