//
//  TalkieWidget.swift
//  TalkieWidget
//
//  Quick record widget for Talkie - Adaptive theme design
//

import WidgetKit
import SwiftUI

// MARK: - Appearance Mode (mirrors app's setting)

enum WidgetAppearance: String {
    case system
    case light
    case dark
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TalkieEntry {
        TalkieEntry(date: Date(), memoCount: 0, recentMemos: [], appearance: .system)
    }

    func getSnapshot(in context: Context, completion: @escaping (TalkieEntry) -> Void) {
        let entry = TalkieEntry(
            date: Date(),
            memoCount: getMemoCount(),
            recentMemos: getRecentMemos(),
            appearance: getAppearance()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkieEntry>) -> Void) {
        let entry = TalkieEntry(
            date: Date(),
            memoCount: getMemoCount(),
            recentMemos: getRecentMemos(),
            appearance: getAppearance()
        )
        // Refresh every 30 minutes for status updates
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func getMemoCount() -> Int {
        let defaults = UserDefaults(suiteName: "group.com.jdi.talkie")
        return defaults?.integer(forKey: "memoCount") ?? 0
    }

    private func getRecentMemos() -> [MemoSnapshot] {
        guard let defaults = UserDefaults(suiteName: "group.com.jdi.talkie"),
              let data = defaults.data(forKey: "recentMemos"),
              let memos = try? JSONDecoder().decode([MemoSnapshot].self, from: data) else {
            return []
        }
        return memos
    }

    private func getAppearance() -> WidgetAppearance {
        guard let defaults = UserDefaults(suiteName: "group.com.jdi.talkie"),
              let mode = defaults.string(forKey: "appearanceMode"),
              let appearance = WidgetAppearance(rawValue: mode) else {
            return .system
        }
        return appearance
    }
}

// MARK: - Memo Snapshot for Widget

struct MemoSnapshot: Codable, Identifiable {
    let id: String
    let title: String
    let duration: TimeInterval
    let hasTranscription: Bool
    let hasAIProcessing: Bool
    let isSynced: Bool
    let createdAt: Date
    let fileSize: Int
    let audioFormat: String
    let isSeenByMac: Bool
    let actionCount: Int

    // Support decoding older snapshots without new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        hasTranscription = try container.decode(Bool.self, forKey: .hasTranscription)
        hasAIProcessing = try container.decode(Bool.self, forKey: .hasAIProcessing)
        isSynced = try container.decode(Bool.self, forKey: .isSynced)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize) ?? 0
        audioFormat = try container.decodeIfPresent(String.self, forKey: .audioFormat) ?? "M4A"
        isSeenByMac = try container.decodeIfPresent(Bool.self, forKey: .isSeenByMac) ?? false
        actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? 0
    }

    init(id: String, title: String, duration: TimeInterval, hasTranscription: Bool, hasAIProcessing: Bool, isSynced: Bool, createdAt: Date, fileSize: Int = 0, audioFormat: String = "M4A", isSeenByMac: Bool = false, actionCount: Int = 0) {
        self.id = id
        self.title = title
        self.duration = duration
        self.hasTranscription = hasTranscription
        self.hasAIProcessing = hasAIProcessing
        self.isSynced = isSynced
        self.createdAt = createdAt
        self.fileSize = fileSize
        self.audioFormat = audioFormat
        self.isSeenByMac = isSeenByMac
        self.actionCount = actionCount
    }
}

// MARK: - Timeline Entry

struct TalkieEntry: TimelineEntry {
    let date: Date
    let memoCount: Int
    let recentMemos: [MemoSnapshot]
    let appearance: WidgetAppearance
}

// MARK: - Theme Colors

struct WidgetColors {
    let background: Color
    let foreground: Color
    let secondaryForeground: Color
    let tertiaryForeground: Color
    let accent: Color

    static func forScheme(_ isDark: Bool) -> WidgetColors {
        if isDark {
            return WidgetColors(
                background: .black,
                foreground: .white.opacity(0.9),
                secondaryForeground: .white.opacity(0.5),
                tertiaryForeground: .white.opacity(0.3),
                accent: .white.opacity(0.5)
            )
        } else {
            return WidgetColors(
                background: .white,
                foreground: .black.opacity(0.85),
                secondaryForeground: .black.opacity(0.5),
                tertiaryForeground: .black.opacity(0.3),
                accent: .black.opacity(0.4)
            )
        }
    }
}

// MARK: - Widget Views

struct TalkieWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var systemColorScheme

    var isDark: Bool {
        switch entry.appearance {
        case .system: return systemColorScheme == .dark
        case .dark: return true
        case .light: return false
        }
    }

    var colors: WidgetColors {
        WidgetColors.forScheme(isDark)
    }

    /// Background color for container - used by widget configuration
    var backgroundColor: Color {
        colors.background
    }

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(memoCount: entry.memoCount, colors: colors)
        case .systemMedium:
            MediumWidgetView(memoCount: entry.memoCount, recentMemos: entry.recentMemos, colors: colors)
        case .systemLarge:
            LargeWidgetView(memoCount: entry.memoCount, recentMemos: entry.recentMemos, colors: colors)
        case .accessoryCircular:
            CircularWidgetView()
        case .accessoryRectangular:
            RectangularWidgetView(memoCount: entry.memoCount)
        default:
            SmallWidgetView(memoCount: entry.memoCount, colors: colors)
        }
    }
}

// MARK: - Small Widget - Tap to record

struct SmallWidgetView: View {
    let memoCount: Int
    let colors: WidgetColors
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        ZStack {
            // Corner accents - hide in tinted mode
            if renderingMode == .fullColor {
                CornerAccents(color: colors.accent)
            }

            // Content
            VStack(spacing: 8) {
                Spacer()

                // Mic button
                ZStack {
                    Circle()
                        .fill(colors.foreground.opacity(0.1))
                        .frame(width: 52, height: 52)

                    Circle()
                        .stroke(colors.secondaryForeground, lineWidth: 1)
                        .frame(width: 52, height: 52)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(colors.foreground)
                        .widgetAccentable()
                }

                Text("RECORD")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(colors.secondaryForeground)
                    .tracking(2)

                Spacer()

                // Memo count
                if memoCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 8))
                        Text("\(memoCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(colors.secondaryForeground)
                    .padding(.bottom, 8)
                }
            }
        }
        .widgetURL(URL(string: "talkie://record"))
    }
}

// MARK: - Medium Widget - Recent memos list

struct MediumWidgetView: View {
    let memoCount: Int
    let recentMemos: [MemoSnapshot]
    let colors: WidgetColors
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        ZStack {
            // Corner accents - hide in tinted mode
            if renderingMode == .fullColor {
                CornerAccents(color: colors.accent)
            }

            VStack(spacing: 0) {
                // Top header - TALKIE centered
                HStack {
                    Spacer()
                    Text("TALKIE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(colors.foreground.opacity(0.9))
                        .tracking(2)
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Main content
                HStack(spacing: 0) {
                    // Left side - Record button
                    Link(destination: URL(string: "talkie://record")!) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(colors.foreground.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                Circle()
                                    .stroke(colors.secondaryForeground, lineWidth: 1)
                                    .frame(width: 40, height: 40)

                                Image(systemName: "mic.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colors.foreground)
                                    .widgetAccentable()
                            }

                            Text("REC")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(colors.secondaryForeground)
                                .tracking(1)
                        }
                        .frame(width: 80)
                    }

                    // Divider
                    Rectangle()
                        .fill(colors.tertiaryForeground)
                        .frame(width: 1)
                        .padding(.vertical, 4)

                    // Right side - Recent memos
                    VStack(alignment: .leading, spacing: 2) {
                        if recentMemos.isEmpty {
                            // Empty state
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 16))
                                        .foregroundColor(colors.tertiaryForeground)
                                    Text("No memos yet")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(colors.tertiaryForeground)
                                }
                                Spacer()
                            }
                            Spacer()
                        } else {
                            // Memo list
                            ForEach(recentMemos.prefix(3)) { memo in
                                Link(destination: URL(string: "talkie://memo?id=\(memo.id)")!) {
                                    WidgetMemoRowView(memo: memo, colors: colors)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Large Widget - More memos with bigger record button

struct LargeWidgetView: View {
    let memoCount: Int
    let recentMemos: [MemoSnapshot]
    let colors: WidgetColors
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        ZStack {
            // Corner accents - hide in tinted mode
            if renderingMode == .fullColor {
                CornerAccents(color: colors.accent)
            }

            VStack(spacing: 0) {
                // Top header - matches app style exactly
                VStack(spacing: 0) {
                    Text("TALKIE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(colors.foreground)
                    Text("\(memoCount) MEMOS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(colors.tertiaryForeground)
                }
                .padding(.top, 12)
                .padding(.bottom, 6)

                // Memos list - table style
                VStack(alignment: .leading, spacing: 0) {
                    if recentMemos.isEmpty {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 24))
                                    .foregroundColor(colors.tertiaryForeground)
                                Text("No memos yet")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(colors.tertiaryForeground)
                            }
                            Spacer()
                        }
                        Spacer()
                    } else {
                        ForEach(recentMemos.prefix(8)) { memo in
                            Link(destination: URL(string: "talkie://memo?id=\(memo.id)")!) {
                                WidgetMemoRowView(memo: memo, colors: colors)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 14)

                // Bottom bar: Search | Record | Settings
                HStack {
                    // Search - left
                    Link(destination: URL(string: "talkie://search")!) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colors.secondaryForeground)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Link(destination: URL(string: "talkie://record")!) {
                        ZStack {
                            Circle()
                                .strokeBorder(colors.secondaryForeground, lineWidth: 1.5)
                                .frame(width: 44, height: 44)

                            Circle()
                                .fill(colors.foreground.opacity(0.1))
                                .frame(width: 36, height: 36)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colors.foreground)
                                .widgetAccentable()
                        }
                    }

                    Spacer()

                    // Settings - right
                    Link(destination: URL(string: "talkie://settings")!) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colors.secondaryForeground)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Widget Memo Row

struct WidgetMemoRowView: View {
    let memo: MemoSnapshot
    let colors: WidgetColors

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 4) {
                Text(memo.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(colors.foreground)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if memo.actionCount > 0 {
                    HStack(spacing: 2) {
                        Text("\(memo.actionCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(colors.accent)
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(colors.accent)
                    }
                }
            }

            HStack(spacing: 0) {
                Text(formatDateTime(memo.createdAt))
                Text(" · ").foregroundColor(colors.tertiaryForeground.opacity(0.5))
                Text(formatFileSize(memo.fileSize))
                if memo.isSeenByMac {
                    Text(" · ").foregroundColor(colors.tertiaryForeground.opacity(0.5))
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 7))
                }
                Spacer()
            }
            .font(.system(size: 8))
            .foregroundColor(colors.tertiaryForeground)
        }
        .padding(.vertical, 3)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "M/d h:mm a"
        }
        return formatter.string(from: date)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "-- KB" }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = Double(bytes) / 1024
            return String(format: "%.0f KB", kb)
        }
    }
}

// MARK: - Corner Accents

struct CornerAccents: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let cornerLength: CGFloat = 14
            let cornerOffset: CGFloat = 3

            // Top-left corner
            Path { path in
                path.move(to: CGPoint(x: cornerOffset, y: cornerOffset + cornerLength))
                path.addLine(to: CGPoint(x: cornerOffset, y: cornerOffset))
                path.addLine(to: CGPoint(x: cornerOffset + cornerLength, y: cornerOffset))
            }
            .stroke(color, lineWidth: 1)

            // Top-right corner
            Path { path in
                path.move(to: CGPoint(x: geo.size.width - cornerOffset - cornerLength, y: cornerOffset))
                path.addLine(to: CGPoint(x: geo.size.width - cornerOffset, y: cornerOffset))
                path.addLine(to: CGPoint(x: geo.size.width - cornerOffset, y: cornerOffset + cornerLength))
            }
            .stroke(color, lineWidth: 1)

            // Bottom-left corner
            Path { path in
                path.move(to: CGPoint(x: cornerOffset, y: geo.size.height - cornerOffset - cornerLength))
                path.addLine(to: CGPoint(x: cornerOffset, y: geo.size.height - cornerOffset))
                path.addLine(to: CGPoint(x: cornerOffset + cornerLength, y: geo.size.height - cornerOffset))
            }
            .stroke(color, lineWidth: 1)

            // Bottom-right corner
            Path { path in
                path.move(to: CGPoint(x: geo.size.width - cornerOffset - cornerLength, y: geo.size.height - cornerOffset))
                path.addLine(to: CGPoint(x: geo.size.width - cornerOffset, y: geo.size.height - cornerOffset))
                path.addLine(to: CGPoint(x: geo.size.width - cornerOffset, y: geo.size.height - cornerOffset - cornerLength))
            }
            .stroke(color, lineWidth: 1)
        }
    }
}

// MARK: - Lock Screen Widgets

struct CircularWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
        }
        .widgetURL(URL(string: "talkie://record"))
    }
}

struct RectangularWidgetView: View {
    let memoCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text("TALKIE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("\(memoCount) memos")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .widgetURL(URL(string: "talkie://record"))
    }
}

// MARK: - Widget Configuration

struct TalkieWidget: Widget {
    let kind: String = "TalkieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TalkieWidgetEntryView(entry: entry)
                .widgetBackground(entry: entry)
        }
        .configurationDisplayName("Talkie")
        .description("Quick access to record voice memos")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

// MARK: - Widget Background Extension

extension View {
    @ViewBuilder
    func widgetBackground(entry: TalkieEntry) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                WidgetBackgroundView(appearance: entry.appearance)
            }
        } else {
            self.background(WidgetBackgroundView(appearance: entry.appearance))
        }
    }
}

/// Widget background view that handles color scheme properly
private struct WidgetBackgroundView: View {
    let appearance: WidgetAppearance
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        switch appearance {
        case .system: return colorScheme == .dark
        case .dark: return true
        case .light: return false
        }
    }

    var body: some View {
        // Use Rectangle with explicit fill - more reliable on device
        Rectangle()
            .fill(isDark ? Color(red: 0, green: 0, blue: 0) : Color(red: 1, green: 1, blue: 1))
            .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    TalkieWidget()
} timeline: {
    TalkieEntry(date: .now, memoCount: 0, recentMemos: [], appearance: .dark)
    TalkieEntry(date: .now, memoCount: 12, recentMemos: [], appearance: .light)
}

#Preview(as: .systemMedium) {
    TalkieWidget()
} timeline: {
    TalkieEntry(date: .now, memoCount: 5, recentMemos: [
        MemoSnapshot(id: "1", title: "Meeting notes", duration: 145, hasTranscription: true, hasAIProcessing: true, isSynced: true, createdAt: Date(), fileSize: 2_320_000, audioFormat: "M4A", isSeenByMac: true, actionCount: 3),
        MemoSnapshot(id: "2", title: "Idea for app", duration: 32, hasTranscription: true, hasAIProcessing: false, isSynced: true, createdAt: Date().addingTimeInterval(-3600), fileSize: 512_000, audioFormat: "M4A", isSeenByMac: true, actionCount: 1),
        MemoSnapshot(id: "3", title: "Quick reminder", duration: 8, hasTranscription: false, hasAIProcessing: false, isSynced: false, createdAt: Date().addingTimeInterval(-7200), fileSize: 128_000, audioFormat: "M4A", isSeenByMac: false, actionCount: 0)
    ], appearance: .dark)
}

#Preview(as: .systemLarge) {
    TalkieWidget()
} timeline: {
    TalkieEntry(date: .now, memoCount: 12, recentMemos: [
        MemoSnapshot(id: "1", title: "Meeting notes", duration: 145, hasTranscription: true, hasAIProcessing: true, isSynced: true, createdAt: Date(), fileSize: 2_320_000, audioFormat: "M4A", isSeenByMac: true, actionCount: 3),
        MemoSnapshot(id: "2", title: "Idea for app", duration: 32, hasTranscription: true, hasAIProcessing: false, isSynced: true, createdAt: Date().addingTimeInterval(-3600), fileSize: 512_000, audioFormat: "M4A", isSeenByMac: true, actionCount: 1),
        MemoSnapshot(id: "3", title: "Quick reminder", duration: 8, hasTranscription: false, hasAIProcessing: false, isSynced: false, createdAt: Date().addingTimeInterval(-7200), fileSize: 128_000, audioFormat: "M4A", isSeenByMac: false, actionCount: 0),
        MemoSnapshot(id: "4", title: "Project brainstorm", duration: 312, hasTranscription: true, hasAIProcessing: true, isSynced: true, createdAt: Date().addingTimeInterval(-86400), fileSize: 4_992_000, audioFormat: "M4A", isSeenByMac: true, actionCount: 2),
        MemoSnapshot(id: "5", title: "Grocery list", duration: 18, hasTranscription: true, hasAIProcessing: false, isSynced: true, createdAt: Date().addingTimeInterval(-172800), fileSize: 288_000, audioFormat: "M4A", isSeenByMac: true, actionCount: 0),
        MemoSnapshot(id: "6", title: "Voice note 11/29", duration: 67, hasTranscription: false, hasAIProcessing: false, isSynced: false, createdAt: Date().addingTimeInterval(-259200), fileSize: 1_072_000, audioFormat: "M4A", isSeenByMac: false, actionCount: 0)
    ], appearance: .dark)
}
