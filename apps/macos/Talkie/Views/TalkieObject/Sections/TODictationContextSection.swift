//
//  TODictationContextSection.swift
//  Talkie
//
//  Context section for dictations and readouts (selections).
//  For dictations: app context, model, duration, window title.
//  For selections: full story — input, context, processing, spoken output.
//

import SwiftUI
import TalkieKit

struct TODictationContextSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager

    private var hasContext: Bool {
        (recording.isDictation || recording.isSelection) && (recording.appContext != nil || recording.transcriptionModel != nil || recording.metadata?.selection != nil)
    }

    var body: some View {
        if hasContext {
            if recording.isSelection {
                selectionBody
            } else {
                dictationBody
            }
        }
    }

    // MARK: - Selection (Readout) Body

    private var selectionBody: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            let sel = recording.metadata?.selection

            // 1. SELECTED TEXT — the primary content, what was highlighted
            if let inputText = sel?.inputText, !inputText.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SELECTED TEXT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(inputText)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.current.foreground)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.foreground.opacity(0.03))
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Theme.current.divider, lineWidth: 0.5)
                )
            }

            // 2. CONTEXT — app, mode, voice, timing
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("CONTEXT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(Tracking.wide)
                    .foregroundColor(Theme.current.foregroundSecondary)

                HStack(spacing: Spacing.sm) {
                    if let appContext = recording.appContext {
                        contextCard(
                            label: "SOURCE",
                            value: appContext.name ?? "Unknown",
                            icon: "app.fill",
                            color: .purple,
                            bundleId: appContext.bundleId
                        )
                    }

                    if let mode = sel?.mode {
                        contextCard(
                            label: "MODE",
                            value: mode.capitalized,
                            icon: "wand.and.stars",
                            color: .teal
                        )
                    }

                    if let voiceId = sel?.voiceId {
                        contextCard(
                            label: "VOICE",
                            value: voiceDisplayName(voiceId),
                            icon: "speaker.wave.2",
                            color: .orange
                        )
                    }

                    if let e2e = sel?.endToEndMs {
                        contextCard(
                            label: "LATENCY",
                            value: "\(e2e)ms",
                            icon: "gauge.with.dots.needle.67percent",
                            color: .gray
                        )
                    }
                }
            }

            // 3. SERVICE CALLS — structured trace of each outbound API call
            if let calls = recording.metadata?.serviceCalls, !calls.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SERVICE CALLS")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    ForEach(calls) { call in
                        ServiceCallCardView(call: call)
                    }
                }
            }

            // 4. SPOKEN OUTPUT — styled distinctly with voice silhouette
            if let outputText = recording.text, !outputText.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SPOKEN OUTPUT")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: "person.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.teal.opacity(0.6))
                            .frame(width: 24)
                            .padding(.top, 2)

                        Text(outputText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Theme.current.foreground.opacity(0.9))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.teal.opacity(0.06), Color.teal.opacity(0.02)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.teal.opacity(0.15), lineWidth: 0.5)
                )
            }

            // 5. SOURCE SCREENSHOT — collapsible, at the end
            if let screenshot = recording.screenshots.first {
                DisclosureGroup {
                    LargeAttachmentView(screenshot: screenshot)
                        .padding(.top, Spacing.xs)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "camera")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text("Source Window")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.current.foregroundSecondary)
                        if let appName = screenshot.appName {
                            Text("— \(appName)")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.foreground.opacity(0.02))
                .cornerRadius(CornerRadius.sm)
            }
        }
    }

    // MARK: - Dictation Body (unchanged)

    private var dictationBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("CONTEXT")
                .font(settings.fontXSMedium)
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            // Context cards
            HStack(spacing: Spacing.sm) {
                if let appContext = recording.appContext {
                    contextCard(
                        label: "SOURCE",
                        value: appContext.name ?? "Unknown",
                        icon: "app.fill",
                        color: .purple,
                        bundleId: appContext.bundleId
                    )
                }

                if let model = recording.transcriptionModel {
                    contextCard(
                        label: "MODEL",
                        value: model,
                        icon: "cpu",
                        color: .blue
                    )
                }

                if recording.duration > 0 {
                    contextCard(
                        label: "DURATION",
                        value: formatDictationDuration(recording.duration),
                        icon: "clock",
                        color: .orange
                    )
                }

                #if DEBUG
                if let perf = recording.performanceMetrics, perf.engineMs != nil {
                    PerfContextCard(
                        perf: perf,
                        audio: recording.metadata?.audio,
                        routing: recording.metadata?.routing
                    )
                }
                #endif
            }

            // Window title
            if let appContext = recording.appContext,
               let windowTitle = appContext.windowTitle, !windowTitle.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(windowTitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Theme.current.foreground.opacity(0.05))
                .cornerRadius(CornerRadius.xs)
            }

            // Browser URL
            if let metadata = recording.metadata,
               let context = metadata.context,
               let browserURL = context.browserURL, !browserURL.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)

                    Text(browserURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(CornerRadius.xs)
            }
        }
    }

    // MARK: - Helpers

    private func voiceDisplayName(_ voiceId: String) -> String {
        if voiceId.hasPrefix("kokoro:") {
            return "Kokoro"
        } else if voiceId.hasPrefix("openai:") {
            return "OpenAI \(voiceId.dropFirst("openai:".count).capitalized)"
        } else if voiceId.hasPrefix("elevenlabs:") {
            return "ElevenLabs"
        } else if voiceId.hasPrefix("com.apple") {
            return "Apple"
        }
        return voiceId
    }

    private func contextCard(label: String, value: String, icon: String, color: Color, bundleId: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.xs) {
                if let bundleId = bundleId {
                    AppIconView(bundleIdentifier: bundleId, size: 14)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(color)
                }

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Theme.current.foreground.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(color.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func formatDictationDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        }
    }
}

// MARK: - Service Call Card

struct ServiceCallCardView: View {
    let call: ServiceCallRecord
    @State private var isExpanded = false

    private var kindIcon: String {
        switch call.kind {
        case "llm": return "brain"
        case "tts": return "speaker.wave.2"
        case "webhook": return "arrow.up.right.circle"
        default: return "arrow.right.circle"
        }
    }

    private var kindLabel: String {
        switch call.kind {
        case "llm": return "LLM"
        case "tts": return "TTS"
        case "webhook": return "Webhook"
        default: return call.kind.uppercased()
        }
    }

    private var accentColor: Color {
        switch call.kind {
        case "llm": return .blue
        case "tts": return .teal
        case "webhook": return .orange
        default: return .gray
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Messages (for LLM calls)
                if let messages = call.messages, !messages.isEmpty {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.role.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(message.role == "system" ? .purple.opacity(0.7) : .blue.opacity(0.7))

                            Text(message.content)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.current.foreground.opacity(0.7))
                                .textSelection(.enabled)
                                .lineLimit(message.role == "system" ? 6 : nil)
                        }
                        .padding(Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.current.foreground.opacity(0.02))
                        .cornerRadius(CornerRadius.xs)
                    }
                }

                // Response
                if let response = call.response, !response.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RESPONSE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.green.opacity(0.7))

                        Text(response)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foreground.opacity(0.7))
                            .textSelection(.enabled)
                    }
                    .padding(Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.foreground.opacity(0.02))
                    .cornerRadius(CornerRadius.xs)
                }

                // Input text (for TTS)
                if let inputText = call.inputText, !inputText.isEmpty, call.kind == "tts" {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INPUT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.teal.opacity(0.7))

                        Text(inputText)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foreground.opacity(0.7))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    .padding(Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.foreground.opacity(0.02))
                    .cornerRadius(CornerRadius.xs)
                }

                // Token counts (if available)
                if call.inputTokens != nil || call.outputTokens != nil {
                    HStack(spacing: Spacing.md) {
                        if let input = call.inputTokens {
                            HStack(spacing: 3) {
                                Text("IN")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundMuted)
                                Text("\(input) tokens")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                        }
                        if let output = call.outputTokens {
                            HStack(spacing: 3) {
                                Text("OUT")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundMuted)
                                Text("\(output) tokens")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                        }
                    }
                }

                // Error
                if let error = call.error, !error.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
            .padding(.top, Spacing.xs)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: kindIcon)
                    .font(.system(size: 10))
                    .foregroundColor(accentColor)
                    .frame(width: 16)

                Text(kindLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)

                Text(call.provider)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(accentColor.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.08))
                    .cornerRadius(3)

                if let model = call.model {
                    Text(model)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                if let ms = call.latencyMs {
                    Text("\(ms)ms")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                if call.status != "success" {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(Spacing.sm)
        .background(accentColor.opacity(0.03))
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(accentColor.opacity(0.1), lineWidth: 0.5)
        )
    }
}
