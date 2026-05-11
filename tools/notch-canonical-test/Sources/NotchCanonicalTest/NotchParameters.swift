import CoreGraphics

struct NotchParameters: Equatable {
    var pokeOut: CGFloat = 40
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 34
    var height: CGFloat = 36
    var topOuterRadius: CGFloat = 0
    var topInnerRadius: CGFloat = 18
    var bottomRadius: CGFloat = 12
    var notchOverlap: CGFloat = 6
}

enum NotchLiveBridge {
    static let suiteName = "to.talkie.app.notch.lab"
    static let hoverPokeOutKey = "hoverPokeOut"
    static let activePokeOutKey = "activePokeOut"
    static let topOuterRadiusKey = "topOuterRadius"
    static let leftTopOuterRadiusKey = "leftTopOuterRadius"
    static let rightTopOuterRadiusKey = "rightTopOuterRadius"
    static let topInnerRadiusKey = "topInnerRadius"
    static let bottomRadiusKey = "bottomRadius"
    static let notchOverlapKey = "notchOverlap"
    static let innerCurveModeKey = "innerCurveMode"
}

enum InnerCurveMode: String, CaseIterable, Identifiable {
    case canonicalDownward
    case hardCorner
    case mirroredUpward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .canonicalDownward:
            return "Canonical"
        case .hardCorner:
            return "Hard Corner"
        case .mirroredUpward:
            return "Mirrored"
        }
    }

    var subtitle: String {
        switch self {
        case .canonicalDownward:
            return "Control at (t, 0), bows downward into each wing."
        case .hardCorner:
            return "No inner curve, straight top-edge transition."
        case .mirroredUpward:
            return "Deliberately wrong control, bows in the opposite direction."
        }
    }
}
