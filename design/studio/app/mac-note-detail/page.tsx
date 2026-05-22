"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacNoteDetail } from "@/components/studies/MacNoteDetail";

/**
 * Mac Note Detail — single-note surface at three widths.
 *
 * Composition: editorial masthead → comfortable serif body with a
 * marginal rule → margin column for provenance + tags → attachments
 * rail at the foot (replaces the player rail).
 *
 * Width-aware: at 1180 the layout is studio default; at 1440 and 1920
 * the pane breathes — wider gutter, wider margin column — but the
 * prose measure stays capped so reading rhythm doesn't break.
 *
 * Palette: PEARL (#F5F8FA pane) on FROST (#F9FBFC canvas). Cool, less
 * cream than the warm family. Amber kept as single accent.
 */

export default function MacNoteDetailStudy() {
  return (
    <StudioPage
      eyebrow="Note detail · macOS · single-note composition"
      title="Note as a page in a notebook"
      help="PEARL on FROST · text-first · attachment rail · three widths"
    >
      <div className="flex flex-col items-center gap-14 py-6">
        <MacNoteDetail width={1180} />
        <MacNoteDetail width={1440} />
        <MacNoteDetail width={1920} />
      </div>
    </StudioPage>
  );
}
