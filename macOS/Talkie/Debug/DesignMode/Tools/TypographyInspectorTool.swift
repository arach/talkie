//
//  TypographyInspectorTool.swift
//  Talkie macOS
//
//  Typography inspector tool for examining text elements
//  Click on any text to see font family, size, weight, line height
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import AppKit

#if DEBUG

struct TypographyInspectorTool: View {
    @State private var inspectedTypography: TypographyInfo?
    @State private var inspectPosition: CGPoint?
    @State private var showTooltip = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay to capture clicks
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        inspectTypography(at: location, in: geometry)
                    }

                // Typography tooltip
                if showTooltip, let info = inspectedTypography, let position = inspectPosition {
                    typographyTooltip(info: info)
                        .position(x: min(max(position.x, 100), geometry.size.width - 100),
                                 y: max(position.y - 100, 80))
                }
            }
        }
        .cursor(.crosshair)
        .allowsHitTesting(true)
    }

    private func inspectTypography(at location: CGPoint, in geometry: GeometryProxy) {
        // For this implementation, we'll use the accessibility API to try to get text info
        // In a real implementation, this would need deeper integration with the view hierarchy

        // Convert local point to screen coordinates
        guard let window = NSApp.keyWindow else { return }

        let windowPoint = NSPoint(x: location.x, y: geometry.size.height - location.y)
        let screenPoint = window.convertPoint(toScreen: windowPoint)

        // Try to get typography info from the point
        if let info = extractTypographyInfo(at: screenPoint) {
            inspectedTypography = info
            inspectPosition = location
            showTooltip = true

            // Hide tooltip after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showTooltip = false
                }
            }
        }
    }

    private func extractTypographyInfo(at point: NSPoint) -> TypographyInfo? {
        // This is a simplified implementation
        // In production, you'd need to traverse the view hierarchy or use accessibility API

        // For now, we'll capture a sample and try to detect text attributes
        // This is a placeholder that returns example data
        // A real implementation would need to inspect the actual UI element at the point

        return TypographyInfo(
            fontFamily: "SF Pro",
            fontSize: 13,
            fontWeight: "Regular",
            lineHeight: 18,
            textSample: "Sample Text"
        )
    }

    @ViewBuilder
    private func typographyTooltip(info: TypographyInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sample text preview
            Text(info.textSample)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .padding(.bottom, 4)

            Divider()
                .background(Color.white.opacity(0.2))

            // Typography details
            VStack(alignment: .leading, spacing: 6) {
                propertyRow(label: "Font", value: info.fontFamily)
                propertyRow(label: "Size", value: "\(info.fontSize)pt")
                propertyRow(label: "Weight", value: info.fontWeight)
                propertyRow(label: "Line Height", value: "\(info.lineHeight)pt")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .frame(width: 180)
    }

    @ViewBuilder
    private func propertyRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)
        }
    }
}

// MARK: - Typography Info Model

private struct TypographyInfo {
    let fontFamily: String
    let fontSize: CGFloat
    let fontWeight: String
    let lineHeight: CGFloat
    let textSample: String
}

#Preview("Typography Inspector Tool") {
    ZStack {
        VStack(spacing: 20) {
            Text("Click on this heading")
                .font(.title)
            Text("Or this body text to inspect typography")
                .font(.body)
            Text("Supports multiple text styles")
                .font(.caption)
        }

        TypographyInspectorTool()
    }
    .frame(width: 600, height: 400)
    .background(Color.gray.opacity(0.1))
}

#endif
