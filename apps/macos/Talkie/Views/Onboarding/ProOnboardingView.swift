//
//  ProOnboardingView.swift
//  Talkie macOS
//
//  Three-step onboarding flow for Pro Tools activation.
//  Explains what Pro Tools unlocks, checks optional local tooling,
//  and activates Pro-facing navigation and detail level.
//

import SwiftUI
import TalkieKit

struct ProOnboardingView: View {
    private enum ProFeature: String, CaseIterable {
        case console
        case extensions
        case detailLevel
        case bridge

        var icon: String {
            switch self {
            case .console: return "terminal"
            case .extensions: return "puzzlepiece.extension"
            case .detailLevel: return "gauge.with.dots.needle.bottom.100percent"
            case .bridge: return "network"
            }
        }

        var title: String {
            switch self {
            case .console: return "System Console"
            case .extensions: return "Extensions & Apps"
            case .detailLevel: return "Technical Detail"
            case .bridge: return "Bridge & Devices"
            }
        }

        var summary: String {
            switch self {
            case .console:
                return "Unlock the Console surface and managed agent profiles."
            case .extensions:
                return "See where JavaScript apps and extension events are configured."
            case .detailLevel:
                return "Show more diagnostics, technical labels, and implementation context."
            case .bridge:
                return "Find the Bridge, TalkieServer, and device networking controls."
            }
        }

        var detail: String {
            switch self {
            case .console:
                return "Console is the advanced workspace in Talkie's sidebar. It is where you can inspect managed agent profiles, prompt material, and raw logs once Pro Tools is active."
            case .extensions:
                return "Extensions live in Settings > Extensions. That is where you enable the framework, inspect loaded apps, and understand what JavaScript apps can do inside Talkie."
            case .detailLevel:
                return "Pro Tools also switches the app to the Technical detail level so advanced surfaces stop hiding diagnostics. You can always dial it back later in Mode settings."
            case .bridge:
                return "Bridge and TalkieServer settings live under Helpers. That area handles pairing, server access, and optional networking extras like Tailscale."
            }
        }

        var location: String {
            switch self {
            case .console:
                return "Appears in the main sidebar under Tools after activation."
            case .extensions:
                return "Settings > Extensions"
            case .detailLevel:
                return "Settings > Mode"
            case .bridge:
                return "Settings > Helpers"
            }
        }

        var learnMoreTitle: String? {
            switch self {
            case .console:
                return nil
            case .extensions:
                return "Open Extensions"
            case .detailLevel:
                return "Open Mode Settings"
            case .bridge:
                return "Open Helpers"
            }
        }

        var settingsSection: SettingsSection? {
            switch self {
            case .console:
                return nil
            case .extensions:
                return .extensions
            case .detailLevel:
                return .mode
            case .bridge:
                return .helpers
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var manager = ProOnboardingManager()
    @State private var selectedFeature: ProFeature = .console
    @State private var selectedToolingItem: PrerequisiteItem = .bun

    private let localToolingItems: [PrerequisiteItem] = [.bun, .serverSource, .dependencies]
    private let optionalToolingItems: [PrerequisiteItem] = [.tailscale]

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    private var progressText: String {
        "\(manager.currentStep.rawValue + 1) of \(ProOnboardingStep.allCases.count)"
    }

    private var localReadyCount: Int {
        localToolingItems.filter { manager.prerequisiteStatuses[$0]?.isPassed == true }.count
    }

    private var optionalReadyCount: Int {
        optionalToolingItems.filter { manager.prerequisiteStatuses[$0]?.isPassed == true }.count
    }

    private var currentStepSummary: String {
        switch manager.currentStep {
        case .intro:
            return "What Pro Tools unlocks across Talkie."
        case .prerequisites:
            return "Optional local setup for repo work and remote access."
        case .complete:
            return "Advanced navigation and technical detail are now active."
        }
    }

    private var stepStatusLabel: String {
        switch manager.currentStep {
        case .intro:
            return "Preview"
        case .prerequisites:
            if manager.localToolingReady {
                return "Local Ready"
            }

            return "\(localReadyCount)/\(localToolingItems.count) Local"
        case .complete:
            return "Active"
        }
    }

    private var stepStatusTint: Color {
        switch manager.currentStep {
        case .intro:
            return colors.textSecondary
        case .prerequisites:
            return manager.localToolingReady ? colors.accent : Color(hex: "F59E0B")
        case .complete:
            return colors.accent
        }
    }

    var body: some View {
        ZStack {
            sheetBackground

            VStack(spacing: 0) {
                topBar

                Group {
                    switch manager.currentStep {
                    case .intro:
                        introStep
                    case .prerequisites:
                        prerequisitesStep
                    case .complete:
                        completeStep
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: manager.currentStep)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(colors.border.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.14), radius: 28, y: 16)
        .frame(width: 760, height: 620)
    }

    private var sheetBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    colors.background,
                    colors.background,
                    colors.surfaceCard.opacity(colorScheme == .dark ? 0.88 : 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GridPatternView(lineColor: colors.gridLine)
                .opacity(Opacity.half)

            RadialGradient(
                colors: [
                    colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    colors.accent.opacity(0)
                ],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 280
            )
            .frame(width: 480, height: 480)
            .offset(x: 170, y: -180)

            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.08),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 240
            )
            .frame(width: 360, height: 360)
            .offset(x: -180, y: 220)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            Button(action: manager.goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(colors.surfaceCard)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .opacity(manager.canGoBack ? 1 : 0)
            .disabled(!manager.canGoBack)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text("PRO TOOLS SETUP")
                    Text(progressText.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colors.accent.opacity(0.12))
                        .clipShape(.rect(cornerRadius: CornerRadius.xs))
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(colors.textSecondary)

                Text(currentStepSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)

                HStack(spacing: Spacing.sm) {
                    ForEach(ProOnboardingStep.allCases, id: \.rawValue) { step in
                        Capsule()
                            .fill(step.rawValue <= manager.currentStep.rawValue ? colors.accent : colors.border)
                            .frame(height: 3)
                    }
                }
                .padding(.top, 2)

                HStack(spacing: Spacing.xs) {
                    Text(manager.currentStep.label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(colors.textTertiary)

                    Text("•")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(colors.textTertiary.opacity(0.5))

                    Text(stepStatusLabel.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(stepStatusTint)
                }
            }

            Spacer()

            headerPill(title: stepStatusLabel.uppercased(), tint: stepStatusTint)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(colors.surfaceCard)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.18),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colors.border.opacity(0.8))
                .frame(height: 1)
        }
    }

    // MARK: - Step 1: Intro

    private var introStep: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "PRO TOOLS",
            subtitle: "Unlock Talkie's advanced tools without guessing where they live.",
            caption: "Pick a card to see what each part of Pro Tools actually changes.",
            illustration: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                }
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(colors.accent)
            },
            content: {
                VStack(spacing: Spacing.md) {
                    introSummaryCard

                    VStack(spacing: Spacing.sm) {
                        ForEach(ProFeature.allCases, id: \.rawValue) { feature in
                            featureRow(feature)
                        }
                    }
                }
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: "CONTINUE",
                    icon: "arrow.right.circle.fill",
                    action: advanceToPrerequisites
                )
            }
        )
    }

    // MARK: - Step 2: Tooling

    private var prerequisitesStep: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "OPTIONAL TOOLING",
            subtitle: "Pro Tools enables now. These cards explain the local tools behind TalkieServer and remote access.",
            caption: "Use each card to see what it installs, how to set it up, and what happens if you leave it for later.",
            illustration: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checklist.checked")
                    Image(systemName: "bolt.badge.checkmark")
                        .font(.system(size: 34, weight: .light))
                }
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(colors.accent)
            },
            content: {
                VStack(spacing: Spacing.md) {
                    toolingOverviewCard

                    toolingSection(
                        title: "LOCAL TALKIESERVER WORK",
                        subtitle: "Needed only if you want to run TalkieServer from this repository checkout.",
                        icon: "shippingbox",
                        accent: colors.accent,
                        badge: "\(localReadyCount)/\(localToolingItems.count) READY",
                        items: localToolingItems
                    )

                    toolingSection(
                        title: "REMOTE ACCESS EXTRA",
                        subtitle: "Useful when you want remote bridge networking and device access.",
                        icon: "network",
                        accent: Color(hex: "F59E0B"),
                        badge: optionalReadyCount > 0 ? "READY" : "OPTIONAL",
                        items: optionalToolingItems
                    )
                }
            },
            cta: {
                VStack(alignment: .trailing, spacing: Spacing.sm) {
                    HStack(alignment: .center, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACTIVATION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(colors.textTertiary)

                            Text(manager.toolingFootnote)
                                .font(.system(size: 10))
                                .foregroundStyle(colors.textSecondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Button(action: {
                            Task { await manager.validatePrerequisites() }
                        }) {
                            Text("Re-check")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.isValidating)

                        OnboardingCTAButton(
                            colors: colors,
                            title: manager.activationButtonTitle,
                            icon: "bolt.fill",
                            isEnabled: manager.canActivateDeveloperMode,
                            isLoading: manager.isValidating,
                            action: {
                                manager.activate()
                                manager.currentStep = .complete
                            }
                        )
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(colors.surfaceCard.opacity(0.92))
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 0.5)
                    )

                    if let errorMessage = manager.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(SemanticColor.error)
                    }
                }
            }
        )
    }

    private var introSummaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("CURRENT FOCUS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(colors.textTertiary)

                    Text(selectedFeature.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(colors.textPrimary)

                    Text(selectedFeature.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: selectedFeature.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: 44, height: 44)
                    .background(colors.accent.opacity(0.12))
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
            }

            HStack(spacing: Spacing.sm) {
                Label(selectedFeature.location, systemImage: "location")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)

                Spacer(minLength: Spacing.sm)
            }
        }
        .padding(Spacing.md)
        .background(colors.surfaceCard.opacity(0.92))
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(colors.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 10, y: 3)
    }

    private var toolingOverviewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SETUP SNAPSHOT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(colors.textTertiary)

                    Text(manager.localToolingReady
                        ? "This Mac is ready for repo-local TalkieServer work."
                        : "Pro Tools can turn on now, and the local setup can catch up later.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)

                    Text("These checks only change whether this checkout can run Bun-based server scripts locally and whether Tailscale-powered remote access is available.")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                headerPill(
                    title: manager.localToolingReady ? "LOCAL READY" : "OPTIONAL SETUP",
                    tint: manager.localToolingReady ? colors.accent : Color(hex: "F59E0B")
                )
            }

            HStack(spacing: Spacing.sm) {
                toolingMetricCard(
                    icon: "terminal",
                    title: "Local tooling",
                    value: "\(localReadyCount)/\(localToolingItems.count)",
                    message: localReadyCount == localToolingItems.count
                        ? "Ready for Bun and repo-local server work."
                        : "Optional setup for running this checkout locally.",
                    tint: colors.accent
                )

                toolingMetricCard(
                    icon: "network",
                    title: "Remote access",
                    value: "\(optionalReadyCount)/\(optionalToolingItems.count)",
                    message: optionalReadyCount > 0
                        ? "Tailscale is available for remote bridge access."
                        : "Only needed when you want remote device networking.",
                    tint: Color(hex: "F59E0B")
                )

                toolingMetricCard(
                    icon: "bolt.circle",
                    title: "Activation",
                    value: manager.activationButtonTitle,
                    message: "Developer surfaces unlock either way.",
                    tint: colors.textSecondary
                )
            }
        }
        .padding(Spacing.md)
        .background(colors.surfaceCard.opacity(0.92))
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(colors.border, lineWidth: 0.5)
        )
    }

    private func toolingSection(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        badge: String,
        items: [PrerequisiteItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.12))
                    .clipShape(.rect(cornerRadius: CornerRadius.xs))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(colors.textTertiary)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer()

                headerPill(title: badge, tint: accent)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(items, id: \.self) { item in
                    prerequisiteRow(item: item)
                }
            }
        }
        .padding(Spacing.md)
        .background(colors.surfaceCard.opacity(0.92))
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(colors.border, lineWidth: 0.5)
        )
    }

    // MARK: - Step 3: Complete

    private var completeStep: some View {
        OnboardingStepLayout(
            colors: colors,
            title: "PRO TOOLS ACTIVE",
            subtitle: "Talkie now exposes its advanced navigation and technical detail.",
            caption: manager.localToolingReady
                ? "Local TalkieServer extras are ready too."
                : "You can finish the optional local server setup later if you need it.",
            illustration: {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(colors.accent)
            },
            content: {
                VStack(spacing: Spacing.md) {
                    VStack(spacing: 0) {
                        activatedRow(icon: "terminal", title: "Console unlocked in the sidebar")
                        Divider().opacity(0.5)
                        activatedRow(icon: "slider.horizontal.3", title: "Settings visibility switched to Pro")
                        Divider().opacity(0.5)
                        activatedRow(icon: "gauge.with.dots.needle.bottom.100percent", title: "Detail level set to Technical")
                        Divider().opacity(0.5)
                        activatedRow(icon: "network", title: "Extensions and Bridge settings are one click away")
                    }
                    .background(colors.surfaceCard)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(colors.border, lineWidth: 0.5)
                    )

                    quickLinksCard
                }
            },
            cta: {
                OnboardingCTAButton(
                    colors: colors,
                    title: "DONE",
                    icon: "checkmark.circle.fill",
                    action: { dismiss() }
                )
            }
        )
    }

    // MARK: - Feature Rows

    private func featureRow(_ feature: ProFeature) -> some View {
        let isSelected = selectedFeature == feature

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { selectedFeature = feature }) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? colors.background : colors.accent)
                        .frame(width: 32, height: 32)
                        .background(isSelected ? colors.accent : colors.accent.opacity(Opacity.subtle))
                        .clipShape(.rect(cornerRadius: CornerRadius.xs))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)

                        Text(feature.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? colors.accent : colors.textTertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, isSelected ? Spacing.xs : Spacing.sm)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isSelected {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Rectangle()
                        .fill(colors.accent.opacity(0.28))
                        .frame(height: 1)

                    Text(feature.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "location")
                            .font(.system(size: 9, weight: .bold))

                        Text(feature.location)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background(colors.background.opacity(0.4))
                    .clipShape(.rect(cornerRadius: CornerRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .strokeBorder(colors.border.opacity(0.9), lineWidth: 0.5)
                    )

                    if let section = feature.settingsSection,
                       let title = feature.learnMoreTitle {
                        smallActionButton(title: title, icon: "arrow.up.right") {
                            openSettings(section)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(isSelected ? colors.accent.opacity(0.08) : colors.surfaceCard)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(isSelected ? colors.accent.opacity(0.6) : colors.border, lineWidth: isSelected ? 1 : 0.5)
        )
        .shadow(color: isSelected ? colors.accent.opacity(0.18) : .clear, radius: 8, y: 3)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
    }

    // MARK: - Tooling Rows

    private func prerequisiteRow(item: PrerequisiteItem) -> some View {
        let status = manager.prerequisiteStatuses[item] ?? .pending
        let isSelected = selectedToolingItem == item

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { selectedToolingItem = item }) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? colors.background : statusColor(for: status))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(isSelected ? statusColor(for: status) : statusColor(for: status).opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: Spacing.xs) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.textPrimary)

                            Text(item.badgeTitle)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(colors.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(colors.border.opacity(0.35))
                                .clipShape(.rect(cornerRadius: 2))
                        }

                        Text(item.description)
                            .font(.system(size: 11))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: Spacing.xs) {
                            statusIcon(for: status)

                            Text(prerequisiteStatusSummary(for: item, status: status))
                                .font(.system(size: 10, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(statusColor(for: status))
                    }

                    Spacer(minLength: Spacing.md)

                    VStack(alignment: .trailing, spacing: Spacing.sm) {
                        prerequisiteStatusBadge(for: status)

                        Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? colors.accent : colors.textTertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, isSelected ? Spacing.xs : Spacing.sm)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isSelected {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Rectangle()
                        .fill(colors.accent.opacity(0.28))
                        .frame(height: 1)

                    prerequisiteNarrativeCard(
                        title: "WHAT THIS COVERS",
                        body: prerequisiteInstallExplanation(for: item),
                        tint: statusColor(for: status)
                    )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("INSTALL STEPS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(colors.textTertiary)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(Array(prerequisiteInstallSteps(for: item).enumerated()), id: \.offset) { index, step in
                                prerequisiteStepRow(number: index + 1, text: step)
                            }
                        }
                        .padding(Spacing.sm)
                        .background(colors.background.opacity(0.4))
                        .clipShape(.rect(cornerRadius: CornerRadius.xs))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .strokeBorder(colors.border.opacity(0.9), lineWidth: 0.5)
                        )
                    }

                    prerequisiteNarrativeCard(
                        title: "IF YOU LEAVE IT FOR LATER",
                        body: prerequisiteLaterImpact(for: item),
                        tint: Color(hex: "F59E0B")
                    )

                    prerequisiteActions(for: item, status: status)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(isSelected ? colors.accent.opacity(0.08) : colors.surfaceCard)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(isSelected ? colors.accent.opacity(0.6) : colors.border, lineWidth: isSelected ? 1 : 0.5)
        )
        .shadow(color: isSelected ? colors.accent.opacity(0.16) : .black.opacity(colorScheme == .dark ? 0.16 : 0.05), radius: 6, y: 1)
    }

    @ViewBuilder
    private func prerequisiteActions(for item: PrerequisiteItem, status: PrerequisiteCheckStatus) -> some View {
        HStack(spacing: Spacing.sm) {
            switch item {
            case .bun:
                if !status.isPassed {
                    smallActionButton(title: "Install Bun", icon: "arrow.down.circle") {
                        openBunDownload()
                    }
                }
                smallActionButton(title: "Setup Guide", icon: "book") {
                    openBridgeDocs()
                }

            case .serverSource:
                smallActionButton(title: status.isPassed ? "Open Overview" : "Why This Matters", icon: "doc.text") {
                    BridgeManager.shared.openTalkieServerOverview()
                }

            case .dependencies:
                if manager.prerequisiteStatuses[.bun]?.isPassed == true &&
                    manager.prerequisiteStatuses[.serverSource]?.isPassed == true &&
                    !status.isPassed {
                    smallActionButton(
                        title: manager.isInstallingDependencies ? "Installing..." : "Install",
                        icon: manager.isInstallingDependencies ? nil : "square.and.arrow.down"
                    ) {
                        Task { await manager.installDependencies() }
                    }
                    .disabled(manager.isInstallingDependencies)
                }

                smallActionButton(title: "What Gets Installed", icon: "shippingbox") {
                    openBridgeDocs()
                }

            case .tailscale:
                if !status.isPassed {
                    smallActionButton(title: "Download", icon: "arrow.down.circle") {
                        openTailscaleDownload()
                    }
                }
                smallActionButton(title: "Setup Guide", icon: "network") {
                    openTailscaleDocs()
                }
            }
        }
    }

    private func prerequisiteStatusSummary(for item: PrerequisiteItem, status: PrerequisiteCheckStatus) -> String {
        switch status {
        case .passed:
            switch item {
            case .bun:
                return "Installed and ready for local Bun commands."
            case .serverSource:
                return "This checkout includes apps/macos/TalkieServer."
            case .dependencies:
                return "Packages are installed for local TalkieServer scripts."
            case .tailscale:
                return "Installed for remote bridge and device networking."
            }

        case .checking:
            switch item {
            case .bun:
                return "Checking whether Bun is available."
            case .serverSource:
                return "Checking this checkout for TalkieServer source."
            case .dependencies:
                return "Checking whether local server packages are installed."
            case .tailscale:
                return "Checking whether Tailscale is available."
            }

        case .failed(let reason):
            return reason

        case .optional(let reason):
            return reason

        case .pending:
            switch item {
            case .bun:
                return "Only needed when you want to run TalkieServer locally."
            case .serverSource:
                return "Only needed when you want this checkout to power the server."
            case .dependencies:
                return "Only needed when you want to run local TalkieServer scripts."
            case .tailscale:
                return "Optional unless you want remote bridge networking."
            }
        }
    }

    private func prerequisiteStatusTitle(for status: PrerequisiteCheckStatus) -> String {
        switch status {
        case .pending:
            return "PENDING"
        case .checking:
            return "CHECKING"
        case .passed:
            return "READY"
        case .failed:
            return "ACTION"
        case .optional:
            return "OPTIONAL"
        }
    }

    private func prerequisiteInstallExplanation(for item: PrerequisiteItem) -> String {
        switch item {
        case .bun:
            return "Bun is the JavaScript runtime and package manager used when Talkie runs the repository-local TalkieServer. It powers both `bun install` and `bun run src/server.ts`."
        case .serverSource:
            return "This card is looking for the local `apps/macos/TalkieServer` checkout. That folder contains `src/server.ts`, the `package.json` manifest, and the workspace packages the local server uses."
        case .dependencies:
            return "Running `bun install` inside `apps/macos/TalkieServer` installs the server packages declared in `package.json`: `elysia`, `@elysiajs/cors`, `@anthropic-ai/sdk`, `@anthropic-ai/claude-code`, the local `@talkie/workflow-core` workspace, and Bun type definitions. The install also runs the bridge setup scripts bundled with the repo."
        case .tailscale:
            return "Tailscale gives Talkie a private-network path for remote bridge access and device workflows. It is extra infrastructure, not part of the basic local setup."
        }
    }

    private func prerequisiteInstallSteps(for item: PrerequisiteItem) -> [String] {
        switch item {
        case .bun:
            return [
                "Install Bun on this Mac.",
                "Open a new terminal so the `bun` command is available on your PATH.",
                "Come back here and press Re-check."
            ]
        case .serverSource:
            return [
                "Keep this repository checkout available locally.",
                "Make sure `apps/macos/TalkieServer/src/server.ts` is present inside it.",
                "Come back here and press Re-check."
            ]
        case .dependencies:
            return [
                "Install Bun first.",
                "From `apps/macos/TalkieServer`, run `bun install`.",
                "Let Bun create `node_modules`, link the workspace packages, and run the bridge setup scripts.",
                "Come back here and press Re-check."
            ]
        case .tailscale:
            return [
                "Install the Tailscale app or CLI.",
                "Sign in and bring the tailnet connection up on this Mac.",
                "Come back here and press Re-check."
            ]
        }
    }

    private func prerequisiteLaterImpact(for item: PrerequisiteItem) -> String {
        switch item {
        case .bun:
            return "If you leave this for later, Talkie still activates normally. You just will not be able to run repo-local TalkieServer commands from this Mac yet."
        case .serverSource:
            return "If you leave this for later, built-app flows still work, but you will not be targeting a local `apps/macos/TalkieServer` checkout for edits or local launches."
        case .dependencies:
            return "If you leave this for later, the checkout is still there, but local scripts like `bun run src/server.ts` will fail as soon as they need missing packages."
        case .tailscale:
            return "If you leave this for later, nothing local breaks. You only lose remote bridge and device networking until you add it."
        }
    }

    private func prerequisiteNarrativeCard(title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(colors.textTertiary)

            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm)
        .background(tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func prerequisiteStepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(colors.background)
                .frame(width: 18, height: 18)
                .background(colors.accent)
                .clipShape(.rect(cornerRadius: CornerRadius.xs))

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: PrerequisiteCheckStatus) -> some View {
        switch status {
        case .checking:
            BrailleSpinner(size: 12)
                .foregroundStyle(statusColor(for: status))
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        case .optional:
            Image(systemName: "minus.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        }
    }

    private func statusColor(for status: PrerequisiteCheckStatus) -> Color {
        switch status {
        case .pending:
            return colors.textTertiary
        case .checking:
            return Color(hex: "60A5FA")
        case .passed:
            return colors.accent
        case .failed:
            return Color(hex: "F87171")
        case .optional:
            return Color(hex: "F59E0B")
        }
    }

    private func prerequisiteStatusBadge(for status: PrerequisiteCheckStatus) -> some View {
        HStack(spacing: 5) {
            statusIcon(for: status)
            Text(prerequisiteStatusTitle(for: status))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundStyle(statusColor(for: status))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(statusColor(for: status).opacity(0.12))
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(statusColor(for: status).opacity(0.2), lineWidth: 0.5)
        )
    }

    private func headerPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(.rect(cornerRadius: CornerRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
            )
    }

    private func toolingMetricCard(
        icon: String,
        title: String,
        value: String,
        message: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(colors.textTertiary)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(colors.textPrimary)

            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(colors.background.opacity(0.45))
        .clipShape(.rect(cornerRadius: CornerRadius.xs))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(colors.border.opacity(0.9), lineWidth: 0.5)
        )
    }

    private func smallActionButton(title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
            }
            .foregroundStyle(colors.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(colors.background.opacity(0.35))
            .clipShape(.rect(cornerRadius: CornerRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
    }

    // MARK: - Completion

    private func activatedRow(icon: String, title: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(colors.accent)
                .font(.system(size: 16))

            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var quickLinksCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("NEXT STOPS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(colors.textTertiary)

            HStack(spacing: Spacing.sm) {
                smallActionButton(title: "Mode", icon: "slider.horizontal.3") {
                    openSettings(.mode)
                }
                smallActionButton(title: "Extensions", icon: "puzzlepiece.extension") {
                    openSettings(.extensions)
                }
                smallActionButton(title: "Helpers", icon: "network") {
                    openSettings(.helpers)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(colors.surfaceCard)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(colors.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, y: 2)
    }

    // MARK: - Actions

    private func advanceToPrerequisites() {
        manager.currentStep = .prerequisites
        Task { await manager.validatePrerequisites() }
    }

    private func openSettings(_ section: SettingsSection) {
        NavigationState.shared.navigateToSettings(section)
        dismiss()
    }

    private func openBridgeDocs() {
        BridgeManager.shared.openBridgeSetupDocs()
    }

    private func openTailscaleDocs() {
        BridgeManager.shared.openTailscaleSetupDocs()
    }

    private func openBunDownload() {
        guard let url = URL(string: "https://bun.sh") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openTailscaleDownload() {
        guard let url = URL(string: "https://tailscale.com/download") else { return }
        NSWorkspace.shared.open(url)
    }
}
