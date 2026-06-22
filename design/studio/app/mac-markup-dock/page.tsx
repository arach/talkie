"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacMarkupDock } from "@/components/studies/MacMarkupDock";

/**
 * Mac Markup Dock · Level Up — the floating tool cluster on the live
 * overlay (shared by screen-recording markup + the desktop ink layer).
 *
 * Holds layout/contents frozen; varies material + shape + iconography so
 * the comparison is purely look-and-feel. Real line-art icons replace the
 * unicode glyphs in every variant. Winner ports to
 * apps/macos/TalkieAgent/TalkieAgent/Resources/CaptureMarkup/overlay.{css,html}.
 */
export default function MacMarkupDockStudy() {
  return (
    <StudioPage
      eyebrow="Capture · macOS · overlay dock · level up"
      title="Mac Markup Dock"
      help="edit components/studies/MacMarkupDock.tsx · ports to overlay.css + overlay.html (live markup + desktop ink)"
    >
      <MacMarkupDock />
    </StudioPage>
  );
}
