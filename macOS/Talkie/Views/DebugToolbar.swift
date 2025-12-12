//
//  DebugToolbar.swift
//  Talkie macOS
//
//  Debug toolbar overlay - available in DEBUG builds
//  Provides quick access to dev tools and convenience functions
//
//  Uses DebugKit package for the core overlay, with app-specific content below.
//

import SwiftUI
import CoreData
import UserNotifications
import DebugKit

#if DEBUG

// MARK: - Talkie Debug Toolbar Wrapper

/// Wrapper around DebugKit's DebugToolbar with Talkie-specific content
struct TalkieDebugToolbar<CustomContent: View>: View {
    let debugInfo: () -> [String: String]
    let customContent: CustomContent

    @State private var showingConsole = false

    /// Initialize with custom content and optional debug info (matches original API)
    init(
        @ViewBuilder content: @escaping () -> CustomContent,
        debugInfo: @escaping () -> [String: String] = { [:] }
    ) {
        self.customContent = content()
        self.debugInfo = debugInfo
    }

    var body: some View {
        DebugToolbar(
            title: "DEV",
            icon: "ant.fill",
            sections: buildSections(),
            actions: [
                DebugAction("View Console", icon: "doc.text.magnifyingglass") {
                    showingConsole = true
                }
            ],
            onCopy: { buildCopyText() }
        ) {
            customContent
        }
        .sheet(isPresented: $showingConsole) {
            DebugConsoleSheet()
        }
    }

    private func buildSections() -> [DebugKit.DebugSection] {
        let info = debugInfo()
        guard !info.isEmpty else { return [] }

        let rows = info.keys.sorted().map { key in
            (key, info[key] ?? "-")
        }
        return [DebugKit.DebugSection("STATE", rows)]
    }

    private func buildCopyText() -> String {
        var lines: [String] = []

        // App info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        lines.append("Talkie macOS \(appVersion) (\(buildNumber))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        // Context state
        let info = debugInfo()
        if !info.isEmpty {
            lines.append("State:")
            for key in info.keys.sorted() {
                lines.append("  \(key): \(info[key] ?? "-")")
            }
            lines.append("")
        }

        // Recent events
        let recentEvents = Array(SystemEventManager.shared.events.prefix(5))
        if !recentEvents.isEmpty {
            lines.append("Recent Events:")
            for event in recentEvents {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let time = formatter.string(from: event.timestamp)
                lines.append("  [\(time)] \(event.type.rawValue): \(event.message)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension TalkieDebugToolbar where CustomContent == EmptyView {
    /// Convenience init with no context content (system-only)
    init() {
        self.init(content: { EmptyView() }, debugInfo: { [:] })
    }
}

// MARK: - Legacy Alias (for compatibility)
typealias DebugToolbarOverlay<Content: View> = TalkieDebugToolbar<Content>

// MARK: - Debug Console Sheet

struct DebugConsoleSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("System Console")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Theme.current.surfaceBase)

            Divider()

            // Console view
            SystemConsoleView()
        }
        .frame(width: 700, height: 500)
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
                .foregroundColor(.secondary)

            content()
        }
    }
}

/// Tappable debug action button
struct DebugActionButton: View {
    let icon: String
    let label: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(destructive ? .red : .accentColor)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(destructive ? .red : .primary)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Theme.current.surface2)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

/// Table-style state display for debug toolbar
struct DebugStateTable: View {
    let info: [String: String]
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(info.keys.sorted().enumerated()), id: \.element) { index, key in
                HStack {
                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(info[key] ?? "-")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(index % 2 == 0 ? Theme.current.surfaceAlternate : Color.clear)
            }
        }
        .background(Theme.current.surface1)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Context-Specific Content

/// Debug content for the main memo list view
/// Follows iOS pattern: view-specific actions → convenience → platform-wide utils
struct ListViewDebugContent: View {
    @ObservedObject private var syncManager = CloudKitSyncManager.shared
    @State private var showConfirmation = false
    @State private var confirmationAction: (() -> Void)?
    @State private var confirmationMessage = ""

    var body: some View {
        VStack(spacing: 10) {
            // 1. Page-specific convenience actions
            DebugSection(title: "SYNC") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "arrow.triangle.2.circlepath", label: "Force Sync") {
                        syncManager.syncNow()
                    }
                    DebugActionButton(icon: "arrow.clockwise", label: "Full Sync") {
                        syncManager.forceFullSync()
                    }
                }
            }

            // 2. Auto-run convenience
            DebugSection(title: "AUTO-RUN") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "checkmark.circle", label: "Mark All Processed") {
                        markAllMemosAsProcessed()
                    }
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Reset Migration") {
                        confirmationMessage = "Reset auto-run migration? All memos will be re-processed."
                        confirmationAction = { resetAutoRunMigration() }
                        showConfirmation = true
                    }
                }
            }

            // 3. Utilities
            DebugSection(title: "UTILITIES") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "waveform.slash", label: "Reset Transcription") {
                        resetTranscriptionState()
                    }
                    DebugActionButton(icon: "bell.badge", label: "Test Notification") {
                        sendTestNotification()
                    }
                }
            }

            // 4. Danger zone (platform-wide destructive utils)
            DebugSection(title: "RESET") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Onboarding", destructive: true) {
                        confirmationMessage = "Reset onboarding state?"
                        confirmationAction = { resetOnboarding() }
                        showConfirmation = true
                    }
                    DebugActionButton(icon: "trash", label: "UserDefaults", destructive: true) {
                        confirmationMessage = "Clear all UserDefaults? This will reset all app settings."
                        confirmationAction = { clearUserDefaults() }
                        showConfirmation = true
                    }
                }
            }
        }
        .alert("Confirm Action", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm", role: .destructive) {
                confirmationAction?()
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - Actions

    private func resetTranscriptionState() {
        // Reset service states
        WhisperService.shared.resetTranscriptionState()
        ParakeetService.shared.resetTranscriptionState()

        // Reset any memos stuck in transcribing state
        let context = PersistenceController.shared.container.viewContext
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "isTranscribing == YES")

        do {
            let stuckMemos = try context.fetch(request)
            if stuckMemos.count > 0 {
                for memo in stuckMemos {
                    memo.isTranscribing = false
                }
                try context.save()
                SystemEventManager.shared.logSync(.system, "Reset transcription state", detail: "Services + \(stuckMemos.count) stuck memo(s)")
            } else {
                SystemEventManager.shared.logSync(.system, "Transcription state reset", detail: "WhisperKit + Parakeet (no stuck memos)")
            }
        } catch {
            SystemEventManager.shared.logSync(.error, "Failed to reset memo states", detail: error.localizedDescription)
        }
    }

    private func markAllMemosAsProcessed() {
        let context = PersistenceController.shared.container.viewContext
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "autoProcessed == NO OR autoProcessed == nil")

        do {
            let memos = try context.fetch(request)
            for memo in memos {
                memo.autoProcessed = true
            }
            try context.save()
            SystemEventManager.shared.logSync(.system, "Marked all memos as processed", detail: "\(memos.count) memo(s)")
        } catch {
            SystemEventManager.shared.logSync(.error, "Failed to mark memos", detail: error.localizedDescription)
        }
    }

    private func resetAutoRunMigration() {
        UserDefaults.standard.removeObject(forKey: "autoRunMigrationCompleted")
        SystemEventManager.shared.logSync(.system, "Auto-run migration reset", detail: "Will re-run on next sync")
    }

    private func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        SystemEventManager.shared.logSync(.system, "Onboarding reset")
    }

    private func clearUserDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
            SystemEventManager.shared.logSync(.system, "UserDefaults cleared")
        }
    }

    private func sendTestNotification() {
        // Send iOS push notification via CloudKit
        let context = PersistenceController.shared.container.viewContext

        let pushNotification = PushNotification(context: context)
        pushNotification.id = UUID()
        pushNotification.title = "Extracted 2 Intents"
        pushNotification.body = "• summarize 85%\n• remind (tomorrow) 70%"
        pushNotification.createdAt = Date()
        pushNotification.soundEnabled = true
        pushNotification.isRead = false
        pushNotification.workflowName = "Test Notification"

        do {
            try context.save()
            SystemEventManager.shared.logSync(.system, "iOS push notification queued")
        } catch {
            SystemEventManager.shared.logSync(.error, "Failed to queue notification", detail: error.localizedDescription)
        }
    }
}

/// Alias for backwards compatibility
typealias MainDebugContent = ListViewDebugContent

/// Debug content for the memo detail view
/// Follows iOS pattern: view-specific actions → convenience → platform-wide utils
struct DetailViewDebugContent: View {
    let memo: VoiceMemo
    @State private var showingInspector = false

    var body: some View {
        VStack(spacing: 10) {
            // 1. Page-specific actions (memo operations)
            DebugSection(title: "MEMO") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "bolt.circle", label: "Re-run Auto-Run") {
                        Task {
                            let context = PersistenceController.shared.container.viewContext
                            await AutoRunProcessor.shared.reprocessMemo(memo, context: context)
                        }
                    }
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Reset autoProcessed") {
                        memo.autoProcessed = false
                        try? memo.managedObjectContext?.save()
                        SystemEventManager.shared.logSync(.system, "Reset autoProcessed", detail: memo.title ?? "Untitled")
                    }
                }
            }

            // 2. Data inspection
            DebugSection(title: "INSPECT") {
                DebugActionButton(icon: "tablecells", label: "VoiceMemo Data") {
                    showingInspector = true
                }
            }
        }
        .sheet(isPresented: $showingInspector) {
            ManagedObjectInspector(object: memo)
        }
    }
}

/// Alias for backwards compatibility
typealias MemoDetailDebugContent = DetailViewDebugContent

// MARK: - Data Inspector

/// Generic data inspector for any NSManagedObject
struct ManagedObjectInspector: View {
    @ObservedObject var object: NSManagedObject
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(entityName)
                    .font(.headline)

                Spacer()

                Button(action: copyAllData) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.clipboard")
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: 12))
                        }
                    }
                }

                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Theme.current.surfaceBase)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Object info
                    inspectorSection("OBJECT") {
                        inspectorRow("Entity", entityName)
                        inspectorRow("Object ID", object.objectID.uriRepresentation().lastPathComponent)
                    }

                    // Attributes
                    inspectorSection("ATTRIBUTES (\(attributes.count))") {
                        ForEach(attributes, id: \.name) { attr in
                            inspectorRow(attr.name, attr.value, typeHint: attr.type)
                        }
                    }

                    // Relationships
                    if !relationships.isEmpty {
                        inspectorSection("RELATIONSHIPS (\(relationships.count))") {
                            ForEach(relationships, id: \.name) { rel in
                                relationshipRow(rel.name, rel.count, rel.objects)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }

    private func inspectorSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                content()
            }
            .background(Theme.current.surface2)
            .cornerRadius(6)
        }
    }

    private func inspectorRow(_ label: String, _ value: String, typeHint: String? = nil) -> some View {
        HStack(alignment: .top) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                if let type = typeHint {
                    Text(type)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(value == "nil" ? .gray : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func relationshipRow(_ name: String, _ count: Int, _ objects: [NSManagedObject]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation {
                    if expandedRelationship == name {
                        expandedRelationship = nil
                    } else {
                        expandedRelationship = name
                    }
                }
            }) {
                HStack {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(count == 0 ? .gray : .primary)

                    Image(systemName: expandedRelationship == name ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if expandedRelationship == name && !objects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(objects, id: \.objectID) { obj in
                        relatedObjectRow(obj)
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private func relatedObjectRow(_ object: NSManagedObject) -> some View {
        HStack {
            Text(object.entity.name ?? "?")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)

            Text(displayName(for: object))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Theme.current.surface2)
        .cornerRadius(4)
    }

    private func displayName(for object: NSManagedObject) -> String {
        let entity = object.entity
        let attributeNames = Set(entity.attributesByName.keys)

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
            return String(id.uuidString.prefix(8))
        }
        return object.objectID.uriRepresentation().lastPathComponent
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

        let stringValue = String(describing: value)
        // Truncate very long values
        if stringValue.count > 200 {
            return String(stringValue.prefix(200)) + "..."
        }
        return stringValue
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

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

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

#endif
