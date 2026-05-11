//
//  TalkieDetailLayout.swift
//  Talkie
//
//  Layout recipe system for TalkieObject detail views.
//  Each TalkieObjectType declares an ordered list of SectionSlots
//  that determines what sections appear, in what order, with what emphasis.
//

import Foundation
import TalkieKit

// MARK: - Section Kind

/// All possible sections a TalkieObject detail can contain.
/// Each section self-gates: renders nothing if the object has no relevant data.
enum SectionKind: String, CaseIterable, Sendable {
    case transcript
    case playback
    case readout
    case mediaGallery
    case attachments
    case notes
    case workflowRuns
    case refinement
    case dictationContext
    case actionBar
    case segments
    case textProvenance
}

// MARK: - Section Mode

/// How a section presents its content.
enum SectionMode: String, Sendable {
    case hero       // Large, prominent, primary content
    case reader     // Read-only display
    case editor     // Editable inline
    case compact    // Minimal footprint
    case gallery    // Grid/gallery layout for visual content
}

// MARK: - Section Chrome

/// Visual container treatment for a section.
enum SectionChrome: String, Sendable {
    case card       // Rounded card with background
    case inline     // No container, blends into page
    case fullBleed  // Edge-to-edge, no padding
}

// MARK: - Section Slot

/// A single slot in a layout recipe: what section, how it looks, how it's wrapped.
struct SectionSlot: Sendable {
    let kind: SectionKind
    let mode: SectionMode
    let chrome: SectionChrome

    init(_ kind: SectionKind, mode: SectionMode, chrome: SectionChrome) {
        self.kind = kind
        self.mode = mode
        self.chrome = chrome
    }
}

// MARK: - Recipes Per Type

// MARK: - Contextual Recipe Overrides

enum DetailRecipeOverride {
    /// Screenshot-forward: media gallery as hero at top, then the type's remaining sections.
    static func screenshotForward(for type: TalkieObjectType) -> [SectionSlot] {
        let base = type.detailRecipe.filter { $0.kind != .mediaGallery }
        return [SectionSlot(.mediaGallery, mode: .hero, chrome: .fullBleed)] + base
    }
}

extension TalkieObjectType {
    /// The layout recipe for this type's detail view.
    /// Sections self-gate — only render if the object has relevant data.
    /// Order here is the display order.
    var detailRecipe: [SectionSlot] {
        switch self {
        case .memo:
            return [
                SectionSlot(.transcript,    mode: .reader,  chrome: .card),
                SectionSlot(.actionBar,     mode: .compact, chrome: .inline),
                SectionSlot(.playback,      mode: .hero,    chrome: .card),
                SectionSlot(.segments,      mode: .compact, chrome: .card),
                SectionSlot(.workflowRuns,  mode: .compact, chrome: .card),
                SectionSlot(.mediaGallery,  mode: .compact, chrome: .card),
                SectionSlot(.textProvenance, mode: .compact, chrome: .card),
                SectionSlot(.notes,         mode: .editor,  chrome: .inline),
                SectionSlot(.attachments,   mode: .compact, chrome: .card),
            ]

        case .dictation:
            return [
                SectionSlot(.dictationContext, mode: .hero,    chrome: .card),
                SectionSlot(.transcript,       mode: .reader,  chrome: .card),
                SectionSlot(.actionBar,        mode: .compact, chrome: .inline),
                SectionSlot(.refinement,       mode: .compact, chrome: .inline),
                SectionSlot(.playback,         mode: .compact, chrome: .card),
            ]

        case .note:
            return [
                SectionSlot(.mediaGallery,   mode: .hero,    chrome: .fullBleed),
                SectionSlot(.transcript,     mode: .editor,  chrome: .inline),
                SectionSlot(.actionBar,      mode: .compact, chrome: .inline),
                SectionSlot(.textProvenance, mode: .compact, chrome: .card),
                SectionSlot(.attachments,    mode: .gallery, chrome: .card),
                SectionSlot(.playback,       mode: .compact, chrome: .card),
                SectionSlot(.notes,          mode: .editor,  chrome: .inline),
                SectionSlot(.workflowRuns,   mode: .compact, chrome: .card),
            ]

        case .segment:
            return [
                SectionSlot(.transcript,    mode: .reader,  chrome: .card),
                SectionSlot(.playback,      mode: .compact, chrome: .card),
            ]

        case .selection:
            return [
                SectionSlot(.mediaGallery,     mode: .hero,    chrome: .fullBleed),
                SectionSlot(.transcript,       mode: .reader,  chrome: .card),
                SectionSlot(.actionBar,        mode: .compact, chrome: .inline),
                SectionSlot(.textProvenance,   mode: .compact, chrome: .card),
                SectionSlot(.readout,          mode: .compact, chrome: .card),
                SectionSlot(.refinement,       mode: .compact, chrome: .inline),
                SectionSlot(.dictationContext, mode: .hero,    chrome: .card),
                SectionSlot(.workflowRuns,     mode: .compact, chrome: .card),
                SectionSlot(.notes,            mode: .editor,  chrome: .inline),
            ]

        case .capture:
            return [
                SectionSlot(.mediaGallery,   mode: .hero,    chrome: .fullBleed),
                SectionSlot(.transcript,     mode: .editor,  chrome: .inline),
                SectionSlot(.actionBar,      mode: .compact, chrome: .inline),
                SectionSlot(.textProvenance, mode: .compact, chrome: .card),
                SectionSlot(.attachments,    mode: .gallery, chrome: .card),
                SectionSlot(.workflowRuns,   mode: .compact, chrome: .card),
                SectionSlot(.notes,          mode: .editor,  chrome: .inline),
            ]
        }
    }
}
