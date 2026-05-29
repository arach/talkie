"use client";

import { StudioPage } from "@/components/StudioPage";
import { ScreenshotsHeaderVariants } from "@/components/studies/ScreenshotsHeaderVariants";

/**
 * Screenshots header — in place, two directions (serif vs mono).
 * The real surface (chrome + header + grid) so the header is judged in
 * context, not in the abstract.
 */
export default function MacScreenshotsHeadersStudy() {
  return (
    <StudioPage
      eyebrow="Screenshots · macOS · header directions"
      title="Screenshots Header"
      help="edit components/studies/ScreenshotsHeaderVariants.tsx · donor: ScreenshotsScreen.swift"
    >
      <div className="py-6">
        <ScreenshotsHeaderVariants />
      </div>
    </StudioPage>
  );
}
