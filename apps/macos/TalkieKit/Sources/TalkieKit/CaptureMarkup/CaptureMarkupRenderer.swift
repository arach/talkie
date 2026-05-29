//
//  CaptureMarkupRenderer.swift
//  TalkieKit
//
//  Headless CoreGraphics compositor for markup export and tests.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreGraphics
import Foundation

/// Output format for a materialized markup export. The markup itself stays a
/// computed document (sidecar layers) — this only describes the flat artifact
/// produced on the way out.
public enum CaptureMarkupExportFormat: String, Sendable, CaseIterable {
    case png
    case jpeg

    /// UTI for the ImageIO destination.
    var utiType: CFString {
        switch self {
        case .png: return "public.png" as CFString
        case .jpeg: return "public.jpeg" as CFString
        }
    }

    /// File extension for the written artifact.
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

public enum CaptureMarkupRenderer {
    /// Render the source image + computed layers into a flat bitmap.
    ///
    /// `scale` multiplies the output pixel dimensions (1 = native capture size,
    /// 2 = retina). Layer geometry is normalized 0…1, stroke weight keys off
    /// `width/600`, and labels off `width/140`, so everything scales cleanly
    /// off the single `size` value — no per-layer scale math required.
    public static func render(
        image: CGImage,
        document: CaptureMarkupDocument,
        scale: CGFloat = 1
    ) -> CGImage? {
        let factor = max(0.1, scale)
        let size = CGSize(
            width: CGFloat(image.width) * factor,
            height: CGFloat(image.height) * factor
        )
        guard size.width > 0, size.height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.setShouldAntialias(true)

        // Overlay geometry is stored normalized with a TOP-LEFT origin (matching
        // the web canvas). The bitmap context is bottom-left, so without this
        // flip every shape renders vertically inverted (an arrow drawn pointing
        // up-right exports pointing down-right). The base image was already
        // drawn upright above; flip only what's composited on top of it.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        for layer in document.layers where layer.visible {
            if let viewport = document.viewport {
                draw(layer: layerInImageBasis(layer, viewport: viewport, imageSize: size), in: context, size: size, image: image)
            } else {
                draw(layer: layer, in: context, size: size, image: image)
            }
        }

        return context.makeImage()
    }

    /// Render + encode to a flat artifact in the requested format and scale.
    /// `quality` applies to JPEG only (0…1); PNG ignores it.
    public static func encodedData(
        image: CGImage,
        document: CaptureMarkupDocument,
        format: CaptureMarkupExportFormat,
        scale: CGFloat = 1,
        quality: CGFloat = 0.9
    ) -> Data? {
        guard let output = render(image: image, document: document, scale: scale) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.utiType,
            1,
            nil
        ) else {
            return nil
        }
        let properties: CFDictionary? = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            : nil
        CGImageDestinationAddImage(dest, output, properties)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// PNG at native scale. Thin wrapper kept for the existing drag-out path.
    public static func renderPNGData(image: CGImage, document: CaptureMarkupDocument) -> Data? {
        encodedData(image: image, document: document, format: .png, scale: 1)
    }

    /// Stroke weight in pixels for the export bitmap. Mirrors the web canvas:
    /// `strokeUnits * max(1, width/600)`, with `2` as the historical default
    /// when a layer carries no explicit `strokeWidth`.
    private static func strokeLineWidth(_ layer: CaptureMarkupLayer, size: CGSize) -> CGFloat {
        let baseUnit = max(1, size.width / 600)
        let units = layer.strokeWidth.map { CGFloat($0) } ?? 2
        return units * baseUnit
    }

    private static func draw(layer: CaptureMarkupLayer, in context: CGContext, size: CGSize, image: CGImage) {
        let color = parseColor(layer.color)
        switch layer.kind {
        case .patch:
            // Clone: copy a region of the source image and draw it at the dest
            // frame. `source`/`frame` are image-normalized here; the crop is in
            // original-image pixels, the destination in output pixels.
            guard let frame = layer.frame, let source = layer.source else { return }
            let imageSize = CGSize(width: image.width, height: image.height)
            let cropRect = source.pixelRect(in: imageSize).integral
            guard cropRect.width >= 1, cropRect.height >= 1,
                  let cropped = image.cropping(to: cropRect) else { return }
            // The overlay context is y-flipped (top-left); drawing a CGImage
            // straight in would mirror it, so un-flip locally around the dest.
            let dest = frame.pixelRect(in: size)
            context.saveGState()
            context.translateBy(x: dest.minX, y: dest.minY + dest.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: dest.width, height: dest.height))
            context.restoreGState()
            return
        case .rect, .highlight:
            guard let frame = layer.frame else { return }
            let rect = frame.pixelRect(in: size)
            if layer.kind == .highlight {
                context.setFillColor(color.copy(alpha: layer.label == "BLUR" ? 0.32 : 0.12) ?? color)
                context.fill(rect)
            }
            context.setStrokeColor(color)
            context.setLineWidth(strokeLineWidth(layer, size: size))
            context.stroke(rect)
            if let label = layer.label {
                drawLabel(label, near: rect, in: context, size: size)
            }
        case .arrow:
            guard let from = layer.from, let to = layer.to else { return }
            let start = from.pixelPoint(in: size)
            let end = to.pixelPoint(in: size)
            context.setStrokeColor(color)
            context.setLineWidth(strokeLineWidth(layer, size: size))
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            // `label == "line"` is the sentinel for a plain line (no arrowhead),
            // matching the web canvas. Other labels are rendered as a tag.
            if layer.label != "line" {
                drawArrowHead(at: end, from: start, color: color, in: context, size: size)
            }
            if let label = layer.label, label != "line" {
                drawLabel(label, near: CGRect(origin: end, size: .zero), in: context, size: size)
            }
        case .label:
            guard let frame = layer.frame, let text = layer.text ?? layer.label else { return }
            drawLabel(
                text,
                near: frame.pixelRect(in: size),
                in: context,
                size: size,
                family: layer.fontFamily,
                bold: layer.bold ?? false,
                italic: layer.italic ?? false,
                plain: layer.plain ?? false,
                sizeScale: CGFloat((layer.fontSize ?? 16) / 16),
                textColorHex: layer.color,
                inPlace: true
            )
        case .guide:
            drawGuides(layer: layer, color: color, in: context, size: size)
        }
    }

    private static func layerInImageBasis(
        _ layer: CaptureMarkupLayer,
        viewport: CaptureMarkupViewport,
        imageSize: CGSize
    ) -> CaptureMarkupLayer {
        func convert(point: CaptureMarkupPoint) -> CaptureMarkupPoint {
            CaptureMarkupPoint(
                x: ((point.x * viewport.width) - viewport.imageX) / (viewport.imageScale * imageSize.width),
                y: ((point.y * viewport.height) - viewport.imageY) / (viewport.imageScale * imageSize.height)
            )
        }

        func convert(rect: CaptureMarkupRect) -> CaptureMarkupRect {
            CaptureMarkupRect(
                x: ((rect.x * viewport.width) - viewport.imageX) / (viewport.imageScale * imageSize.width),
                y: ((rect.y * viewport.height) - viewport.imageY) / (viewport.imageScale * imageSize.height),
                width: (rect.width * viewport.width) / (viewport.imageScale * imageSize.width),
                height: (rect.height * viewport.height) / (viewport.imageScale * imageSize.height)
            )
        }

        var converted = layer
        if let frame = layer.frame {
            converted.frame = convert(rect: frame)
        }
        if let source = layer.source {
            converted.source = convert(rect: source)
        }
        if let from = layer.from {
            converted.from = convert(point: from)
        }
        if let to = layer.to {
            converted.to = convert(point: to)
        }
        return converted
    }

    private static func drawGuides(
        layer: CaptureMarkupLayer,
        color: CGColor,
        in context: CGContext,
        size: CGSize
    ) {
        let interval = layer.interval ?? 50
        let orientation = layer.orientation ?? "h"
        context.setStrokeColor(color.copy(alpha: 0.55) ?? color)
        context.setLineWidth(1)

        if orientation == "h" || orientation == "both" {
            var y = interval
            while y < size.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: size.width, y: y))
                y += interval
            }
        }
        if orientation == "v" || orientation == "both" {
            var x = interval
            while x < size.width {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: size.height))
                x += interval
            }
        }
        context.strokePath()
    }

    private static func drawArrowHead(
        at tip: CGPoint,
        from start: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize
    ) {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let headLength = max(8, size.width / 120)
        let left = CGPoint(
            x: tip.x - headLength * cos(angle - .pi / 6),
            y: tip.y - headLength * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: tip.x - headLength * cos(angle + .pi / 6),
            y: tip.y - headLength * sin(angle + .pi / 6)
        )
        context.setFillColor(color)
        context.move(to: tip)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()
    }

    /// Draw a label. Defaults reproduce the historical shape-tag look (mono
    /// semibold, white-on-dark pill, anchored *above* the shape). `.label`
    /// layers pass their own typography and `inPlace: true` so the text sits at
    /// its frame and matches the web canvas.
    private static func drawLabel(
        _ text: String,
        near rect: CGRect,
        in context: CGContext,
        size: CGSize,
        family: String? = nil,
        bold: Bool = false,
        italic: Bool = false,
        plain: Bool = false,
        sizeScale: CGFloat = 1,
        textColorHex: String? = nil,
        inPlace: Bool = false
    ) {
        #if canImport(AppKit)
        let fontSize = max(11, size.width / 140) * sizeScale
        let weight: NSFont.Weight = bold ? .bold : (family == nil ? .semibold : .regular)
        var font: NSFont
        switch family {
        case "sans":
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        case "serif":
            let base = NSFont.systemFont(ofSize: fontSize, weight: weight)
            font = base.fontDescriptor.withDesign(.serif)
                .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
        default: // "mono" or nil
            font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        }
        if italic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            if let italicFont = NSFont(descriptor: descriptor, size: fontSize) {
                font = italicFont
            }
        }

        let textColor: NSColor = plain
            ? (NSColor(cgColor: parseColor(textColorHex ?? "#C47D1C")) ?? .white)
            : .white
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let measured = (text as NSString).size(withAttributes: attrs)
        let padding = CGSize(width: 8, height: 5)
        // In-place labels anchor at their frame's top-left; tags float just
        // above the shape they annotate. Coordinates are top-left (the render
        // context is already flipped), so no inversion math is needed.
        let labelTopLeft: CGPoint
        if inPlace {
            labelTopLeft = CGPoint(x: rect.minX, y: max(4, rect.minY))
        } else {
            labelTopLeft = CGPoint(
                x: rect.minX,
                y: max(4, rect.minY - measured.height - padding.height * 2)
            )
        }
        let labelRect = CGRect(
            origin: labelTopLeft,
            size: CGSize(
                width: measured.width + padding.width * 2,
                height: measured.height + padding.height * 2
            )
        )

        if !plain {
            context.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.84))
            context.addPath(
                CGPath(roundedRect: labelRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            )
            context.fillPath()
        }

        // Context is y-flipped; flip the text matrix so glyphs read upright and
        // place the baseline at top + ascent within the pill.
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(
            x: labelRect.minX + padding.width,
            y: labelRect.minY + padding.height + font.ascender
        )
        CTLineDraw(line, context)
        context.restoreGState()
        #endif
    }

    private static func parseColor(_ hex: String) -> CGColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return CGColor(red: 0.77, green: 0.49, blue: 0.11, alpha: 1)
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}

#if canImport(AppKit)
import CoreText
#endif
