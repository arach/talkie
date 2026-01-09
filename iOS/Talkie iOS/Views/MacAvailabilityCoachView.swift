//
//  MacAvailabilityCoachView.swift
//  Talkie iOS
//
//  Shows Mac sync status for async memo processing via iCloud.
//  This is NOT about direct Mac connection - it shows whether
//  memos will be processed when synced via iCloud.
//

import SwiftUI

struct MacAvailabilityCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var observer = MacStatusObserver.shared

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Explanation header
                    iCloudSyncExplanation

                    // Current Mac Status
                    macStatusSection

                    // Recommendations
                    recommendationsSection

                    // Power State Guide
                    powerStateGuideSection

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Mac Sync Status")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await observer.refresh()
        }
    }

    // MARK: - iCloud Sync Explanation

    private var iCloudSyncExplanation: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "icloud")
                    .foregroundColor(.active)
                Text("Memos sync via iCloud")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
            }

            Text("Your Mac processes memos in the background when they sync via iCloud. This shows whether your Mac is available to process new memos.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary.opacity(0.5))
        .cornerRadius(CornerRadius.sm)
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Current Mac Status Section

    private var macStatusSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("YOUR MAC")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            if let status = observer.macStatus {
                VStack(spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.hostname)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.textPrimary)

                            Text("Last seen: \(status.timeSinceLastSeen)")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()

                        StatusBadge(status: status)
                    }

                    Divider()
                        .background(Color.borderPrimary)

                    // Capabilities
                    HStack(spacing: Spacing.lg) {
                        CapabilityIndicator(
                            title: "Sync Memos",
                            isAvailable: status.canProcessMemos,
                            icon: "arrow.triangle.2.circlepath"
                        )

                        CapabilityIndicator(
                            title: "Run Workflows",
                            isAvailable: status.canRunWorkflows,
                            icon: "gearshape.2"
                        )
                    }

                    if !status.isAvailable {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                            Text("Available: \(status.estimatedAvailability)")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.top, Spacing.xs)
                    }
                }
                .padding(Spacing.md)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )
                .padding(.horizontal, Spacing.md)
            } else {
                // No Mac connected
                VStack(spacing: Spacing.md) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 32))
                        .foregroundColor(.textTertiary)

                    Text("No Mac Connected")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text("Open Talkie on your Mac to enable sync.\nMake sure both devices are signed into the same iCloud account.")
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("OPTIMIZE FOR REMOTE MEMOS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            if shouldShowRecommendation {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.warning)
                        Text("Tip: Keep your Mac available longer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }

                    Text("Your Mac sleeps quickly after you leave. For uninterrupted memo processing while you're away:")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        InstructionRow(step: "1", text: "Open System Settings on your Mac")
                        InstructionRow(step: "2", text: "Go to Energy (or Battery)")
                        InstructionRow(step: "3", text: "Enable \"Prevent automatic sleeping when display is off\"")
                        InstructionRow(step: "4", text: "Enable \"Wake for network access\"")
                    }

                    Text("This keeps your Mac processing memos even when the screen is off, without affecting security.")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(Spacing.md)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.warning.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, Spacing.md)
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                    Text("Your Mac is configured for optimal availability")
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - Power State Guide Section

    private var powerStateGuideSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("UNDERSTANDING MAC STATES")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                StateExplanationRow(
                    state: "Active",
                    icon: "bolt.fill",
                    color: .success,
                    description: "Memos process immediately"
                )

                Divider().background(Color.borderPrimary)

                StateExplanationRow(
                    state: "Idle",
                    icon: "moon.fill",
                    color: .warning,
                    description: "Still processing, user is away"
                )

                Divider().background(Color.borderPrimary)

                StateExplanationRow(
                    state: "Screen Off",
                    icon: "display",
                    color: .warning,
                    description: "Depends on Energy settings"
                )

                Divider().background(Color.borderPrimary)

                StateExplanationRow(
                    state: "Power Nap",
                    icon: "zzz",
                    color: .warning,
                    description: "Brief processing windows only"
                )

                Divider().background(Color.borderPrimary)

                StateExplanationRow(
                    state: "Sleeping",
                    icon: "moon.zzz.fill",
                    color: .textTertiary,
                    description: "Memos queue until Mac wakes"
                )
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Helpers

    private var shouldShowRecommendation: Bool {
        guard let status = observer.macStatus else { return false }
        // Show recommendation if Mac sleeps quickly (within 10 min of idle)
        // or if Mac is currently sleeping/unavailable
        return status.powerState == "sleeping" ||
               (status.powerState == "idle" && status.idleMinutes < 10) ||
               !status.isAvailable
    }
}

// MARK: - Supporting Views

private struct StatusBadge: View {
    let status: MacStatusObserver.MacStatusInfo

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.statusDescription)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surfaceTertiary)
        .cornerRadius(CornerRadius.sm)
    }

    private var statusColor: Color {
        switch status.powerState {
        case "active":
            return .success
        case "idle":
            return .warning
        case "screenOff":
            return status.canProcessMemos ? .success : .warning
        case "sleeping", "shuttingDown":
            return .textTertiary
        default:
            return .textTertiary
        }
    }
}

private struct CapabilityIndicator: View {
    let title: String
    let isAvailable: Bool
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isAvailable ? .success : .textTertiary)

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(isAvailable ? .textPrimary : .textTertiary)

            Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12))
                .foregroundColor(isAvailable ? .success : .textTertiary)
        }
    }
}

private struct InstructionRow: View {
    let step: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(step)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.active)
                .frame(width: 16, height: 16)
                .background(Color.active.opacity(0.15))
                .cornerRadius(4)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
        }
    }
}

private struct StateExplanationRow: View {
    let state: String
    let icon: String
    let color: Color
    let description: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(state)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    NavigationView {
        MacAvailabilityCoachView()
    }
}
