"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacDictationDetail } from "@/components/studies/MacDictationDetail";

/**
 * Mac Dictation Detail — current vs one-iteration proposed.
 *
 * Variant I replicates the surface that ships today (TalkieView when
 * the selected item is a dictation): timestamp-derived title, double
 * toolbar, FILED/RUNTIME/SOURCE dashboard grid, stacked MEDIA /
 * READOUT / SCRATCHPAD utility blocks.
 *
 * Variant II proposes the same editorial framing we just shipped for
 * Notes + Captures, with one dictation-specific addition: a slim
 * audio scrubber at the foot. Derived headline replaces the
 * timestamp; transcript becomes the document; side-rail carries
 * actions + provenance + transcription stats.
 */

export default function MacDictationDetailStudy() {
  return (
    <StudioPage
      eyebrow="Dictation detail · macOS · current vs proposed"
      title="Dictation detail · one iteration"
      help="Variant I replicates today's surface · Variant II is the proposed cleanup"
    >
      <div className="py-6">
        <MacDictationDetail />
      </div>
    </StudioPage>
  );
}
