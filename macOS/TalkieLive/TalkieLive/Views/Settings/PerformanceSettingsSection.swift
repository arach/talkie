//
//  PerformanceSettingsSection.swift
//  TalkieLive
//
//  Performance measurement UI for debugging dictation latency.
//  Shows traces from hotkey → paste with step-level breakdown.
//

import SwiftUI

// MARK: - Performance Settings Section

struct PerformanceSettingsSection: View {
    @ObservedObject private var store = LivePerformanceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 20))
                        .foregroundColor(TalkieTheme.accent)

                    Text("PERFORMANCE")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(TalkieTheme.textPrimary)

                    Spacer()

                    if !store.traces.isEmpty {
                        Button(action: { store.clear() }) {
                            Text("Clear")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Dictation latency measurements")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            if store.traces.isEmpty {
                // Empty state
                GlassCard {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 32))
                            .foregroundColor(TalkieTheme.textMuted)

                        Text("No traces yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TalkieTheme.textSecondary)

                        Text("Complete a dictation to see performance data")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                }
            } else {
                // Summary statistics
                SummaryStatsCard(store: store)

                // Step breakdown
                StepBreakdownCard(store: store)

                // Recent traces
                RecentTracesCard(store: store)
            }
        }
        .padding(Spacing.lg)
    }
}

// MARK: - Summary Stats Card

private struct SummaryStatsCard: View {
    @ObservedObject var store: LivePerformanceStore

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("LATENCY")
                        .font(.techLabelSmall)
                        .foregroundColor(TalkieTheme.textMuted)

                    Spacer()

                    Text("excludes recording time")
                        .font(.system(size: 8))
                        .foregroundColor(TalkieTheme.textMuted)
                }

                // Primary metrics: actionable latency
                HStack(spacing: Spacing.lg) {
                    StatItem(
                        label: "Avg Latency",
                        value: "\(store.averageActionableMs)ms",
                        color: .accentColor
                    )

                    StatItem(
                        label: "P95",
                        value: "\(store.p95ActionableMs)ms",
                        color: store.p95ActionableMs > 500 ? .orange : .green
                    )

                    StatItem(
                        label: "Pre-Rec",
                        value: "\(store.averagePreRecordingMs)ms",
                        color: .purple
                    )

                    StatItem(
                        label: "Post-Rec",
                        value: "\(store.averagePostRecordingMs)ms",
                        color: .blue
                    )
                }

                // Secondary info
                HStack(spacing: Spacing.lg) {
                    StatItem(
                        label: "Traces",
                        value: "\(store.traces.count)",
                        color: TalkieTheme.textSecondary
                    )

                    if let bottleneck = store.mostCommonBottleneck {
                        StatItem(
                            label: "Bottleneck",
                            value: bottleneck,
                            color: .orange
                        )
                    }
                }
            }
        }
    }
}

private struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(TalkieTheme.textMuted)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - Step Breakdown Card

private struct StepBreakdownCard: View {
    @ObservedObject var store: LivePerformanceStore

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("STEP BREAKDOWN")
                    .font(.techLabelSmall)
                    .foregroundColor(TalkieTheme.textMuted)

                VStack(spacing: Spacing.xs) {
                    ForEach(store.stepStatistics) { stats in
                        StepStatRow(stats: stats)
                    }
                }
            }
        }
    }
}

private struct StepStatRow: View {
    let stats: StepStats

    // Color based on step name
    private var stepColor: Color {
        switch stats.name {
        case "engine": return .blue
        case "recording": return .green
        case "context_capture": return .purple
        case "file_save": return .orange
        case "routing": return .cyan
        default: return TalkieTheme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Step name with color indicator
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(stepColor)
                    .frame(width: 6, height: 6)

                Text(stats.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textPrimary)
            }
            .frame(width: 100, alignment: .leading)

            Spacer()

            // Stats
            HStack(spacing: Spacing.md) {
                Text("avg \(stats.avgMs)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(TalkieTheme.textSecondary)

                Text("p95 \(stats.p95Ms)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(stats.p95Ms > 1000 ? .orange : TalkieTheme.textMuted)

                Text("(\(stats.count)x)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recent Traces Card

private struct RecentTracesCard: View {
    @ObservedObject var store: LivePerformanceStore
    @State private var expandedTraceId: UUID?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("RECENT TRACES")
                    .font(.techLabelSmall)
                    .foregroundColor(TalkieTheme.textMuted)

                VStack(spacing: Spacing.xs) {
                    ForEach(store.traces.prefix(10)) { trace in
                        TraceRow(
                            trace: trace,
                            isExpanded: expandedTraceId == trace.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedTraceId = expandedTraceId == trace.id ? nil : trace.id
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct TraceRow: View {
    let trace: LiveTraceMetric
    let isExpanded: Bool
    let onToggle: () -> Void

    private var timeAgo: String {
        let interval = -trace.timestamp.timeIntervalSinceNow
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    // Color based on actionable latency (not total including recording)
    private var latencyColor: Color {
        let ms = trace.actionableMs
        if ms < 200 { return .green }
        if ms < 500 { return .yellow }
        if ms < 1000 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary row (always visible)
            Button(action: onToggle) {
                HStack(spacing: Spacing.sm) {
                    // Actionable latency with color (excludes recording)
                    Text("\(trace.actionableMs)ms")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(latencyColor)
                        .frame(width: 55, alignment: .leading)

                    // Pre/post breakdown
                    Text("\(trace.preRecordingMs)+\(trace.postRecordingMs)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)

                    Spacer()

                    // Recording duration (dimmed, for context)
                    if trace.recordingMs > 0 {
                        Text("rec: \(String(format: "%.1f", Double(trace.recordingMs) / 1000))s")
                            .font(.system(size: 9))
                            .foregroundColor(TalkieTheme.textMuted.opacity(0.6))
                    }

                    // Word count if available
                    if let words = trace.wordCount {
                        Text("\(words)w")
                            .font(.system(size: 9))
                            .foregroundColor(TalkieTheme.textMuted)
                    }

                    // Time ago
                    Text(timeAgo)
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textMuted)

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textMuted)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isExpanded ? Color.white.opacity(0.05) : Color.clear)
                )
            }
            .buttonStyle(.plain)

            // Expanded detail (conditional)
            if isExpanded {
                TraceDetailView(trace: trace)
                    .padding(.top, Spacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct TraceDetailView: View {
    let trace: LiveTraceMetric

    // Human-readable step names
    private func displayName(for step: String) -> String {
        switch step {
        case "hotkey_received", "hotkey_pressed": return "Hotkey"
        case "context_capture": return "Context"
        case "recording": return "Recording"
        case "file_save": return "Save Audio"
        case "engine": return "Transcribe"
        case "routing": return "Paste"
        default: return step
        }
    }

    // Color for each step
    private func colorFor(_ name: String) -> Color {
        switch name {
        case "engine": return .blue
        case "context_capture": return .purple
        case "file_save": return .orange
        case "routing": return .cyan
        case "recording": return Color.white.opacity(0.3)
        default: return TalkieTheme.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Timeline visualization
            TraceTimeline(steps: trace.steps, totalMs: trace.totalMs)

            // Step list (grouped: pre-recording, recording, post-recording)
            VStack(spacing: 2) {
                ForEach(trace.steps) { step in
                    let isRecording = step.name == "recording"

                    HStack(spacing: Spacing.sm) {
                        // Color dot
                        Circle()
                            .fill(colorFor(step.name))
                            .frame(width: 6, height: 6)

                        Text(displayName(for: step.name))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isRecording ? TalkieTheme.textMuted.opacity(0.5) : TalkieTheme.textSecondary)
                            .frame(width: 70, alignment: .leading)

                        // Duration - show recording in seconds, others in ms
                        if isRecording {
                            Text("\(String(format: "%.1f", Double(step.durationMs) / 1000))s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(TalkieTheme.textMuted.opacity(0.4))
                        } else {
                            Text("\(step.durationMs)ms")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(step.durationMs > 500 ? .orange : TalkieTheme.textPrimary)
                        }

                        if let meta = step.metadata {
                            Text(meta)
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textMuted)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .opacity(isRecording ? 0.6 : 1.0)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(Color.white.opacity(0.03))
            )

            // Transcript preview if available
            if let preview = trace.transcriptPreview {
                Text("\"\(preview)...\"")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(TalkieTheme.textMuted)
                    .italic()
                    .lineLimit(1)
                    .padding(.horizontal, Spacing.sm)
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }
}

// MARK: - Trace Timeline Visualization

private struct TraceTimeline: View {
    let steps: [LiveTraceStep]
    let totalMs: Int

    // Actionable time (excludes recording)
    private var actionableMs: Int {
        steps.filter { $0.name != "recording" }.reduce(0) { $0 + $1.durationMs }
    }

    // Color for each step type
    private func colorFor(_ name: String) -> Color {
        switch name {
        case "engine": return .blue
        case "context_capture": return .purple
        case "file_save": return .orange
        case "routing": return .cyan
        case "hotkey_received": return .yellow
        default: return .gray
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // Scale based on actionable time only (recording excluded)
            let scale = actionableMs > 0 ? (width - 20) / CGFloat(actionableMs) : 1

            HStack(spacing: 0) {
                // Pre-recording steps
                let preSteps = steps.filter { $0.name != "recording" && $0.endMs <= (steps.first(where: { $0.name == "recording" })?.startMs ?? 0) }
                ForEach(preSteps) { step in
                    if step.durationMs > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorFor(step.name))
                            .frame(width: max(2, CGFloat(step.durationMs) * scale), height: 8)
                    }
                }

                // Recording break indicator (fixed width, dotted)
                if steps.contains(where: { $0.name == "recording" }) {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 2, height: 2)
                        }
                    }
                    .frame(width: 20, height: 8)
                }

                // Post-recording steps
                let recordingEnd = steps.first(where: { $0.name == "recording" })?.endMs ?? 0
                let postSteps = steps.filter { $0.name != "recording" && $0.startMs >= recordingEnd }
                ForEach(postSteps) { step in
                    if step.durationMs > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorFor(step.name))
                            .frame(width: max(2, CGFloat(step.durationMs) * scale), height: 8)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .padding(.horizontal, Spacing.sm)
    }
}

// MARK: - Preview

#Preview {
    PerformanceSettingsSection()
        .frame(width: 500, height: 600)
        .background(TalkieTheme.background)
        .preferredColorScheme(.dark)
}
