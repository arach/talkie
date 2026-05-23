#if os(macOS)
import AppKit

public extension NSColor {
    /// Perceived brightness (ITU-R BT.709 luma). Returns 0.0 (black) – 1.0 (white).
    /// Use for tone-classification, not for accessibility contrast (use APCA / WCAG for that).
    var perceivedBrightness: CGFloat {
        let rgb = usingColorSpace(.extendedSRGB) ?? self
        return (0.2126 * rgb.redComponent)
             + (0.7152 * rgb.greenComponent)
             + (0.0722 * rgb.blueComponent)
    }
}
#endif
