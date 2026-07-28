#if canImport(UIKit) && !os(watchOS)

/// Visual language for Talkie's reusable in-app keyboard.
///
/// The automatic style follows UIKit traits. The instrument style is the
/// fabricated mineral/copper surface used by Talkie's physical-interface
/// themes and App Store campaign.
public enum KeyboardVisualStyle: Equatable, Sendable {
    case automatic
    case mineralInstrument
}

#endif
