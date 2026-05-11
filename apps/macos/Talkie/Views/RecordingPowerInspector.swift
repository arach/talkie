//
//  RecordingPowerInspector.swift
//  Talkie
//
//  Power inspector for Recording metadata - shows everything we know
//  For debugging sync, migration, and data flow issues
//

import SwiftUI
import TalkieKit

#if DEBUG

/// Comprehensive metadata inspector for Recording model
/// Cmd+Shift+F to open from RecordingDetail
struct RecordingPowerInspector: View {
    let recording: TalkieObject

    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false
    @State private var copyMode: CopyMode = .formatted
    @State private var expandedSections: Set<String> = ["identity", "audio", "timestamps", "transcription", "metadata"]

    enum CopyMode: String, CaseIterable {
        case formatted = "Formatted"
        case json = "JSON"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identitySection
                    audioSection
                    timestampsSection
                    transcriptionSection
                    aiProcessingSection
                    syncSection
                    richMetadataSection
                    rawJSONSection
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
        .background(Theme.current.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording Inspector")
                    .font(.headline)

                Text(recording.id.uuidString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .textSelection(.enabled)
            }

            Spacer()

            // Copy mode picker
            Picker("", selection: $copyMode) {
                ForEach(CopyMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            // Copy button
            Button(action: copyAllData) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.clipboard")
                    Text(showCopied ? "Copied!" : "Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(showCopied ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15))
                .foregroundColor(showCopied ? .green : .accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding()
        .background(Theme.current.surfaceBase)
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        CollapsibleSection(title: "IDENTITY", isExpanded: binding(for: "identity")) {
            VStack(spacing: 0) {
                inspectorRow("id", recording.id.uuidString, mono: true)
                inspectorRow("type", recording.type.rawValue, badge: recording.type == .memo ? .blue : .cyan)
                inspectorRow("source", recording.source.rawValue, badge: recording.source.color)
                inspectorRow("sourceDeviceId", recording.sourceDeviceId ?? "nil", dim: recording.sourceDeviceId == nil)
                inspectorRow("isMemo", recording.isMemo.description)
                inspectorRow("isDictation", recording.isDictation.description)
                inspectorRow("wasPromoted", recording.wasPromoted.description, highlight: recording.wasPromoted)
                inspectorRow("isDeleted", recording.isDeleted.description, highlight: recording.isDeleted)
            }
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        CollapsibleSection(title: "AUDIO", isExpanded: binding(for: "audio")) {
            VStack(spacing: 0) {
                inspectorRow("duration", String(format: "%.2f sec", recording.duration))

                // Database column value
                inspectorRow("audioFilename (db)", recording.audioFilename ?? "nil", dim: recording.audioFilename == nil, mono: true)

                // ID-based path check (TalkieAgent convention)
                let idBasedPath = AudioStorage.audioDirectory.appendingPathComponent("\(recording.id.uuidString).m4a")
                let idBasedExists = FileManager.default.fileExists(atPath: idBasedPath.path)
                inspectorRow("{id}.m4a exists", idBasedExists ? "YES" : "NO",
                           badge: idBasedExists ? .green : (recording.audioFilename == nil ? .orange : nil))

                // Computed values (after fallback logic)
                inspectorRow("hasAudio (computed)", recording.hasAudio.description,
                           badge: recording.hasAudio ? .green : .red)

                if let url = recording.audioURL {
                    let usingFallback = recording.audioFilename == nil
                    inspectorRow("audioURL", url.lastPathComponent + (usingFallback ? " (fallback)" : ""), mono: true)

                    let exists = FileManager.default.fileExists(atPath: url.path)
                    inspectorRow("File exists", exists ? "YES" : "NO", highlight: !exists, badge: exists ? .green : .red)

                    if exists {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                            if let size = attrs[.size] as? Int64 {
                                inspectorRow("File size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            }
                            if let modified = attrs[.modificationDate] as? Date {
                                inspectorRow("File modified", formatDate(modified))
                            }
                        }
                    }
                } else {
                    inspectorRow("audioURL", "nil (no file found)", highlight: true)
                }
            }
        }
    }

    // MARK: - Timestamps Section

    private var timestampsSection: some View {
        CollapsibleSection(title: "TIMESTAMPS", isExpanded: binding(for: "timestamps")) {
            VStack(spacing: 0) {
                inspectorRow("createdAt", formatDateFull(recording.createdAt))
                inspectorRow("lastModified", recording.lastModified.map { formatDateFull($0) } ?? "nil", dim: recording.lastModified == nil)
                inspectorRow("deletedAt", recording.deletedAt.map { formatDateFull($0) } ?? "nil", dim: recording.deletedAt == nil)
                inspectorRow("promotedAt", recording.promotedAt.map { formatDateFull($0) } ?? "nil", dim: recording.promotedAt == nil)

                // Time since creation
                let age = Date().timeIntervalSince(recording.createdAt)
                inspectorRow("Age", formatAge(age))
            }
        }
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        CollapsibleSection(title: "TRANSCRIPTION", isExpanded: binding(for: "transcription")) {
            VStack(spacing: 0) {
                let statusColor: Color = {
                    switch recording.transcriptionStatus {
                    case .success: return .green
                    case .pending: return .orange
                    case .failed: return .red
                    }
                }()
                inspectorRow("transcriptionStatus", recording.transcriptionStatus.rawValue, badge: statusColor)
                inspectorRow("isTranscribing (computed)", recording.isTranscribing.description)
                inspectorRow("transcriptionModel", recording.transcriptionModel ?? "nil", dim: recording.transcriptionModel == nil, mono: true)
                inspectorRow("transcriptionError", recording.transcriptionError ?? "nil", dim: recording.transcriptionError == nil, highlight: recording.transcriptionError != nil)

                Divider().padding(.vertical, 4)

                inspectorRow("text length", recording.text.map { "\($0.count) chars" } ?? "nil", dim: recording.text == nil)
                inspectorRow("wordCount (computed)", "\(recording.wordCount) words")
                inspectorRow("title", recording.title ?? "nil", dim: recording.title == nil)
                inspectorRow("notes length", recording.notes.map { "\($0.count) chars" } ?? "nil", dim: recording.notes == nil)
            }
        }
    }

    // MARK: - AI Processing Section

    private var aiProcessingSection: some View {
        CollapsibleSection(title: "AI PROCESSING", isExpanded: binding(for: "ai")) {
            VStack(spacing: 0) {
                inspectorRow("autoProcessed", recording.autoProcessed.description)
                inspectorRow("isProcessing (computed)", recording.isProcessing.description, highlight: recording.isProcessing)

                Divider().padding(.vertical, 4)

                inspectorRow("isProcessingSummary", recording.isProcessingSummary.description, highlight: recording.isProcessingSummary)
                inspectorRow("summary length", recording.summary.map { "\($0.count) chars" } ?? "nil", dim: recording.summary == nil)

                inspectorRow("isProcessingTasks", recording.isProcessingTasks.description, highlight: recording.isProcessingTasks)
                inspectorRow("tasks length", recording.tasks.map { "\($0.count) chars" } ?? "nil", dim: recording.tasks == nil)

                inspectorRow("isProcessingReminders", recording.isProcessingReminders.description, highlight: recording.isProcessingReminders)
                inspectorRow("reminders length", recording.reminders.map { "\($0.count) chars" } ?? "nil", dim: recording.reminders == nil)
            }
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        CollapsibleSection(title: "SYNC & WORKFLOWS", isExpanded: binding(for: "sync")) {
            VStack(spacing: 0) {
                inspectorRow("cloudSyncedAt", recording.cloudSyncedAt.map { formatDateFull($0) } ?? "nil", dim: recording.cloudSyncedAt == nil)

                if let syncedAt = recording.cloudSyncedAt {
                    let syncAge = Date().timeIntervalSince(syncedAt)
                    inspectorRow("Last sync", formatAge(syncAge) + " ago")
                }

                inspectorRow("pendingWorkflowIds", recording.pendingWorkflowIds ?? "nil", dim: recording.pendingWorkflowIds == nil, mono: true)
            }
        }
    }

    // MARK: - Rich Metadata Section (from JSON)

    private var richMetadataSection: some View {
        CollapsibleSection(title: "RICH METADATA (JSON)", isExpanded: binding(for: "metadata")) {
            VStack(spacing: 0) {
                if let metadata = recording.metadata {
                    // App Context
                    if let app = metadata.app {
                        inspectorRow("app.bundleId", app.bundleId ?? "nil", dim: app.bundleId == nil, mono: true)
                        inspectorRow("app.name", app.name ?? "nil", dim: app.name == nil)
                        inspectorRow("app.windowTitle", app.windowTitle ?? "nil", dim: app.windowTitle == nil)
                    } else {
                        inspectorRow("app", "nil", dim: true)
                    }

                    Divider().padding(.vertical, 4)

                    // End App Context
                    if let endApp = metadata.endApp {
                        inspectorRow("endApp.bundleId", endApp.bundleId ?? "nil", dim: endApp.bundleId == nil, mono: true)
                        inspectorRow("endApp.name", endApp.name ?? "nil", dim: endApp.name == nil)
                    } else {
                        inspectorRow("endApp", "nil", dim: true)
                    }

                    Divider().padding(.vertical, 4)

                    // Rich Context
                    if let context = metadata.context {
                        inspectorRow("context.browserURL", context.browserURL ?? "nil", dim: context.browserURL == nil, mono: true)
                        inspectorRow("context.terminalWorkingDir", context.terminalWorkingDir ?? "nil", dim: context.terminalWorkingDir == nil, mono: true)
                        inspectorRow("context.documentURL", context.documentURL ?? "nil", dim: context.documentURL == nil, mono: true)
                    } else {
                        inspectorRow("context", "nil", dim: true)
                    }

                    Divider().padding(.vertical, 4)

                    // Performance
                    if let perf = metadata.performance {
                        inspectorRow("perf.engineMs", perf.engineMs.map { "\($0) ms" } ?? "nil", dim: perf.engineMs == nil)
                        inspectorRow("perf.endToEndMs", perf.endToEndMs.map { "\($0) ms" } ?? "nil", dim: perf.endToEndMs == nil)
                        inspectorRow("perf.inAppMs", perf.inAppMs.map { "\($0) ms" } ?? "nil", dim: perf.inAppMs == nil)
                        inspectorRow("perf.sessionId", perf.sessionId ?? "nil", dim: perf.sessionId == nil, mono: true)
                    } else {
                        inspectorRow("performance", "nil", dim: true)
                    }

                    Divider().padding(.vertical, 4)

                    // Routing
                    if let routing = metadata.routing {
                        inspectorRow("routing.mode", routing.mode ?? "nil", dim: routing.mode == nil)
                        inspectorRow("routing.wasRouted", routing.wasRouted.map { $0.description } ?? "nil", dim: routing.wasRouted == nil)
                        if let ts = routing.pasteTimestamp {
                            inspectorRow("routing.pasteTimestamp", formatDateFull(Date(timeIntervalSince1970: ts)))
                        } else {
                            inspectorRow("routing.pasteTimestamp", "nil", dim: true)
                        }
                    } else {
                        inspectorRow("routing", "nil", dim: true)
                    }

                    Divider().padding(.vertical, 4)

                    // Audio Metrics
                    if let audio = metadata.audio {
                        inspectorRow("audio.peakAmplitude", audio.peakAmplitude.map { String(format: "%.4f", $0) } ?? "nil", dim: audio.peakAmplitude == nil)
                        inspectorRow("audio.averageAmplitude", audio.averageAmplitude.map { String(format: "%.4f", $0) } ?? "nil", dim: audio.averageAmplitude == nil)
                    } else {
                        inspectorRow("audio", "nil", dim: true)
                    }
                } else {
                    inspectorRow("metadataJSON", recording.metadataJSON == nil ? "nil" : "Parse failed", dim: true, highlight: recording.metadataJSON != nil)
                }
            }
        }
    }

    // MARK: - Raw JSON Section

    private var rawJSONSection: some View {
        CollapsibleSection(title: "RAW DATA", isExpanded: binding(for: "raw")) {
            VStack(alignment: .leading, spacing: 8) {
                if let json = recording.metadataJSON {
                    Text("metadataJSON:")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Pretty print JSON
                    if let data = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data),
                       let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
                       let prettyString = String(data: pretty, encoding: .utf8) {
                        Text(prettyString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.current.surface1)
                            .cornerRadius(4)
                    } else {
                        Text(json)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No metadataJSON")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Divider().padding(.vertical, 4)

                // Text preview
                if let text = recording.text {
                    Text("text (first 200 chars):")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(String(text.prefix(200)) + (text.count > 200 ? "..." : ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.current.surface1)
                        .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func binding(for section: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private func inspectorRow(_ label: String, _ value: String, dim: Bool = false, highlight: Bool = false, mono: Bool = false, badge: Color? = nil) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 180, alignment: .leading)

            if let badgeColor = badge {
                HStack(spacing: 4) {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 6, height: 6)
                    Text(value)
                        .font(.system(size: 11, design: mono ? .monospaced : .default))
                        .foregroundColor(highlight ? .orange : (dim ? .gray : Theme.current.foreground))
                }
            } else {
                Text(value)
                    .font(.system(size: 11, design: mono ? .monospaced : .default))
                    .foregroundColor(highlight ? .orange : (dim ? .gray : Theme.current.foreground))
            }

            Spacer()
        }
        .textSelection(.enabled)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(highlight ? Color.orange.opacity(0.1) : Color.clear)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDateFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func formatAge(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }

    // MARK: - Copy

    private func copyAllData() {
        let text: String
        switch copyMode {
        case .formatted:
            text = buildFormattedText()
        case .json:
            text = buildJSON()
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }

    private func buildFormattedText() -> String {
        var lines: [String] = []

        lines.append("=== RECORDING INSPECTOR ===")
        lines.append("")

        // Identity
        lines.append("IDENTITY")
        lines.append("  id: \(recording.id.uuidString)")
        lines.append("  type: \(recording.type.rawValue)")
        lines.append("  source: \(recording.source.rawValue)")
        lines.append("  sourceDeviceId: \(recording.sourceDeviceId ?? "nil")")
        lines.append("  wasPromoted: \(recording.wasPromoted)")
        lines.append("  isDeleted: \(recording.isDeleted)")
        lines.append("")

        // Audio
        lines.append("AUDIO")
        lines.append("  duration: \(String(format: "%.2f", recording.duration)) sec")
        lines.append("  audioFilename: \(recording.audioFilename ?? "nil")")
        lines.append("  hasAudio: \(recording.hasAudio)")
        if let url = recording.audioURL {
            let exists = FileManager.default.fileExists(atPath: url.path)
            lines.append("  audioURL: \(url.lastPathComponent)")
            lines.append("  File exists: \(exists)")
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                lines.append("  File size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            }
        }
        lines.append("")

        // Timestamps
        lines.append("TIMESTAMPS")
        lines.append("  createdAt: \(formatDateFull(recording.createdAt))")
        lines.append("  lastModified: \(recording.lastModified.map { formatDateFull($0) } ?? "nil")")
        lines.append("  deletedAt: \(recording.deletedAt.map { formatDateFull($0) } ?? "nil")")
        lines.append("  promotedAt: \(recording.promotedAt.map { formatDateFull($0) } ?? "nil")")
        lines.append("")

        // Transcription
        lines.append("TRANSCRIPTION")
        lines.append("  status: \(recording.transcriptionStatus.rawValue)")
        lines.append("  model: \(recording.transcriptionModel ?? "nil")")
        lines.append("  error: \(recording.transcriptionError ?? "nil")")
        lines.append("  text length: \(recording.text?.count ?? 0) chars")
        lines.append("  wordCount: \(recording.wordCount)")
        lines.append("")

        // AI Processing
        lines.append("AI PROCESSING")
        lines.append("  autoProcessed: \(recording.autoProcessed)")
        lines.append("  isProcessingSummary: \(recording.isProcessingSummary)")
        lines.append("  isProcessingTasks: \(recording.isProcessingTasks)")
        lines.append("  isProcessingReminders: \(recording.isProcessingReminders)")
        lines.append("  summary length: \(recording.summary?.count ?? 0) chars")
        lines.append("  tasks length: \(recording.tasks?.count ?? 0) chars")
        lines.append("  reminders length: \(recording.reminders?.count ?? 0) chars")
        lines.append("")

        // Sync
        lines.append("SYNC")
        lines.append("  cloudSyncedAt: \(recording.cloudSyncedAt.map { formatDateFull($0) } ?? "nil")")
        lines.append("  pendingWorkflowIds: \(recording.pendingWorkflowIds ?? "nil")")
        lines.append("")

        // Rich Metadata
        if let metadata = recording.metadata {
            lines.append("RICH METADATA")
            if let app = metadata.app {
                lines.append("  app.bundleId: \(app.bundleId ?? "nil")")
                lines.append("  app.name: \(app.name ?? "nil")")
                lines.append("  app.windowTitle: \(app.windowTitle ?? "nil")")
            }
            if let perf = metadata.performance {
                lines.append("  perf.engineMs: \(perf.engineMs.map { "\($0)" } ?? "nil")")
                lines.append("  perf.endToEndMs: \(perf.endToEndMs.map { "\($0)" } ?? "nil")")
                lines.append("  perf.sessionId: \(perf.sessionId ?? "nil")")
            }
            if let routing = metadata.routing {
                lines.append("  routing.mode: \(routing.mode ?? "nil")")
                lines.append("  routing.wasRouted: \(routing.wasRouted.map { "\($0)" } ?? "nil")")
            }
            lines.append("")
        }

        // Text preview
        if let text = recording.text {
            lines.append("TEXT (first 500 chars)")
            lines.append(String(text.prefix(500)))
        }

        return lines.joined(separator: "\n")
    }

    private func buildJSON() -> String {
        var dict: [String: Any] = [
            "id": recording.id.uuidString,
            "type": recording.type.rawValue,
            "source": recording.source.rawValue,
            "duration": recording.duration,
            "createdAt": formatDateFull(recording.createdAt),
            "transcriptionStatus": recording.transcriptionStatus.rawValue,
            "hasAudio": recording.hasAudio,
            "wordCount": recording.wordCount,
            "autoProcessed": recording.autoProcessed,
            "wasPromoted": recording.wasPromoted,
            "isDeleted": recording.isDeleted
        ]

        // Optional fields
        if let v = recording.sourceDeviceId { dict["sourceDeviceId"] = v }
        if let v = recording.audioFilename { dict["audioFilename"] = v }
        if let v = recording.lastModified { dict["lastModified"] = formatDateFull(v) }
        if let v = recording.deletedAt { dict["deletedAt"] = formatDateFull(v) }
        if let v = recording.promotedAt { dict["promotedAt"] = formatDateFull(v) }
        if let v = recording.transcriptionModel { dict["transcriptionModel"] = v }
        if let v = recording.transcriptionError { dict["transcriptionError"] = v }
        if let v = recording.title { dict["title"] = v }
        if let v = recording.text { dict["text"] = v }
        if let v = recording.notes { dict["notes"] = v }
        if let v = recording.summary { dict["summary"] = v }
        if let v = recording.tasks { dict["tasks"] = v }
        if let v = recording.reminders { dict["reminders"] = v }
        if let v = recording.cloudSyncedAt { dict["cloudSyncedAt"] = formatDateFull(v) }
        if let v = recording.pendingWorkflowIds { dict["pendingWorkflowIds"] = v }
        if let v = recording.metadataJSON { dict["metadataJSON"] = v }

        // Audio file info
        if let url = recording.audioURL {
            let exists = FileManager.default.fileExists(atPath: url.path)
            dict["audioFileExists"] = exists
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                dict["audioFileSize"] = size
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }

        return "{}"
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 14)

                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.current.surface1)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    content()
                }
                .background(Theme.current.surface2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.current.foreground.opacity(0.1), lineWidth: 0.5)
        )
    }
}

#endif
