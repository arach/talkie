//
//  StatusCheckView.swift
//  Talkie macOS
//
//  Status check screen - monitors background downloads and service startup
//  Ported from TalkieLive's EngineWarmupStepView with conditional checks
//

import SwiftUI
import TalkieKit

struct StatusCheckView: View {
    let onNext: () -> Void
    @Bindable private var manager = OnboardingManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    private var statusSubtitle: String {
        if manager.allChecksComplete {
            return "All systems ready"
        } else if let inProgressCheck = manager.checkStatuses.first(where: {
            if case .inProgress = $0.value { return true }
            return false
        }) {
            if case .inProgress(let message) = inProgressCheck.value {
                return message
            }
        }
        return "Verifying setup..."
    }

    private var hasInProgressCheck: Bool {
        manager.checkStatuses.contains { check in
            if case .inProgress = check.value { return true }
            return false
        }
    }

    private var hasError: Bool {
        manager.checkStatuses.contains { check in
            if case .error = check.value { return true }
            return false
        }
    }

    private var overallStatusColor: Color {
        if hasError {
            return SemanticColor.error
        } else if manager.allChecksComplete {
            return SemanticColor.success
        } else {
            return colors.textTertiary.opacity(0.5)
        }
    }

    var body: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "SYSTEM STATUS",
            subtitle: statusSubtitle,
            illustration: {
                // Terminal-style icon with scan line animation
                ZStack {
                    // Background grid effect
                    GeometryReader { geo in
                        Path { path in
                            let spacing: CGFloat = 8
                            // Vertical lines
                            for i in stride(from: 0, through: geo.size.width, by: spacing) {
                                path.move(to: CGPoint(x: i, y: 0))
                                path.addLine(to: CGPoint(x: i, y: geo.size.height))
                            }
                            // Horizontal lines
                            for i in stride(from: 0, through: geo.size.height, by: spacing) {
                                path.move(to: CGPoint(x: 0, y: i))
                                path.addLine(to: CGPoint(x: geo.size.width, y: i))
                            }
                        }
                        .stroke(colors.accent.opacity(0.1), lineWidth: 0.5)
                    }

                    Image(systemName: "terminal.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(colors.accent)
                }
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colors.accent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(colors.accent.opacity(0.3), lineWidth: 1)
                        )
                )
                .opacity(manager.allChecksComplete ? 1.0 : 0.85)
            },
            content: {
                // Terminal-style status check panel
                VStack(alignment: .leading, spacing: 0) {
                    // Header bar - matches row style with status indicator
                    HStack(spacing: Spacing.sm) {
                        // Status dot in brackets - reflects overall status
                        HStack(spacing: 0) {
                            Text("[")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(colors.textTertiary)

                            // Status dot: gray (pending), green (complete), red (error)
                            Circle()
                                .fill(overallStatusColor)
                                .frame(width: 6, height: 6)
                                .shadow(color: manager.allChecksComplete ? SemanticColor.success.opacity(0.6) : Color.clear, radius: 2)

                            Text("]")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(colors.textTertiary)
                        }

                        Text("DIAGNOSTICS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)

                        Spacer()

                        if hasError {
                            Text("ERROR")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(SemanticColor.error)
                        } else if !manager.allChecksComplete {
                            HStack(spacing: 4) {
                                BrailleSpinner(speed: 0.08)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(colors.textTertiary)
                                Text("CHECKING...")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(colors.textTertiary)
                            }
                        } else {
                            Text("ALL CLEAR")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(SemanticColor.success)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(colors.background.opacity(0.5))

                    Divider()
                        .background(colors.border)

                    // Status check rows in terminal style
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(manager.visibleChecks, id: \.self) { check in
                            TechyStatusCheckRow(
                                colors: colors,
                                check: check,
                                status: manager.checkStatuses[check] ?? .pending
                            )

                            if check != manager.visibleChecks.last {
                                Divider()
                                    .background(colors.border.opacity(0.5))
                            }
                        }
                    }
                }
                .frame(width: 400)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .strokeBorder(colors.border, lineWidth: 1)
                        )
                )

                // Helper note about permissions
                if !manager.allChecksComplete && hasInProgressCheck {
                    Text("Note: Helper apps may request microphone permission")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(colors.textTertiary.opacity(0.7))
                        .padding(.top, Spacing.xs)
                }
            },
            cta: {
                if manager.allChecksComplete {
                    OnboardingCTAButton(
                        colors: colors,
                        title: "CONTINUE",
                        icon: "arrow.right",
                        action: onNext
                    )
                } else if let errorCheck = manager.checkStatuses.first(where: {
                    if case .error = $0.value { return true }
                    return false
                }) {
                    // Show retry button if there's an error
                    VStack(spacing: Spacing.xs) {
                        if case .error(let message) = errorCheck.value {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(SemanticColor.error)
                                .padding(.bottom, Spacing.xs)
                        }

                        OnboardingCTAButton(
                            colors: colors,
                            title: "RETRY",
                            icon: "arrow.clockwise",
                            action: {
                                Task {
                                    await manager.performStatusChecks()
                                }
                            }
                        )
                    }
                } else {
                    // Checks in progress
                    OnboardingCTAButton(
                        colors: colors,
                        title: "CHECKING...",
                        icon: "",
                        isEnabled: false,
                        action: {}
                    )
                }
            }
        )
        .onAppear {
            Task {
                await manager.performStatusChecks()
            }
        }
    }
}

// MARK: - Techy Status Check Row (Terminal Style)

private struct TechyStatusCheckRow: View {
    let colors: OnboardingColors
    let check: StatusCheck
    let status: CheckStatus

    private var statusText: String {
        switch status {
        case .pending: return "Waiting"
        case .inProgress(let message): return message
        case .complete: return "Ready"
        case .error(let message): return message
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return colors.textTertiary
        case .inProgress: return colors.accent
        case .complete: return SemanticColor.success
        case .error: return SemanticColor.error
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Left: Bracket with indicator inside [·] or [✓]
            HStack(spacing: 0) {
                Text("[")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(colors.textTertiary)

                // Indicator inside brackets
                Group {
                    switch status {
                    case .pending:
                        Text("·")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textTertiary.opacity(0.5))
                    case .inProgress:
                        BrailleSpinner(speed: 0.08)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(colors.accent)
                    case .complete:
                        Circle()
                            .fill(SemanticColor.success)
                            .frame(width: 6, height: 6)
                            .shadow(color: SemanticColor.success.opacity(0.6), radius: 2)
                    case .error:
                        Text("!")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(SemanticColor.error)
                    }
                }
                .frame(width: 12, height: 12)

                Text("]")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(colors.textTertiary)
            }

            // Check name
            Text(check.rawValue.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(colors.textPrimary)

            Spacer()

            // Right: Status text
            Text(statusText.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(status == .complete ? SemanticColor.success.opacity(0.03) : Color.clear)
        )
    }
}

// MARK: - Preview

#Preview("Light") {
    StatusCheckView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatusCheckView(onNext: {})
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
}
