//
//  DesignHomeView.swift
//  Talkie macOS
//
//  Design System Overview - Philosophy, principles, and guidelines
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

struct DesignHomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                headerSection

                // Main content grid
                HStack(alignment: .top, spacing: Spacing.xl) {
                    // Left column
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        screenResolutionSection
                        designPrinciplesSection
                    }
                    .frame(maxWidth: .infinity)

                    // Right column
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        spacingPhilosophySection
                        quickReferenceSection
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Design System")
                .font(Theme.current.fontTitle)
                .foregroundColor(Theme.current.foreground)

            Text("Philosophy, principles, and alignment guidelines")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    // MARK: - Screen Resolution (Prominent)

    private var screenResolutionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title: "Screen Resolution Strategy")

            VStack(alignment: .leading, spacing: Spacing.md) {
                resolutionTier(
                    size: "900 × 600",
                    label: "Minimum",
                    description: "All UI must be functional and readable. Optimize for information density."
                )

                resolutionTier(
                    size: "1440 × 900",
                    label: "Optimal",
                    description: "Primary design target. Most users work at this resolution. Prioritize comfort and clarity."
                )

                resolutionTier(
                    size: "1920 × 1080+",
                    label: "Large",
                    description: "Use extra space for breathing room, not larger elements. Maintain visual density."
                )
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Design Principles

    private var designPrinciplesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title: "Design Principles")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                principleRow(
                    title: "Minimal & Refined",
                    description: "Understated elegance over visual noise"
                )

                principleRow(
                    title: "Information Dense",
                    description: "Maximize signal, minimize chrome"
                )

                principleRow(
                    title: "Consistency First",
                    description: "Use semantic tokens, never hardcode"
                )

                principleRow(
                    title: "8pt Grid",
                    description: "All spacing multiples of 8 for visual rhythm"
                )
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Spacing Philosophy

    private var spacingPhilosophySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title: "Spacing Philosophy")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Use semantic tokens to express relationships:")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                spacingGuideline(token: "xxs, xs", usage: "Within components")
                spacingGuideline(token: "sm, md", usage: "Between components")
                spacingGuideline(token: "lg, xl", usage: "Section breaks")
                spacingGuideline(token: "xxl", usage: "Major divisions")

                Divider()
                    .background(Theme.current.divider)
                    .padding(.vertical, Spacing.xs)

                Text("Never hardcode spacing values. If the scale doesn't fit, the scale is wrong.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .italic()
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Quick Reference

    private var quickReferenceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title: "Quick Reference")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                referenceRow(category: "Spacing", token: "Spacing.{xxs...xxl}")
                referenceRow(category: "Typography", token: "Theme.current.font*")
                referenceRow(category: "Colors", token: "Theme.current.*")
                referenceRow(category: "Corners", token: "CornerRadius.{xs...lg}")
                referenceRow(category: "Opacity", token: "Opacity.{subtle...heavy}")

                Divider()
                    .background(Theme.current.divider)
                    .padding(.vertical, Spacing.xs)

                Text("See Components view for detailed token inventory")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(Theme.current.fontHeadlineBold)
            .foregroundColor(Theme.current.foreground)
    }

    private func resolutionTier(size: String, label: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(size)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(label)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.xs)
            }

            Text(description)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func principleRow(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)

            Text(description)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    private func spacingGuideline(token: String, usage: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(token)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
                .frame(width: 60, alignment: .leading)

            Text(usage)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func referenceRow(category: String, token: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(category)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
                .frame(width: 80, alignment: .leading)

            Text(token)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }
}

#Preview("Design Home") {
    DesignHomeView()
        .frame(width: 1200, height: 800)
}

#endif
