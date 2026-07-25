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
import CoreImage
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
    private static let materialCIContext = CIContext(options: [.useSoftwareRenderer: false])
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

    private static func strokeDash(_ layer: CaptureMarkupLayer, size: CGSize) -> [CGFloat] {
        guard let dash = layer.lineDash, !dash.isEmpty else { return [] }
        let baseUnit = max(1, size.width / 600)
        return dash.map { CGFloat(max(0, $0)) * baseUnit }
    }

    private static func strokeWithEffects(
        _ layer: CaptureMarkupLayer,
        in context: CGContext,
        size: CGSize,
        stroke: () -> Void
    ) {
        context.saveGState()
        context.setLineDash(phase: 0, lengths: strokeDash(layer, size: size))
        if layer.shadow == true {
            let baseUnit = max(1, size.width / 600)
            let color = parseColor(layer.shadowColor ?? "rgba(0, 0, 0, 0.28)")
            let offset = CGSize(width: 0, height: CGFloat(layer.shadowOffsetY ?? 5) * baseUnit)
            context.setShadow(offset: offset, blur: CGFloat(layer.shadowBlur ?? 12) * baseUnit, color: color)
        }
        stroke()
        context.restoreGState()
    }

    private static func smoothedInkPoints(_ points: [CaptureMarkupPoint], size: CGSize) -> [CGPoint] {
        let pixelPoints = points.map { $0.pixelPoint(in: size) }
        guard pixelPoints.count >= 3 else { return pixelPoints }
        var smoothed: [CGPoint] = [pixelPoints[0]]
        for index in 1..<(pixelPoints.count - 1) {
            let previous = pixelPoints[index - 1]
            let point = pixelPoints[index]
            let next = pixelPoints[index + 1]
            smoothed.append(CGPoint(
                x: point.x * 0.5 + (previous.x + next.x) * 0.25,
                y: point.y * 0.5 + (previous.y + next.y) * 0.25
            ))
        }
        smoothed.append(pixelPoints[pixelPoints.count - 1])
        return smoothed
    }

    private static func addSmoothedInkPath(_ points: [CaptureMarkupPoint], to context: CGContext, size: CGSize) {
        let smoothed = smoothedInkPoints(points, size: size)
        guard smoothed.count >= 2 else { return }
        context.move(to: smoothed[0])
        if smoothed.count == 2 {
            context.addLine(to: smoothed[1])
            return
        }
        for index in 1..<(smoothed.count - 1) {
            let current = smoothed[index]
            let next = smoothed[index + 1]
            context.addQuadCurve(
                to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2),
                control: current
            )
        }
        context.addLine(to: smoothed[smoothed.count - 1])
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
                if layer.label == CaptureMarkupAutoBlur.layerLabel {
                    drawPrivacyBlur(
                        frame: frame,
                        destinationRect: rect,
                        sourceImage: image,
                        in: context,
                        outputSize: size
                    )
                    return
                }
                context.setFillColor(color.copy(alpha: 0.12) ?? color)
                context.fill(rect)
            } else if let fillAlpha = layer.fillAlpha, fillAlpha > 0 {
                let fillColor = parseColor(layer.fillColor ?? layer.color)
                context.setFillColor(fillColor.copy(alpha: CGFloat(min(1, max(0, fillAlpha)))) ?? fillColor)
                context.fill(rect)
            }
            context.setStrokeColor(color)
            context.setLineWidth(strokeLineWidth(layer, size: size))
            strokeWithEffects(layer, in: context, size: size) {
                context.stroke(rect)
            }
            if let label = layer.label {
                drawLabel(label, near: rect, in: context, size: size)
            }
        case .ellipse:
            guard let frame = layer.frame else { return }
            let rect = frame.pixelRect(in: size)
            if let fillAlpha = layer.fillAlpha, fillAlpha > 0 {
                let fillColor = parseColor(layer.fillColor ?? layer.color)
                context.setFillColor(fillColor.copy(alpha: CGFloat(min(1, max(0, fillAlpha)))) ?? fillColor)
                context.fillEllipse(in: rect)
            }
            context.setStrokeColor(color)
            context.setLineWidth(strokeLineWidth(layer, size: size))
            strokeWithEffects(layer, in: context, size: size) {
                context.strokeEllipse(in: rect)
            }
            if let label = layer.label {
                drawLabel(label, near: rect, in: context, size: size)
            }
        case .ink:
            guard let points = layer.points, points.count >= 2 else { return }
            let lineWidth = strokeLineWidth(layer, size: size)
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            addSmoothedInkPath(points, to: context, size: size)
            strokeWithEffects(layer, in: context, size: size) {
                context.strokePath()
            }
        case .arrow:
            guard let from = layer.from, let to = layer.to else { return }
            let start = from.pixelPoint(in: size)
            let end = to.pixelPoint(in: size)
            let lineWidth = strokeLineWidth(layer, size: size)
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            let endPointer = pointer(for: layer, endpoint: .end)
            if endPointer == "grow" || endPointer == "block" {
                drawRibbonArrow(
                    layer: layer,
                    start: start,
                    end: end,
                    color: color,
                    in: context,
                    size: size,
                    lineWidth: lineWidth,
                    style: endPointer
                )
            } else {
                switch arrowStyle(for: layer) {
                case "curved":
                    drawCurvedArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
                case "elbow":
                    drawElbowArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
                case "swoop":
                    drawSwoopArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
                case "shaped":
                    drawShapedArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
                default:
                    drawStraightArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
                }
            }
            if let label = layer.label, label != "line" {
                drawLabel(label, near: CGRect(origin: end, size: .zero), in: context, size: size)
            }
        case .label:
            guard let frame = layer.frame, let text = layer.text ?? layer.label else { return }
            if layer.noteStyle == "glass", let blur = layer.backgroundBlur, blur > 0 {
                drawAdaptiveGlassBackdrop(
                    image: image,
                    rect: frame.pixelRect(in: size),
                    blur: CGFloat(blur) * max(1, size.width / 1200),
                    cornerRadius: CGFloat(layer.cornerRadius ?? 8) * max(1, size.width / 1200),
                    in: context,
                    size: size
                )
            }
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
                textPreset: layer.textPreset,
                explicitTextColorHex: layer.textColor,
                backgroundColorHex: layer.backgroundColor,
                backgroundAlpha: layer.backgroundAlpha,
                borderColorHex: layer.borderColor,
                borderAlpha: layer.borderAlpha,
                borderWidth: layer.borderWidth,
                cornerRadius: layer.cornerRadius,
                paddingX: layer.paddingX,
                paddingY: layer.paddingY,
                shadow: layer.shadow ?? false,
                shadowColorHex: layer.shadowColor,
                shadowBlur: layer.shadowBlur,
                shadowOffsetY: layer.shadowOffsetY,
                inPlace: true
            )
        case .guide:
            drawGuides(layer: layer, color: color, in: context, size: size)
        }
    }

    private static func drawAdaptiveGlassBackdrop(
        image: CGImage,
        rect: CGRect,
        blur: CGFloat,
        cornerRadius: CGFloat,
        in context: CGContext,
        size: CGSize
    ) {
        let sourceScaleX = CGFloat(image.width) / max(1, size.width)
        let sourceScaleY = CGFloat(image.height) / max(1, size.height)
        let sourceRect = CGRect(
            x: rect.minX * sourceScaleX,
            y: rect.minY * sourceScaleY,
            width: rect.width * sourceScaleX,
            height: rect.height * sourceScaleY
        )
        let expansion = max(2, blur * max(sourceScaleX, sourceScaleY) * 2)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = sourceRect
            .insetBy(dx: -expansion, dy: -expansion)
            .intersection(imageBounds)
            .integral
        guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1,
              let cropped = image.cropping(to: cropRect) else {
            return
        }

        let input = CIImage(cgImage: cropped)
        let blurred = input
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blur * max(sourceScaleX, sourceScaleY)]
            )
            .cropped(to: input.extent)
        guard let output = materialCIContext.createCGImage(blurred, from: input.extent) else { return }

        let destination = CGRect(
            x: cropRect.minX / sourceScaleX,
            y: cropRect.minY / sourceScaleY,
            width: cropRect.width / sourceScaleX,
            height: cropRect.height / sourceScaleY
        )
        let clipPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        context.translateBy(x: destination.minX, y: destination.minY + destination.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(output, in: CGRect(origin: .zero, size: destination.size))
        context.restoreGState()
    }

    private static func drawPrivacyBlur(
        frame: CaptureMarkupRect,
        destinationRect: CGRect,
        sourceImage: CGImage,
        in context: CGContext,
        outputSize: CGSize
    ) {
        let sourceSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        let sourceRect = frame.pixelRect(in: sourceSize)
            .intersection(CGRect(origin: .zero, size: sourceSize))
            .integral
        guard sourceRect.width >= 1,
              sourceRect.height >= 1,
              let cropped = sourceImage.cropping(to: sourceRect) else {
            return
        }

        let input = CIImage(cgImage: cropped)
        let pixelScale = max(8, min(input.extent.width, input.extent.height) / 10)
        guard let filter = CIFilter(name: "CIPixellate") else { return }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(pixelScale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let pixelated = materialCIContext.createCGImage(output, from: input.extent) else {
            return
        }

        // Markup drawing is already in a top-left coordinate system. Unflip
        // locally so the CGImage crop is not mirrored inside the blur frame.
        context.saveGState()
        context.translateBy(x: destinationRect.minX, y: destinationRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(
            pixelated,
            in: CGRect(origin: .zero, size: destinationRect.size)
        )
        context.restoreGState()

        // A subtle edge makes the editable region discoverable without
        // re-exposing any source pixels.
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        context.setLineWidth(max(1, outputSize.width / 1600))
        context.stroke(destinationRect)
        context.restoreGState()
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
        if let points = layer.points {
            converted.points = points.map(convert(point:))
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

    private enum PointerEndpoint {
        case start
        case end
    }

    private static func normalizedPointerStyle(_ value: String?) -> String {
        guard let value else { return "open" }
        switch value {
        case "none", "open", "filled", "dot", "bar", "grow", "block":
            return value
        default:
            return "open"
        }
    }

    private static func arrowStyle(for layer: CaptureMarkupLayer) -> String {
        if layer.label == "line" {
            return "straight"
        }
        switch layer.arrowStyle {
        case "curved", "elbow", "swoop", "shaped":
            return layer.arrowStyle ?? "straight"
        default:
            return "straight"
        }
    }

    private static func curvedArrowControlPoint(layer: CaptureMarkupLayer, start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0.0001 else {
            return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        }
        let offset = CGFloat(layer.curveOffset ?? 0.2)
        return CGPoint(
            x: (start.x + end.x) / 2 - (dy / distance) * distance * offset,
            y: (start.y + end.y) / 2 + (dx / distance) * distance * offset
        )
    }

    private static func drawStraightArrow(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat
    ) {
        context.beginPath()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: start)
        context.addLine(to: end)
        strokeWithEffects(layer, in: context, size: size) {
            context.strokePath()
        }
        drawPointer(pointer(for: layer, endpoint: .start), at: start, from: end, color: color, in: context, size: size, lineWidth: lineWidth)
        drawPointer(pointer(for: layer, endpoint: .end), at: end, from: start, color: color, in: context, size: size, lineWidth: lineWidth)
    }

    private static func drawCurvedArrow(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat
    ) {
        let control = curvedArrowControlPoint(layer: layer, start: start, end: end)
        context.beginPath()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: start)
        context.addQuadCurve(to: end, control: control)
        strokeWithEffects(layer, in: context, size: size) {
            context.strokePath()
        }
        drawPointer(pointer(for: layer, endpoint: .start), at: start, from: control, color: color, in: context, size: size, lineWidth: lineWidth)
        drawPointer(pointer(for: layer, endpoint: .end), at: end, from: control, color: color, in: context, size: size, lineWidth: lineWidth)
    }

    private static func drawElbowArrow(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard abs(dx) >= 8, abs(dy) >= 8 else {
            drawStraightArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
            return
        }
        let corner = CGPoint(x: end.x, y: start.y)
        let radius = min(18, abs(dx) * 0.28, abs(dy) * 0.28)
        let signedXRadius = dx < 0 ? -radius : radius
        let signedYRadius = dy < 0 ? -radius : radius
        let before = CGPoint(x: corner.x - signedXRadius, y: corner.y)
        let after = CGPoint(x: corner.x, y: corner.y + signedYRadius)

        context.beginPath()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: start)
        context.addLine(to: before)
        context.addQuadCurve(to: after, control: corner)
        context.addLine(to: end)
        strokeWithEffects(layer, in: context, size: size) {
            context.strokePath()
        }
        drawPointer(pointer(for: layer, endpoint: .start), at: start, from: before, color: color, in: context, size: size, lineWidth: lineWidth)
        drawPointer(pointer(for: layer, endpoint: .end), at: end, from: after, color: color, in: context, size: size, lineWidth: lineWidth)
    }

    private static func swoopControlPoints(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint
    ) -> (first: CGPoint, second: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0.0001 else { return (start, end) }
        let normalX = -dy / distance
        let normalY = dx / distance
        let offset = distance * CGFloat(layer.curveOffset ?? 0.18)
        return (
            CGPoint(
                x: start.x + dx * 0.28 + normalX * offset,
                y: start.y + dy * 0.28 + normalY * offset
            ),
            CGPoint(
                x: start.x + dx * 0.72 - normalX * offset * 0.75,
                y: start.y + dy * 0.72 - normalY * offset * 0.75
            )
        )
    }

    private static func addSwoopPath(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        to context: CGContext
    ) -> (first: CGPoint, second: CGPoint) {
        let controls = swoopControlPoints(layer: layer, start: start, end: end)
        context.move(to: start)
        context.addCurve(to: end, control1: controls.first, control2: controls.second)
        return controls
    }

    private static func drawSwoopArrow(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat
    ) {
        context.saveGState()
        context.setStrokeColor(color.copy(alpha: 0.12) ?? color)
        context.setLineWidth(max(lineWidth + 3, lineWidth * 2.4))
        context.setLineCap(.round)
        context.beginPath()
        _ = addSwoopPath(layer: layer, start: start, end: end, to: context)
        context.strokePath()
        context.restoreGState()

        context.beginPath()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let controls = addSwoopPath(layer: layer, start: start, end: end, to: context)
        strokeWithEffects(layer, in: context, size: size) {
            context.strokePath()
        }
        drawPointer(pointer(for: layer, endpoint: .start), at: start, from: controls.first, color: color, in: context, size: size, lineWidth: lineWidth)
        drawPointer(pointer(for: layer, endpoint: .end), at: end, from: controls.second, color: color, in: context, size: size, lineWidth: lineWidth)
    }

    private static func sampledArrowPath(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        steps: Int = 40
    ) -> [CGPoint] {
        switch arrowStyle(for: layer) {
        case "curved":
            let control = curvedArrowControlPoint(layer: layer, start: start, end: end)
            return (0...steps).map { index in
                let t = CGFloat(index) / CGFloat(steps)
                let inverse = 1 - t
                return CGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                )
            }
        case "swoop":
            let controls = swoopControlPoints(layer: layer, start: start, end: end)
            return (0...steps).map { index in
                let t = CGFloat(index) / CGFloat(steps)
                let inverse = 1 - t
                return CGPoint(
                    x: inverse * inverse * inverse * start.x
                        + 3 * inverse * inverse * t * controls.first.x
                        + 3 * inverse * t * t * controls.second.x
                        + t * t * t * end.x,
                    y: inverse * inverse * inverse * start.y
                        + 3 * inverse * inverse * t * controls.first.y
                        + 3 * inverse * t * t * controls.second.y
                        + t * t * t * end.y
                )
            }
        default:
            return [start, end]
        }
    }

    private static func ribbonBodyPoints(
        _ points: [CGPoint],
        headLength: CGFloat
    ) -> (points: [CGPoint], neck: CGPoint, tip: CGPoint)? {
        guard points.count >= 2, let tip = points.last else { return nil }
        var lengths: [CGFloat] = [0]
        for index in 1..<points.count {
            lengths.append(lengths[index - 1] + hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            ))
        }
        guard let total = lengths.last, total >= 18 else { return nil }
        let neckDistance = max(total * 0.52, total - min(headLength, total * 0.38))
        var index = 1
        while index < lengths.count, lengths[index] < neckDistance {
            index += 1
        }
        let beforeIndex = max(0, index - 1)
        let afterIndex = min(points.count - 1, index)
        let span = max(0.0001, lengths[afterIndex] - lengths[beforeIndex])
        let progress = (neckDistance - lengths[beforeIndex]) / span
        let neck = CGPoint(
            x: points[beforeIndex].x + (points[afterIndex].x - points[beforeIndex].x) * progress,
            y: points[beforeIndex].y + (points[afterIndex].y - points[beforeIndex].y) * progress
        )
        return (Array(points[..<afterIndex]) + [neck], neck, tip)
    }

    private static func normal(at index: Int, in points: [CGPoint]) -> CGPoint {
        let previous = points[max(0, index - 1)]
        let next = points[min(points.count - 1, index + 1)]
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        let distance = max(0.0001, hypot(dx, dy))
        return CGPoint(x: -dy / distance, y: dx / distance)
    }

    private static func drawRibbonArrow(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat,
        style: String
    ) {
        let block = style == "block"
        let headLength = max(block ? 20 : 22, lineWidth * (block ? 5.2 : 5.4))
        guard let body = ribbonBodyPoints(
            sampledArrowPath(layer: layer, start: start, end: end),
            headLength: headLength
        ) else {
            var fallback = layer
            fallback.pointerEnd = "filled"
            fallback.pointerStyle = "filled"
            drawStraightArrow(layer: fallback, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
            return
        }

        let startHalf = block ? max(2.6, lineWidth * 0.95) : max(0.55, lineWidth * 0.16)
        let endHalf = block ? startHalf : max(1.7, lineWidth * 0.88)
        let headHalf = block
            ? max(7, endHalf * 2.05, lineWidth * 2.2)
            : max(7, endHalf * 1.75, lineWidth * 1.9)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for (index, point) in body.points.enumerated() {
            let progress = CGFloat(index) / CGFloat(max(1, body.points.count - 1))
            let half = startHalf + (endHalf - startHalf) * pow(progress, 0.78)
            let perpendicular = normal(at: index, in: body.points)
            left.append(CGPoint(
                x: point.x + perpendicular.x * half,
                y: point.y + perpendicular.y * half
            ))
            right.append(CGPoint(
                x: point.x - perpendicular.x * half,
                y: point.y - perpendicular.y * half
            ))
        }
        let neckPath = body.points + [body.tip]
        let neckNormal = normal(at: body.points.count - 1, in: neckPath)
        let headLeft = CGPoint(
            x: body.neck.x + neckNormal.x * headHalf,
            y: body.neck.y + neckNormal.y * headHalf
        )
        let headRight = CGPoint(
            x: body.neck.x - neckNormal.x * headHalf,
            y: body.neck.y - neckNormal.y * headHalf
        )

        let path = CGMutablePath()
        guard let first = left.first else { return }
        path.move(to: first)
        for point in left.dropFirst() { path.addLine(to: point) }
        path.addLine(to: headLeft)
        path.addLine(to: body.tip)
        path.addLine(to: headRight)
        for point in right.reversed() { path.addLine(to: point) }
        path.closeSubpath()

        context.saveGState()
        if layer.shadow == true {
            let baseUnit = max(1, size.width / 600)
            let shadowColor = parseColor(layer.shadowColor ?? "rgba(0, 0, 0, 0.28)")
            let offset = CGSize(width: 0, height: CGFloat(layer.shadowOffsetY ?? 5) * baseUnit)
            context.setShadow(offset: offset, blur: CGFloat(layer.shadowBlur ?? 12) * baseUnit, color: shadowColor)
        }
        context.addPath(path)
        context.setFillColor(color.copy(alpha: 0.95) ?? color)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.copy(alpha: 0.9) ?? color)
        context.setLineWidth(max(0.8, lineWidth * 0.22))
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawShapedArrow(
        layer: CaptureMarkupLayer,
        start: CGPoint,
        end: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance >= max(24, lineWidth * 8) else {
            drawStraightArrow(layer: layer, start: start, end: end, color: color, in: context, size: size, lineWidth: lineWidth)
            return
        }

        let ux = dx / distance
        let uy = dy / distance
        let px = -uy
        let py = ux
        let tailHalf = max(5, lineWidth * 1.35)
        let headHalf = max(tailHalf * 2.2, lineWidth * 3.2)
        let headLength = min(max(18, lineWidth * 5.2), distance * 0.48)
        let neckX = distance - headLength

        func pointAlong(_ x: CGFloat, _ half: CGFloat) -> CGPoint {
            CGPoint(
                x: start.x + ux * x + px * half,
                y: start.y + uy * x + py * half
            )
        }

        let path = CGMutablePath()
        path.move(to: pointAlong(0, tailHalf))
        path.addLine(to: pointAlong(neckX, tailHalf))
        path.addLine(to: pointAlong(neckX, headHalf))
        path.addLine(to: pointAlong(distance, 0))
        path.addLine(to: pointAlong(neckX, -headHalf))
        path.addLine(to: pointAlong(neckX, -tailHalf))
        path.addLine(to: pointAlong(0, -tailHalf))
        path.closeSubpath()

        context.saveGState()
        if layer.shadow == true {
            let baseUnit = max(1, size.width / 600)
            let shadowColor = parseColor(layer.shadowColor ?? "rgba(0, 0, 0, 0.28)")
            let offset = CGSize(width: 0, height: CGFloat(layer.shadowOffsetY ?? 5) * baseUnit)
            context.setShadow(offset: offset, blur: CGFloat(layer.shadowBlur ?? 12) * baseUnit, color: shadowColor)
        }
        context.addPath(path)
        context.setFillColor(color.copy(alpha: 0.94) ?? color)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.copy(alpha: 0.92) ?? color)
        context.setLineWidth(max(1, lineWidth * 0.38))
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func pointer(for layer: CaptureMarkupLayer, endpoint: PointerEndpoint) -> String {
        let raw = endpoint == .start ? layer.pointerStart : layer.pointerEnd
        if let raw {
            return normalizedPointerStyle(raw)
        }
        if layer.pointerStart != nil || layer.pointerEnd != nil {
            return "none"
        }
        if layer.label == "line" {
            return "none"
        }
        return endpoint == .end ? normalizedPointerStyle(layer.pointerStyle) : "none"
    }

    private static func drawPointer(
        _ style: String,
        at tip: CGPoint,
        from tail: CGPoint,
        color: CGColor,
        in context: CGContext,
        size: CGSize,
        lineWidth: CGFloat
    ) {
        guard style != "none" else { return }
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let headLength = max(8, size.width / 120)
        let left = CGPoint(
            x: tip.x - headLength * cos(angle - .pi / 6),
            y: tip.y - headLength * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: tip.x - headLength * cos(angle + .pi / 6),
            y: tip.y - headLength * sin(angle + .pi / 6)
        )

        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch style {
        case "filled":
            context.move(to: tip)
            context.addLine(to: left)
            context.addLine(to: right)
            context.closePath()
            context.fillPath()
        case "dot":
            let radius = max(3.5, headLength * 0.32)
            context.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
        case "bar":
            let length = headLength * 0.74
            let px = cos(angle + .pi / 2) * length
            let py = sin(angle + .pi / 2) * length
            context.move(to: CGPoint(x: tip.x - px, y: tip.y - py))
            context.addLine(to: CGPoint(x: tip.x + px, y: tip.y + py))
            context.strokePath()
        default:
            context.move(to: tip)
            context.addLine(to: left)
            context.move(to: tip)
            context.addLine(to: right)
            context.strokePath()
        }

        context.restoreGState()
    }

    private struct LabelStyle {
        var plain: Bool
        var textColorHex: String
        var backgroundColorHex: String
        var backgroundAlpha: CGFloat
        var borderColorHex: String
        var borderAlpha: CGFloat
    }

    private static func labelPreset(_ value: String?) -> LabelStyle {
        switch value {
        case "on-dark":
            return LabelStyle(
                plain: false,
                textColorHex: "#232423",
                backgroundColorHex: "#F4E8D4",
                backgroundAlpha: 0.94,
                borderColorHex: "#4F7DFF",
                borderAlpha: 0.34
            )
        case "accent":
            return LabelStyle(
                plain: false,
                textColorHex: "#101A33",
                backgroundColorHex: "#AFC5FF",
                backgroundAlpha: 0.96,
                borderColorHex: "#2D5BDB",
                borderAlpha: 0.34
            )
        case "plain":
            return LabelStyle(
                plain: true,
                textColorHex: "#4F7DFF",
                backgroundColorHex: "#FFFFFF",
                backgroundAlpha: 0,
                borderColorHex: "#4F7DFF",
                borderAlpha: 0
            )
        default:
            return LabelStyle(
                plain: false,
                textColorHex: "#FFFFFF",
                backgroundColorHex: "#14181E",
                backgroundAlpha: 0.86,
                borderColorHex: "#FFFFFF",
                borderAlpha: 0.22
            )
        }
    }

    private static func labelStyle(
        preset: String?,
        plain: Bool,
        fallbackTextColorHex: String?,
        explicitTextColorHex: String?,
        backgroundColorHex: String?,
        backgroundAlpha: Double?,
        borderColorHex: String?,
        borderAlpha: Double?
    ) -> LabelStyle {
        var style = labelPreset(plain ? "plain" : preset)
        style.plain = plain || style.plain
        style.textColorHex = explicitTextColorHex ?? (style.plain ? (fallbackTextColorHex ?? style.textColorHex) : style.textColorHex)
        if let backgroundColorHex {
            style.backgroundColorHex = backgroundColorHex
        }
        if let backgroundAlpha {
            style.backgroundAlpha = CGFloat(backgroundAlpha)
        }
        if let borderColorHex {
            style.borderColorHex = borderColorHex
        }
        if let borderAlpha {
            style.borderAlpha = CGFloat(borderAlpha)
        }
        return style
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
        textPreset: String? = nil,
        explicitTextColorHex: String? = nil,
        backgroundColorHex: String? = nil,
        backgroundAlpha: Double? = nil,
        borderColorHex: String? = nil,
        borderAlpha: Double? = nil,
        borderWidth: Double? = nil,
        cornerRadius: Double? = nil,
        paddingX: Double? = nil,
        paddingY: Double? = nil,
        shadow: Bool = false,
        shadowColorHex: String? = nil,
        shadowBlur: Double? = nil,
        shadowOffsetY: Double? = nil,
        inPlace: Bool = false
    ) {
        #if canImport(AppKit)
        let style = labelStyle(
            preset: textPreset,
            plain: plain,
            fallbackTextColorHex: textColorHex,
            explicitTextColorHex: explicitTextColorHex,
            backgroundColorHex: backgroundColorHex,
            backgroundAlpha: backgroundAlpha,
            borderColorHex: borderColorHex,
            borderAlpha: borderAlpha
        )
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

        let textColor = NSColor(cgColor: parseColor(style.textColorHex)) ?? .white
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let measured = (text as NSString).size(withAttributes: attrs)
        let styleUnit = max(1, size.width / 1200)
        let padding = CGSize(
            width: CGFloat(paddingX ?? 8) * styleUnit,
            height: CGFloat(paddingY ?? 5) * styleUnit
        )
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
            size: inPlace
                ? rect.size
                : CGSize(
                    width: measured.width + padding.width * 2,
                    height: measured.height + padding.height * 2
                )
        )

        if !style.plain {
            let radius = CGFloat(cornerRadius ?? 6) * styleUnit
            let labelPath = CGPath(
                roundedRect: labelRect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            context.saveGState()
            if shadow {
                let shadowColor = parseColor(shadowColorHex ?? "rgba(0, 0, 0, 0.18)")
                context.setShadow(
                    offset: CGSize(width: 0, height: CGFloat(shadowOffsetY ?? 2) * styleUnit),
                    blur: CGFloat(shadowBlur ?? 8) * styleUnit,
                    color: shadowColor
                )
            }
            context.setFillColor(parseColor(style.backgroundColorHex).copy(alpha: style.backgroundAlpha) ?? parseColor(style.backgroundColorHex))
            context.addPath(labelPath)
            context.fillPath()
            context.restoreGState()
            if style.borderAlpha > 0 {
                context.setStrokeColor(parseColor(style.borderColorHex).copy(alpha: style.borderAlpha) ?? parseColor(style.borderColorHex))
                context.setLineWidth(max(0.5, CGFloat(borderWidth ?? 1) * styleUnit))
                context.addPath(labelPath)
                context.strokePath()
            }
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
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        if lowered.hasPrefix("rgb"),
           let open = raw.firstIndex(of: "("),
           let close = raw.lastIndex(of: ")"),
           open < close {
            let body = raw[raw.index(after: open)..<close]
            let parts = body.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count >= 3,
               let red = Double(parts[0]),
               let green = Double(parts[1]),
               let blue = Double(parts[2]) {
                let alpha = parts.count >= 4 ? (Double(parts[3]) ?? 1) : 1
                return CGColor(
                    red: CGFloat(min(max(red / 255, 0), 1)),
                    green: CGFloat(min(max(green / 255, 0), 1)),
                    blue: CGFloat(min(max(blue / 255, 0), 1)),
                    alpha: CGFloat(min(max(alpha, 0), 1))
                )
            }
        }

        var cleaned = raw
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return CGColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1)
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
