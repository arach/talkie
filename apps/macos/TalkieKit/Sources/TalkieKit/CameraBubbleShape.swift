import Foundation

public enum CameraBubbleShape: String, CaseIterable, Codable, Identifiable, Sendable {
    case circle
    case roundedSquare = "rounded-square"
    case widescreen

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .circle: "Circle"
        case .roundedSquare: "Soft square"
        case .widescreen: "Wide"
        }
    }

    public var symbolName: String {
        switch self {
        case .circle: "circle"
        case .roundedSquare: "square.roundedrect"
        case .widescreen: "rectangle.ratio.16.to.9"
        }
    }

    public func dimensions(for size: CameraBubbleSize) -> CGSize {
        switch self {
        case .circle, .roundedSquare:
            CGSize(width: size.points, height: size.points)
        case .widescreen:
            CGSize(width: size.points * 1.55, height: size.points)
        }
    }

    public func cornerRadius(for size: CGSize) -> CGFloat {
        switch self {
        case .circle: min(size.width, size.height) / 2
        case .roundedSquare: min(size.width, size.height) * 0.23
        case .widescreen: min(size.width, size.height) * 0.2
        }
    }
}
