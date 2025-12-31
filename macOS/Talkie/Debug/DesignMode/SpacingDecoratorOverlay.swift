//
//  SpacingDecoratorOverlay.swift
//  Talkie macOS
//
//  Spacing decorator - Shows design token reference and layout info
//  Useful for screenshots and documentation
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import AppKit

#if DEBUG

/// Shows design tokens and layout reference for documentation
struct SpacingDecoratorOverlay: View {
    @State private var windowSize: CGSize = .zero

    // Layout configuration from NavigationViewNative
    private let sidebar = (min: 160, ideal: 200, max: 280)
    private let content = (min: 180, ideal: 220, max: 320)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // === WINDOW DIMENSIONS (top center) ===
                windowDimensionsCard
                    .position(x: geometry.size.width / 2, y: 24)

                // === SPACING TOKEN REFERENCE (left side) ===
                spacingTokenCard
                    .position(x: 80, y: geometry.size.height / 2)

                // === LAYOUT CONFIG (right side) ===
                layoutConfigCard
                    .position(x: geometry.size.width - 90, y: geometry.size.height / 2 - 60)

                // === CORNER RADIUS REFERENCE (bottom left) ===
                radiusTokenCard
                    .position(x: 80, y: geometry.size.height - 60)
            }
            .onAppear {
                updateWindowSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
                updateWindowSize()
            }
        }
        .allowsHitTesting(false)
    }

    private func updateWindowSize() {
        if let window = NSApp.mainWindow {
            windowSize = window.frame.size
        }
    }

    // MARK: - Window Dimensions Card

    @ViewBuilder
    private var windowDimensionsCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "macwindow")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan)

                Text("WINDOW")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            Text("\(Int(windowSize.width)) × \(Int(windowSize.height))")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    // MARK: - Spacing Token Card

    @ViewBuilder
    private var spacingTokenCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text("SPACING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 4) {
                spacingRow("xxs", 2, .cyan.opacity(0.3))
                spacingRow("xs", 4, .cyan.opacity(0.4))
                spacingRow("sm", 8, .cyan.opacity(0.5))
                spacingRow("md", 12, .cyan.opacity(0.6))
                spacingRow("lg", 16, .cyan.opacity(0.7))
                spacingRow("xl", 24, .cyan.opacity(0.8))
                spacingRow("xxl", 32, .cyan.opacity(0.9))
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    @ViewBuilder
    private func spacingRow(_ name: String, _ value: CGFloat, _ color: Color) -> some View {
        HStack(spacing: 6) {
            // Visual bar
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: value, height: 6)

            // Label
            Text(name)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 28, alignment: .leading)

            // Value
            Text("\(Int(value))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 20, alignment: .trailing)
        }
    }

    // MARK: - Layout Config Card

    @ViewBuilder
    private var layoutConfigCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("LAYOUT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 6) {
                // Sidebar range
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sidebar")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 4) {
                        rangeBar(min: sidebar.min, ideal: sidebar.ideal, max: sidebar.max, color: .cyan)
                    }

                    Text("\(sidebar.min)–\(sidebar.max)px")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                }

                // Content column range
                VStack(alignment: .leading, spacing: 2) {
                    Text("Content Col")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 4) {
                        rangeBar(min: content.min, ideal: content.ideal, max: content.max, color: .orange)
                    }

                    Text("\(content.min)–\(content.max)px")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.8))
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Common heights
                VStack(alignment: .leading, spacing: 3) {
                    Text("Heights")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    heightRow("Toolbar", "52px")
                    heightRow("StatusBar", "32px")
                    heightRow("Row", "44px")
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    @ViewBuilder
    private func rangeBar(min: Int, ideal: Int, max: Int, color: Color) -> some View {
        let scale: CGFloat = 0.3 // Scale down for display

        ZStack(alignment: .leading) {
            // Full range (min to max)
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.3))
                .frame(width: CGFloat(max) * scale, height: 8)

            // Ideal marker
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 10)
                .offset(x: CGFloat(ideal) * scale - 1)
        }
    }

    @ViewBuilder
    private func heightRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.purple)
        }
    }

    // MARK: - Radius Token Card

    @ViewBuilder
    private var radiusTokenCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("RADIUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 8) {
                radiusPreview("xs", 4)
                radiusPreview("sm", 8)
                radiusPreview("md", 12)
                radiusPreview("lg", 16)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    @ViewBuilder
    private func radiusPreview(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                .frame(width: 24, height: 24)

            Text(name)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Shared Styles

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

#Preview("Spacing Decorator") {
    ZStack {
        // Simulated app background
        Color(white: 0.12)

        SpacingDecoratorOverlay()
    }
    .frame(width: 900, height: 600)
}

#endif
