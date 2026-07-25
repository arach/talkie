//
//  CaptureMarkupAutoBlur.swift
//  TalkieKit
//
//  Converts local OCR geometry into editable privacy-blur markup layers.
//

import Foundation

public enum CaptureMarkupAutoBlur {
    public static let layerLabel = "BLUR"
    public static let stylePreset = "auto-blur-text"

    public static func layers(
        for result: OCRGeometryResult,
        minimumConfidence: Float = 0.2,
        paddingPixels: Double = 4
    ) -> [CaptureMarkupLayer] {
        guard result.imageWidth > 0, result.imageHeight > 0 else { return [] }

        return result.observations.compactMap { observation in
            guard observation.confidence >= minimumConfidence,
                  !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let rect = padded(
                observation.markupRect,
                imageWidth: result.imageWidth,
                imageHeight: result.imageHeight,
                paddingPixels: paddingPixels
            )
            guard rect.width > 0, rect.height > 0 else { return nil }

            return CaptureMarkupLayer(
                kind: .highlight,
                frame: rect,
                color: "#646464",
                intent: "privacy",
                stylePreset: stylePreset,
                label: layerLabel,
                author: .user
            )
        }
    }

    public static func isAutoBlurLayer(_ layer: CaptureMarkupLayer) -> Bool {
        layer.kind == .highlight
            && layer.label == layerLabel
            && layer.stylePreset == stylePreset
    }

    private static func padded(
        _ rect: CaptureMarkupRect,
        imageWidth: Double,
        imageHeight: Double,
        paddingPixels: Double
    ) -> CaptureMarkupRect {
        let horizontalPadding = max(
            paddingPixels / imageWidth,
            min(0.012, rect.height * 0.18)
        )
        let verticalPadding = max(
            paddingPixels / imageHeight,
            min(0.012, rect.height * 0.12)
        )
        let minX = max(0, rect.x - horizontalPadding)
        let minY = max(0, rect.y - verticalPadding)
        let maxX = min(1, rect.x + rect.width + horizontalPadding)
        let maxY = min(1, rect.y + rect.height + verticalPadding)
        return CaptureMarkupRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }
}
