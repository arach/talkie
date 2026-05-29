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

public enum CaptureMarkupRenderer {
    public static func render(image: CGImage, document: CaptureMarkupDocument) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
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

        for layer in document.layers where layer.visible {
            if let viewport = document.viewport {
                draw(layer: layerInImageBasis(layer, viewport: viewport, imageSize: size), in: context, size: size)
            } else {
                draw(layer: layer, in: context, size: size)
            }
        }

        return context.makeImage()
    }

    public static func renderPNGData(image: CGImage, document: CaptureMarkupDocument) -> Data? {
        guard let output = render(image: image, document: document) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(dest, output, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Stroke weight in pixels for the export bitmap. Mirrors the web canvas:
    /// `strokeUnits * max(1, width/600)`, with `2` as the historical default
    /// when a layer carries no explicit `strokeWidth`.
    private static func strokeLineWidth(_ layer: CaptureMarkupLayer, size: CGSize) -> CGFloat {
        let baseUnit = max(1, size.width / 600)
        let units = layer.strokeWidth.map { CGFloat($0) } ?? 2
        return units * baseUnit
    }

    private static func draw(layer: CaptureMarkupLayer, in context: CGContext, size: CGSize) {
        let color = parseColor(layer.color)
        switch layer.kind {
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
            drawLabel(text, near: frame.pixelRect(in: size), in: context, size: size)
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

        var converted = layer
        if let frame = layer.frame {
            converted.frame = CaptureMarkupRect(
                x: ((frame.x * viewport.width) - viewport.imageX) / (viewport.imageScale * imageSize.width),
                y: ((frame.y * viewport.height) - viewport.imageY) / (viewport.imageScale * imageSize.height),
                width: (frame.width * viewport.width) / (viewport.imageScale * imageSize.width),
                height: (frame.height * viewport.height) / (viewport.imageScale * imageSize.height)
            )
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

    private static func drawLabel(
        _ text: String,
        near rect: CGRect,
        in context: CGContext,
        size: CGSize
    ) {
        #if canImport(AppKit)
        let fontSize = max(11, size.width / 140)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let measured = (text as NSString).size(withAttributes: attrs)
        let padding = CGSize(width: 8, height: 5)
        let topLeftY = min(rect.minY, size.height - rect.maxY)
        let labelTopLeft = CGPoint(
            x: rect.minX,
            y: max(4, topLeftY - measured.height - padding.height * 2)
        )
        let labelRectTopLeft = CGRect(
            origin: labelTopLeft,
            size: CGSize(
                width: measured.width + padding.width * 2,
                height: measured.height + padding.height * 2
            )
        )

        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let flippedRect = CGRect(
            origin: CGPoint(
                x: labelRectTopLeft.minX,
                y: size.height - labelRectTopLeft.minY - labelRectTopLeft.height
            ),
            size: labelRectTopLeft.size
        )
        context.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.84))
        context.addPath(
            CGPath(roundedRect: flippedRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        )
        context.fillPath()

        let drawPoint = CGPoint(
            x: flippedRect.minX + padding.width,
            y: flippedRect.minY + padding.height
        )
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        context.textPosition = drawPoint
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
