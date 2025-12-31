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

// MARK: - Token Diff (Introspection-based)

/// A single difference between two token values
struct TokenDelta: Identifiable {
    let id = UUID()
    let path: String           // e.g. "bgCanvas", "card.radius", "table.rowHeight"
    let category: String       // e.g. "Colors", "Components", "Animation"
    let defaultValue: String   // String representation of default
    let currentValue: String   // String representation of current
    let defaultPreview: AnyView?  // Optional visual preview
    let currentPreview: AnyView?  // Optional visual preview
}

/// Compares two SemanticTokens using Mirror introspection
struct TokenDiff {
    let deltas: [TokenDelta]

    init(current: any SemanticTokens, baseline: any SemanticTokens) {
        var diffs: [TokenDelta] = []

        let currentMirror = Mirror(reflecting: current)
        let baselineMirror = Mirror(reflecting: baseline)

        // Build baseline lookup
        var baselineValues: [String: Any] = [:]
        for child in baselineMirror.children {
            if let label = child.label {
                baselineValues[label] = child.value
            }
        }

        // Compare each property
        for child in currentMirror.children {
            guard let label = child.label else { continue }
            let currentVal = child.value
            let baselineVal = baselineValues[label]

            // Compare and add delta if different
            if let delta = Self.compareValues(
                path: label,
                current: currentVal,
                baseline: baselineVal
            ) {
                diffs.append(contentsOf: delta)
            }
        }

        self.deltas = diffs.sorted { $0.category < $1.category || ($0.category == $1.category && $0.path < $1.path) }
    }

    private static func compareValues(path: String, current: Any, baseline: Any?) -> [TokenDelta]? {
        guard let baseline = baseline else { return nil }

        // Handle Color
        if let currColor = current as? Color, let baseColor = baseline as? Color {
            if !colorsEqual(currColor, baseColor) {
                return [TokenDelta(
                    path: path,
                    category: categoryFor(path),
                    defaultValue: colorDescription(baseColor),
                    currentValue: colorDescription(currColor),
                    defaultPreview: AnyView(colorPreview(baseColor)),
                    currentPreview: AnyView(colorPreview(currColor))
                )]
            }
        }

        // Handle CGFloat
        if let currFloat = current as? CGFloat, let baseFloat = baseline as? CGFloat {
            if abs(currFloat - baseFloat) > 0.5 {
                return [TokenDelta(
                    path: path,
                    category: categoryFor(path),
                    defaultValue: "\(Int(baseFloat))",
                    currentValue: "\(Int(currFloat))",
                    defaultPreview: nil,
                    currentPreview: nil
                )]
            }
        }

        // Handle Animation (compare by description since Animation isn't Equatable)
        if current is Animation && baseline is Animation {
            let currDesc = String(describing: current)
            let baseDesc = String(describing: baseline)
            if currDesc != baseDesc {
                return [TokenDelta(
                    path: path,
                    category: "Animation",
                    defaultValue: animationName(baseDesc),
                    currentValue: animationName(currDesc),
                    defaultPreview: nil,
                    currentPreview: nil
                )]
            }
        }

        // Handle ShadowPrimitive
        if let currShadow = current as? ShadowPrimitive, let baseShadow = baseline as? ShadowPrimitive {
            if !shadowsEqual(currShadow, baseShadow) {
                return [TokenDelta(
                    path: path,
                    category: "Shadows",
                    defaultValue: shadowDescription(baseShadow),
                    currentValue: shadowDescription(currShadow),
                    defaultPreview: nil,
                    currentPreview: nil
                )]
            }
        }

        // Handle TableTokens (recurse into nested struct)
        if let currTable = current as? TableTokens, let baseTable = baseline as? TableTokens {
            return compareTableTokens(currTable, baseTable)
        }

        // Handle CardTokens
        if let currCard = current as? CardTokens, let baseCard = baseline as? CardTokens {
            return compareCardTokens(currCard, baseCard)
        }

        // Handle ButtonTokens
        if let currBtn = current as? ButtonTokens, let baseBtn = baseline as? ButtonTokens {
            return compareButtonTokens(currBtn, baseBtn)
        }

        return nil
    }

    private static func compareTableTokens(_ curr: TableTokens, _ base: TableTokens) -> [TokenDelta]? {
        var deltas: [TokenDelta] = []

        if abs(curr.rowHeight - base.rowHeight) > 0.5 {
            deltas.append(TokenDelta(path: "table.rowHeight", category: "Components", defaultValue: "\(Int(base.rowHeight))", currentValue: "\(Int(curr.rowHeight))", defaultPreview: nil, currentPreview: nil))
        }
        if abs(curr.rowPadding - base.rowPadding) > 0.5 {
            deltas.append(TokenDelta(path: "table.rowPadding", category: "Components", defaultValue: "\(Int(base.rowPadding))", currentValue: "\(Int(curr.rowPadding))", defaultPreview: nil, currentPreview: nil))
        }
        if !colorsEqual(curr.rowHover, base.rowHover) {
            deltas.append(TokenDelta(path: "table.rowHover", category: "Components", defaultValue: "color", currentValue: "color", defaultPreview: AnyView(colorPreview(base.rowHover)), currentPreview: AnyView(colorPreview(curr.rowHover))))
        }
        if !colorsEqual(curr.divider, base.divider) {
            deltas.append(TokenDelta(path: "table.divider", category: "Components", defaultValue: "color", currentValue: "color", defaultPreview: AnyView(colorPreview(base.divider)), currentPreview: AnyView(colorPreview(curr.divider))))
        }

        return deltas.isEmpty ? nil : deltas
    }

    private static func compareCardTokens(_ curr: CardTokens, _ base: CardTokens) -> [TokenDelta]? {
        var deltas: [TokenDelta] = []

        if abs(curr.radius - base.radius) > 0.5 {
            deltas.append(TokenDelta(path: "card.radius", category: "Components", defaultValue: "\(Int(base.radius))", currentValue: "\(Int(curr.radius))", defaultPreview: nil, currentPreview: nil))
        }
        if abs(curr.padding - base.padding) > 0.5 {
            deltas.append(TokenDelta(path: "card.padding", category: "Components", defaultValue: "\(Int(base.padding))", currentValue: "\(Int(curr.padding))", defaultPreview: nil, currentPreview: nil))
        }
        if abs(curr.borderWidth - base.borderWidth) > 0.1 {
            deltas.append(TokenDelta(path: "card.borderWidth", category: "Components", defaultValue: "\(base.borderWidth)", currentValue: "\(curr.borderWidth)", defaultPreview: nil, currentPreview: nil))
        }
        if !shadowsEqual(curr.shadow, base.shadow) {
            deltas.append(TokenDelta(path: "card.shadow", category: "Components", defaultValue: shadowDescription(base.shadow), currentValue: shadowDescription(curr.shadow), defaultPreview: nil, currentPreview: nil))
        }

        return deltas.isEmpty ? nil : deltas
    }

    private static func compareButtonTokens(_ curr: ButtonTokens, _ base: ButtonTokens) -> [TokenDelta]? {
        var deltas: [TokenDelta] = []

        if abs(curr.primaryRadius - base.primaryRadius) > 0.5 {
            deltas.append(TokenDelta(path: "button.primaryRadius", category: "Components", defaultValue: "\(Int(base.primaryRadius))", currentValue: "\(Int(curr.primaryRadius))", defaultPreview: nil, currentPreview: nil))
        }
        if abs(curr.heightMd - base.heightMd) > 0.5 {
            deltas.append(TokenDelta(path: "button.heightMd", category: "Components", defaultValue: "\(Int(base.heightMd))", currentValue: "\(Int(curr.heightMd))", defaultPreview: nil, currentPreview: nil))
        }
        if abs(curr.pressScale - base.pressScale) > 0.01 {
            deltas.append(TokenDelta(path: "button.pressScale", category: "Components", defaultValue: String(format: "%.2f", base.pressScale), currentValue: String(format: "%.2f", curr.pressScale), defaultPreview: nil, currentPreview: nil))
        }

        return deltas.isEmpty ? nil : deltas
    }

    // MARK: - Helpers

    private static func categoryFor(_ path: String) -> String {
        if path.hasPrefix("bg") { return "Backgrounds" }
        if path.hasPrefix("fg") { return "Foregrounds" }
        if path.hasPrefix("border") { return "Borders" }
        if path.hasPrefix("accent") { return "Accent" }
        if path.hasPrefix("shadow") { return "Shadows" }
        if path.hasPrefix("radius") { return "Radius" }
        if path.hasPrefix("animation") { return "Animation" }
        if path.hasPrefix("highlight") { return "Highlights" }
        if path.hasPrefix("success") || path.hasPrefix("warning") || path.hasPrefix("error") { return "Semantic" }
        return "Other"
    }

    private static func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        let nsA = NSColor(a)
        let nsB = NSColor(b)
        guard let rgbA = nsA.usingColorSpace(.deviceRGB),
              let rgbB = nsB.usingColorSpace(.deviceRGB) else { return false }
        let tolerance: CGFloat = 0.02
        return abs(rgbA.redComponent - rgbB.redComponent) < tolerance &&
               abs(rgbA.greenComponent - rgbB.greenComponent) < tolerance &&
               abs(rgbA.blueComponent - rgbB.blueComponent) < tolerance &&
               abs(rgbA.alphaComponent - rgbB.alphaComponent) < tolerance
    }

    private static func shadowsEqual(_ a: ShadowPrimitive, _ b: ShadowPrimitive) -> Bool {
        return a.radius == b.radius && a.x == b.x && a.y == b.y && colorsEqual(a.color, b.color)
    }

    private static func colorDescription(_ color: Color) -> String {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return "?" }
        if rgb.alphaComponent < 1.0 {
            return String(format: "rgba(%.0f,%.0f,%.0f,%.1f)", rgb.redComponent*255, rgb.greenComponent*255, rgb.blueComponent*255, rgb.alphaComponent)
        }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent*255), Int(rgb.greenComponent*255), Int(rgb.blueComponent*255))
    }

    private static func colorPreview(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
    }

    private static func shadowDescription(_ shadow: ShadowPrimitive) -> String {
        if shadow.radius == 0 { return "none" }
        if shadow.y == 0 && shadow.x == 0 {
            return "glow r:\(Int(shadow.radius))"
        }
        return "drop r:\(Int(shadow.radius)) y:\(Int(shadow.y))"
    }

    private static func animationName(_ desc: String) -> String {
        if desc.contains("0.15") || desc.contains("snappy") { return "snappy" }
        if desc.contains("spring") { return "spring" }
        return "smooth"
    }
}

// MARK: - Token Showcase View

struct TokenShowcaseView: View {
    @State private var selectedTheme: ThemeOption = .linear
    @State private var showOnlyDeltas: Bool = true
    @Environment(\.dismiss) private var dismiss

    // Reference tokens for comparison
    private var defaultTokens: any SemanticTokens { MidnightTokens() }

    private var tokenDiff: TokenDiff {
        TokenDiff(current: selectedTheme.tokens, baseline: defaultTokens)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Theme Picker
                    themePicker

                    // Delta summary
                    if selectedTheme != .midnight {
                        deltaSummary
                    } else {
                        Text("Midnight is the baseline theme - select another theme to see differences.")
                            .font(.system(size: 11))
                            .foregroundColor(currentTokens.fgMuted)
                            .padding()
                    }

                    // Full diff list
                    if selectedTheme != .midnight {
                        diffList
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 550, height: 600)
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

    // MARK: - Theme Picker

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("COMPARE THEME")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(currentTokens.fgMuted)
                .tracking(1)

            HStack(spacing: Spacing.sm) {
                ForEach(ThemeOption.allCases, id: \.self) { theme in
                    themeButton(theme)
                }
            }
        }
    }

    private var deltaSummary: some View {
        let deltas = tokenDiff.deltas
        let categories = Set(deltas.map { $0.category })

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(deltas.count) differences")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(currentTokens.fgPrimary)

                Text("from Midnight baseline")
                    .font(.system(size: 11))
                    .foregroundColor(currentTokens.fgMuted)

                Spacer()
            }

            // Category chips
            HStack(spacing: Spacing.xs) {
                ForEach(Array(categories).sorted(), id: \.self) { category in
                    let count = deltas.filter { $0.category == category }.count
                    Text("\(category): \(count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(currentTokens.fgSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(currentTokens.bgElevated)
                        )
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(currentTokens.bgSurface)
        )
    }

    private var diffList: some View {
        let deltas = tokenDiff.deltas
        let grouped = Dictionary(grouping: deltas) { $0.category }

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(category.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(currentTokens.fgMuted)
                        .tracking(1)

                    VStack(spacing: 1) {
                        ForEach(grouped[category] ?? []) { delta in
                            deltaRow(delta)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(currentTokens.bgSurface)
                    )
                }
            }
        }
    }

    private func deltaRow(_ delta: TokenDelta) -> some View {
        HStack(spacing: Spacing.sm) {
            // Property name
            Text(delta.path)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(currentTokens.fgPrimary)
                .frame(width: 140, alignment: .leading)

            // Default value
            HStack(spacing: 4) {
                if let preview = delta.defaultPreview {
                    preview
                }
                Text(delta.defaultValue)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(currentTokens.fgMuted)
                    .strikethrough()
            }
            .frame(width: 120, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(Color.green)

            // Current value
            HStack(spacing: 4) {
                if let preview = delta.currentPreview {
                    preview
                }
                Text(delta.currentValue)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.green)
            }
            .frame(width: 120, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(currentTokens.bgSurface)
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

    // MARK: - Helpers

    private var currentTokens: any SemanticTokens {
        selectedTheme.tokens
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
