//
//  SystemConsoleView.swift
//  Talkie macOS
//
//  Live activity console with tactical dark theme
//

import SwiftUI
import Combine

// MARK: - System Event Model

enum SystemEventType: String {
    case sync = "SYNC"
    case record = "RECORD"
    case transcribe = "WHISPER"
    case workflow = "WORKFLOW"
    case error = "ERROR"
    case system = "SYSTEM"

    var color: Color {
        switch self {
        case .sync: return Color(red: 0.4, green: 0.8, blue: 0.4) // Soft green
        case .record: return Color(red: 0.4, green: 0.6, blue: 1.0) // Soft blue
        case .transcribe: return Color(red: 0.7, green: 0.5, blue: 1.0) // Soft purple
        case .workflow: return Color(red: 1.0, green: 0.7, blue: 0.3) // Amber
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4) // Soft red
        case .system: return Color(red: 0.5, green: 0.5, blue: 0.5) // Gray
        }
    }
}

struct SystemEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: SystemEventType
    let message: String
    let detail: String?

    init(type: SystemEventType, message: String, detail: String? = nil) {
        self.timestamp = Date()
        self.type = type
        self.message = message
        self.detail = detail
    }
}

// MARK: - Event Manager

@MainActor
class SystemEventManager: ObservableObject {
    static let shared = SystemEventManager()

    @Published var events: [SystemEvent] = []
    private let maxEvents = 200

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()

        // Initial boot event
        log(.system, "Console initialized", detail: "Talkie OS v1.0")
    }

    func log(_ type: SystemEventType, _ message: String, detail: String? = nil) {
        let event = SystemEvent(type: type, message: message, detail: detail)
        events.insert(event, at: 0)

        // Trim old events
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
    }

    private func setupObservers() {
        // Listen for sync started
        NotificationCenter.default.publisher(for: .talkieSyncStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.log(.sync, "Sync started", detail: "Fetching changes...")
            }
            .store(in: &cancellables)

        // Listen for sync completed
        NotificationCenter.default.publisher(for: .talkieSyncCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let changes = notification.userInfo?["changes"] as? Int ?? 0
                if changes > 0 {
                    self?.log(.sync, "Sync completed", detail: "\(changes) change(s) from iCloud")
                } else {
                    self?.log(.sync, "Sync completed", detail: "No changes")
                }
            }
            .store(in: &cancellables)

        // Listen for local saves
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>, !inserted.isEmpty {
                    self?.log(.system, "Data saved", detail: "\(inserted.count) object(s)")
                }
            }
            .store(in: &cancellables)
    }

    func clear() {
        events.removeAll()
        log(.system, "Console cleared")
    }
}

// MARK: - Console View

struct SystemConsoleView: View {
    @StateObject private var eventManager = SystemEventManager.shared
    @State private var autoScroll = true
    @State private var filterType: SystemEventType? = nil

    private let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)
    private let borderColor = Color(red: 0.15, green: 0.15, blue: 0.18)
    private let subtleGreen = Color(red: 0.4, green: 0.8, blue: 0.4)

    var filteredEvents: [SystemEvent] {
        if let filter = filterType {
            return eventManager.events.filter { $0.type == filter }
        }
        return eventManager.events
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            consoleHeader

            // Filter bar
            filterBar

            Divider()
                .background(borderColor)

            // Console output
            consoleOutput

            // Input/status bar
            consoleStatusBar
        }
        .background(bgColor)
    }

    // MARK: - Header

    private var consoleHeader: some View {
        HStack(spacing: 8) {
            // Terminal icon
            Image(systemName: "terminal")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(subtleGreen.opacity(0.7))

            Text("SYSTEM CONSOLE")
                .font(SettingsManager.shared.fontXSBold)
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.9))

            Text("v1.0")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            // Live indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(subtleGreen)
                    .frame(width: 5, height: 5)
                    .shadow(color: subtleGreen.opacity(0.5), radius: 3)

                Text("LIVE")
                    .font(SettingsManager.shared.fontXSBold)
                    .foregroundColor(subtleGreen.opacity(0.8))
            }

            // Clear button
            Button(action: { eventManager.clear() }) {
                Text("CLEAR")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterChip(nil, label: "ALL")
            filterChip(.sync, label: "SYNC")
            filterChip(.record, label: "RECORD")
            filterChip(.transcribe, label: "WHISPER")
            filterChip(.workflow, label: "WORKFLOW")
            filterChip(.error, label: "ERROR")

            Spacer()

            Text("\(filteredEvents.count) events")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bgColor)
    }

    private func filterChip(_ type: SystemEventType?, label: String) -> some View {
        let isSelected = filterType == type
        let chipColor = type?.color ?? .white

        return Button(action: { filterType = type }) {
            Text(label)
                .font(SettingsManager.shared.fontXSBold)
                .foregroundColor(isSelected ? bgColor : chipColor.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? chipColor : chipColor.opacity(0.1))
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Console Output

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEvents.reversed()) { event in
                        ConsoleEventRow(event: event)
                            .id(event.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: eventManager.events.count) {
                if autoScroll, let lastEvent = filteredEvents.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastEvent.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(bgColor)
    }

    // MARK: - Status Bar

    private var consoleStatusBar: some View {
        HStack(spacing: 12) {
            // Prompt
            HStack(spacing: 4) {
                Text(">")
                    .font(SettingsManager.shared.fontXSBold)
                    .foregroundColor(subtleGreen)

                Text("ready")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Auto-scroll toggle
            Button(action: { autoScroll.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(SettingsManager.shared.fontXS)
                    Text("AUTO")
                        .font(SettingsManager.shared.fontXS)
                }
                .foregroundColor(autoScroll ? subtleGreen : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(borderColor),
            alignment: .top
        )
    }
}

// MARK: - Console Event Row

struct ConsoleEventRow: View {
    let event: SystemEvent

    @State private var isHovering = false

    private let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp (compact)
            Text(formatTime(event.timestamp))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 52, alignment: .leading)

            // Type badge (compact)
            Text(event.type.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(event.type.color)
                .frame(width: 60, alignment: .leading)

            // Message (takes remaining space)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.message)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)

                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isHovering ? Color.white.opacity(0.02) : Color.clear)
        .onHover { hovering in isHovering = hovering }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    SystemConsoleView()
        .frame(width: 600, height: 400)
}
