//
//  StatusCheckView.swift
//  Talkie macOS
//
//  Status check screen - monitors background downloads and service startup
//  Ported from TalkieLive's EngineWarmupStepView with conditional checks
//

import SwiftUI

struct StatusCheckView: View {
    let onNext: () -> Void
    @ObservedObject private var manager = OnboardingManager.shared
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
                    // Header bar with monospaced font
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.allChecksComplete ? SemanticColor.success : colors.accent)
                            .frame(width: 6, height: 6)
                        Text("DIAGNOSTICS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(colors.textTertiary)
                        Spacer()
                        if !manager.allChecksComplete {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
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

    private var statusDotColor: Color {
        switch status {
        case .pending: return colors.textTertiary.opacity(0.4)
        case .inProgress: return colors.accent
        case .complete: return SemanticColor.success
        case .error: return SemanticColor.error
        }
    }

    private var summaryText: String {
        switch status {
        case .pending: return "Waiting..."
        case .inProgress(let message): return message
        case .complete: return "Ready"
        case .error(let message): return message
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Step name on left
            Text(check.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(colors.textPrimary)
                .frame(width: 140, alignment: .leading)

            // Summary message in middle
            Text(summaryText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)

            // Status dot on right - aligned
            HStack(spacing: 6) {
                if case .inProgress = status {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusDotColor.opacity(status == .complete ? 0.5 : 0), radius: 3)
                }
            }
            .frame(width: 20, alignment: .trailing)
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
