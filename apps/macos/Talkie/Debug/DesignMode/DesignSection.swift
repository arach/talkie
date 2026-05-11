//
//  DesignSection.swift
//  Talkie macOS
//
//  View modifiers for marking up layout sections and components in Design Mode.
//  When "Borders" is enabled, elements show colored outlines with labels.
//
//  Usage:
//    // For large sections (headers, columns, content areas)
//    localModelsSection
//        .designSection("Local Models", color: .blue)
//
//    // For components (buttons, rows, cards) - more compact
//    TalkieButton("Download")
//        .designBounds("Button")
//
//  IMPORTANT: All implementation is DEBUG-only. In RELEASE builds,
//  these modifiers compile to zero-cost identity functions.
//
//  Future ideas explored:
//  - Color Picker tool: eyedropper to inspect any color on screen
//  - Typography inspector: show font/size/weight on hover
//  - Element Bounds on hover: automatic bounds without manual annotation
//  - Pixel Zoom: 2x/4x magnifier following cursor
//  - Center/Edge guides: crosshairs and margin indicators
//

import SwiftUI

// MARK: - View Extensions (available in all builds)

extension View {
    /// Mark a view as a design section for debugging
    /// When Design Mode "Borders" is enabled, shows colored outline with label
    /// In RELEASE builds: zero-cost no-op (compiles away)
    @ViewBuilder
    func designSection(_ label: String, color: Color = .cyan) -> some View {
        #if DEBUG
        modifier(DesignSectionModifier(label: label, color: color))
        #else
        self
        #endif
    }

    /// Mark a component with design bounds for debugging
    /// More compact than designSection - for buttons, rows, cards, controls
    /// In RELEASE builds: zero-cost no-op (compiles away)
    @ViewBuilder
    func designBounds(_ label: String, color: Color = .cyan, showDimensions: Bool = true) -> some View {
        #if DEBUG
        modifier(DesignBoundsModifier(label: label, color: color, showDimensions: showDimensions))
        #else
        self
        #endif
    }
}

// MARK: - DEBUG-only Implementation

#if DEBUG

// MARK: - Design Section Modifier (for large layout areas)

struct DesignSectionModifier: ViewModifier {
    let label: String
    let color: Color

    @Bindable private var designMode = DesignModeManager.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if designMode.isEnabled && designMode.showBorders {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            // Border outline
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(color, lineWidth: 2)
                                .background(color.opacity(0.05))

                            // Label badge (floats above)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 6, height: 6)

                                Text(label)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)

                                Text("\(Int(geometry.size.width))×\(Int(geometry.size.height))")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.9))
                            .cornerRadius(4)
                            .offset(x: 4, y: -12)
                        }
                    }
                }
            }
    }
}

// MARK: - Design Bounds Modifier (for components)

struct DesignBoundsModifier: ViewModifier {
    let label: String
    let color: Color
    let showDimensions: Bool

    @Bindable private var designMode = DesignModeManager.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if designMode.isEnabled && designMode.showBorders {
                    GeometryReader { geometry in
                        ZStack(alignment: .topTrailing) {
                            // Subtle border outline
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(color.opacity(0.6), lineWidth: 1)

                            // Compact inline label (top-right corner)
                            HStack(spacing: 2) {
                                Text(label)
                                    .font(.system(size: 7, weight: .semibold, design: .monospaced))

                                if showDimensions {
                                    Text("\(Int(geometry.size.width))×\(Int(geometry.size.height))")
                                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                                        .opacity(0.7)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.85))
                            .cornerRadius(2)
                            .offset(x: -2, y: 2)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Predefined Colors

enum DesignSectionColor {
    // Layout sections
    static let primary = Color.cyan
    static let secondary = Color.orange
    static let tertiary = Color.green
    static let accent = Color.purple
    static let warning = Color.yellow

    // Semantic colors for sections
    static let header = Color.blue
    static let content = Color.cyan
    static let sidebar = Color.purple
    static let footer = Color.gray
    static let card = Color.orange
    static let grid = Color.green
}

enum DesignBoundsColor {
    // Component types
    static let button = Color.blue
    static let row = Color.cyan
    static let card = Color.orange
    static let toggle = Color.green
    static let checkbox = Color.mint
    static let dropdown = Color.purple
    static let input = Color.purple
    static let tabSelector = Color.orange
    static let list = Color.green
    static let section = Color.yellow
}

// MARK: - Previews

#Preview("Design Sections") {
    VStack(spacing: 20) {
        Text("Header Area")
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .designSection("Header", color: .blue)

        HStack(spacing: 16) {
            VStack {
                Text("Left Column")
                Text("Content here")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .designSection("Left Column", color: .cyan)

            VStack {
                Text("Right Column")
                Text("More content")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .designSection("Right Column", color: .orange)
        }
        .designSection("Content HStack", color: .purple)
    }
    .padding()
    .frame(width: 600, height: 400)
    .onAppear {
        DesignModeManager.shared.isEnabled = true
        DesignModeManager.shared.showBorders = true
    }
}

#Preview("Design Bounds - Components") {
    VStack(spacing: 16) {
        Button("Primary Action") {}
            .buttonStyle(.borderedProminent)
            .designBounds("Button", color: .blue)

        Toggle("Enable Feature", isOn: .constant(true))
            .designBounds("Toggle", color: .green)

        HStack {
            Text("Row Content")
            Spacer()
            Image(systemName: "chevron.right")
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .designBounds("Row", color: .cyan)

        TextField("Enter text...", text: .constant(""))
            .textFieldStyle(.roundedBorder)
            .designBounds("Input", color: .purple)
    }
    .padding()
    .frame(width: 400, height: 300)
    .onAppear {
        DesignModeManager.shared.isEnabled = true
        DesignModeManager.shared.showBorders = true
    }
}

#endif
