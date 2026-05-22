"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacTalkieButton } from "@/components/studies/MacTalkieButton";

/**
 * Mac Talkie Button — single anchor replaces the sidebar.
 *
 * Three sections stacked:
 *   1. States gallery (8 lifecycle moments)
 *   2. Summoned overlays (palette + sectioned nav popover)
 *   3. Variants A & B in context — MacHome reframed two ways at
 *      820 / 1180 / 1440.
 *
 * Variant A is the maximalist read (no global nav at all). Variant B
 * preserves a 52pt icon-rail anchored by the Talkie button so surfaces
 * like Library that work well with nav-in-context don't regress.
 */
export default function MacTalkieButtonStudy() {
  return (
    <StudioPage
      eyebrow="Talkie Button · macOS · Consolidation study"
      title="Mac Talkie Button"
      help="edit components/studies/MacTalkieButton.tsx · one button replaces sidebar + palette + voice-command overlay"
    >
      <div className="py-6">
        <MacTalkieButton />
      </div>
    </StudioPage>
  );
}
