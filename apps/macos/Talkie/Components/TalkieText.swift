//
//  TalkieText.swift
//  Talkie
//
//  Unified text component with named styles and debug-mode live tuning.
//

import SwiftUI
import TalkieKit

// MARK: - Text Style

/// Named text styles — the single source of truth for all semantic typography.
/// Each case defines its own font parameters directly. No registry, no indirection.
enum TalkieTextStyle: String, CaseIterable, Identifiable {
    case pageTitle        // "Home", "Library", "Compose", etc.
    case sectionHeader    // Section labels within a page
    case settingsTitle    // Settings page titles (distinct from brand wordmark)
    case body
    case bodySmall
    case caption
    case label
    case labelSmall

    var id: String { rawValue }

    /// Default font parameters for this style.
    var params: TalkieTextParams {
        switch self {
        case .pageTitle:
            TalkieTextParams(size: 18, weight: .light, tracking: 0.3, lineHeight: 20, smallCaps: true)
        case .sectionHeader:
            TalkieTextParams(size: 13, weight: .semibold, tracking: 0.5, smallCaps: true)
        case .settingsTitle:
            TalkieTextParams(size: 18, weight: .light, tracking: 0.3, lineHeight: 20)
        case .body:
            TalkieTextParams(size: 14, weight: .regular)
        case .bodySmall:
            TalkieTextParams(size: 12, weight: .regular)
        case .caption:
            TalkieTextParams(size: 11, weight: .regular)
        case .label:
            TalkieTextParams(size: 13, weight: .medium)
        case .labelSmall:
            TalkieTextParams(size: 11, weight: .medium)
        }
    }

    var displayName: String {
        switch self {
        case .pageTitle:      "Page Title"
        case .sectionHeader:  "Section Header"
        case .settingsTitle:  "Settings Title"
        case .body:           "Body"
        case .bodySmall:      "Body Small"
        case .caption:        "Caption"
        case .label:          "Label"
        case .labelSmall:     "Label Small"
        }
    }
}

// MARK: - Style Parameters

/// All the font parameters needed to render a text style.
struct TalkieTextParams {
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design = .default
    var tracking: CGFloat = 0
    var lineHeight: CGFloat? = nil
    var smallCaps: Bool = false
    var monospaced: Bool = false
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    var font: Font {
        var f = Font.system(size: size, weight: weight, design: design)
        if smallCaps { f = f.smallCaps() }
        if monospaced { f = f.monospacedDigit() }
        return f
    }
}

// MARK: - TalkieText View

/// Unified text component. Use instead of raw `Text` for anything
/// that should participate in the shared typography system.
///
///   TalkieText("Library", style: .pageTitle)
///   TalkieText("TRANSCRIPT", style: .sectionHeader)
///
struct TalkieText: View {
    let content: String
    let style: TalkieTextStyle
    var color: Color?

    init(_ content: String, style: TalkieTextStyle, color: Color? = nil) {
        self.content = content
        self.style = style
        self.color = color
    }

    var body: some View {
        #if DEBUG
        let p = TalkieTextInspector.shared.overrides[style] ?? style.params
        #else
        let p = style.params
        #endif

        Text(content)
            .font(p.font)
            .tracking(p.tracking)
            .foregroundColor(color ?? Theme.current.foreground)
            .modifier(LineHeightModifier(height: p.lineHeight))
            .offset(x: p.offsetX, y: p.offsetY)
        #if DEBUG
            .overlay(inspectorOverlay(p))
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func inspectorOverlay(_ params: TalkieTextParams) -> some View {
        if TalkieTextInspector.shared.isActive {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    TalkieTextInspector.shared.inspect(style: style, params: params)
                }
                .overlay(alignment: .topTrailing) {
                    if TalkieTextInspector.shared.selectedStyle == style {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -3)
                    }
                }
        }
    }
    #endif
}

/// Applies a fixed frame height if lineHeight is specified.
private struct LineHeightModifier: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height, alignment: .center)
        } else {
            content
        }
    }
}

// MARK: - Debug Inspector

#if DEBUG
/// Singleton that tracks which TalkieText is being inspected and any live overrides.
/// Activated via design mode — tap any TalkieText to inspect it.
@Observable
final class TalkieTextInspector {
    static let shared = TalkieTextInspector()

    /// When true, all TalkieText instances become tappable for inspection
    var isActive = false

    /// Currently selected style (tapped by user)
    var selectedStyle: TalkieTextStyle?

    /// Live param overrides — only populated when the user tunes values in the panel
    var overrides: [TalkieTextStyle: TalkieTextParams] = [:]

    /// The params being edited (original or overridden)
    var editingParams: TalkieTextParams?

    private init() {}

    func inspect(style: TalkieTextStyle, params: TalkieTextParams) {
        selectedStyle = style
        editingParams = overrides[style] ?? params
    }

    func applyEdit(for style: TalkieTextStyle, params: TalkieTextParams) {
        overrides[style] = params
        editingParams = params
    }

    func resetStyle(_ style: TalkieTextStyle) {
        overrides.removeValue(forKey: style)
        editingParams = style.params
    }

    func resetAll() {
        overrides.removeAll()
        if let s = selectedStyle {
            editingParams = s.params
        }
    }
}

/// Inline panel that appears when a TalkieText is selected in inspect mode.
/// Shows the current style name, its params, and lets you tweak them live.
struct TalkieTextInspectorPanel: View {
    @Bindable var inspector = TalkieTextInspector.shared

    private let weights: [(String, Font.Weight)] = [
        ("UltraLight", .ultraLight), ("Thin", .thin), ("Light", .light),
        ("Regular", .regular), ("Medium", .medium), ("Semibold", .semibold),
        ("Bold", .bold), ("Heavy", .heavy),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header — matches other Design Tools sections
            HStack {
                Image(systemName: "textformat.size")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(inspector.isActive ? .cyan : .white.opacity(0.5))

                Text("Text Styles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Button(action: { inspector.isActive.toggle() }) {
                    Text(inspector.isActive ? "ON" : "OFF")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(inspector.isActive ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(inspector.isActive ? Color.cyan : Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            if inspector.isActive {
                if let style = inspector.selectedStyle, let _ = inspector.editingParams {
                    // Selected style info
                    HStack(spacing: 4) {
                        Text(style.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                        Text(".\(style.rawValue)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        if inspector.overrides[style] != nil {
                            Button("Reset") { inspector.resetStyle(style) }
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                                .buttonStyle(.plain)
                        }
                    }

                    // Live preview
                    TalkieTextInspectorPreview(style: style)
                        .padding(4)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(4)

                    // Controls
                    let binding = Binding(
                        get: { inspector.editingParams ?? style.params },
                        set: { inspector.applyEdit(for: style, params: $0) }
                    )

                    VStack(spacing: 4) {
                        paramRow("Size") {
                            Slider(value: binding.size, in: 8...32, step: 1)
                            Text("\(Int(binding.wrappedValue.size))pt")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 30, alignment: .trailing)
                        }
                        paramRow("Weight") {
                            Picker("", selection: binding.weight) {
                                ForEach(Array(weights.enumerated()), id: \.offset) { _, w in
                                    Text(w.0).tag(w.1)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        paramRow("Track") {
                            Slider(value: binding.tracking, in: -2...4, step: 0.1)
                            Text(String(format: "%.1f", binding.wrappedValue.tracking))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 30, alignment: .trailing)
                        }
                        paramRow("Offset X") {
                            Slider(value: binding.offsetX, in: -12...12, step: 0.5)
                            Text(String(format: "%.1f", binding.wrappedValue.offsetX))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 30, alignment: .trailing)
                        }
                        paramRow("Offset Y") {
                            Slider(value: binding.offsetY, in: -12...12, step: 0.5)
                            Text(String(format: "%.1f", binding.wrappedValue.offsetY))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 30, alignment: .trailing)
                        }
                        HStack(spacing: 12) {
                            Toggle("Small Caps", isOn: binding.smallCaps)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            Toggle("Mono", isOn: binding.monospaced)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    Text("Tap any TalkieText to inspect it")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }

                if !inspector.overrides.isEmpty {
                    HStack {
                        Text("\(inspector.overrides.count) overrides")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        Button("Reset All") { inspector.resetAll() }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paramRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 40, alignment: .leading)
            content()
        }
    }
}

/// Preview text that uses the override if available, without the inspector overlay
/// (avoids recursive tap handling).
private struct TalkieTextInspectorPreview: View {
    let style: TalkieTextStyle

    var body: some View {
        let p = TalkieTextInspector.shared.overrides[style] ?? style.params
        Text("The quick brown fox")
            .font(p.font)
            .tracking(p.tracking)
            .foregroundColor(Theme.current.foreground)
    }
}
#endif
