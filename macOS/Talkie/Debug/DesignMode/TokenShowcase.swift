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

// MARK: - Token Value (for displaying all tokens)

/// Represents a single token value with optional diff info
struct TokenValue: Identifiable {
    let id = UUID()
    let path: String
    let category: String
    let value: String
    let preview: AnyView?
    let baselineValue: String?  // nil if same as current
    let baselinePreview: AnyView?

    var isDifferent: Bool { baselineValue != nil }
}

/// Introspects all token values from a SemanticTokens instance
struct TokenIntrospector {
    let values: [TokenValue]
    let diffCount: Int

    init(tokens: any SemanticTokens, baseline: any SemanticTokens) {
        var allValues: [TokenValue] = []

        let tokenMirror = Mirror(reflecting: tokens)
        let baselineMirror = Mirror(reflecting: baseline)

        // Build baseline lookup
        var baselineMap: [String: Any] = [:]
        for child in baselineMirror.children {
            if let label = child.label {
                baselineMap[label] = child.value
            }
        }

        // Introspect all properties
        for child in tokenMirror.children {
            guard let label = child.label else { continue }
            let baseVal = baselineMap[label]

            let extracted = Self.extractValues(
                path: label,
                value: child.value,
                baseline: baseVal
            )
            allValues.append(contentsOf: extracted)
        }

        self.values = allValues.sorted {
            $0.category < $1.category || ($0.category == $1.category && $0.path < $1.path)
        }
        self.diffCount = allValues.filter { $0.isDifferent }.count
    }

    private static func extractValues(path: String, value: Any, baseline: Any?) -> [TokenValue] {
        // Handle Color
        if let color = value as? Color {
            let baseColor = baseline as? Color
            let isDiff = baseColor != nil && !colorsEqual(color, baseColor!)
            return [TokenValue(
                path: path,
                category: categoryFor(path),
                value: colorDescription(color),
                preview: AnyView(colorPreview(color)),
                baselineValue: isDiff ? colorDescription(baseColor!) : nil,
                baselinePreview: isDiff ? AnyView(colorPreview(baseColor!)) : nil
            )]
        }

        // Handle CGFloat
        if let num = value as? CGFloat {
            let baseNum = baseline as? CGFloat
            let isDiff = baseNum != nil && abs(num - baseNum!) > 0.01
            return [TokenValue(
                path: path,
                category: categoryFor(path),
                value: formatNumber(num),
                preview: nil,
                baselineValue: isDiff ? formatNumber(baseNum!) : nil,
                baselinePreview: nil
            )]
        }

        // Handle Animation
        if value is Animation {
            let currDesc = String(describing: value)
            let baseDesc = baseline.map { String(describing: $0) }
            let isDiff = baseDesc != nil && currDesc != baseDesc!
            return [TokenValue(
                path: path,
                category: "Animation",
                value: animationName(currDesc),
                preview: nil,
                baselineValue: isDiff ? animationName(baseDesc!) : nil,
                baselinePreview: nil
            )]
        }

        // Handle ShadowPrimitive
        if let shadow = value as? ShadowPrimitive {
            let baseShadow = baseline as? ShadowPrimitive
            let isDiff = baseShadow != nil && !shadowsEqual(shadow, baseShadow!)
            return [TokenValue(
                path: path,
                category: "Shadows",
                value: shadowDescription(shadow),
                preview: nil,
                baselineValue: isDiff ? shadowDescription(baseShadow!) : nil,
                baselinePreview: nil
            )]
        }

        // Handle nested structs (TableTokens, CardTokens, ButtonTokens, etc.)
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .struct && !mirror.children.isEmpty {
            var nestedValues: [TokenValue] = []

            // Build baseline lookup for nested struct
            var nestedBaselineMap: [String: Any] = [:]
            if let baselineVal = baseline {
                let baseMirror = Mirror(reflecting: baselineVal)
                for child in baseMirror.children {
                    if let label = child.label {
                        nestedBaselineMap[label] = child.value
                    }
                }
            }

            for child in mirror.children {
                guard let label = child.label else { continue }
                let nestedPath = "\(path).\(label)"
                let nestedBaseline = nestedBaselineMap[label]
                nestedValues.append(contentsOf: extractValues(
                    path: nestedPath,
                    value: child.value,
                    baseline: nestedBaseline
                ))
            }
            return nestedValues
        }

        return []
    }

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
        if path.contains(".") { return "Components" }
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

    private static func formatNumber(_ value: CGFloat) -> String {
        if value == floor(value) {
            return "\(Int(value))"
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Token Showcase View

struct TokenShowcaseView: View {
    @State private var selectedTheme: ThemeOption = .midnight
    @State private var showOnlyDiffs: Bool = false
    @Environment(\.dismiss) private var dismiss

    // Reference tokens for comparison
    private var baselineTokens: any SemanticTokens { MidnightTokens() }

    private var introspector: TokenIntrospector {
        TokenIntrospector(tokens: selectedTheme.tokens, baseline: baselineTokens)
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

                    // Filter toggle + summary
                    filterBar

                    // All tokens list
                    tokensList
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 600, height: 650)
        .background(currentTokens.bgCanvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Showcase")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(currentTokens.fgPrimary)

                Text("All design tokens for \(selectedTheme.name)")
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
            Text("SELECT THEME")
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            // Token count
            Text("\(introspector.values.count) tokens")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(currentTokens.fgPrimary)

            if introspector.diffCount > 0 {
                Text("•")
                    .foregroundColor(currentTokens.fgMuted)

                Text("\(introspector.diffCount) differ from Midnight")
                    .font(.system(size: 11))
                    .foregroundColor(Color.orange)
            }

            Spacer()

            // Filter toggle
            if introspector.diffCount > 0 {
                Button(action: { showOnlyDiffs.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showOnlyDiffs ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11))
                        Text(showOnlyDiffs ? "Showing diffs only" : "Show all")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(showOnlyDiffs ? Color.orange : currentTokens.fgSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(showOnlyDiffs ? Color.orange.opacity(0.15) : currentTokens.bgElevated)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(currentTokens.bgSurface)
        )
    }

    // MARK: - Tokens List

    private var tokensList: some View {
        let values = showOnlyDiffs
            ? introspector.values.filter { $0.isDifferent }
            : introspector.values
        let grouped = Dictionary(grouping: values) { $0.category }

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Category header
                    HStack {
                        Text(category.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(currentTokens.fgMuted)
                            .tracking(1)

                        let diffCount = (grouped[category] ?? []).filter { $0.isDifferent }.count
                        if diffCount > 0 && !showOnlyDiffs {
                            Text("(\(diffCount) diff)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color.orange)
                        }

                        Spacer()
                    }

                    // Token rows
                    VStack(spacing: 1) {
                        ForEach(grouped[category] ?? []) { token in
                            tokenRow(token)
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

    private func tokenRow(_ token: TokenValue) -> some View {
        HStack(spacing: Spacing.sm) {
            // Property name
            Text(token.path)
                .font(.system(size: 10, weight: token.isDifferent ? .semibold : .regular, design: .monospaced))
                .foregroundColor(token.isDifferent ? Color.orange : currentTokens.fgPrimary)
                .frame(width: 150, alignment: .leading)

            // Preview + Value
            HStack(spacing: 4) {
                if let preview = token.preview {
                    preview
                }
                Text(token.value)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(token.isDifferent ? currentTokens.fgPrimary : currentTokens.fgSecondary)
            }
            .frame(width: 140, alignment: .leading)

            // Diff indicator (if different)
            if token.isDifferent, let baseValue = token.baselineValue {
                HStack(spacing: 4) {
                    Text("was")
                        .font(.system(size: 8))
                        .foregroundColor(currentTokens.fgMuted)

                    if let basePreview = token.baselinePreview {
                        basePreview
                    }
                    Text(baseValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(currentTokens.fgMuted)
                        .strikethrough()
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            token.isDifferent
                ? Color.orange.opacity(0.08)
                : Color.clear
        )
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
