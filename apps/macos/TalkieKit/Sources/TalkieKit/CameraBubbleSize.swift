import Foundation

public enum CameraBubbleSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small
    case standard
    case large
    case extraLarge = "extra-large"

    public var id: String { rawValue }

    public var points: CGFloat {
        switch self {
        case .small: 80
        case .standard: 100
        case .large: 130
        case .extraLarge: 168
        }
    }

    public var label: String {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "XL"
        }
    }
}
