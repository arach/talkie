//
//  CaptureMarkupDocument.swift
//  TalkieKit
//
//  Non-destructive capture/media markup sidecar schema.
//

import CoreGraphics
import Foundation

public struct CaptureMarkupDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 3

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
    case ellipse
    case arrow
    case label
    case guide
    case highlight
    case ink
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
    /// Freehand path points for `.ink` layers, normalized to the same basis as
    /// `frame`/`from`/`to`.
    public var points: [CaptureMarkupPoint]?
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
    public var lineHeight: Double?
    /// Label typeface family: "sans" | "serif" | "mono". Optional so older
    /// sidecars (and shape tags) keep the historical mono rendering.
    public var fontFamily: String?
    /// Label weight / slant. Optional → false. `.label` layers only.
    public var bold: Bool?
    public var italic: Bool?
    /// When true, the label draws as plain colored text instead of the default
    /// white-on-dark pill. `.label` layers only.
    public var plain: Bool?
    /// Label contrast preset: "on-light" | "on-dark" | "accent" | "plain".
    /// Optional so older sidecars keep the historical pill rendering.
    public var textPreset: String?
    /// Optional explicit label colors. New presets write these so the web
    /// canvas and headless exporter stay in lockstep; older labels leave them
    /// nil and use renderer defaults.
    public var textColor: String?
    public var backgroundColor: String?
    public var backgroundAlpha: Double?
    /// Optional interior treatment for rectangle and ellipse annotations.
    /// `fillStyle` is the named UI treatment; color/alpha are persisted so
    /// renderers do not need to know the preset table.
    public var fillStyle: String?
    public var fillColor: String?
    public var fillAlpha: Double?
    public var borderColor: String?
    public var borderAlpha: Double?
    public var borderWidth: Double?
    public var cornerRadius: Double?
    public var paddingX: Double?
    public var paddingY: Double?
    /// Radius in screen points for an adaptive material backdrop. The live
    /// overlay samples and blurs the pixels beneath the label; the headless
    /// renderer repeats the blur from the source image during export.
    public var backgroundBlur: Double?
    /// Optional visual preset/effect hints for live markup. Renderers that do
    /// not know these fields can ignore them and still draw the base layer.
    public var intent: String?
    public var stylePreset: String?
    public var noteStyle: String?
    public var lineStyle: String?
    public var lineDash: [Double]?
    public var shadow: Bool?
    public var shadowColor: String?
    public var shadowBlur: Double?
    public var shadowOffsetY: Double?
    /// Arrow endpoint styling. Values are "none" | "open" | "filled" | "dot"
    /// | "bar" | "grow" | "block". Grow and block are filled body treatments
    /// whose geometry follows `arrowStyle`. Optional preserves legacy arrows:
    /// end pointer only unless `label == "line"`.
    public var pointerStart: String?
    public var pointerEnd: String?
    public var pointerStyle: String?
    /// Arrow body/path styling. Values are "straight" | "curved" | "elbow"
    /// | "swoop" | "shaped".
    /// Optional preserves legacy straight arrows.
    public var arrowStyle: String?
    public var curveOffset: Double?
    public var label: String?
    public var orientation: String?
    public var interval: Double?
    /// Optional media timing for video or time-based artifacts. Values are
    /// seconds from the start of the source asset. A nil range means the layer
    /// applies to the whole still image or the current untimed artifact.
    public var startTime: Double?
    public var endTime: Double?
    /// Agent turn provenance for layers produced by capture markup runs.
    /// Optional so older sidecars and hand-drawn layers remain unchanged.
    public var turnPass: Int?
    public var turnInstruction: String?
    public var turnModel: String?
    public var turnSummary: String?
    public var turnElapsed: Double?
    public var visible: Bool
    public var author: CaptureMarkupAuthor

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case frame
        case source
        case from
        case to
        case points
        case text
        case color
        case strokeWidth
        case fontSize
        case lineHeight
        case fontFamily
        case bold
        case italic
        case plain
        case textPreset
        case textColor
        case backgroundColor
        case backgroundAlpha
        case fillStyle
        case fillColor
        case fillAlpha
        case borderColor
        case borderAlpha
        case borderWidth
        case cornerRadius
        case paddingX
        case paddingY
        case backgroundBlur
        case intent
        case stylePreset
        case noteStyle
        case lineStyle
        case lineDash
        case shadow
        case shadowColor
        case shadowBlur
        case shadowOffsetY
        case pointerStart
        case pointerEnd
        case pointerStyle
        case arrowStyle
        case curveOffset
        case label
        case orientation
        case interval
        case startTime
        case endTime
        case turnPass
        case turnInstruction
        case turnModel
        case turnSummary
        case turnElapsed
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
        points: [CaptureMarkupPoint]? = nil,
        text: String? = nil,
        color: String = "#4F7DFF",
        strokeWidth: Double? = nil,
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        fontFamily: String? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        plain: Bool? = nil,
        textPreset: String? = nil,
        textColor: String? = nil,
        backgroundColor: String? = nil,
        backgroundAlpha: Double? = nil,
        fillStyle: String? = nil,
        fillColor: String? = nil,
        fillAlpha: Double? = nil,
        borderColor: String? = nil,
        borderAlpha: Double? = nil,
        borderWidth: Double? = nil,
        cornerRadius: Double? = nil,
        paddingX: Double? = nil,
        paddingY: Double? = nil,
        backgroundBlur: Double? = nil,
        intent: String? = nil,
        stylePreset: String? = nil,
        noteStyle: String? = nil,
        lineStyle: String? = nil,
        lineDash: [Double]? = nil,
        shadow: Bool? = nil,
        shadowColor: String? = nil,
        shadowBlur: Double? = nil,
        shadowOffsetY: Double? = nil,
        pointerStart: String? = nil,
        pointerEnd: String? = nil,
        pointerStyle: String? = nil,
        arrowStyle: String? = nil,
        curveOffset: Double? = nil,
        label: String? = nil,
        orientation: String? = nil,
        interval: Double? = nil,
        startTime: Double? = nil,
        endTime: Double? = nil,
        turnPass: Int? = nil,
        turnInstruction: String? = nil,
        turnModel: String? = nil,
        turnSummary: String? = nil,
        turnElapsed: Double? = nil,
        visible: Bool = true,
        author: CaptureMarkupAuthor = .agent
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.source = source
        self.from = from
        self.to = to
        self.points = points
        self.text = text
        self.color = color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontFamily = fontFamily
        self.bold = bold
        self.italic = italic
        self.plain = plain
        self.textPreset = textPreset
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.backgroundAlpha = backgroundAlpha
        self.fillStyle = fillStyle
        self.fillColor = fillColor
        self.fillAlpha = fillAlpha
        self.borderColor = borderColor
        self.borderAlpha = borderAlpha
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.backgroundBlur = backgroundBlur
        self.intent = intent
        self.stylePreset = stylePreset
        self.noteStyle = noteStyle
        self.lineStyle = lineStyle
        self.lineDash = lineDash
        self.shadow = shadow
        self.shadowColor = shadowColor
        self.shadowBlur = shadowBlur
        self.shadowOffsetY = shadowOffsetY
        self.pointerStart = pointerStart
        self.pointerEnd = pointerEnd
        self.pointerStyle = pointerStyle
        self.arrowStyle = arrowStyle
        self.curveOffset = curveOffset
        self.label = label
        self.orientation = orientation
        self.interval = interval
        self.startTime = startTime
        self.endTime = endTime
        self.turnPass = turnPass
        self.turnInstruction = turnInstruction
        self.turnModel = turnModel
        self.turnSummary = turnSummary
        self.turnElapsed = turnElapsed
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
        points = try container.decodeIfPresent([CaptureMarkupPoint].self, forKey: .points)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#4F7DFF"
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        lineHeight = try container.decodeIfPresent(Double.self, forKey: .lineHeight)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic)
        plain = try container.decodeIfPresent(Bool.self, forKey: .plain)
        textPreset = try container.decodeIfPresent(String.self, forKey: .textPreset)
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor)
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        backgroundAlpha = try container.decodeIfPresent(Double.self, forKey: .backgroundAlpha)
        fillStyle = try container.decodeIfPresent(String.self, forKey: .fillStyle)
        fillColor = try container.decodeIfPresent(String.self, forKey: .fillColor)
        fillAlpha = try container.decodeIfPresent(Double.self, forKey: .fillAlpha)
        borderColor = try container.decodeIfPresent(String.self, forKey: .borderColor)
        borderAlpha = try container.decodeIfPresent(Double.self, forKey: .borderAlpha)
        borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        paddingX = try container.decodeIfPresent(Double.self, forKey: .paddingX)
        paddingY = try container.decodeIfPresent(Double.self, forKey: .paddingY)
        backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur)
        intent = try container.decodeIfPresent(String.self, forKey: .intent)
        stylePreset = try container.decodeIfPresent(String.self, forKey: .stylePreset)
        noteStyle = try container.decodeIfPresent(String.self, forKey: .noteStyle)
        lineStyle = try container.decodeIfPresent(String.self, forKey: .lineStyle)
        lineDash = try container.decodeIfPresent([Double].self, forKey: .lineDash)
        shadow = try container.decodeIfPresent(Bool.self, forKey: .shadow)
        shadowColor = try container.decodeIfPresent(String.self, forKey: .shadowColor)
        shadowBlur = try container.decodeIfPresent(Double.self, forKey: .shadowBlur)
        shadowOffsetY = try container.decodeIfPresent(Double.self, forKey: .shadowOffsetY)
        pointerStart = try container.decodeIfPresent(String.self, forKey: .pointerStart)
        pointerEnd = try container.decodeIfPresent(String.self, forKey: .pointerEnd)
        pointerStyle = try container.decodeIfPresent(String.self, forKey: .pointerStyle)
        arrowStyle = try container.decodeIfPresent(String.self, forKey: .arrowStyle)
        curveOffset = try container.decodeIfPresent(Double.self, forKey: .curveOffset)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        orientation = try container.decodeIfPresent(String.self, forKey: .orientation)
        interval = try container.decodeIfPresent(Double.self, forKey: .interval)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
        turnPass = try container.decodeIfPresent(Int.self, forKey: .turnPass)
        turnInstruction = try container.decodeIfPresent(String.self, forKey: .turnInstruction)
        turnModel = try container.decodeIfPresent(String.self, forKey: .turnModel)
        turnSummary = try container.decodeIfPresent(String.self, forKey: .turnSummary)
        turnElapsed = try container.decodeIfPresent(Double.self, forKey: .turnElapsed)
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
