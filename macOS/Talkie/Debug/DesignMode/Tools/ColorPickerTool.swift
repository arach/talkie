//
//  ColorPickerTool.swift
//  Talkie macOS
//
//  Color picker tool for grabbing colors from anywhere on screen
//  Click anywhere to grab color - shows swatch + hex + RGB values
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import AppKit

#if DEBUG

struct ColorPickerTool: View {
    @State private var pickedColor: NSColor?
    @State private var pickPosition: CGPoint?
    @State private var showTooltip = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay to capture clicks
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        captureColor(at: location, in: geometry)
                    }

                // Color tooltip
                if showTooltip, let color = pickedColor, let position = pickPosition {
                    colorTooltip(color: color)
                        .position(x: min(max(position.x, 120), geometry.size.width - 120),
                                 y: max(position.y - 80, 60))
                }
            }
        }
        .cursor(.crosshair)
        .allowsHitTesting(true)
    }

    private func captureColor(at location: CGPoint, in geometry: GeometryProxy) {
        // Convert local point to screen coordinates
        guard let window = NSApp.keyWindow else { return }

        let windowPoint = NSPoint(x: location.x, y: geometry.size.height - location.y)
        let screenPoint = window.convertPoint(toScreen: NSRect(origin: windowPoint, size: .zero)).origin

        // Capture pixel color at screen point
        if let color = captureScreenColor(at: screenPoint) {
            pickedColor = color
            pickPosition = location
            showTooltip = true

            // Hide tooltip after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showTooltip = false
                }
            }
        }
    }

    private func captureScreenColor(at point: NSPoint) -> NSColor? {
        // Create a 1x1 screenshot at the point
        let rect = CGRect(x: point.x, y: point.y, width: 1, height: 1)

        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else { return nil }

        // Get the pixel color
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let color = bitmap.colorAt(x: 0, y: 0) else { return nil }

        return color
    }

    @ViewBuilder
    private func colorTooltip(color: NSColor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Color swatch
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: color))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    // Hex value
                    Text(color.hexString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    // RGB values
                    Text("RGB(\(color.rgbString))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // Copy button
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(color.hexString, forType: .string)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                    Text("Copy Hex")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .frame(width: 160)
    }
}

// MARK: - NSColor Extensions

private extension NSColor {
    var hexString: String {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return "0, 0, 0" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return "\(r), \(g), \(b)"
    }
}

// MARK: - Custom Cursor

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview("Color Picker Tool") {
    ColorPickerTool()
        .frame(width: 600, height: 400)
        .background(
            LinearGradient(
                colors: [.blue, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
}

#endif
