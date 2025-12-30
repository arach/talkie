//
//  StartupLogger.swift
//  Talkie
//
//  Observable logger for startup progress - shows terminal-style output
//

import SwiftUI
import TalkieKit

// MARK: - Startup Logger

@MainActor
@Observable
final class StartupLogger {
    static let shared = StartupLogger()

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let isError: Bool

        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }

    private(set) var logs: [LogEntry] = []
    private(set) var currentPhase: String = "Starting..."
    private(set) var isComplete = false

    private init() {}

    func log(_ message: String, isError: Bool = false) {
        let entry = LogEntry(timestamp: Date(), message: message, isError: isError)
        logs.append(entry)

        // Also print to console for debugging
        let prefix = isError ? "❌" : "→"
        print("\(prefix) [Startup] \(message)")
    }

    func setPhase(_ phase: String) {
        currentPhase = phase
        log(phase)
    }

    func complete() {
        isComplete = true
        log("Ready")
    }

    func reset() {
        logs.removeAll()
        currentPhase = "Starting..."
        isComplete = false
    }
}

// MARK: - Startup View

struct StartupView: View {
    let logger = StartupLogger.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Center content
            VStack(spacing: Spacing.lg) {
                // App icon or logo
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                // Current phase with braille spinner
                HStack(spacing: Spacing.sm) {
                    BrailleSpinner(speed: 0.08)
                        .font(Font.system(size: 14).monospaced())
                        .foregroundColor(TalkieTheme.textMuted)

                    Text(logger.currentPhase)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TalkieTheme.textSecondary)
                }
            }

            Spacer()

            // Terminal-style log viewer at bottom
            TerminalLogView(logs: logger.logs)
                .frame(height: 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MidnightSurface.content)
    }
}

// MARK: - Terminal Log View

struct TerminalLogView: View {
    let logs: [StartupLogger.LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Terminal header
            HStack(spacing: Spacing.sm) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 8, height: 8)

                Spacer()

                Text("startup")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logs) { entry in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Text(entry.formattedTime)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(TalkieTheme.textMuted.opacity(0.6))

                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.isError ? .red : TalkieTheme.textSecondary)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(Spacing.sm)
                }
                .onChange(of: logs.count) { _, _ in
                    if let lastLog = logs.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(Spacing.md)
    }
}

// MARK: - Preview

#Preview {
    StartupView()
        .frame(width: 600, height: 400)
        .onAppear {
            // Simulate startup logs
            let logger = StartupLogger.shared
            logger.reset()
            logger.setPhase("Initializing database...")

            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run { logger.log("Opening talkie_grdb.sqlite") }

                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run { logger.log("Running migration v1_initial_schema") }

                try? await Task.sleep(for: .milliseconds(150))
                await MainActor.run { logger.log("Created table: voice_memos") }

                try? await Task.sleep(for: .milliseconds(100))
                await MainActor.run { logger.log("Created indexes") }

                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run { logger.setPhase("Checking migration status...") }

                try? await Task.sleep(for: .milliseconds(100))
                await MainActor.run { logger.complete() }
            }
        }
}
