import SwiftUI

// MARK: - Object Array Field View

/// A view for displaying and editing arrays of objects based on a schema
/// Renders as a collapsible list with expand/collapse for each item
public struct ObjectArrayFieldView: View {
    let fieldSchema: WFFieldSchema
    let objectSchema: WFObjectSchema
    let items: [[String: String]]  // Parsed array of objects
    let isReadOnly: Bool
    let onUpdate: ([[String: String]]) -> Void

    @State private var expandedItems: Set<Int> = []
    @Environment(\.wfTheme) private var theme

    public init(
        fieldSchema: WFFieldSchema,
        objectSchema: WFObjectSchema,
        items: [[String: String]],
        isReadOnly: Bool = true,
        onUpdate: @escaping ([[String: String]]) -> Void = { _ in }
    ) {
        self.fieldSchema = fieldSchema
        self.objectSchema = objectSchema
        self.items = items
        self.isReadOnly = isReadOnly
        self.onUpdate = onUpdate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with item count
            HStack(spacing: 6) {
                if let icon = objectSchema.itemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(theme.textTertiary)
                }

                Text(fieldSchema.displayName)
                    .font(.system(size: 9, weight: .medium, design: .default))
                    .tracking(0.3)
                    .foregroundColor(theme.textTertiary)
                    .textCase(.uppercase)

                Text("(\(items.count))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textTertiary)

                Spacer()

                // Expand/Collapse all button
                if !items.isEmpty {
                    Button(action: toggleAll) {
                        Image(systemName: expandedItems.count == items.count ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(expandedItems.count == items.count ? "Collapse all" : "Expand all")
                }
            }

            // Items list
            if items.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        objectItemView(index: index, item: item)
                    }
                }
            }

            // Add button (only in edit mode)
            if !isReadOnly {
                Button(action: addItem) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text(objectSchema.addLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(theme.accent)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
            Text("No items")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textTertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(theme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Object Item View

    @ViewBuilder
    private func objectItemView(index: Int, item: [String: String]) -> some View {
        let isExpanded = expandedItems.contains(index)
        let displayValue = item[objectSchema.displayField] ?? "Item \(index + 1)"

        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: { toggleItem(index) }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 12)

                    if let icon = objectSchema.itemIcon {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundColor(theme.textSecondary)
                    }

                    Text(displayValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Delete button (only in edit mode)
                    if !isReadOnly {
                        Button(action: { removeItem(at: index) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .opacity(0.6)
                        .help("Remove item")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(theme.inputBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(theme.border.opacity(0.5))
                        .frame(height: 1)

                    // Render fields based on schema
                    ForEach(objectSchema.fields.sorted(by: { $0.order < $1.order })) { field in
                        objectFieldRow(field: field, value: item[field.id], itemIndex: index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .background(theme.inputBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Object Field Row

    @ViewBuilder
    private func objectFieldRow(field: WFFieldSchema, value: String?, itemIndex: Int) -> some View {
        // Skip hidden fields
        if case .hidden = field.type {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Field label
                HStack(spacing: 4) {
                    Text(field.displayName)
                        .font(.system(size: 8, weight: .medium))
                        .tracking(0.3)
                        .foregroundColor(theme.textTertiary)
                        .textCase(.uppercase)

                    if field.isRequired {
                        Text("*")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                    }

                    if let helpText = field.helpText {
                        Button(action: {}) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 8))
                                .foregroundColor(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help(helpText)
                    }
                }

                // Field value display/editor
                if isReadOnly {
                    readOnlyFieldValue(field: field, value: value)
                } else {
                    editableFieldValue(field: field, value: value, itemIndex: itemIndex)
                }
            }
        }
    }

    // MARK: - Read-Only Field Value

    @ViewBuilder
    private func readOnlyFieldValue(field: WFFieldSchema, value: String?) -> some View {
        let displayValue = value ?? field.placeholder ?? "-"

        switch field.type {
        case .boolean:
            HStack(spacing: 6) {
                Image(systemName: (value == "true" || value == "1") ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor((value == "true" || value == "1") ? theme.accent : theme.textTertiary)
                Text((value == "true" || value == "1") ? "Yes" : "No")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
            }

        case .picker(let options):
            let label = options.first(where: { $0.value == value })?.label ?? displayValue
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusXS))

        case .text:
            Text(displayValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusXS))

        default:
            Text(displayValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(value == nil ? theme.textTertiary : theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusXS))
        }
    }

    // MARK: - Editable Field Value (Future)

    @ViewBuilder
    private func editableFieldValue(field: WFFieldSchema, value: String?, itemIndex: Int) -> some View {
        // For now, show read-only even in edit mode
        // Full editing support would require binding updates
        readOnlyFieldValue(field: field, value: value)
    }

    // MARK: - Actions

    private func toggleItem(_ index: Int) {
        if expandedItems.contains(index) {
            expandedItems.remove(index)
        } else {
            expandedItems.insert(index)
        }
    }

    private func toggleAll() {
        if expandedItems.count == items.count {
            expandedItems.removeAll()
        } else {
            expandedItems = Set(0..<items.count)
        }
    }

    private func addItem() {
        var newItems = items
        var newItem: [String: String] = [:]
        for field in objectSchema.fields {
            newItem[field.id] = field.placeholder ?? ""
        }
        newItems.append(newItem)
        onUpdate(newItems)
    }

    private func removeItem(at index: Int) {
        var newItems = items
        newItems.remove(at: index)
        // Update expanded items indices
        expandedItems = Set(expandedItems.compactMap { $0 > index ? $0 - 1 : ($0 < index ? $0 : nil) })
        onUpdate(newItems)
    }
}

// MARK: - String Array Field View

/// A view for displaying and editing arrays of strings
public struct StringArrayFieldView: View {
    let fieldSchema: WFFieldSchema
    let options: WFStringArrayOptions
    let items: [String]
    let isReadOnly: Bool
    let onUpdate: ([String]) -> Void

    @Environment(\.wfTheme) private var theme

    public init(
        fieldSchema: WFFieldSchema,
        options: WFStringArrayOptions,
        items: [String],
        isReadOnly: Bool = true,
        onUpdate: @escaping ([String]) -> Void = { _ in }
    ) {
        self.fieldSchema = fieldSchema
        self.options = options
        self.items = items
        self.isReadOnly = isReadOnly
        self.onUpdate = onUpdate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                if let icon = options.itemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(theme.textTertiary)
                }

                Text(fieldSchema.displayName)
                    .font(.system(size: 9, weight: .medium, design: .default))
                    .tracking(0.3)
                    .foregroundColor(theme.textTertiary)
                    .textCase(.uppercase)

                Text("(\(items.count))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textTertiary)

                Spacer()
            }

            // Items list
            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                    Text("No items")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(theme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                .overlay(
                    RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            if let icon = options.itemIcon {
                                Image(systemName: icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.textSecondary)
                            }

                            Text(item)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            if !isReadOnly {
                                Button(action: { removeItem(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .opacity(0.6)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusXS))
                        .overlay(
                            RoundedRectangle(cornerRadius: WFDesign.radiusXS)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                    }
                }
            }

            // Add button
            if !isReadOnly {
                Button(action: addItem) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text(options.addLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(theme.accent)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addItem() {
        var newItems = items
        newItems.append("")
        onUpdate(newItems)
    }

    private func removeItem(at index: Int) {
        var newItems = items
        newItems.remove(at: index)
        onUpdate(newItems)
    }

    /// Parse a string array from customFields (comma-separated or JSON array)
    static func parseItems(from customFields: [String: String], fieldId: String) -> [String] {
        guard let value = customFields[fieldId] else { return [] }

        // Try JSON array first
        if value.hasPrefix("["),
           let data = value.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }

        // Fallback: comma-separated
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Key-Value Array Field View

/// A view for displaying and editing arrays of key-value pairs
public struct KeyValueArrayFieldView: View {
    let fieldSchema: WFFieldSchema
    let options: WFKeyValueOptions
    let items: [(key: String, value: String)]
    let isReadOnly: Bool
    let onUpdate: ([(key: String, value: String)]) -> Void

    @Environment(\.wfTheme) private var theme

    public init(
        fieldSchema: WFFieldSchema,
        options: WFKeyValueOptions,
        items: [(key: String, value: String)],
        isReadOnly: Bool = true,
        onUpdate: @escaping ([(key: String, value: String)]) -> Void = { _ in }
    ) {
        self.fieldSchema = fieldSchema
        self.options = options
        self.items = items
        self.isReadOnly = isReadOnly
        self.onUpdate = onUpdate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)

                Text(fieldSchema.displayName)
                    .font(.system(size: 9, weight: .medium, design: .default))
                    .tracking(0.3)
                    .foregroundColor(theme.textTertiary)
                    .textCase(.uppercase)

                Text("(\(items.count))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textTertiary)

                Spacer()
            }

            // Items list
            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                    Text("No entries")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(theme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                .overlay(
                    RoundedRectangle(cornerRadius: WFDesign.radiusSM)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Text(item.key)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(theme.accent)
                                .lineLimit(1)
                                .frame(minWidth: 60, alignment: .leading)

                            Text(":")
                                .font(.system(size: 10))
                                .foregroundColor(theme.textTertiary)

                            Text(item.value)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            if !isReadOnly {
                                Button(action: { removeItem(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .opacity(0.6)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusXS))
                        .overlay(
                            RoundedRectangle(cornerRadius: WFDesign.radiusXS)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                    }
                }
            }

            // Add button
            if !isReadOnly {
                Button(action: addItem) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text(options.addLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(theme.accent)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: WFDesign.radiusSM))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addItem() {
        var newItems = items
        newItems.append((key: "", value: ""))
        onUpdate(newItems)
    }

    private func removeItem(at index: Int) {
        var newItems = items
        newItems.remove(at: index)
        onUpdate(newItems)
    }

    /// Parse key-value pairs from customFields (JSON object or "key: value" lines)
    static func parseItems(from customFields: [String: String], fieldId: String) -> [(key: String, value: String)] {
        guard let value = customFields[fieldId] else { return [] }

        // Try JSON object first
        if value.hasPrefix("{"),
           let data = value.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return dict.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        }

        // Fallback: "key: value" per line or "key=value" format
        var result: [(key: String, value: String)] = []
        let lines = value.split(separator: "\n")
        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                result.append((key, val))
            } else if let eqIndex = line.firstIndex(of: "=") {
                let key = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                result.append((key, val))
            }
        }
        return result
    }
}

// MARK: - Helper to Parse Object Array from customFields

extension ObjectArrayFieldView {
    /// Parse an object array from the flattened customFields format
    /// This handles both JSON array strings and the flattened key format (e.g., "field.0.name")
    static func parseItems(from customFields: [String: String], fieldId: String, schema: WFObjectSchema) -> [[String: String]] {
        // First, try to find a JSON array string
        if let jsonString = customFields[fieldId],
           let data = jsonString.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.map { dict in
                var result: [String: String] = [:]
                for (key, value) in dict {
                    if let stringValue = value as? String {
                        result[key] = stringValue
                    } else if let boolValue = value as? Bool {
                        result[key] = boolValue ? "true" : "false"
                    } else {
                        result[key] = String(describing: value)
                    }
                }
                return result
            }
        }

        // Fallback: Try to parse from flattened format (e.g., "recognizedIntents.0.name")
        var itemsDict: [Int: [String: String]] = [:]
        let prefix = "\(fieldId)."

        for (key, value) in customFields {
            if key.hasPrefix(prefix) {
                let suffix = String(key.dropFirst(prefix.count))
                // Parse "0.name" format
                let parts = suffix.split(separator: ".", maxSplits: 1)
                if parts.count == 2, let index = Int(parts[0]) {
                    let fieldKey = String(parts[1])
                    if itemsDict[index] == nil {
                        itemsDict[index] = [:]
                    }
                    itemsDict[index]?[fieldKey] = value
                }
            }
        }

        // Convert to sorted array
        if !itemsDict.isEmpty {
            return itemsDict.keys.sorted().compactMap { itemsDict[$0] }
        }

        // Last resort: If the value is comma-separated, create simple items
        if let commaValue = customFields[fieldId], commaValue.contains(",") {
            let names = commaValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return names.map { [schema.displayField: $0] }
        }

        return []
    }
}
