"use client";

import { StudioPage } from "@/components/StudioPage";
import { HeaderSystem } from "@/components/studies/HeaderSystem";

/**
 * Header System — one canonical standard for every screen header.
 *
 * Eyebrow (mono) → Title (serif, one size) → Tags (mono). The serif reads
 * as instrument only when bracketed by mono chrome. Maps the drifted
 * headers (Dictations "28 May", controls-only Screenshots) back onto it.
 */
export default function HeaderSystemStudy() {
  return (
    <StudioPage
      eyebrow="Foundations · type · header standard"
      title="Header System"
      help="edit components/studies/HeaderSystem.tsx · donors: CompactScopePageHeader · ScopeLibraryView · ScreenshotsScreen"
    >
      <div className="py-6">
        <HeaderSystem />
      </div>
    </StudioPage>
  );
}
