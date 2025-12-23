//
//  DesignHomeView.swift
//  Talkie macOS
//
//  Design System One-Pager - Self-documenting reference for all design tokens
//  Shows WHY tokens exist, WHEN to use them, and HOW they relate to screen sizes
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

struct DesignHomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Header
                headerSection

                // Spacing Scale
                spacingSection

                // Typography
                typographySection

                // Colors
                colorsSection

                // Screen Resolution
                screenResolutionSection

                // Component Dimensions
                componentDimensionsSection
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    TalkieTheme.accent.opacity(0.15),
                    TalkieTheme.accent.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(CornerRadius.lg)

            // Content
            HStack(spacing: Spacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(TalkieTheme.accent.opacity(0.2))
                        .frame(width: 80, height: 80)

                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 36))
                        .foregroundColor(TalkieTheme.accent)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Design System")
                        .font(Theme.current.fontDisplay)
                        .foregroundColor(Theme.current.foreground)

                    Text("Self-documenting reference for Talkie's design tokens")
                        .font(Theme.current.fontBody)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Metadata badges
                    HStack(spacing: Spacing.xs) {
                        badge(icon: "ruler", text: "8pt Grid")
                        badge(icon: "textformat", text: "6 Type Categories")
                        badge(icon: "paintpalette", text: "Semantic Colors")
                    }
                    .padding(.top, Spacing.xs)
                }

                Spacer()
            }
            .padding(Spacing.xl)
        }
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(Theme.current.fontXS)
        }
        .foregroundColor(TalkieTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TalkieTheme.accent.opacity(0.15))
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Spacing Section

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader(
                icon: "ruler.fill",
                title: "Spacing Scale",
                subtitle: "8pt grid system for consistent visual rhythm",
                accentColor: .cyan
            )

            VStack(alignment: .leading, spacing: Spacing.md) {
                spacingToken("xxs", value: Spacing.xxs, usage: "Micro spacing for tight element grouping (badges, inline icons)")
                spacingToken("xs", value: Spacing.xs, usage: "Extra small spacing for related elements (label-to-control)")
                spacingToken("sm", value: Spacing.sm, usage: "Small spacing within sections (form fields, list items)")
                spacingToken("md", value: Spacing.md, usage: "Medium spacing between sections (card padding, section dividers)")
                spacingToken("lg", value: Spacing.lg, usage: "Large spacing for major section breaks (settings groups)")
                spacingToken("xl", value: Spacing.xl, usage: "Extra large spacing (page padding, major divisions)")
                spacingToken("xxl", value: Spacing.xxl, usage: "Maximum spacing for major layout divisions")
            }
            .padding(Spacing.lg)
            .background(
                ZStack {
                    Theme.current.surface1

                    // Subtle accent border
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                }
            )
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Typography Section

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader(
                icon: "textformat.size",
                title: "Typography",
                subtitle: "Type hierarchy guides user attention and establishes information hierarchy",
                accentColor: .purple
            )

            VStack(alignment: .leading, spacing: Spacing.lg) {
                typeCategory(
                    category: "Display",
                    description: "Large titles, hero text, onboarding headers"
                ) {
                    typeExample("displayLarge", font: .displayLarge, text: "Display Large (32pt bold)")
                    typeExample("displayMedium", font: .displayMedium, text: "Display Medium (26pt bold)")
                    typeExample("displaySmall", font: .displaySmall, text: "Display Small (22pt semibold)")
                }

                Divider().opacity(0.3)

                typeCategory(
                    category: "Headline",
                    description: "Section titles, emphasis, subsection headers"
                ) {
                    typeExample("headlineLarge", font: .headlineLarge, text: "Headline Large (18pt semibold)")
                    typeExample("headlineMedium", font: .headlineMedium, text: "Headline Medium (16pt semibold)")
                    typeExample("headlineSmall", font: .headlineSmall, text: "Headline Small (14pt semibold)")
                }

                Divider().opacity(0.3)

                typeCategory(
                    category: "Body",
                    description: "Primary content, readable text (monospaced for tactical feel)"
                ) {
                    typeExample("bodyLarge", font: .bodyLarge, text: "Body Large (16pt regular mono)")
                    typeExample("bodyMedium", font: .bodyMedium, text: "Body Medium (14pt regular mono)")
                    typeExample("bodySmall", font: .bodySmall, text: "Body Small (12pt regular mono)")
                }

                Divider().opacity(0.3)

                typeCategory(
                    category: "Label",
                    description: "UI chrome, navigation, control labels"
                ) {
                    typeExample("labelLarge", font: .labelLarge, text: "Label Large (13pt medium)")
                    typeExample("labelMedium", font: .labelMedium, text: "Label Medium (11pt medium)")
                    typeExample("labelSmall", font: .labelSmall, text: "Label Small (10pt medium)")
                }

                Divider().opacity(0.3)

                typeCategory(
                    category: "Tech Label",
                    description: "Section headers, status indicators (uppercase, bold mono)"
                ) {
                    typeExample("techLabel", font: .techLabel, text: "TECH LABEL (10PT BOLD MONO)")
                    typeExample("techLabelSmall", font: .techLabelSmall, text: "TECH LABEL SMALL (9PT BOLD MONO)")
                }

                Divider().opacity(0.3)

                typeCategory(
                    category: "Mono",
                    description: "Technical data, durations, counts, timestamps"
                ) {
                    typeExample("monoLarge", font: .monoLarge, text: "Mono Large (16pt medium)")
                    typeExample("monoMedium", font: .monoMedium, text: "Mono Medium (14pt medium)")
                    typeExample("monoSmall", font: .monoSmall, text: "Mono Small (12pt regular)")
                    typeExample("monoXSmall", font: .monoXSmall, text: "Mono XSmall (10pt regular)")
                }
            }
            .padding(Spacing.lg)
            .background(
                ZStack {
                    Theme.current.surface1

                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                }
            )
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Colors Section

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader(
                icon: "paintpalette.fill",
                title: "Color Palette",
                subtitle: "Semantic color system for consistent visual language",
                accentColor: .pink
            )

            VStack(alignment: .leading, spacing: Spacing.lg) {
                colorCategory(category: "Backgrounds") {
                    colorSwatch(name: "background", color: Theme.current.background, usage: "Primary content area")
                    colorSwatch(name: "backgroundSecondary", color: Theme.current.backgroundSecondary, usage: "Sidebar, secondary panels")
                    colorSwatch(name: "backgroundTertiary", color: Theme.current.backgroundTertiary, usage: "Elevated areas, bottom bars, toolbars")
                }

                Divider().opacity(0.3)

                colorCategory(category: "Foreground (Text)") {
                    colorSwatch(name: "foreground", color: Theme.current.foreground, usage: "Primary text, headlines")
                    colorSwatch(name: "foregroundSecondary", color: Theme.current.foregroundSecondary, usage: "Body text, descriptions")
                    colorSwatch(name: "foregroundMuted", color: Theme.current.foregroundMuted, usage: "Metadata, timestamps, tertiary text")
                }

                Divider().opacity(0.3)

                colorCategory(category: "Surfaces") {
                    colorSwatch(name: "surface1", color: Theme.current.surface1, usage: "Cards, panels, elevated content")
                    colorSwatch(name: "surface2", color: Theme.current.surface2, usage: "Nested cards, secondary elevation")
                    colorSwatch(name: "surface3", color: Theme.current.surface3, usage: "Tertiary elevation, tooltips")
                    colorSwatch(name: "surfaceInput", color: Theme.current.surfaceInput, usage: "Text fields, inputs")
                    colorSwatch(name: "surfaceHover", color: Theme.current.surfaceHover, usage: "Hover states on interactive elements")
                    colorSwatch(name: "surfaceSelected", color: Theme.current.surfaceSelected, usage: "Selected items, active states")
                }

                Divider().opacity(0.3)

                colorCategory(category: "Semantic Colors") {
                    colorSwatch(name: "success", color: SemanticColor.success, usage: "Success states, enabled toggles, confirmations")
                    colorSwatch(name: "warning", color: SemanticColor.warning, usage: "Warnings, caution messages, auto-run indicators")
                    colorSwatch(name: "error", color: SemanticColor.error, usage: "Errors, destructive actions, validation failures")
                    colorSwatch(name: "info", color: SemanticColor.info, usage: "Info badges, notifications, highlights")
                    colorSwatch(name: "pin", color: SemanticColor.pin, usage: "Pin/favorite accent, bookmarks")
                    colorSwatch(name: "processing", color: SemanticColor.processing, usage: "Processing states, activity indicators")
                }

                Divider().opacity(0.3)

                colorCategory(category: "Accent (TalkieTheme)") {
                    colorSwatch(name: "accent", color: TalkieTheme.accent, usage: "Primary brand accent, CTAs, highlights")
                }
            }
            .padding(Spacing.lg)
            .background(
                ZStack {
                    Theme.current.surface1

                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                }
            )
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Screen Resolution Section

    private var screenResolutionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader(
                icon: "rectangle.on.rectangle.angled",
                title: "Screen Resolution Guidance",
                subtitle: "Responsive design strategy for various screen sizes",
                accentColor: .orange
            )

            VStack(alignment: .leading, spacing: Spacing.md) {
                resolutionInfo(
                    title: "Minimum Supported",
                    size: "900×600",
                    description: "Smallest usable size. Sidebar collapses, content flows to single column."
                )

                resolutionInfo(
                    title: "Optimal Desktop",
                    size: "1440×900",
                    description: "Ideal size for desktop usage. Full sidebar, comfortable content width."
                )

                resolutionInfo(
                    title: "Large Displays",
                    size: "1920×1080+",
                    description: "Spacious layouts, wider content areas, more breathing room."
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Responsive Strategy:")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("• Collapsible sidebar adapts to narrow widths")
                    Text("• Fluid content areas with max-width constraints")
                    Text("• Touch targets remain 44pt minimum on all devices")
                    Text("• Font sizes scale proportionally with window size")
                }
                .font(Theme.current.fontBody)
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.top, Spacing.sm)
            }
            .padding(Spacing.lg)
            .background(
                ZStack {
                    Theme.current.surface1

                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                }
            )
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Component Dimensions Section

    private var componentDimensionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionHeader(
                icon: "square.on.circle.fill",
                title: "Component Dimensions",
                subtitle: "Standard heights and the 8pt grid system",
                accentColor: .green
            )

            VStack(alignment: .leading, spacing: Spacing.md) {
                dimensionInfo(name: "OnboardingLayout.headerHeight", value: "48pt", usage: "Header zone height (top icon/status area)")
                dimensionInfo(name: "OnboardingLayout.footerHeight", value: "48pt", usage: "Footer zone height (action button area)")
                dimensionInfo(name: "OnboardingLayout.buttonHeight", value: "48pt", usage: "Standard button height in footer")
                dimensionInfo(name: "OnboardingLayout.contentTopPadding", value: "24pt", usage: "Top padding for content after header")
                dimensionInfo(name: "OnboardingLayout.horizontalPadding", value: "24pt", usage: "Horizontal padding for all content")

                Divider().opacity(0.3).padding(.vertical, Spacing.xs)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Corner Radius:")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)

                    cornerRadiusExample("xs", value: CornerRadius.xs, usage: "Minimal rounding for inline elements")
                    cornerRadiusExample("sm", value: CornerRadius.sm, usage: "Small cards, buttons")
                    cornerRadiusExample("md", value: CornerRadius.md, usage: "Medium cards, panels")
                    cornerRadiusExample("lg", value: CornerRadius.lg, usage: "Large cards, modals")
                    cornerRadiusExample("xl", value: CornerRadius.xl, usage: "Extra large, hero elements")
                }
                .padding(.top, Spacing.sm)
            }
            .padding(Spacing.lg)
            .background(
                ZStack {
                    Theme.current.surface1

                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                }
            )
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(icon: String, title: String, subtitle: String, accentColor: Color) -> some View {
        HStack(spacing: Spacing.md) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                accentColor.opacity(0.3),
                                accentColor.opacity(0.15)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Theme.current.fontHeadlineBold)
                    .foregroundColor(Theme.current.foreground)

                Text(subtitle)
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()
        }
    }

    private func spacingToken(_ name: String, value: CGFloat, usage: String) -> some View {
        HStack(spacing: Spacing.md) {
            // Visual bar with gradient and glow
            ZStack {
                // Glow effect
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.cyan.opacity(0.3))
                    .frame(width: value + 4, height: 24)
                    .blur(radius: 4)

                // Main bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.cyan,
                                Color.cyan.opacity(0.7)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: value, height: 20)
            }

            // Token info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text("Spacing.\(name)")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("\(Int(value))pt")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Color.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15))
                        .cornerRadius(4)
                }

                Text(usage)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }

    private func typeCategory<Content: View>(
        category: String,
        description: String,
        @ViewBuilder examples: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category)
                    .font(Theme.current.fontBodyBold)
                    .foregroundColor(Theme.current.foreground)

                Text(description)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                examples()
            }
        }
    }

    private func typeExample(_ tokenName: String, font: Font, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Text(text)
                .font(font)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Text("Font.\(tokenName)")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.current.surface2)
                .cornerRadius(4)
        }
    }

    private func colorCategory<Content: View>(
        category: String,
        @ViewBuilder swatches: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(category)
                .font(Theme.current.fontBodyBold)
                .foregroundColor(Theme.current.foreground)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                swatches()
            }
        }
    }

    private func colorSwatch(name: String, color: Color, usage: String) -> some View {
        HStack(spacing: Spacing.md) {
            // Color swatch with depth
            ZStack {
                // Shadow
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(color.opacity(0.4))
                    .frame(width: 64, height: 36)
                    .blur(radius: 6)
                    .offset(y: 2)

                // Main swatch
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(color)
                    .frame(width: 60, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                    .overlay(
                        // Highlight reflection
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.clear
                            ]),
                            startPoint: .top,
                            endPoint: .center
                        )
                        .cornerRadius(CornerRadius.sm)
                    )
            }

            // Color info
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme.current.\(name)")
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(usage)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }

    private func resolutionInfo(title: String, size: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(size)
                    .font(Theme.current.fontXS)
                    .foregroundColor(TalkieTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TalkieTheme.accent.opacity(0.15))
                    .cornerRadius(4)
            }

            Text(description)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func dimensionInfo(name: String, value: String, usage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Text(name)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(value)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.current.surface2)
                    .cornerRadius(4)
            }

            Text(usage)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func cornerRadiusExample(_ name: String, value: CGFloat, usage: String) -> some View {
        HStack(spacing: Spacing.md) {
            // Visual example with depth
            ZStack {
                // Glow
                RoundedRectangle(cornerRadius: value)
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .blur(radius: 6)

                // Main shape
                RoundedRectangle(cornerRadius: value)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.green.opacity(0.4),
                                Color.green.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: value)
                            .stroke(Color.green, lineWidth: 2)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text("CornerRadius.\(name)")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("\(Int(value))pt")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Color.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }

                Text(usage)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }
}

#Preview("Design Home") {
    DesignHomeView()
        .frame(width: 800, height: 600)
}

#endif
