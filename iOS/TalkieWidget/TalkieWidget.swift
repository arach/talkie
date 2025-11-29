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
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                colors.background

                // Corner accents
                CornerAccents(color: colors.accent)

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
        }
        .widgetURL(URL(string: "talkie://record"))
    }
}

// MARK: - Medium Widget - Recent memos list

struct MediumWidgetView: View {
    let memoCount: Int
    let recentMemos: [MemoSnapshot]
    let colors: WidgetColors

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                colors.background

                // Corner accents
                CornerAccents(color: colors.accent)

                HStack(spacing: 0) {
                    // Left side - Record button
                    Link(destination: URL(string: "talkie://record")!) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(colors.foreground.opacity(0.1))
                                    .frame(width: 44, height: 44)

                                Circle()
                                    .stroke(colors.secondaryForeground, lineWidth: 1)
                                    .frame(width: 44, height: 44)

                                Image(systemName: "mic.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(colors.foreground)
                            }

                            Text("REC")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(colors.secondaryForeground)
                                .tracking(1.5)
                        }
                        .frame(width: geo.size.width * 0.28)
                    }

                    // Divider
                    Rectangle()
                        .fill(colors.tertiaryForeground)
                        .frame(width: 1)
                        .padding(.vertical, 16)

                    // Right side - Recent memos
                    VStack(alignment: .leading, spacing: 4) {
                        // Header
                        HStack {
                            Text("TALKIE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(colors.secondaryForeground)
                                .tracking(1.5)

                            Spacer()

                            Text("\(memoCount)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(colors.tertiaryForeground)
                        }
                        .padding(.bottom, 2)

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
                                    MemoRowView(memo: memo, colors: colors)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                colors.background

                // Corner accents
                CornerAccents(color: colors.accent)

                VStack(spacing: 0) {
                    // Top section - Record button
                    Link(destination: URL(string: "talkie://record")!) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(colors.foreground.opacity(0.1))
                                    .frame(width: 56, height: 56)

                                Circle()
                                    .stroke(colors.secondaryForeground, lineWidth: 1)
                                    .frame(width: 56, height: 56)

                                Image(systemName: "mic.fill")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(colors.foreground)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("RECORD")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(colors.foreground)
                                    .tracking(2)

                                Text("Tap to start")
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundColor(colors.tertiaryForeground)
                            }
                            .padding(.leading, 12)

                            Spacer()

                            Text("\(memoCount)")
                                .font(.system(size: 24, weight: .light, design: .monospaced))
                                .foregroundColor(colors.tertiaryForeground)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }

                    // Divider
                    Rectangle()
                        .fill(colors.tertiaryForeground)
                        .frame(height: 1)
                        .padding(.horizontal, 12)

                    // Memos list
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("TALKIE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(colors.secondaryForeground)
                                .tracking(1.5)
                            Spacer()
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 4)

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
                            ForEach(recentMemos.prefix(6)) { memo in
                                Link(destination: URL(string: "talkie://memo?id=\(memo.id)")!) {
                                    MemoRowView(memo: memo, colors: colors)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
    }
}

// MARK: - Memo Row

struct MemoRowView: View {
    let memo: MemoSnapshot
    let colors: WidgetColors

    var body: some View {
        HStack(spacing: 6) {
            // Title
            Text(memo.title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(colors.foreground)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Duration
            Text(formatDuration(memo.duration))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(colors.secondaryForeground)
        }
        .padding(.vertical, 3)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
                .containerBackground(.clear, for: .widget)
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
        MemoSnapshot(id: "1", title: "Meeting notes", duration: 145, hasTranscription: true, hasAIProcessing: true, isSynced: true, createdAt: Date()),
        MemoSnapshot(id: "2", title: "Idea for app", duration: 32, hasTranscription: true, hasAIProcessing: false, isSynced: true, createdAt: Date()),
        MemoSnapshot(id: "3", title: "Quick reminder", duration: 8, hasTranscription: false, hasAIProcessing: false, isSynced: false, createdAt: Date())
    ], appearance: .dark)
}

#Preview(as: .systemLarge) {
    TalkieWidget()
} timeline: {
    TalkieEntry(date: .now, memoCount: 12, recentMemos: [
        MemoSnapshot(id: "1", title: "Meeting notes", duration: 145, hasTranscription: true, hasAIProcessing: true, isSynced: true, createdAt: Date()),
        MemoSnapshot(id: "2", title: "Idea for app", duration: 32, hasTranscription: true, hasAIProcessing: false, isSynced: true, createdAt: Date()),
        MemoSnapshot(id: "3", title: "Quick reminder", duration: 8, hasTranscription: false, hasAIProcessing: false, isSynced: false, createdAt: Date()),
        MemoSnapshot(id: "4", title: "Project brainstorm", duration: 312, hasTranscription: true, hasAIProcessing: true, isSynced: true, createdAt: Date()),
        MemoSnapshot(id: "5", title: "Grocery list", duration: 18, hasTranscription: true, hasAIProcessing: false, isSynced: true, createdAt: Date()),
        MemoSnapshot(id: "6", title: "Voice note 11/29", duration: 67, hasTranscription: false, hasAIProcessing: false, isSynced: false, createdAt: Date())
    ], appearance: .dark)
}
