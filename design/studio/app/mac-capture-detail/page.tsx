"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCaptureDetail } from "@/components/studies/MacCaptureDetail";

/**
 * Mac Capture Detail — image-first surface at three widths.
 *
 * Composition: toolbar → hero column (filename + derived caption +
 * full-bleed checker mat with the image) → margin column (capture +
 * Tray metadata) → foot rail (dimensions / actions).
 *
 * Width-aware: image scales with the canvas so it actually fills the
 * room at wide widths. The margin column stays fixed so metadata
 * doesn't outgrow itself.
 *
 * Palette: PEARL on FROST. The cool mat reads cleaner than warm cream
 * behind a screenshot.
 */

export default function MacCaptureDetailStudy() {
  return (
    <StudioPage
      eyebrow="Capture detail · macOS · image-first composition"
      title="Capture · image is the content"
      help="PEARL on FROST · derived caption promotes to Note · three widths"
    >
      <div className="flex flex-col items-center gap-14 py-6">
        <MacCaptureDetail width={1180} />
        <MacCaptureDetail width={1440} />
        <MacCaptureDetail width={1920} />
      </div>
    </StudioPage>
  );
}
