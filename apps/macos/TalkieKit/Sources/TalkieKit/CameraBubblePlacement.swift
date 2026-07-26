public enum CameraBubblePlacement: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeading = "top-leading"
    case topTrailing = "top-trailing"
    case bottomLeading = "bottom-leading"
    case bottomTrailing = "bottom-trailing"
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .topLeading: "Top left"
        case .topTrailing: "Top right"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        case .custom: "Custom"
        }
    }

    public var symbolName: String {
        switch self {
        case .topLeading: "arrow.up.left"
        case .topTrailing: "arrow.up.right"
        case .bottomLeading: "arrow.down.left"
        case .bottomTrailing: "arrow.down.right"
        case .custom: "move.3d"
        }
    }
}
