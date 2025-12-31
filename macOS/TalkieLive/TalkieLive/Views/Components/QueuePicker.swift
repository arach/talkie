//
//  QueuePicker.swift
//  TalkieLive
//
//  Minimal overlay for selecting from queued (unpasted) Lives
//  Triggered by ⌥⌘V (Special Paste)
//

import SwiftUI
import AppKit

// MARK: - Queue Picker Controller

@MainActor
final class QueuePickerController {
    static let shared = QueuePickerController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<QueuePickerView>?
    private var eventMonitor: Any?
    private var localEventMonitor: Any?

    private init() {}

    func show() {
        // If already showing, dismiss
        if panel != nil {
            dismiss()
            return
        }

        let items = LiveDatabase.fetchQueued()
        guard !items.isEmpty else { return }

        let viewModel = QueuePickerViewModel(items: items)
        viewModel.onSelect = { [weak self] item in
            self?.pasteAndDismiss(item)
        }
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }

        let view = QueuePickerView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: view)

        // Calculate size based on items - compact view
        let itemHeight: CGFloat = 40  // More compact
        let headerHeight: CGFloat = 36
        let maxItems = min(items.count, 8)  // Show more items
        let height = headerHeight + CGFloat(maxItems) * itemHeight + 12

        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: height)

        // Create floating panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: height),
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
            let x = screenFrame.midX - 210
            let y = screenFrame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        panel.makeKey()  // Make panel accept keyboard input
        self.panel = panel
        self.hostingView = hostingView

        // Global monitor for keyboard events (works even when app is not focused)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }

            DispatchQueue.main.async {
                switch event.keyCode {
                case 53: // Escape
                    self.dismiss()
                case 125: // Down arrow
                    viewModel.selectNext()
                case 126: // Up arrow
                    viewModel.selectPrevious()
                case 36: // Return
                    if let selected = viewModel.selectedItem {
                        self.pasteAndDismiss(selected)
                    }
                default:
                    break
                }
            }
        }

        // Local monitor for keyboard navigation and clicks (when app is focused)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }

            if event.type == .keyDown {
                switch event.keyCode {
                case 53: // Escape
                    self.dismiss()
                    return nil
                case 125: // Down arrow
                    viewModel.selectNext()
                    return nil
                case 126: // Up arrow
                    viewModel.selectPrevious()
                    return nil
                case 36: // Return
                    if let selected = viewModel.selectedItem {
                        self.pasteAndDismiss(selected)
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

    private func pasteAndDismiss(_ item: LiveDictation) {
        guard let id = item.id else {
            dismiss()
            return
        }

        let text = item.text

        // Mark as pasted in database
        LiveDatabase.markPasted(id: id)

        dismiss()

        // Use TextInserter for robust paste
        Task { @MainActor in
            let success = await TextInserter.shared.insert(text, intoAppWithBundleID: nil)
            if !success {
                // Fallback: copy to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class QueuePickerViewModel: ObservableObject {
    @Published var items: [LiveDictation]
    @Published var selectedIndex: Int = 0

    var onSelect: ((LiveDictation) -> Void)?
    var onDismiss: (() -> Void)?

    var selectedItem: LiveDictation? {
        guard selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    init(items: [LiveDictation]) {
        self.items = items
    }

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

    func select(_ item: LiveDictation) {
        onSelect?(item)
    }

    func dismiss() {
        onDismiss?()
    }
}

// MARK: - SwiftUI Views

struct QueuePickerView: View {
    @ObservedObject var viewModel: QueuePickerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Unpasted Lives")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)
                Spacer()
                Text("\(viewModel.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(TalkieTheme.border)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)

            // Items list
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            QueueItemRow(
                                item: item,
                                isSelected: index == viewModel.selectedIndex
                            )
                            .id(index)
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                viewModel.select(item)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 420)
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

struct QueueItemRow: View {
    let item: LiveDictation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Text preview - single line for compact view
            Text(item.text.prefix(60) + (item.text.count > 60 ? "…" : ""))
                .font(.system(size: 11))
                .foregroundColor(Color(white: isSelected ? 1.0 : 0.85))
                .lineLimit(1)

            Spacer()

            // Inline metadata
            HStack(spacing: 6) {
                Text(timeAgo(from: item.createdAt))
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textMuted)

                if let wordCount = item.wordCount {
                    Text("·")
                        .foregroundColor(TalkieTheme.textMuted)
                    Text("\(wordCount)w")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textMuted)
                }
            }

            // Return key hint when selected
            if isSelected {
                Text("↵")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
        .padding(.horizontal, 6)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}

#Preview {
    let items = [
        LiveDictation(text: "This is a test utterance that was queued because it was recorded inside Talkie Live", appName: "Talkie Live", wordCount: 16, createdInTalkieView: true),
        LiveDictation(text: "Another queued item with some longer text to show how it wraps and truncates properly", appName: "Talkie Live", wordCount: 14, createdInTalkieView: true),
        LiveDictation(text: "Short one", appName: "Talkie Live", wordCount: 2, createdInTalkieView: true),
    ]
    let viewModel = QueuePickerViewModel(items: items)

    return QueuePickerView(viewModel: viewModel)
        .frame(height: 300)
        .background(Color.black)
}
