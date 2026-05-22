//
//  ThemeContrastDebugNext.swift
//  Talkie iOS
//
//  Debug-only theme contrast inspector. Renders the four primary
//  color pairs (background vs textPrimary / textSecondary /
//  textTertiary / accent) for every theme with a computed WCAG
//  contrast ratio. Flags pairs below WCAG AA thresholds:
//    - normal text: 4.5:1
//    - large text:  3.0:1
//
//  Surfaced from SettingsNext.LAB. Not a user-facing screen.
//

import SwiftUI
import UIKit

struct ThemeContrastDebugNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Computed WCAG contrast ratios for every theme. Targets: 4.5:1 for normal body text, 3:1 for large text or icons.")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.top, 16)

                        ForEach(AppTheme.allCases) { themeCase in
                            ThemeContrastCard(theme: themeCase)
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 96)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · CONTRAST")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))
            Spacer()
            Button(action: { AppShellRouter.shared.openSettings() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close contrast inspector")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

private struct ThemeContrastCard: View {
    let theme: AppTheme

    @ObservedObject private var manager = ThemeManager.shared

    private var colors: ThemeColors { theme.colors }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.chrome.accent)
                    .frame(width: 16, height: 16)
                Text(theme.displayName.uppercased())
                    .talkieType(.channelLabel)
                    .foregroundStyle(manager.colors.textPrimary)
                Spacer()
                Text(theme.description)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(manager.colors.textTertiary)
            }

            // Render a small preview block inside the actual theme's
            // background + foreground so the eye can confirm what the
            // numbers say. Uses the theme's own colors, not the active
            // theme's, so each card is a self-contained sample.
            ZStack {
                colors.background
                VStack(alignment: .leading, spacing: 4) {
                    Text("Primary text — the editorial body voice.")
                        .foregroundStyle(colors.textPrimary)
                        .font(.system(size: 13))
                    Text("Secondary text — labels, subtitles, hints.")
                        .foregroundStyle(colors.textSecondary)
                        .font(.system(size: 12))
                    Text("Tertiary text — meta, eyebrows, faint.")
                        .foregroundStyle(colors.textTertiary)
                        .font(.system(size: 11))
                    Text("Accent — chips, links, action chrome.")
                        .foregroundStyle(theme.chrome.accent)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(manager.currentTheme.chrome.edgeFaint,
                                  lineWidth: manager.currentTheme.chrome.hairlineWidth)
            )

            // Contrast metrics
            VStack(spacing: 0) {
                contrastRow(label: "Primary",   fg: colors.textPrimary,   bg: colors.background)
                contrastRow(label: "Secondary", fg: colors.textSecondary, bg: colors.background)
                contrastRow(label: "Tertiary",  fg: colors.textTertiary,  bg: colors.background)
                contrastRow(label: "Accent",    fg: theme.chrome.accent,  bg: colors.background, large: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(manager.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(manager.currentTheme.chrome.edgeFaint,
                                      lineWidth: manager.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private func contrastRow(label: String, fg: Color, bg: Color, large: Bool = false) -> some View {
        let ratio = WCAG.contrastRatio(foreground: fg, background: bg)
        let threshold: Double = large ? 3.0 : 4.5
        let passes = ratio >= threshold
        let pillColor: Color = passes
            ? Color(red: 0.36, green: 0.74, blue: 0.50)
            : Color(red: 0.85, green: 0.46, blue: 0.34)

        return HStack {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(manager.colors.textPrimary)
            if large {
                Text("· LARGE")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(manager.colors.textTertiary)
            }
            Spacer()
            Text(String(format: "%.2f:1", ratio))
                .talkieType(.instrumentReadoutSmall)
                .foregroundStyle(manager.colors.textPrimary)
                .monospacedDigit()
            Text(passes ? "PASS" : "FAIL")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(pillColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(
                    Capsule()
                        .strokeBorder(pillColor.opacity(0.55),
                                      lineWidth: manager.currentTheme.chrome.hairlineWidth)
                )
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(manager.currentTheme.chrome.edgeFaint)
                .frame(height: manager.currentTheme.chrome.hairlineWidth)
        }
    }
}

// MARK: - WCAG contrast math

private enum WCAG {
    /// Compute WCAG 2.x contrast ratio between two SwiftUI colors.
    /// Ratio range: 1 (no contrast) to 21 (black on white).
    static func contrastRatio(foreground: Color, background: Color) -> Double {
        let fgLum = relativeLuminance(of: foreground)
        let bgLum = relativeLuminance(of: background)
        let lighter = max(fgLum, bgLum)
        let darker  = min(fgLum, bgLum)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG relative luminance from sRGB components in [0, 1].
    static func relativeLuminance(of color: Color) -> Double {
        let (r, g, b) = sRGBComponents(of: color)
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private static func channel(_ value: Double) -> Double {
        if value <= 0.03928 { return value / 12.92 }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func sRGBComponents(of color: Color) -> (r: Double, g: Double, b: Double) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
