"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacLibrary } from "@/components/studies/MacLibrary";
import { MacWindowGrid } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Library at three widths.
 *
 * Mirrors the Swift breakpoint at 880 — the 820 stamp collapses to
 * list-only (inspector hidden); 1180 and 1440 show the split with the
 * inspector breathing more at the wide size. The width-class eyebrow
 * above each frame names the format the artifact represents.
 */
export default function MacLibraryStudy() {
  return (
    <StudioPage
      eyebrow="Library · macOS · Composition study · 3-up"
      title="Mac Library"
      help="edit components/studies/MacLibrary.tsx · 820 falls below the 880 Swift breakpoint to list-only"
    >
      <div className="py-6">
        <MacWindowGrid
          title="Talkie · Library"
          render={(size) => <MacLibrary width={size.width} />}
        />
      </div>
    </StudioPage>
  );
}
