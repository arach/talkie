//
//  TokenShowcase.swift
//  Talkie macOS
//
//  Token System Showcase - Visualize design token differences between themes
//  Accessed via Design Mode (⌘⇧D) → Token Showcase
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import TalkieKit

#if DEBUG

// MARK: - Token Showcase View

struct TokenShowcaseView: View {
    @State private var selectedTheme: ThemeOption = .linear
    @State private var showDeltas: Bool = true  // Show differences from defaults
    @Environment(\.dismiss) private var dismiss

    // Reference tokens for comparison
    private var defaultTokens: any SemanticTokens { MidnightTokens() }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Theme Picker + Delta Toggle
                    controlsSection

                    // Component Previews
                    componentSection

                    // Token Values
                    tokenValuesSection
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 650, height: 750)
        .background(currentTokens.bgCanvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Showcase")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(currentTokens.fgPrimary)

                Text("Compare design tokens across themes")
                    .font(.system(size: 11))
                    .foregroundColor(currentTokens.fgSecondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.md)
        .background(currentTokens.bgSurface)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Theme Picker
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("THEME")

                HStack(spacing: Spacing.sm) {
                    ForEach(ThemeOption.allCases, id: \.self) { theme in
                        themeButton(theme)
                    }
                }
            }

            // Delta Toggle
            HStack(spacing: Spacing.md) {
                Toggle(isOn: $showDeltas) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11))
                        Text("Show differences from Midnight (default)")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(currentTokens.fgSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                if showDeltas && selectedTheme != .midnight {
                    deltaLegend
                }
            }
            .padding(.top, Spacing.xs)
        }
    }

    private var deltaLegend: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green.opacity(0.6))
                    .frame(width: 8, height: 8)
                Text("Changed")
                    .font(.system(size: 9))
                    .foregroundColor(currentTokens.fgMuted)
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(currentTokens.fgMuted.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text("Same as default")
                    .font(.system(size: 9))
                    .foregroundColor(currentTokens.fgMuted)
            }
        }
    }

    private func themeButton(_ theme: ThemeOption) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTheme = theme
            }
        }) {
            VStack(spacing: 4) {
                // Color preview circles
                HStack(spacing: 2) {
                    Circle()
                        .fill(theme.tokens.bgCanvas)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(theme.tokens.accent)
                        .frame(width: 12, height: 12)
                }

                Text(theme.name)
                    .font(.system(size: 10, weight: selectedTheme == theme ? .semibold : .regular))
                    .foregroundColor(selectedTheme == theme ? currentTokens.accent : currentTokens.fgSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTheme == theme ? currentTokens.accent.opacity(0.15) : currentTokens.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selectedTheme == theme ? currentTokens.accent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Component Section

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Cards
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("CARDS")

                HStack(spacing: Spacing.md) {
                    cardPreview(preset: "default", tokens: currentTokens.card)
                    cardPreview(preset: "glow", tokens: CardTokens.glow())
                    cardPreview(preset: "soft", tokens: CardTokens.soft)
                }
            }

            // Buttons
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("BUTTONS")

                HStack(spacing: Spacing.md) {
                    buttonPreview(preset: "default", tokens: currentTokens.button)
                    buttonPreview(preset: "pill", tokens: ButtonTokens.pill)
                    buttonPreview(preset: "sharp", tokens: ButtonTokens.sharp)
                    buttonPreview(preset: "warm", tokens: ButtonTokens.warm())
                }
            }

            // Table Rows
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("TABLE ROWS")

                tablePreview()
            }
        }
    }

    // MARK: - Card Preview

    private func cardPreview(preset: String, tokens: CardTokens) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Card
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(currentTokens.accent)
                        .frame(width: 8, height: 8)
                    Text("Card Title")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(currentTokens.fgPrimary)
                }

                Text("Detail text here")
                    .font(.system(size: 9))
                    .foregroundColor(currentTokens.fgSecondary)
            }
            .padding(tokens.padding)
            .background(
                RoundedRectangle(cornerRadius: tokens.radius)
                    .fill(tokens.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius)
                    .strokeBorder(tokens.border, lineWidth: tokens.borderWidth)
            )
            .tokenShadow(tokens.shadow)

            // Label
            Text(".\(preset)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(currentTokens.fgMuted)
        }
        .frame(width: 140)
    }

    // MARK: - Button Preview

    private func buttonPreview(preset: String, tokens: ButtonTokens) -> some View {
        VStack(spacing: Spacing.xs) {
            // Button
            Text("Button")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tokens.primaryFg)
                .padding(.horizontal, tokens.paddingH)
                .frame(height: tokens.heightMd)
                .background(
                    RoundedRectangle(cornerRadius: tokens.primaryRadius)
                        .fill(tokens.primaryBg)
                )

            // Label
            Text(".\(preset)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(currentTokens.fgMuted)
        }
    }

    // MARK: - Table Preview

    private func tablePreview() -> some View {
        let tableTokens = currentTokens.table
        let defaultTokens = TableTokens.default

        return VStack(spacing: 0) {
            // Header
            HStack {
                Text("Row Height")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(currentTokens.fgSecondary)
                Spacer()
                Text("\(Int(tableTokens.rowHeight))px")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(currentTokens.accent)
                Text("(default: \(Int(defaultTokens.rowHeight))px)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(currentTokens.fgMuted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(currentTokens.bgElevated)

            // Sample rows
            ForEach(0..<3, id: \.self) { index in
                HStack {
                    Circle()
                        .fill(index == 1 ? currentTokens.accent : currentTokens.fgMuted)
                        .frame(width: 6, height: 6)

                    Text("Sample row \(index + 1)")
                        .font(.system(size: 11))
                        .foregroundColor(currentTokens.fgPrimary)

                    Spacer()

                    Text("value")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(currentTokens.fgSecondary)
                }
                .padding(.horizontal, Spacing.sm)
                .frame(height: tableTokens.rowHeight)
                .background(
                    index == 1 ? tableTokens.rowHover : Color.clear
                )
            }

            Divider()
                .background(tableTokens.divider)
        }
        .background(currentTokens.bgSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(currentTokens.borderDefault, lineWidth: 1)
        )
    }

    // MARK: - Token Values Section

    private var tokenValuesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Colors
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("COLORS")

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.sm) {
                    colorSwatch("bgCanvas", currentTokens.bgCanvas, default: defaultTokens.bgCanvas)
                    colorSwatch("bgSurface", currentTokens.bgSurface, default: defaultTokens.bgSurface)
                    colorSwatch("bgElevated", currentTokens.bgElevated, default: defaultTokens.bgElevated)
                    colorSwatch("fgPrimary", currentTokens.fgPrimary, default: defaultTokens.fgPrimary)
                    colorSwatch("fgSecondary", currentTokens.fgSecondary, default: defaultTokens.fgSecondary)
                    colorSwatch("accent", currentTokens.accent, default: defaultTokens.accent)
                }
            }

            // Spacing, Radius, Component Tokens
            HStack(alignment: .top, spacing: Spacing.xl) {
                // Spacing
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    sectionHeader("SPACING (8pt grid)")

                    VStack(alignment: .leading, spacing: 4) {
                        spacingRow("xs", SpacingPrimitive.x1)
                        spacingRow("sm", SpacingPrimitive.x2)
                        spacingRow("md", SpacingPrimitive.x3)
                        spacingRow("lg", SpacingPrimitive.x4)
                        spacingRow("xl", SpacingPrimitive.x6)
                    }
                }

                // Radius
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    sectionHeader("RADIUS")

                    VStack(alignment: .leading, spacing: 4) {
                        radiusRow("button", currentTokens.radiusButton, default: defaultTokens.radiusButton)
                        radiusRow("card", currentTokens.radiusCard, default: defaultTokens.radiusCard)
                        radiusRow("modal", currentTokens.radiusModal, default: defaultTokens.radiusModal)
                    }
                }

                // Component Deltas
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    sectionHeader("COMPONENTS")

                    VStack(alignment: .leading, spacing: 4) {
                        componentDeltaRow("card.radius", Int(currentTokens.card.radius), default: Int(defaultTokens.card.radius))
                        componentDeltaRow("card.padding", Int(currentTokens.card.padding), default: Int(defaultTokens.card.padding))
                        componentDeltaRow("button.radius", Int(currentTokens.button.primaryRadius), default: Int(defaultTokens.button.primaryRadius))
                        componentDeltaRow("table.rowHeight", Int(currentTokens.table.rowHeight), default: Int(defaultTokens.table.rowHeight))
                    }
                }
            }

            // Animation comparison
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("ANIMATION STYLE")

                HStack(spacing: Spacing.lg) {
                    animationCompare("Linear", isSnappy: true, isActive: selectedTheme == .linear)
                    animationCompare("Warm", isSnappy: false, isActive: selectedTheme == .warm)
                    animationCompare("Default", isSnappy: false, isActive: selectedTheme == .midnight)
                }
            }
        }
    }

    private func animationCompare(_ name: String, isSnappy: Bool, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? currentTokens.accent : currentTokens.fgMuted)

            Text(isSnappy ? "Snappy" : "Smooth")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(currentTokens.fgSecondary)

            if isActive {
                Circle()
                    .fill(currentTokens.accent)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? currentTokens.accent.opacity(0.1) : Color.clear)
        )
    }

    // MARK: - Helpers

    private var currentTokens: any SemanticTokens {
        selectedTheme.tokens
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(currentTokens.fgMuted)
            .tracking(1)
    }

    private func colorSwatch(_ name: String, _ color: Color, default defaultColor: Color) -> some View {
        let isDifferent = !colorsEqual(color, defaultColor)

        return HStack(spacing: Spacing.xs) {
            ZStack {
                // Show default color behind if different
                if showDeltas && isDifferent {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(defaultColor)
                        .frame(width: 24, height: 24)
                        .offset(x: -4, y: 4)
                        .opacity(0.5)
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isDifferent && showDeltas ? Color.green : currentTokens.borderDefault, lineWidth: isDifferent && showDeltas ? 2 : 1)
                    )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isDifferent && showDeltas ? Color.green : currentTokens.fgSecondary)

                if showDeltas && isDifferent {
                    Text("changed")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(Color.green.opacity(0.8))
                }
            }
        }
        .frame(width: 100, alignment: .leading)
    }

    /// Simple color comparison (not perfect but good enough for debug)
    private func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        // Compare by resolving to NSColor components
        let nsA = NSColor(a)
        let nsB = NSColor(b)
        guard let rgbA = nsA.usingColorSpace(.deviceRGB),
              let rgbB = nsB.usingColorSpace(.deviceRGB) else {
            return false
        }
        let tolerance: CGFloat = 0.01
        return abs(rgbA.redComponent - rgbB.redComponent) < tolerance &&
               abs(rgbA.greenComponent - rgbB.greenComponent) < tolerance &&
               abs(rgbA.blueComponent - rgbB.blueComponent) < tolerance
    }

    private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(currentTokens.fgSecondary)
                .frame(width: 24, alignment: .leading)

            Rectangle()
                .fill(currentTokens.accent.opacity(0.5))
                .frame(width: value, height: 12)

            Text("\(Int(value))pt")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(currentTokens.fgMuted)
        }
    }

    private func radiusRow(_ name: String, _ value: CGFloat, default defaultValue: CGFloat) -> some View {
        let isDifferent = abs(value - defaultValue) > 0.5

        return HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isDifferent && showDeltas ? Color.green : currentTokens.fgSecondary)
                .frame(width: 40, alignment: .leading)

            ZStack {
                // Show default radius behind if different
                if showDeltas && isDifferent {
                    RoundedRectangle(cornerRadius: defaultValue)
                        .stroke(currentTokens.fgMuted.opacity(0.3), lineWidth: 1)
                        .frame(width: 32, height: 20)
                }

                RoundedRectangle(cornerRadius: value)
                    .fill(currentTokens.accent.opacity(isDifferent && showDeltas ? 0.5 : 0.3))
                    .frame(width: 32, height: 20)
            }

            if showDeltas && isDifferent {
                HStack(spacing: 2) {
                    Text("\(Int(defaultValue))")
                        .strikethrough()
                        .foregroundColor(currentTokens.fgMuted)
                    Text("→")
                        .foregroundColor(Color.green)
                    Text("\(Int(value))")
                        .foregroundColor(Color.green)
                }
                .font(.system(size: 9, design: .monospaced))
            } else {
                Text("\(Int(value))pt")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(currentTokens.fgMuted)
            }
        }
    }

    private func componentDeltaRow(_ name: String, _ value: Int, default defaultValue: Int) -> some View {
        let isDifferent = value != defaultValue
        let delta = value - defaultValue

        return HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(isDifferent && showDeltas ? Color.green : currentTokens.fgSecondary)
                .frame(width: 90, alignment: .leading)

            if showDeltas && isDifferent {
                HStack(spacing: 2) {
                    Text("\(defaultValue)")
                        .strikethrough()
                        .foregroundColor(currentTokens.fgMuted)
                    Text("→")
                        .foregroundColor(Color.green)
                    Text("\(value)")
                        .foregroundColor(Color.green)

                    Text("(\(delta > 0 ? "+" : "")\(delta))")
                        .foregroundColor(delta < 0 ? Color.orange : Color.green)
                }
                .font(.system(size: 9, design: .monospaced))
            } else {
                Text("\(value)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(currentTokens.fgMuted)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isDifferent && showDeltas ? Color.green.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Theme Options

enum ThemeOption: String, CaseIterable {
    case midnight
    case linear
    case warm
    case terminal
    case minimal
    case classic

    var name: String {
        rawValue.capitalized
    }

    var tokens: any SemanticTokens {
        switch self {
        case .midnight: return MidnightTokens()
        case .linear: return LinearTokens()
        case .warm: return WarmTokens()
        case .terminal: return TerminalTokens()
        case .minimal: return MinimalTokens()
        case .classic: return ClassicTokens()
        }
    }
}

// MARK: - Debug Button for Design Overlay

struct TokenShowcaseButton: View {
    @State private var showShowcase = false

    var body: some View {
        Button(action: { showShowcase = true }) {
            HStack(spacing: 6) {
                Image(systemName: "swatchpalette")
                    .font(.system(size: 11))
                Text("Token Showcase")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.cyan.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showShowcase) {
            TokenShowcaseView()
        }
    }
}

// MARK: - Preview

#Preview("Token Showcase") {
    TokenShowcaseView()
}

#endif
