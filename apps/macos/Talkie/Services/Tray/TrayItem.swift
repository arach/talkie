//
//  TrayItem.swift
//  Talkie
//
//  Unified wrapper for screenshots and clips in the capture tray.
//  Used by TrayBadge (hover grid) and TrayViewer (gallery).
//

import AppKit
import QuartzCore
import SwiftUI
import TalkieKit

// MARK: - TrayItem Enum

enum TrayItem: Identifiable {
    case screenshot(TrayScreenshot)
    case clip(TrayClip)
    case selection(TraySelectionText)

    var id: UUID {
        switch self {
        case .screenshot(let s): s.id
        case .clip(let c): c.id
        case .selection(let s): s.id
        }
    }

    var capturedAt: Date {
        switch self {
        case .screenshot(let s): s.capturedAt
        case .clip(let c): c.capturedAt
        case .selection(let s): s.capturedAt
        }
    }

    var image: NSImage? {
        switch self {
        case .screenshot(let s): s.image
        case .clip(let c): c.thumbnail
        case .selection: nil
        }
    }

    var isClip: Bool {
        if case .clip = self { return true }
        return false
    }

    var isText: Bool {
        if case .selection = self { return true }
        return false
    }

    var pinned: Bool {
        switch self {
        case .screenshot(let s): s.pinned
        case .clip(let c): c.pinned
        case .selection(let s): s.pinned
        }
    }

    var width: Int {
        switch self {
        case .screenshot(let s): s.width
        case .clip(let c): c.width
        case .selection(let s): min(max(s.characterCount / 4, 40), 220)
        }
    }

    var height: Int {
        switch self {
        case .screenshot(let s): s.height
        case .clip(let c): c.height
        case .selection: 72
        }
    }

    var aspectRatio: CGFloat {
        guard height > 0 else { return 16.0 / 9.0 }
        return max(CGFloat(width) / CGFloat(height), 0.1)
    }

    var appName: String? {
        switch self {
        case .screenshot(let s): s.appName
        case .clip(let c): c.appName
        case .selection(let s): s.appName
        }
    }

    var windowTitle: String? {
        switch self {
        case .screenshot(let s): s.windowTitle
        case .clip(let c): c.windowTitle
        case .selection(let s): s.windowTitle
        }
    }

    var displayName: String? {
        switch self {
        case .screenshot(let s): s.displayName
        case .clip(let c): c.displayName
        case .selection(let s): s.displayName
        }
    }

    var previewText: String? {
        switch self {
        case .selection(let s): s.textPreview
        case .screenshot, .clip: nil
        }
    }

    /// First non-nil of appName, windowTitle, displayName
    var contextLabel: String? {
        appName ?? windowTitle ?? displayName
    }

    var modeIcon: String {
        switch self {
        case .screenshot(let s):
            switch s.mode {
            case .region: "crop"
            case .fullscreen: "rectangle.dashed"
            case .window: "macwindow"
            }
        case .clip(let c):
            switch c.captureMode {
            case "camera": "video.fill"
            case "region": "crop"
            case "fullscreen": "rectangle.dashed"
            case "window": "macwindow"
            default: "video.fill"
            }
        case .selection:
            "text.quote"
        }
    }

    var durationLabel: String? {
        guard case .clip(let c) = self else { return nil }
        let seconds = c.durationMs / 1000
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }

    var tempURL: URL {
        switch self {
        case .screenshot(let s): s.tempURL
        case .clip(let c): c.tempURL
        case .selection(let s): s.tempURL
        }
    }

    /// Merges both trays into a chronological timeline, newest first.
    @MainActor static func allItems() -> [TrayItem] {
        let screenshots = ScreenshotTray.shared.items.map { TrayItem.screenshot($0) }
        let clips = ClipTray.shared.items.map { TrayItem.clip($0) }
        let selections = SelectionTray.shared.items.map { TrayItem.selection($0) }
        return (screenshots + clips + selections).sorted { $0.capturedAt > $1.capturedAt }
    }
}

// MARK: - Dossier Card View

/// Shared cell used by both badge hover grid and viewer grid.
/// Polaroid/dossier aesthetic: image region on top, tactical data strip below,
/// thin bezel border, monospaced metadata.
@MainActor
private enum TrayCardPalette {
    static var mediaSurface: Color { Theme.current.surface2 }
    static var metadataSurface: Color { Theme.current.surface1 }
    static var selectionSurface: Color { Theme.current.surface3 }
    static var border: Color { Theme.current.divider }
    static var textPrimary: Color { Theme.current.textPrimary }
    static var textSecondary: Color { Theme.current.textSecondary }
    static var textTertiary: Color { Theme.current.textTertiary }
    static var textMuted: Color { Theme.current.textMuted }
    static var timecodeSurface: Color { Theme.current.background.opacity(0.88) }
}

struct DossierCardView: View {
    let item: TrayItem
    let imageHeight: CGFloat
    let fontSize: CGFloat  // base font size — strip scales from this

    init(item: TrayItem, imageHeight: CGFloat = 52, fontSize: CGFloat = 7) {
        self.item = item
        self.imageHeight = imageHeight
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(spacing: 0) {
            // Image region — squared off, blueprint-precise
            ZStack(alignment: .bottomLeading) {
                if let nsImage = item.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, minHeight: imageHeight, maxHeight: imageHeight)
                        .clipped()
                } else if let previewText = item.previewText {
                    selectionPreview(previewText)
                        .frame(maxWidth: .infinity, minHeight: imageHeight, maxHeight: imageHeight)
                } else {
                    TrayCardPalette.mediaSurface
                        .frame(maxWidth: .infinity, minHeight: imageHeight, maxHeight: imageHeight)
                        .overlay(
                            Image(systemName: item.isClip ? "video.fill" : "photo")
                                .font(.system(size: fontSize * 2, weight: .light))
                                .foregroundStyle(TrayCardPalette.textMuted)
                        )
                }

                // Bottom-left: pin indicator (only for pinned items)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: max(fontSize - 1, 5), weight: .heavy))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(2.5)
                        .background(Circle().fill(Color.orange.opacity(0.85)))
                        .offset(x: 3, y: -3)
                }

                // Bottom-right: clip timecode burn-in
                if let duration = item.durationLabel {
                    HStack {
                        Spacer()
                        Text(duration)
                            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                            .foregroundColor(TrayCardPalette.textPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(TrayCardPalette.timecodeSurface)
                            .offset(x: -2, y: -2)
                    }
                }
            }

            // Data strip — tactical metadata
            HStack(spacing: 3) {
                Image(systemName: item.modeIcon)
                    .font(.system(size: max(fontSize - 1, 5), weight: .bold))
                    .foregroundColor(TrayCardPalette.textSecondary)
                Text(metadataLabel)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textTertiary)
                Spacer()
                if item.pinned {
                    Text("PIN")
                        .font(.system(size: max(fontSize - 1, 5), weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.6))
                }
                Text(compactTimeAgo(item.capturedAt))
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textTertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(TrayCardPalette.metadataSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(TrayCardPalette.border, lineWidth: 0.5)
        )
    }

    private func compactTimeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h"
    }

    private var metadataLabel: String {
        if let previewText = item.previewText {
            return "\(previewText.count)c"
        }
        return "\(item.width)×\(item.height)"
    }

    @ViewBuilder
    private func selectionPreview(_ text: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(TrayCardPalette.selectionSurface)
            VStack(alignment: .leading, spacing: 4) {
                Text("SELECTION")
                    .font(.system(size: max(fontSize - 1, 5), weight: .bold, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textTertiary)
                Text(text)
                    .font(.system(size: max(fontSize + 1, 6), weight: .medium, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textPrimary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(6)
        }
    }
}

// MARK: - Adaptive Card View

/// Aspect-ratio-aware card used by TrayViewer gallery/carousel and shelf surfaces.
/// Unlike DossierCardView, the image region uses `.fit` so orientation is preserved.
struct AdaptiveCardView: View {
    let item: TrayItem
    let isSelected: Bool
    let isFocused: Bool
    let fontSize: CGFloat

    init(item: TrayItem, isSelected: Bool = false, isFocused: Bool = false, fontSize: CGFloat = 8) {
        self.item = item
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                TrayCardPalette.mediaSurface

                if let nsImage = item.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let previewText = item.previewText {
                    selectionAdaptivePreview(previewText)
                } else {
                    Image(systemName: item.isClip ? "video.fill" : "photo")
                        .font(.system(size: fontSize * 2, weight: .light))
                        .foregroundStyle(TrayCardPalette.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: max(fontSize - 1, 5), weight: .heavy))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(2.5)
                        .background(Circle().fill(Color.orange.opacity(0.85)))
                        .offset(x: 3, y: -3)
                }

                if let duration = item.durationLabel {
                    HStack {
                        Spacer()
                        Text(duration)
                            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                            .foregroundColor(TrayCardPalette.textPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(TrayCardPalette.timecodeSurface)
                            .offset(x: -2, y: -2)
                    }
                }
            }

            HStack(spacing: 3) {
                Image(systemName: item.modeIcon)
                    .font(.system(size: max(fontSize - 1, 5), weight: .bold))
                    .foregroundColor(TrayCardPalette.textSecondary)
                Text(metadataLabel)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textTertiary)
                Spacer()
                if item.pinned {
                    Text("PIN")
                        .font(.system(size: max(fontSize - 1, 5), weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.6))
                }
                Text(compactTimeAgo(item.capturedAt))
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textTertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(TrayCardPalette.metadataSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(borderOverlay)
    }

    private var metadataLabel: String {
        if case .selection(let selection) = item {
            return "\(selection.characterCount)c"
        }
        return "\(item.width)×\(item.height)"
    }

    @ViewBuilder
    private func selectionAdaptivePreview(_ text: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(TrayCardPalette.selectionSurface)
            VStack(alignment: .leading, spacing: 6) {
                Text("SELECTION")
                    .font(.system(size: max(fontSize - 1, 6), weight: .bold, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textTertiary)
                Text(text)
                    .font(.system(size: max(fontSize + 1, 8), weight: .medium, design: .monospaced))
                    .foregroundColor(TrayCardPalette.textPrimary)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
        }
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(borderColor, style: StrokeStyle(lineWidth: borderWidth, dash: borderDash))
    }

    private var borderColor: Color {
        if isFocused { return .accentColor.opacity(0.95) }
        if isSelected { return .accentColor.opacity(0.65) }
        return TrayCardPalette.border
    }

    private var borderWidth: CGFloat {
        if isFocused { return 1.6 }
        if isSelected { return 1.2 }
        return 0.5
    }

    private var borderDash: [CGFloat] {
        isFocused && !isSelected ? [3, 2] : []
    }

    private func compactTimeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h"
    }
}

// MARK: - Panel Self-Capture

/// Screenshots a panel to clipboard and Desktop.
/// Uses view-tree rendering as primary (always works regardless of sharingType),
/// with ScreenCaptureKit as optional upgrade when the window is shareable.
@MainActor
func capturePanelToClipboard(_ window: NSWindow, metadataLines: [String] = []) {
    Task { @MainActor in
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        CATransaction.flush()

        var cgImage: CGImage?

        if window.sharingType != .none {
            let windowID = CGWindowID(window.windowNumber)
            cgImage = await ScreenshotCaptureService.shared.captureWindowImage(windowID: windowID)
            if let image = cgImage, isLikelyBlackImage(image) {
                cgImage = nil
            }
        }

        if cgImage == nil {
            cgImage = renderWindowContentImage(window)
        }

        guard let cgImage else {
            Log(.system).warning("Panel capture failed")
            return
        }

        writePanelCapture(cgImage, window: window, metadataLines: metadataLines)
    }
}

@MainActor
private func writePanelCapture(_ cgImage: CGImage, window: NSWindow, metadataLines: [String]) {
    // Size in points (not pixels) so Retina images paste at correct dimensions
    let scale = window.screen?.backingScaleFactor ?? 2.0
    let pointSize = NSSize(
        width: CGFloat(cgImage.width) / scale,
        height: CGFloat(cgImage.height) / scale
    )
    let baseImage = NSImage(cgImage: cgImage, size: pointSize)
    let finalImage = annotatedCaptureImage(baseImage, metadataLines: metadataLines)

    // Copy to clipboard
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([finalImage])

    // Add to tray (not Desktop — we are the screenshot tool)
    if let png = pngData(from: finalImage) {
        Task { @MainActor in
            await ScreenshotTray.shared.add(
                data: png,
                width: cgImage.width,
                height: cgImage.height,
                mode: .fullscreen,
                windowTitle: "Tray",
                appName: "Talkie"
            )
        }
        Log(.system).info("Panel captured → tray + clipboard")
    }
}

@MainActor
private func annotatedCaptureImage(_ image: NSImage, metadataLines: [String]) -> NSImage {
    let lines = metadataLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !lines.isEmpty else { return image }

    let canvas = NSImage(size: image.size)
    canvas.lockFocus()

    image.draw(in: NSRect(origin: .zero, size: image.size))

    let inset: CGFloat = 10
    let innerPaddingX: CGFloat = 8
    let innerPaddingY: CGFloat = 7
    let rowGap: CGFloat = 3
    let cornerRadius: CGFloat = 8

    let headerAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92)
    ]
    let rowAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.86)
    ]

    let header = "Notch Animator"
    let headerSize = (header as NSString).size(withAttributes: headerAttrs)
    let lineSizes = lines.map { ($0 as NSString).size(withAttributes: rowAttrs) }
    let widestLine = lineSizes.map(\.width).max() ?? 0

    let blockWidth = min(
        image.size.width - (inset * 2),
        max(headerSize.width, widestLine) + (innerPaddingX * 2)
    )
    let contentHeight = headerSize.height +
        (lineSizes.reduce(CGFloat(0)) { $0 + $1.height }) +
        (CGFloat(max(0, lines.count - 1)) * rowGap)
    let blockHeight = contentHeight + (innerPaddingY * 2)
    let blockRect = NSRect(
        x: inset,
        y: inset,
        width: max(140, blockWidth),
        height: max(44, blockHeight)
    )

    NSColor.black.withAlphaComponent(0.72).setFill()
    NSBezierPath(roundedRect: blockRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

    let dividerY = blockRect.maxY - innerPaddingY - headerSize.height - 3
    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(rect: NSRect(x: blockRect.minX + innerPaddingX, y: dividerY, width: blockRect.width - (innerPaddingX * 2), height: 0.5)).fill()

    let headerPoint = NSPoint(
        x: blockRect.minX + innerPaddingX,
        y: blockRect.maxY - innerPaddingY - headerSize.height
    )
    (header as NSString).draw(at: headerPoint, withAttributes: headerAttrs)

    var cursorY = dividerY - 6
    for (index, line) in lines.enumerated() {
        let size = lineSizes[index]
        cursorY -= size.height
        let point = NSPoint(x: blockRect.minX + innerPaddingX, y: cursorY)
        (line as NSString).draw(at: point, withAttributes: rowAttrs)
        cursorY -= rowGap
    }

    canvas.unlockFocus()
    return canvas
}

@MainActor
private func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

@MainActor
private func renderWindowContentImage(_ window: NSWindow) -> CGImage? {
    guard let view = window.contentView else { return nil }
    view.layoutSubtreeIfNeeded()
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
    view.cacheDisplay(in: bounds, to: rep)
    return rep.cgImage
}

@MainActor
private func windowListBounds(for window: NSWindow) -> CGRect {
    let frame = window.frame
    let screenFrame = window.screen?.frame ?? NSScreen.main?.frame ?? frame
    return CGRect(
        x: frame.origin.x,
        y: screenFrame.maxY - frame.maxY,
        width: frame.width,
        height: frame.height
    )
}

private func isLikelyBlackImage(_ image: CGImage) -> Bool {
    guard let data = image.dataProvider?.data else { return false }
    let length = CFDataGetLength(data)
    guard length > 0 else { return true }
    guard let bytes = CFDataGetBytePtr(data) else { return false }

    let bytesPerPixel = max(image.bitsPerPixel / 8, 1)
    let bytesPerRow = image.bytesPerRow
    let width = image.width
    let height = image.height
    guard width > 0, height > 0, bytesPerRow > 0 else { return true }

    // Sample across the image; if every sample is very dark, treat as failed capture.
    let sampleCount = min(96, max(12, (width * height) / 20_000))
    var nonDarkSamples = 0

    for i in 0..<sampleCount {
        let x = (i * 131 + 17) % width
        let y = (i * 71 + 9) % height
        let offset = y * bytesPerRow + x * bytesPerPixel
        if offset + 2 >= length { continue }

        let c0 = Int(bytes[offset])
        let c1 = Int(bytes[offset + 1])
        let c2 = Int(bytes[offset + 2])
        if max(c0, c1, c2) > 18 {
            nonDarkSamples += 1
            if nonDarkSamples >= 2 {
                return false
            }
        }
    }

    return true
}
