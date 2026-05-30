//
//  CaptureMarkupDocument.swift
//  TalkieKit
//
//  Non-destructive screenshot markup sidecar schema.
//

import CoreGraphics
import Foundation

public struct CaptureMarkupDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 2

    public var version: Int
    public var imageWidth: Double
    public var imageHeight: Double
    public var viewport: CaptureMarkupViewport?
    public var layers: [CaptureMarkupLayer]

    public init(
        version: Int = CaptureMarkupDocument.currentVersion,
        imageWidth: Double,
        imageHeight: Double,
        viewport: CaptureMarkupViewport? = nil,
        layers: [CaptureMarkupLayer] = []
    ) {
        self.version = version
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.viewport = viewport
        self.layers = layers
    }

    public init(imageSize: CGSize, layers: [CaptureMarkupLayer] = []) {
        self.init(
            imageWidth: Double(imageSize.width),
            imageHeight: Double(imageSize.height),
            layers: layers
        )
    }

    public var imageSize: CGSize {
        CGSize(width: imageWidth, height: imageHeight)
    }
}

/// Logical Capture Markup workspace. Layer frames/points remain normalized
/// 0…1 values; when present, this viewport is the basis for those values and
/// the source image is drawn at `imageX`/`imageY` with `imageScale`.
public struct CaptureMarkupViewport: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var imageX: Double
    public var imageY: Double
    public var imageScale: Double

    public init(
        width: Double,
        height: Double,
        imageX: Double,
        imageY: Double,
        imageScale: Double
    ) {
        self.width = width
        self.height = height
        self.imageX = imageX
        self.imageY = imageY
        self.imageScale = imageScale
    }
}

public enum CaptureMarkupLayerKind: String, Codable, Sendable {
    case rect
    case arrow
    case label
    case guide
    case highlight
    /// A cloned region of the source image: pixels copied from `source` and
    /// drawn at `frame`. Non-destructive — no bitmap is stored; the pixels are
    /// recomputed from the original image on every render.
    case patch
}

public enum CaptureMarkupAuthor: String, Codable, Sendable {
    case agent
    case user
}

/// Normalized rect in 0…1 coordinates (origin top-left).
public struct CaptureMarkupRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func pixelRect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    public static func normalized(from rect: CGRect, in size: CGSize) -> CaptureMarkupRect {
        guard size.width > 0, size.height > 0 else {
            return CaptureMarkupRect(x: 0, y: 0, width: 0, height: 0)
        }
        return CaptureMarkupRect(
            x: rect.origin.x / size.width,
            y: rect.origin.y / size.height,
            width: rect.width / size.width,
            height: rect.height / size.height
        )
    }
}

public struct CaptureMarkupLayer: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: CaptureMarkupLayerKind
    public var frame: CaptureMarkupRect?
    /// Copy-from region for `.patch` layers (normalized, same basis as `frame`).
    public var source: CaptureMarkupRect?
    public var from: CaptureMarkupPoint?
    public var to: CaptureMarkupPoint?
    public var text: String?
    public var color: String
    /// Relative stroke weight (the web canvas interprets `2` as the historical
    /// default `max(2, imageWidth/600)`). Optional so older sidecars that never
    /// carried it keep rendering unchanged. Set by the markup toolbar's width
    /// picker — both at create time and when restyling a selected layer.
    public var strokeWidth: Double?
    /// Relative label font size, same convention as `strokeWidth`. Only
    /// meaningful for `.label` layers.
    public var fontSize: Double?
    /// Label typeface family: "sans" | "serif" | "mono". Optional so older
    /// sidecars (and shape tags) keep the historical mono rendering.
    public var fontFamily: String?
    /// Label weight / slant. Optional → false. `.label` layers only.
    public var bold: Bool?
    public var italic: Bool?
    /// When true, the label draws as plain colored text instead of the default
    /// white-on-dark pill. `.label` layers only.
    public var plain: Bool?
    public var label: String?
    public var orientation: String?
    public var interval: Double?
    public var visible: Bool
    public var author: CaptureMarkupAuthor

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case frame
        case source
        case from
        case to
        case text
        case color
        case strokeWidth
        case fontSize
        case fontFamily
        case bold
        case italic
        case plain
        case label
        case orientation
        case interval
        case visible
        case author
    }

    public init(
        id: String = UUID().uuidString,
        kind: CaptureMarkupLayerKind,
        frame: CaptureMarkupRect? = nil,
        source: CaptureMarkupRect? = nil,
        from: CaptureMarkupPoint? = nil,
        to: CaptureMarkupPoint? = nil,
        text: String? = nil,
        color: String = "#C47D1C",
        strokeWidth: Double? = nil,
        fontSize: Double? = nil,
        fontFamily: String? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        plain: Bool? = nil,
        label: String? = nil,
        orientation: String? = nil,
        interval: Double? = nil,
        visible: Bool = true,
        author: CaptureMarkupAuthor = .agent
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.source = source
        self.from = from
        self.to = to
        self.text = text
        self.color = color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.bold = bold
        self.italic = italic
        self.plain = plain
        self.label = label
        self.orientation = orientation
        self.interval = interval
        self.visible = visible
        self.author = author
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decode(CaptureMarkupLayerKind.self, forKey: .kind)
        frame = try container.decodeIfPresent(CaptureMarkupRect.self, forKey: .frame)
        source = try container.decodeIfPresent(CaptureMarkupRect.self, forKey: .source)
        from = try container.decodeIfPresent(CaptureMarkupPoint.self, forKey: .from)
        to = try container.decodeIfPresent(CaptureMarkupPoint.self, forKey: .to)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#C47D1C"
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic)
        plain = try container.decodeIfPresent(Bool.self, forKey: .plain)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        orientation = try container.decodeIfPresent(String.self, forKey: .orientation)
        interval = try container.decodeIfPresent(Double.self, forKey: .interval)
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        author = try container.decodeIfPresent(CaptureMarkupAuthor.self, forKey: .author) ?? .agent
    }
}

public struct CaptureMarkupPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func pixelPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}

/// Single layer operation from an agent plan.
public struct CaptureMarkupLayerOp: Codable, Sendable {
    public var action: String
    public var layer: CaptureMarkupLayer?

    public init(action: String, layer: CaptureMarkupLayer? = nil) {
        self.action = action
        self.layer = layer
    }
}

public enum CaptureMarkupDocumentError: Error, Sendable {
    case invalidImageSize
    case layerNotFound(String)
    case decodeFailed
}

public extension CaptureMarkupDocument {
    mutating func apply(ops: [CaptureMarkupLayerOp]) {
        for op in ops {
            switch op.action {
            case "add":
                if let layer = op.layer {
                    layers.append(layer)
                }
            case "update":
                if let layer = op.layer,
                   let index = layers.firstIndex(where: { $0.id == layer.id }) {
                    layers[index] = layer
                }
            case "remove":
                if let id = op.layer?.id {
                    layers.removeAll { $0.id == id }
                }
            default:
                break
            }
        }
    }

    mutating func removeLayer(id: String) {
        layers.removeAll { $0.id == id }
    }
}
