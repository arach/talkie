//
//  SyncPanel.swift
//  Talkie
//
//  Lightweight panel for sync status and history.
//  Used as both a popover (from status bar) and expanded sheet.
//  Reads all state locally (GRDB + ServiceManager) — zero XPC on open.
//

import SwiftUI
import TalkieKit

// MARK: - Sync Panel Mode

enum SyncPanelMode {
    case popover
    case sheet
}

// MARK: - Sync Panel

struct SyncPanel: View {
    var mode: SyncPanelMode = .popover
    var onExpand: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var initialEventID: String? = nil

    @Environment(CloudKitSyncManager.self) private var syncManager

    @State private var pendingDeletions: [MemoModel] = []
    @State private var selectedDeletions: Set<UUID> = []
    @State private var localMemoCount: Int = 0
    @State private var syncError: String?
    @State private var isSyncInitiating = false
    @State private var showingDeletionsSheet = false
    @State private var showingDevStats = false
    @State private var showActivityLog = true
    @State private var selectedHistoryEvent: SyncEvent?
    @State private var hasAppliedInitialEvent = false

    private let viewModel = MemosViewModel()

    private var syncState: SyncServiceState {
        ServiceManager.shared.sync
    }

    /// True when either we're kicking off a sync or the manager reports syncing
    private var isBusy: Bool {
        isSyncInitiating || syncManager.isSyncing
    }

    private var isSheet: Bool { mode == .sheet }

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var panelWidth: CGFloat { isSheet ? 560 : 420 }
    private var panelHeight: CGFloat { isSheet ? 480 : 380 }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            progressSection

            if mode == .popover {
                pendingDeletionsBanner
            }

            Divider()

            // Inline pending deletions in sheet mode
            if isSheet && !pendingDeletions.isEmpty {
                PendingDeletionsSection(
                    deletions: pendingDeletions,
                    selectedDeletions: $selectedDeletions,
                    onApprove: { approveDeletions() },
                    onRestore: { restoreDeletions() }
                )
                Divider()
            }

            // Activity log (live sync steps)
            activityLogSection

            historySection

            footerSection
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(Theme.current.surfaceBase)
        .task {
            await loadLocalState()
            applyInitialEventIfNeeded()
        }
        .onChange(of: syncManager.syncHistory.count) { _, _ in
            applyInitialEventIfNeeded()
        }
        .sheet(isPresented: $showingDeletionsSheet) {
            deletionsSheet
        }
        .sheet(item: $selectedHistoryEvent) { event in
            SyncEventDetailViewEmbedded(
                event: event,
                onBack: { selectedHistoryEvent = nil },
                onDone: { selectedHistoryEvent = nil },
                backLabel: "Back"
            )
        }
        #if DEBUG
        .sheet(isPresented: $showingDevStats) {
            devStatsSheet
        }
        #endif
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text("Sync")
                    .font(Theme.current.fontTitleMedium)

                statusPill

                Spacer()

                #if DEBUG
                Button {
                    showingDevStats = true
                } label: {
                    Label("Overview", systemImage: "square.stack.3d.up")
                        .font(Theme.current.fontSM)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Sync overview & dev stats")
                #endif

                syncActionButton

                if isSheet {
                    Button("Done") { onDismiss?() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            // Last synced subtitle
            HStack {
                if let lastSync = syncManager.lastSyncDate {
                    Text("Last synced \(smartRelativeTime(lastSync))")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    Text("Never synced")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                if isSheet {
                    Text("\(localMemoCount) memo\(localMemoCount == 1 ? "" : "s")")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(statusPillColor)
                .frame(width: 6, height: 6)
            Text(statusPillLabel)
                .font(Theme.current.fontXSMedium)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background(statusPillColor.opacity(0.12))
        .cornerRadius(10)
        .help(statusPillTooltip)
    }

    private var statusPillColor: Color {
        if isBusy { return .blue }
        if !syncState.isRunning { return .secondary }
        if !syncState.isConnected { return .orange }
        return .green
    }

    private var statusPillLabel: String {
        if isBusy { return "Syncing" }
        if !syncState.isRunning { return "Idle" }
        if !syncState.isConnected { return "Disconnected" }
        return "Connected"
    }

    private var statusPillTooltip: String {
        if isBusy { return "Sync in progress" }
        if !syncState.isRunning { return "Sync helper is not running" }
        if !syncState.isConnected { return "Process running but XPC not connected" }
        return "Sync helper is connected and ready"
    }

    // MARK: - Sync Action Button

    private var syncActionButton: some View {
        HStack(spacing: Spacing.xs) {
            if isBusy {
                // Status label
                HStack(spacing: Spacing.xs) {
                    BrailleSpinner(size: 10)

                    if isSyncInitiating && !syncManager.isSyncing {
                        Text("Starting...")
                            .font(Theme.current.fontSM)
                    } else {
                        Text(SyncClient.shared.syncStatusMessage.isEmpty
                             ? "Syncing..."
                             : SyncClient.shared.syncStatusMessage)
                            .font(Theme.current.fontSM)
                            .lineLimit(1)
                    }
                }

                // Cancel button
                Button {
                    cancelSync()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Cancel sync")
            } else {
                Button {
                    performSync()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                        Text("Sync Now")
                            .font(Theme.current.fontSM)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if isBusy {
            VStack(spacing: Spacing.xs) {
                ProgressView(value: syncManager.isSyncing ? SyncClient.shared.syncProgress : nil)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                if isSyncInitiating && !syncManager.isSyncing {
                    Text("Launching sync service...")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xs)
        }

        // Error banner
        if let error = syncError, !isBusy {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)
                Text(error)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(2)
                Spacer()
                Button {
                    syncError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
            .background(Color.orange.opacity(0.08))
        }
    }

    // MARK: - Pending Deletions Banner (popover only)

    @ViewBuilder
    private var pendingDeletionsBanner: some View {
        if !pendingDeletions.isEmpty {
            Button {
                showingDeletionsSheet = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.orange)
                    Text("\(pendingDeletions.count) pending deletion\(pendingDeletions.count == 1 ? "" : "s")")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(.orange)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.orange.opacity(0.06))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - History

    private var historySection: some View {
        Group {
            if syncManager.syncHistory.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: isSheet ? 32 : 28))
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text("No sync history yet")
                        .font(isSheet ? Theme.current.fontBody : Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(syncManager.syncHistory) { event in
                            Button {
                                selectedHistoryEvent = event
                            } label: {
                                CompactSyncEventRow(event: event, showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.sm) {
                if !isSheet {
                    Text("\(localMemoCount) memo\(localMemoCount == 1 ? "" : "s")")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Copy history
                Button {
                    copyHistoryToClipboard()
                } label: {
                    if isSheet {
                        Label("Copy History", systemImage: "doc.on.doc")
                            .font(Theme.current.fontSM)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(Theme.current.fontXS)
                    }
                }
                .buttonStyle(.borderless)
                .help("Copy sync history")

                // Expand to sheet (popover only)
                if !isSheet, let onExpand {
                    Button {
                        onExpand()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.borderless)
                    .help("Expand to full view")
                }

                #if DEBUG
                if isSheet {
                    Button {
                        showingDevStats = true
                    } label: {
                        Label("Dev Stats", systemImage: "wrench")
                            .font(Theme.current.fontSM)
                    }
                    .buttonStyle(.borderless)
                }
                #endif

                // Settings
                Button {
                    NavigationState.shared.navigateToSettings(.sync)
                    if isSheet { onDismiss?() }
                } label: {
                    if isSheet {
                        Label("Sync Settings", systemImage: "gearshape")
                            .font(Theme.current.fontSM)
                    } else {
                        Image(systemName: "gearshape")
                            .font(Theme.current.fontXS)
                    }
                }
                .buttonStyle(.borderless)
                .help("Sync settings")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Sheets

    private var deletionsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pending Deletions")
                    .font(Theme.current.fontTitleMedium)
                Spacer()
                Button("Done") { showingDeletionsSheet = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(Spacing.lg)

            Divider()

            ScrollView {
                PendingDeletionsSection(
                    deletions: pendingDeletions,
                    selectedDeletions: $selectedDeletions,
                    onApprove: { approveDeletions() },
                    onRestore: { restoreDeletions() }
                )
            }
        }
        .frame(width: 480, height: 400)
        .background(Theme.current.surfaceBase)
    }

    #if DEBUG
    private var devStatsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sync Overview")
                    .font(Theme.current.fontTitleMedium)
                Spacer()
                Button("Done") { showingDevStats = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(Spacing.lg)

            Divider()

            ScrollView {
                DevModeSyncSection(
                    syncManager: syncManager,
                    onForceBridge: {
                        syncManager.forceSyncToGRDB()
                    }
                )
                .padding(.vertical, Spacing.sm)
            }
        }
        .frame(width: 480, height: 400)
        .background(Theme.current.surfaceBase)
    }
    #endif

    // MARK: - Activity Log

    @ViewBuilder
    private var activityLogSection: some View {
        let entries = SyncClient.shared.activityLog
        if !entries.isEmpty {
            VStack(spacing: 0) {
                // Toggle header
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showActivityLog.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: showActivityLog ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .frame(width: 12)

                        Text("Activity")
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .textCase(.uppercase)

                        Spacer()

                        Text("\(entries.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)

                        Button {
                            let lines: [String] = entries.map { entry in
                                let time = Self.logTimeFormatter.string(from: entry.timestamp)
                                let level: String
                                switch entry.level {
                                case .info: level = "info"
                                case .success: level = "ok"
                                case .warning: level = "warn"
                                case .error: level = "error"
                                }
                                return "\(time) [\(level)] \(entry.message)"
                            }
                            let text = lines.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: NSPasteboard.PasteboardType.string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .help("Copy activity log")

                        Button {
                            SyncClient.shared.activityLog.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .help("Clear activity log")
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showActivityLog {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(entries) { entry in
                                    SyncActivityRow(entry: entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.xs)
                        }
                        .frame(maxHeight: isSheet ? 160 : 120)
                        .background(Theme.current.backgroundSecondary.opacity(0.5))
                        .onChange(of: entries.count) { _, _ in
                            if let last = entries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()
            }
        }
    }

    // MARK: - Actions

    private func performSync() {
        syncError = nil
        isSyncInitiating = true
        Task {
            do {
                try await SyncClient.shared.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)
                syncError = nil
            } catch {
                syncError = error.localizedDescription
            }
            isSyncInitiating = false
        }
    }

    private func cancelSync() {
        Task {
            await SyncClient.shared.cancelSync()
            isSyncInitiating = false
        }
    }

    private func loadLocalState() async {
        pendingDeletions = await viewModel.fetchPendingDeletions()
        do {
            localMemoCount = try await LocalRepository().countMemos()
        } catch {
            localMemoCount = 0
        }
    }

    private func approveDeletions() {
        let idsToDelete = selectedDeletions.isEmpty
            ? Set(pendingDeletions.map(\.id))
            : selectedDeletions

        Task {
            await viewModel.permanentlyDeleteMemos(idsToDelete)
            pendingDeletions = await viewModel.fetchPendingDeletions()
            selectedDeletions.removeAll()
        }
    }

    private func restoreDeletions() {
        let idsToRestore = selectedDeletions.isEmpty
            ? Set(pendingDeletions.map(\.id))
            : selectedDeletions

        Task {
            await viewModel.restoreMemos(idsToRestore)
            pendingDeletions = await viewModel.fetchPendingDeletions()
            selectedDeletions.removeAll()
        }
    }

    /// Relative time that says "just now" for anything under 10 seconds
    private func smartRelativeTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 10 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyHistoryToClipboard() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        var text = "Sync History\n============\n\n"

        for event in syncManager.syncHistory {
            let status = event.status.rawValue.capitalized
            let time = dateFormatter.string(from: event.timestamp)
            let duration = event.duration.map { String(format: "%.1fs", $0) } ?? "-"

            let modeTag = event.syncMode.map { " (\($0))" } ?? ""
            text += "[\(status)\(modeTag)] \(time)\n"

            if let inserted = event.inserted, let updated = event.updated, let deleted = event.deleted {
                text += "  +\(inserted) new, ~\(updated) updated, -\(deleted) deleted"
                if let skipped = event.skipped { text += ", =\(skipped) unchanged" }
                text += "\n"
                if let fetchMs = event.fetchTimeMs, let totalMs = event.totalTimeMs {
                    text += "  Timing: fetch \(fetchMs)ms, total \(totalMs)ms\n"
                }
            } else {
                text += "  Items: \(event.itemCount), Duration: \(duration)\n"
            }

            if let local = event.localCount {
                text += "  Local: \(local)"
                if let remote = event.remoteCount {
                    text += ", Remote: \(remote)"
                }
                text += "\n"
            }

            if let error = event.errorMessage {
                text += "  Error: \(error)\n"
            }
            text += "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func applyInitialEventIfNeeded() {
        guard !hasAppliedInitialEvent, let initialEventID else { return }
        guard let event = syncManager.syncHistory.first(where: { $0.id == initialEventID }) else { return }
        selectedHistoryEvent = event
        hasAppliedInitialEvent = true
    }
}

// MARK: - Compact Sync Event Row

struct CompactSyncEventRow: View {
    let event: SyncEvent
    var showsDisclosure: Bool = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status icon
            Image(systemName: event.status.icon)
                .font(.system(size: 12))
                .foregroundColor(event.status.color)
                .frame(width: 16)

            // Summary
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xs) {
                    Text(summaryText)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(summaryColor)
                        .lineLimit(1)

                    if let mode = event.syncMode {
                        Text(mode)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(mode == "incremental" ? .blue : .secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background((mode == "incremental" ? Color.blue : Color.secondary).opacity(0.12))
                            .cornerRadius(3)
                    }
                }

                if event.status == .failed, let error = event.errorMessage {
                    Text(error)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Duration
            if let duration = event.duration {
                Text(String(format: "%.1fs", duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Relative time
            Text(smartRelativeTime(event.timestamp))
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 64, alignment: .trailing)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private var summaryText: String {
        switch event.status {
        case .failed:
            return "Failed"
        case .success where event.inserted != nil:
            // Real stats available — show breakdown
            return statBreakdownText
        case .success where event.itemCount > 0:
            return "+\(event.itemCount) item\(event.itemCount == 1 ? "" : "s")"
        case .success:
            return "Up to date"
        case .partial:
            return "Partial sync"
        }
    }

    /// Build a compact breakdown like "+3 new, ~12 updated" from real sync stats
    private var statBreakdownText: String {
        guard let inserted = event.inserted,
              let updated = event.updated,
              let deleted = event.deleted else {
            return "Up to date"
        }

        if inserted == 0 && updated == 0 && deleted == 0 {
            return "Up to date"
        }

        var parts: [String] = []
        if inserted > 0 { parts.append("+\(inserted) new") }
        if updated > 0 { parts.append("~\(updated) updated") }
        if deleted > 0 { parts.append("-\(deleted) deleted") }
        return parts.joined(separator: ", ")
    }

    private var summaryColor: Color {
        switch event.status {
        case .failed: return .red
        case .success where event.itemCount > 0: return .green
        case .partial: return .orange
        default: return .primary
        }
    }

    private func smartRelativeTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 10 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Sync Activity Row

private struct SyncActivityRow: View {
    let entry: SyncActivityEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
                .frame(width: 56, alignment: .leading)

            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .offset(y: 4)

            Text(entry.message)
                .font(.system(size: 11))
                .foregroundColor(textColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dotColor: Color {
        switch entry.level {
        case .info: return Theme.current.foregroundMuted
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var textColor: Color {
        switch entry.level {
        case .info: return Theme.current.foregroundSecondary
        case .success: return Theme.current.foreground
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Sync Panel Sheet (thin wrapper)

struct SyncPanelSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialEventID: String? = nil

    var body: some View {
        SyncPanel(mode: .sheet, onDismiss: { dismiss() }, initialEventID: initialEventID)
    }
}
