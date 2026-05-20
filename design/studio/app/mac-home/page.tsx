"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacHome } from "@/components/studies/MacHome";
import { MacWindowGrid } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Home at three widths.
 *
 * The composition itself has no breakpoint in Swift today — it relies
 * on flex + grid behavior at the window's chosen width. Stamping it at
 * 820 / 1180 / 1440 surfaces where the 3-col Capture row, the 2-col
 * Routines strip, and the activity table start to feel cramped or
 * over-padded so we can decide if Home needs a real breakpoint.
 */
export default function MacHomeStudy() {
  return (
    <StudioPage
      eyebrow="Home · macOS · Composition study · 3-up"
      title="Mac Home"
      help="edit components/studies/MacHome.tsx · stamped at 820 / 1180 / 1440 to see breakpoint behavior"
    >
      <div className="py-6">
        <MacWindowGrid
          title="Talkie · Home"
          render={(size) => <MacHome width={size.width} />}
        />
      </div>
    </StudioPage>
  );
}
