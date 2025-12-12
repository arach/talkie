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

        let items = PastLivesDatabase.fetchQueued()
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

        // Calculate size based on items
        let itemHeight: CGFloat = 56
        let headerHeight: CGFloat = 40
        let maxItems = min(items.count, 6)
        let height = headerHeight + CGFloat(maxItems) * itemHeight + 16

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
        self.panel = panel
        self.hostingView = hostingView

        // Global monitor for escape key (works even when app is not focused)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }

            if event.keyCode == 53 { // Escape
                DispatchQueue.main.async {
                    self.dismiss()
                }
            }
        }

        // Local monitor for keyboard navigation and clicks
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

    private func pasteAndDismiss(_ item: LiveUtterance) {
        guard let id = item.id else {
            dismiss()
            return
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)

        // Mark as pasted in database
        PastLivesDatabase.markPasted(id: id)

        dismiss()

        // Simulate Cmd+V to paste into frontmost app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePaste()
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd down
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        // V down
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        // V up
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        // Cmd up
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - View Model

@MainActor
final class QueuePickerViewModel: ObservableObject {
    @Published var items: [LiveUtterance]
    @Published var selectedIndex: Int = 0

    var onSelect: ((LiveUtterance) -> Void)?
    var onDismiss: (() -> Void)?

    var selectedItem: LiveUtterance? {
        guard selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    init(items: [LiveUtterance]) {
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

    func select(_ item: LiveUtterance) {
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
    let item: LiveUtterance
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Text preview
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text.prefix(80) + (item.text.count > 80 ? "..." : ""))
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: isSelected ? 1.0 : 0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    // Time ago
                    Text(timeAgo(from: item.createdAt))
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)

                    // Word count
                    if let wordCount = item.wordCount {
                        Text("\(wordCount) words")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    // Source app
                    if let appName = item.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }
            }

            Spacer()

            // Return key hint when selected
            if isSelected {
                Text("↵")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
        .padding(.horizontal, 8)
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
        LiveUtterance(text: "This is a test utterance that was queued because it was recorded inside Talkie Live", appName: "Talkie Live", wordCount: 16, createdInTalkieView: true),
        LiveUtterance(text: "Another queued item with some longer text to show how it wraps and truncates properly", appName: "Talkie Live", wordCount: 14, createdInTalkieView: true),
        LiveUtterance(text: "Short one", appName: "Talkie Live", wordCount: 2, createdInTalkieView: true),
    ]
    let viewModel = QueuePickerViewModel(items: items)

    return QueuePickerView(viewModel: viewModel)
        .frame(height: 300)
        .background(Color.black)
}
