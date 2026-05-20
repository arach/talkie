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
            // actionBar + workflow pills dropped from the recipe — the
            // toolbar slug at the top of TOHeaderSection now carries
            // Copy/Share/Export/⋯ (and the workflow picker lives in the
            // overflow menu). Keeping the action pills below the body
            // duplicated those affordances and orphaned the workflow
            // icons in dead space.
            //
            // Playback dropped — TalkieView pins it as a fixed footer.
            // textProvenance dropped — its data lives in the right-margin
            // metadata column alongside the masthead.
            return [
                SectionSlot(.transcript,    mode: .reader,  chrome: .card),
                SectionSlot(.segments,      mode: .compact, chrome: .card),
                SectionSlot(.workflowRuns,  mode: .compact, chrome: .card),
                SectionSlot(.mediaGallery,  mode: .compact, chrome: .card),
                SectionSlot(.notes,         mode: .editor,  chrome: .inline),
                SectionSlot(.attachments,   mode: .compact, chrome: .card),
            ]

        case .dictation:
            // actionBar + refinement dropped (refinement is dev tooling,
            // not part of the editorial reading view). dictationContext
            // already dropped from the hero slot — its data lives in the
            // right-margin metadata column.
            return [
                SectionSlot(.transcript,       mode: .reader,  chrome: .card),
            ]

        case .note:
            // Media gallery dropped from the hero slot — it was the
            // ugly dark fullBleed band at the top of the pane. Playback
            // dropped — TalkieView pins it as a fixed footer.
            return [
                SectionSlot(.transcript,     mode: .editor,  chrome: .inline),
                SectionSlot(.actionBar,      mode: .compact, chrome: .inline),
                SectionSlot(.mediaGallery,   mode: .compact, chrome: .inline),
                SectionSlot(.attachments,    mode: .gallery, chrome: .card),
                SectionSlot(.notes,          mode: .editor,  chrome: .inline),
                SectionSlot(.workflowRuns,   mode: .compact, chrome: .card),
            ]

        case .segment:
            return [
                SectionSlot(.transcript,    mode: .reader,  chrome: .card),
            ]

        case .selection:
            return [
                SectionSlot(.transcript,       mode: .reader,  chrome: .card),
                SectionSlot(.actionBar,        mode: .compact, chrome: .inline),
                SectionSlot(.mediaGallery,     mode: .compact, chrome: .inline),
                SectionSlot(.readout,          mode: .compact, chrome: .card),
                SectionSlot(.refinement,       mode: .compact, chrome: .inline),
                SectionSlot(.dictationContext, mode: .hero,    chrome: .card),
                SectionSlot(.workflowRuns,     mode: .compact, chrome: .card),
                SectionSlot(.notes,            mode: .editor,  chrome: .inline),
            ]

        case .capture:
            return [
                SectionSlot(.transcript,     mode: .editor,  chrome: .inline),
                SectionSlot(.actionBar,      mode: .compact, chrome: .inline),
                SectionSlot(.mediaGallery,   mode: .compact, chrome: .inline),
                SectionSlot(.attachments,    mode: .gallery, chrome: .card),
                SectionSlot(.workflowRuns,   mode: .compact, chrome: .card),
                SectionSlot(.notes,          mode: .editor,  chrome: .inline),
            ]
        }
    }
}
