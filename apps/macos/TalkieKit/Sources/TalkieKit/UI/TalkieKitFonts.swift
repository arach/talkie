//
//  TalkieKitFonts.swift
//  TalkieKit
//
//  Registers the brand fonts that ship inside TalkieKit so that targets
//  which don't bundle their own fonts (e.g. TalkieAgent) still resolve the
//  real JetBrains Mono instead of silently falling back to SF Mono. The main
//  Talkie app already ships these via `ATSApplicationFontsPath`; a duplicate
//  registration here is harmless (already-registered fonts just no-op).
//

import Foundation
import CoreText

public enum TalkieKitFonts {
    private static var didRegister = false

    /// Idempotently registers TalkieKit's bundled brand fonts with the process
    /// so `ScopeType.mono` (JetBrains Mono) and `ScopeType.display` (Cormorant
    /// Garamond — the homepage's display face) resolve instead of silently
    /// falling back to SF Mono / system serif. Targets that don't ship their
    /// own fonts (e.g. TalkieAgent) rely on this; the main Talkie app already
    /// ships them via `ATSApplicationFontsPath`, so the duplicate registration
    /// here just no-ops.
    /// Call once at launch (e.g. `applicationDidFinishLaunching`).
    @MainActor
    public static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        let fonts = [
            "JetBrainsMono-Regular",
            "JetBrainsMono-Medium",
            "JetBrainsMono-SemiBold",
            "JetBrainsMono-Bold",
            "CormorantGaramond-Regular",
            "CormorantGaramond-Medium",
        ]
        for font in fonts {
            guard let url = Bundle.module.url(
                forResource: font, withExtension: "ttf", subdirectory: "Fonts"
            ) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
