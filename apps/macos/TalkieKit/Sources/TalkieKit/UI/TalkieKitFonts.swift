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

    /// Idempotently registers TalkieKit's bundled JetBrains Mono weights with
    /// the process so `ScopeType.mono` / `Font.custom("JetBrainsMono-…")` work.
    /// Call once at launch (e.g. `applicationDidFinishLaunching`).
    @MainActor
    public static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        let weights = [
            "JetBrainsMono-Regular",
            "JetBrainsMono-Medium",
            "JetBrainsMono-SemiBold",
            "JetBrainsMono-Bold",
        ]
        for weight in weights {
            guard let url = Bundle.module.url(
                forResource: weight, withExtension: "ttf", subdirectory: "Fonts"
            ) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
