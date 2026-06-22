"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacShareExport } from "@/components/studies/MacShareExport";

/**
 * Mac Share Export — TLK-032 screenshot Export Panel (V1).
 *
 * Source of truth: docs/specs/tlk-032-share-export-studio.md (revised,
 * screenshot-only). This board is the visual seat for the panel before
 * any SwiftUI ships: large live preview on the left, inspector on the
 * right (Original/Polished presets · background · padding · corner radius
 * · shadow · format · JPEG quality · dimensions/size readout · Copy /
 * Save As).
 *
 * Scope is deliberately narrow — screenshots only. No video, clips,
 * recording cards, destinations, or Private mode are mocked here; those
 * are Later Tracks in the spec and must not re-enter this study.
 *
 * The interactive controls let a reviewer drive every state; the
 * Original-vs-Polished reference strip and the Swift porting notes below
 * the panel are study chrome — nothing instructional is painted inside
 * the panel surface itself.
 */
export default function MacShareExportStudy() {
  return (
    <StudioPage
      eyebrow="Export · macOS · screenshot · preview + inspector · V1"
      title="Share Export"
      help="edit components/studies/MacShareExport.tsx · spec: docs/specs/tlk-032-share-export-studio.md"
    >
      <div className="py-6 flex justify-center">
        <MacShareExport />
      </div>
    </StudioPage>
  );
}
