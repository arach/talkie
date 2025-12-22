//
//  FailedQueuePicker.swift
//  TalkieLive
//
//  Shows failed/pending transcriptions with retry and delete actions
//

import SwiftUI
import AppKit

// MARK: - Failed Queue Controller

@MainActor
final class FailedQueueController {
    static let shared = FailedQueueController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FailedQueueView>?
    private var eventMonitor: Any?
    private var localEventMonitor: Any?

    private init() {}

    func show() {
        // If already showing, dismiss
        if panel != nil {
            dismiss()
            return
        }

        let items = LiveDatabase.fetchNeedsRetry()
        guard !items.isEmpty else { return }

        let viewModel = FailedQueueViewModel(items: items)
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }
        viewModel.onRetryAll = { [weak self] in
            self?.dismiss()
            Task {
                await TranscriptionRetryManager.shared.retryFailedTranscriptions()
            }
        }

        let view = FailedQueueView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: view)

        // Calculate size based on items - compact rows
        let itemHeight: CGFloat = 36  // More compact
        let headerHeight: CGFloat = 52
        let footerHeight: CGFloat = 52
        let maxItems = min(items.count, 8)  // Show more items
        let height = headerHeight + CGFloat(maxItems) * itemHeight + footerHeight + 12

        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: height)

        // Create floating panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.hasShadow = true

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 220
            let y = screenFrame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
        self.hostingView = hostingView

        // Global monitor for escape key
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                DispatchQueue.main.async {
                    self?.dismiss()
                }
            }
        }

        // Local monitor for keyboard and clicks
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self, weak viewModel] event in
            guard let self, let panel = self.panel else { return event }

            if event.type == .keyDown {
                switch event.keyCode {
                case 53:  // Escape
                    self.dismiss()
                    return nil
                case 125:  // Down arrow
                    viewModel?.selectNext()
                    return nil
                case 126:  // Up arrow
                    viewModel?.selectPrevious()
                    return nil
                case 36:  // Enter - retry selected
                    if viewModel?.isEngineConnected == true {
                        viewModel?.retrySelected()
                    }
                    return nil
                case 51:  // Delete/Backspace - delete selected
                    viewModel?.deleteSelected()
                    return nil
                case 15 where event.modifierFlags.contains(.command):  // Cmd+R - retry all
                    if viewModel?.isEngineConnected == true {
                        viewModel?.retryAll()
                    }
                    return nil
                default:
                    break
                }
            }

            // Click outside to dismiss
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if event.window != panel {
                    self.dismiss()
                }
            }

            return event
        }
    }

    func dismiss() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

// MARK: - View Model

@MainActor
final class FailedQueueViewModel: ObservableObject {
    @Published var items: [LiveDictation]
    @Published var retryingItems: Set<Int64> = []
    @Published var selectedIndex: Int = 0  // For keyboard navigation

    var onDismiss: (() -> Void)?
    var onRetryAll: (() -> Void)?

    var isEngineConnected: Bool {
        EngineClient.shared.isConnected
    }

    init(items: [LiveDictation]) {
        self.items = items
    }

    // Keyboard navigation
    func selectNext() {
        if selectedIndex < items.count - 1 {
            selectedIndex += 1
        }
    }

    func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func retrySelected() {
        guard selectedIndex < items.count else { return }
        retry(items[selectedIndex])
    }

    func deleteSelected() {
        guard selectedIndex < items.count else { return }
        delete(items[selectedIndex])
        // Adjust selection if needed
        if selectedIndex >= items.count && selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func retry(_ item: LiveDictation) {
        guard let id = item.id else { return }
        retryingItems.insert(id)

        Task {
            let success = await TranscriptionRetryManager.shared.retrySingle(item)
            retryingItems.remove(id)

            if success {
                // Remove from list
                items.removeAll { $0.id == id }
                if items.isEmpty {
                    onDismiss?()
                }
            }
        }
    }

    func delete(_ item: LiveDictation) {
        guard let id = item.id else { return }

        // Delete from database (this also removes the audio file)
        LiveDatabase.delete(item)

        // Remove from list
        items.removeAll { $0.id == id }

        if items.isEmpty {
            onDismiss?()
        }
    }

    func retryAll() {
        onRetryAll?()
    }

    func dismiss() {
        onDismiss?()
    }
}

// MARK: - SwiftUI Views

struct FailedQueueView: View {
    @ObservedObject var viewModel: FailedQueueViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending Transcriptions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TalkieTheme.textPrimary)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isEngineConnected ? SemanticColor.success : SemanticColor.warning)
                            .frame(width: 6, height: 6)
                        Text(viewModel.isEngineConnected ? "Engine connected" : "Engine offline")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }

                Spacer()

                Text("\(viewModel.items.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(SemanticColor.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SemanticColor.warning.opacity(0.15))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Divider
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)

            // Items list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        FailedItemRow(
                            item: item,
                            isRetrying: viewModel.retryingItems.contains(item.id ?? -1),
                            isEngineConnected: viewModel.isEngineConnected,
                            isSelected: index == viewModel.selectedIndex,
                            onRetry: { viewModel.retry(item) },
                            onDelete: { viewModel.delete(item) },
                            onSelect: { viewModel.selectedIndex = index }
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            // Divider
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)

            // Footer with Retry All
            HStack {
                Button(action: { viewModel.dismiss() }) {
                    Text("Close")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TalkieTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TalkieTheme.surfaceCard)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Spacer()

                // Keyboard hints
                HStack(spacing: 8) {
                    KeyboardHint(key: "↑↓", label: "nav")
                    KeyboardHint(key: "⏎", label: "retry")
                    KeyboardHint(key: "⌫", label: "delete")
                }

                Spacer()

                if viewModel.isEngineConnected {
                    Button(action: { viewModel.retryAll() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Retry All")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(SemanticColor.success)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(TalkieTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(TalkieTheme.border, lineWidth: 1)
                )
        )
    }
}

struct FailedItemRow: View {
    let item: LiveDictation
    let isRetrying: Bool
    let isEngineConnected: Bool
    let isSelected: Bool
    let onRetry: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    private var statusColor: Color {
        item.transcriptionStatus == .failed ? SemanticColor.error : SemanticColor.warning
    }

    var body: some View {
        HStack(spacing: 8) {
            // Compact: waveform + duration inline
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textTertiary)

                if let duration = item.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)
                }
            }
            .frame(width: 50, alignment: .leading)

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            // Time ago
            Text(timeAgo(from: item.createdAt))
                .font(.system(size: 10))
                .foregroundColor(TalkieTheme.textTertiary)

            // App name
            if let appName = item.appName {
                Text("•")
                    .foregroundColor(TalkieTheme.textMuted)
                Text(appName)
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Actions - smaller buttons
            HStack(spacing: 6) {
                Button(action: onRetry) {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isEngineConnected ? SemanticColor.success : TalkieTheme.textMuted)
                            .frame(width: 24, height: 24)
                            .background(isEngineConnected ? SemanticColor.success.opacity(0.1) : TalkieTheme.surfaceCard)
                            .cornerRadius(5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isEngineConnected || isRetrying)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SemanticColor.error.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(SemanticColor.error.opacity(0.1))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}

// MARK: - Keyboard Hint

struct KeyboardHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(TalkieTheme.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(TalkieTheme.surfaceCard)
                .cornerRadius(3)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(TalkieTheme.textMuted)
        }
    }
}

#Preview {
    let items = [
        LiveDictation(
            text: "",
            appName: "Slack",
            durationSeconds: 12.5,
            wordCount: nil,
            audioFilename: "test.m4a",
            transcriptionStatus: .failed,
            transcriptionError: "Engine not running"
        ),
        LiveDictation(
            text: "",
            appName: "Messages",
            durationSeconds: 45.2,
            wordCount: nil,
            audioFilename: "test2.m4a",
            transcriptionStatus: .pending,
            transcriptionError: nil
        ),
    ]
    let viewModel = FailedQueueViewModel(items: items)

    return FailedQueueView(viewModel: viewModel)
        .frame(height: 350)
        .background(Color.black)
}
