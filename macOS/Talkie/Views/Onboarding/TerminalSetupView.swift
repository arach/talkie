//
//  TerminalSetupView.swift
//  Talkie macOS
//
//  Retro terminal-style setup utility component
//  Displays progress bars, console logs, and status messages
//

import SwiftUI

// MARK: - Terminal Setup View

struct TerminalSetupView: View {
    let mode: TerminalMode
    @State private var displayedLines: [ConsoleLine] = []
    @State private var cursorVisible = true

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text("TALKIE SETUP UTILITY")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 20)

                Spacer()

                // Content area
                switch mode {
                case .progress(let config):
                    ProgressModeContent(config: config)
                case .console(let config):
                    ConsoleModeContent(displayedLines: $displayedLines, config: config, cursorVisible: cursorVisible)
                case .combined(let progressConfig, let consoleConfig):
                    CombinedModeContent(
                        progressConfig: progressConfig,
                        consoleConfig: consoleConfig,
                        displayedLines: $displayedLines,
                        cursorVisible: cursorVisible
                    )
                }

                Spacer()

                // Footer
                Text("SECURE BINARY VERIFICATION: PASS (SHA-256: BA5F9...)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            startCursorBlink()
            if case .console(let config) = mode {
                streamConsoleLines(config.lines)
            } else if case .combined(_, let consoleConfig) = mode {
                streamConsoleLines(consoleConfig.lines)
            }
        }
    }

    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            cursorVisible.toggle()
        }
    }

    private func streamConsoleLines(_ lines: [ConsoleLine]) {
        Task {
            for line in lines {
                displayedLines.append(line)
                try? await Task.sleep(nanoseconds: UInt64(line.delay * 1_000_000_000))
            }
        }
    }
}

// MARK: - Terminal Mode

enum TerminalMode {
    case progress(ProgressConfig)
    case console(ConsoleConfig)
    case combined(ProgressConfig, ConsoleConfig)
}

struct ProgressConfig {
    let progress: Double // 0.0 to 1.0
    let statusText: String
    let subtitleText: String?
}

struct ConsoleConfig {
    let lines: [ConsoleLine]
    let showASCIILogo: Bool
}

struct ConsoleLine: Identifiable {
    let id = UUID()
    let timestamp: String
    let icon: String // "→" or other
    let text: String
    let delay: Double // seconds before showing
}

// MARK: - Progress Mode Content

private struct ProgressModeContent: View {
    let config: ProgressConfig

    var body: some View {
        VStack(spacing: 24) {
            // Status text
            Text(config.statusText.uppercased())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.7))

            // Progress bar
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.white.opacity(0.1))

                            // Progress fill
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(config.progress))
                        }
                    }
                    .frame(height: 4)

                    // Percentage
                    Text("\(Int(config.progress * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(width: 40, alignment: .trailing)
                }

                // Subtitle
                if let subtitle = config.subtitleText {
                    Text(subtitle.uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                }
            }
            .frame(width: 420)
        }
    }
}

// MARK: - Console Mode Content

private struct ConsoleModeContent: View {
    @Binding var displayedLines: [ConsoleLine]
    let config: ConsoleConfig
    let cursorVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ASCII Logo
            if config.showASCIILogo {
                ASCIILogoView()
                    .padding(.bottom, 32)
            }

            // Console lines
            VStack(alignment: .leading, spacing: 6) {
                ForEach(displayedLines) { line in
                    ConsoleLineView(line: line)
                }

                // Cursor
                if !displayedLines.isEmpty {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 8, height: 14)
                            .opacity(cursorVisible ? 1 : 0)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Combined Mode Content

private struct CombinedModeContent: View {
    let progressConfig: ProgressConfig
    let consoleConfig: ConsoleConfig
    @Binding var displayedLines: [ConsoleLine]
    let cursorVisible: Bool

    var body: some View {
        VStack(spacing: 40) {
            // Progress section
            ProgressModeContent(config: progressConfig)

            // Console section (compact)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(displayedLines.suffix(5)) { line in
                    ConsoleLineView(line: line, compact: true)
                }
            }
            .frame(width: 500, alignment: .leading)
        }
    }
}

// MARK: - ASCII Logo View

private struct ASCIILogoView: View {
    var body: some View {
        Text("""
        ████████╗ █████╗ ██╗     ██╗  ██╗██╗███████╗
        ╚══██╔══╝██╔══██╗██║     ██║ ██╔╝██║██╔════╝
           ██║   ███████║██║     █████╔╝ ██║█████╗
           ██║   ██╔══██║██║     ██╔═██╗ ██║██╔══╝
           ██║   ██║  ██║███████╗██║  ██╗██║███████╗
           ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝
        """)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundColor(.green)
        .lineSpacing(2)
    }
}

// MARK: - Console Line View

private struct ConsoleLineView: View {
    let line: ConsoleLine
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(line.timestamp)
                .font(.system(size: compact ? 9 : 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))

            // Icon
            Text(line.icon)
                .font(.system(size: compact ? 9 : 10, design: .monospaced))
                .foregroundColor(.green)

            // Text
            Text(line.text)
                .font(.system(size: compact ? 9 : 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Preview

#Preview("Progress Mode") {
    TerminalSetupView(
        mode: .progress(
            ProgressConfig(
                progress: 0.28,
                statusText: "Deploying Primitives",
                subtitleText: "Setting up local intelligence environment"
            )
        )
    )
    .frame(width: 680, height: 560)
}

#Preview("Console Mode") {
    TerminalSetupView(
        mode: .console(
            ConsoleConfig(
                lines: [
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Initializing Talkie bootstrapper v2.4.0...", delay: 0.2),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Verifying Secure Enclave connectivity...", delay: 0.4),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Establishing encrypted local SQLite database...", delay: 0.6),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Mounting Private CloudKit container...", delay: 0.8),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Scanning for local inference capability (MLX/CoreML)...", delay: 1.0),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Optimizing Neural Engine paths...", delay: 1.2),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Installing default intelligence primitives...", delay: 1.4),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "Finalizing security isolation barrier...", delay: 1.6),
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "→", text: "System ready for user authentication.", delay: 1.8),
                ],
                showASCIILogo: true
            )
        )
    )
    .frame(width: 680, height: 560)
}

#Preview("Combined Mode") {
    TerminalSetupView(
        mode: .combined(
            ProgressConfig(
                progress: 0.65,
                statusText: "Installing Models",
                subtitleText: "Downloading Parakeet v3"
            ),
            ConsoleConfig(
                lines: [
                    ConsoleLine(timestamp: "[4:37:48 PM]", icon: "✓", text: "Model verification complete", delay: 0.2),
                    ConsoleLine(timestamp: "[4:37:49 PM]", icon: "→", text: "Extracting neural weights...", delay: 0.4),
                    ConsoleLine(timestamp: "[4:37:50 PM]", icon: "→", text: "Optimizing for Apple Silicon...", delay: 0.6),
                ],
                showASCIILogo: false
            )
        )
    )
    .frame(width: 680, height: 560)
}
