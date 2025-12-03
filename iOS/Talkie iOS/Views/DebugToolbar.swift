//
//  DebugToolbar.swift
//  Talkie iOS
//
//  Debug toolbar overlay - available on all screens in DEBUG builds
//  Uses Option 4: shared chrome with pluggable context-specific content
//

import SwiftUI
import CoreData

#if DEBUG
/// Reusable debug toolbar with shared chrome and context-specific content
/// Usage: DebugToolbarOverlay { YourContextActions() }
struct DebugToolbarOverlay<Content: View>: View {
    @State private var showToolbar = false
    @State private var showingLogs = false
    @State private var showCopiedFeedback = false
    let contextContent: () -> Content
    let debugInfo: () -> [String: String]

    init(
        @ViewBuilder content: @escaping () -> Content,
        debugInfo: @escaping () -> [String: String] = { [:] }
    ) {
        self.contextContent = content
        self.debugInfo = debugInfo
    }

    /// Convenience init with no context content (system-only)
    init() where Content == EmptyView {
        self.contextContent = { EmptyView() }
        self.debugInfo = { [:] }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Expanded panel
            if showToolbar {
                VStack(alignment: .leading, spacing: 0) {
                    // Header (shared chrome)
                    HStack {
                        Text("DEV")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showToolbar = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surfaceSecondary.opacity(0.5))

                    Divider()
                        .background(Color.borderPrimary)

                    // Content area
                    VStack(alignment: .leading, spacing: 10) {
                        // Context-specific content (passed in by each view)
                        contextContent()

                        // Context state (if any)
                        let info = debugInfo()
                        if !info.isEmpty {
                            DebugSection(title: "STATE") {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(info.keys.sorted()), id: \.self) { key in
                                        DebugInfoRow(label: key, value: info[key] ?? "-")
                                    }
                                }
                            }
                        }

                        // System-level actions (always shown)
                        DebugSection(title: "SYSTEM") {
                            VStack(spacing: 4) {
                                DebugActionButton(icon: "doc.text.magnifyingglass", label: "View Logs") {
                                    showingLogs = true
                                }
                                DebugActionButton(
                                    icon: showCopiedFeedback ? "checkmark" : "doc.on.clipboard",
                                    label: showCopiedFeedback ? "Copied!" : "Copy Debug Info"
                                ) {
                                    copyDebugInfo()
                                }
                            }
                        }
                    }
                    .padding(10)
                    .padding(.bottom, 6)
                }
                .frame(width: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.surfacePrimary.opacity(0.98))
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
                )
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            }

            // Toggle button (always visible - shared chrome)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showToolbar.toggle()
                }
            }) {
                Image(systemName: "ant.fill")
                    .font(.system(size: 14))
                    .foregroundColor(showToolbar ? .active : .textTertiary)
                    .rotationEffect(.degrees(showToolbar ? 180 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showToolbar)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.surfaceSecondary)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.textTertiary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .sheet(isPresented: $showingLogs) {
            DebugLogsView()
        }
    }

    private func copyDebugInfo() {
        let info = debugInfo()
        var lines: [String] = []

        // App info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        lines.append("Talkie iOS \(appVersion) (\(buildNumber))")
        lines.append("iOS \(UIDevice.current.systemVersion)")
        lines.append("Device: \(UIDevice.current.model)")
        lines.append("")

        // Context state
        if !info.isEmpty {
            lines.append("State:")
            for key in info.keys.sorted() {
                lines.append("  \(key): \(info[key] ?? "-")")
            }
            lines.append("")
        }

        // Recent logs (last 5)
        let recentLogs = Array(LogStore.shared.entries.prefix(5))
        if !recentLogs.isEmpty {
            lines.append("Recent Logs:")
            for log in recentLogs {
                lines.append("  [\(log.formattedTime)] \(log.level.rawValue) \(log.category): \(log.message)")
            }
        }

        UIPasteboard.general.string = lines.joined(separator: "\n")

        // Show feedback
        withAnimation {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
}

// MARK: - Debug Logs View

/// Full-screen logs viewer
struct DebugLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logStore = LogStore.shared
    @State private var filterLevel: LogEntry.LogLevel? = nil

    var filteredEntries: [LogEntry] {
        if let level = filterLevel {
            return logStore.entries.filter { $0.level == level }
        }
        return logStore.entries
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter bar
                HStack(spacing: 8) {
                    FilterChip(label: "ALL", isSelected: filterLevel == nil) {
                        filterLevel = nil
                    }
                    FilterChip(label: "INFO", isSelected: filterLevel == .info) {
                        filterLevel = .info
                    }
                    FilterChip(label: "WARN", isSelected: filterLevel == .warning) {
                        filterLevel = .warning
                    }
                    FilterChip(label: "ERROR", isSelected: filterLevel == .error) {
                        filterLevel = .error
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.surfaceSecondary)

                // Log entries
                if filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "doc.text")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(.textTertiary)
                        Text("No logs")
                            .font(.bodySmall)
                            .foregroundColor(.textTertiary)
                        Spacer()
                    }
                } else {
                    List(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.surfacePrimary)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.surfacePrimary)
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        logStore.clear()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(isSelected ? .white : .textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.active : Color.surfacePrimary)
                .cornerRadius(4)
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.formattedTime)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.textTertiary)

                Text(entry.level.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(entry.level.color)

                Text(entry.category)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textPrimary)
                .lineLimit(3)
        }
    }
}

// MARK: - Reusable Debug Components

/// Section header for debug toolbar content
struct DebugSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.textTertiary)

            content()
        }
    }
}

/// Tappable debug action button
struct DebugActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.active)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.textPrimary)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color.surfaceSecondary.opacity(0.5))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Context-Specific Content

/// Debug content for the main memo list view
struct ListViewDebugContent: View {
    var body: some View {
        EmptyView()
    }
}

/// Debug content for the memo detail view
struct DetailViewDebugContent: View {
    let memo: VoiceMemo
    let onTriggerToast: () -> Void
    let onTriggerReminderToast: () -> Void
    @State private var showingDataInspector = false

    var body: some View {
        VStack(spacing: 10) {
            DebugSection(title: "INSPECT") {
                DebugActionButton(icon: "tablecells", label: "VoiceMemo") {
                    showingDataInspector = true
                }
            }

            DebugSection(title: "TOASTS") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "desktopcomputer", label: "Mac Workflow") {
                        onTriggerToast()
                    }
                    DebugActionButton(icon: "bell.fill", label: "Reminder") {
                        onTriggerReminderToast()
                    }
                }
            }
        }
        .sheet(isPresented: $showingDataInspector) {
            ManagedObjectInspector(object: memo)
        }
    }
}

// MARK: - Data Inspector

/// Generic data inspector for any NSManagedObject
struct ManagedObjectInspector: View {
    @ObservedObject var object: NSManagedObject
    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false
    @State private var expandedRelationship: String? = nil

    private var entityName: String {
        object.entity.name ?? "Unknown"
    }

    private var attributes: [(name: String, value: String, type: String)] {
        let entity = object.entity
        return entity.attributesByName
            .sorted { $0.key < $1.key }
            .map { (name, attr) in
                let value = formatValue(object.value(forKey: name), type: attr.attributeType)
                return (name: name, value: value, type: attr.attributeTypeName)
            }
    }

    private var relationships: [(name: String, count: Int, objects: [NSManagedObject])] {
        let entity = object.entity
        return entity.relationshipsByName
            .sorted { $0.key < $1.key }
            .compactMap { (name, rel) in
                if rel.isToMany {
                    if let set = object.value(forKey: name) as? NSSet {
                        let objects = set.allObjects as? [NSManagedObject] ?? []
                        return (name: name, count: objects.count, objects: objects)
                    }
                    return (name: name, count: 0, objects: [])
                } else {
                    if let related = object.value(forKey: name) as? NSManagedObject {
                        return (name: name, count: 1, objects: [related])
                    }
                    return (name: name, count: 0, objects: [])
                }
            }
    }

    var body: some View {
        NavigationView {
            List {
                // Entity info
                Section {
                    InspectorRow(label: "Entity", value: entityName)
                    InspectorRow(label: "Object ID", value: object.objectID.uriRepresentation().lastPathComponent)
                } header: {
                    sectionHeader("OBJECT")
                }

                // Attributes
                Section {
                    ForEach(attributes, id: \.name) { attr in
                        InspectorRow(
                            label: attr.name,
                            value: attr.value,
                            typeHint: attr.type
                        )
                    }
                } header: {
                    sectionHeader("ATTRIBUTES (\(attributes.count))")
                }

                // Relationships
                if !relationships.isEmpty {
                    Section {
                        ForEach(relationships, id: \.name) { rel in
                            RelationshipRow(
                                name: rel.name,
                                count: rel.count,
                                objects: rel.objects,
                                isExpanded: expandedRelationship == rel.name,
                                onToggle: {
                                    withAnimation {
                                        if expandedRelationship == rel.name {
                                            expandedRelationship = nil
                                        } else {
                                            expandedRelationship = rel.name
                                        }
                                    }
                                }
                            )
                        }
                    } header: {
                        sectionHeader("RELATIONSHIPS (\(relationships.count))")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color.surfacePrimary)
            .navigationTitle(entityName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: copyAllData) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.clipboard")
                            if showCopied {
                                Text("Copied")
                                    .font(.system(size: 12))
                            }
                        }
                        .font(.system(size: 14))
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
    }

    private func formatValue(_ value: Any?, type: NSAttributeType) -> String {
        guard let value = value else { return "nil" }

        switch type {
        case .dateAttributeType:
            if let date = value as? Date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return formatter.string(from: date)
            }
        case .binaryDataAttributeType:
            if let data = value as? Data {
                return "\(data.count) bytes"
            }
        case .UUIDAttributeType:
            if let uuid = value as? UUID {
                return uuid.uuidString
            }
        case .booleanAttributeType:
            if let bool = value as? Bool {
                return bool ? "true" : "false"
            }
        case .doubleAttributeType, .floatAttributeType:
            if let num = value as? Double {
                return String(format: "%.2f", num)
            }
        default:
            break
        }

        return String(describing: value)
    }

    private func copyAllData() {
        var lines: [String] = []
        lines.append("=== \(entityName.uppercased()) ===")
        lines.append("Object ID: \(object.objectID.uriRepresentation().lastPathComponent)")
        lines.append("")
        lines.append("ATTRIBUTES")
        for attr in attributes {
            lines.append("  \(attr.name): \(attr.value)")
        }
        lines.append("")
        lines.append("RELATIONSHIPS")
        for rel in relationships {
            lines.append("  \(rel.name): \(rel.count) object(s)")
        }

        UIPasteboard.general.string = lines.joined(separator: "\n")

        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

extension NSAttributeDescription {
    var attributeTypeName: String {
        switch attributeType {
        case .undefinedAttributeType: return "undefined"
        case .integer16AttributeType: return "Int16"
        case .integer32AttributeType: return "Int32"
        case .integer64AttributeType: return "Int64"
        case .decimalAttributeType: return "Decimal"
        case .doubleAttributeType: return "Double"
        case .floatAttributeType: return "Float"
        case .stringAttributeType: return "String"
        case .booleanAttributeType: return "Bool"
        case .dateAttributeType: return "Date"
        case .binaryDataAttributeType: return "Data"
        case .UUIDAttributeType: return "UUID"
        case .URIAttributeType: return "URI"
        case .transformableAttributeType: return "Transformable"
        case .objectIDAttributeType: return "ObjectID"
        case .compositeAttributeType: return "Composite"
        @unknown default: return "unknown"
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String
    var typeHint: String? = nil

    private var isLongValue: Bool {
        value != "nil" && value.count > 60
    }

    var body: some View {
        if isLongValue {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.textSecondary)
                    if let type = typeHint {
                        Text(type)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }

                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .top) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.textSecondary)
                    if let type = typeHint {
                        Text(type)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(value == "nil" ? .textTertiary : .textPrimary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }
    }
}

struct RelationshipRow: View {
    let name: String
    let count: Int
    let objects: [NSManagedObject]
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.textSecondary)

                    Spacer()

                    Text("\(count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(count == 0 ? .textTertiary : .textPrimary)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded && !objects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(objects, id: \.objectID) { obj in
                        RelatedObjectRow(object: obj)
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 12)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RelatedObjectRow: View {
    let object: NSManagedObject
    @State private var showingInspector = false

    private var displayName: String {
        let entity = object.entity
        let attributeNames = Set(entity.attributesByName.keys)

        // Try common name attributes (only if they exist on this entity)
        if attributeNames.contains("title"),
           let title = object.value(forKey: "title") as? String,
           !title.isEmpty {
            return title
        }
        if attributeNames.contains("name"),
           let name = object.value(forKey: "name") as? String,
           !name.isEmpty {
            return name
        }
        if attributeNames.contains("id"),
           let id = object.value(forKey: "id") as? UUID {
            return id.uuidString.prefix(8).description
        }
        // Fallback to object ID
        return object.objectID.uriRepresentation().lastPathComponent
    }

    var body: some View {
        Button(action: { showingInspector = true }) {
            HStack {
                Text(object.entity.name ?? "?")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.active)

                Text(displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.surfaceSecondary.opacity(0.5))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingInspector) {
            ManagedObjectInspector(object: object)
        }
    }
}
#endif
