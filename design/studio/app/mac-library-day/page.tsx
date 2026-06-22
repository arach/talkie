"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacLibraryDay } from "@/components/studies/MacLibraryDay";

/**
 * Mac Library · Day digest — the no-selection detail pane, populated.
 *
 * The shipped `ScopeLibraryEmptyState.todaySection` renders a captures
 * day as a wall of identical placeholder boxes. This board reproduces
 * that Ship state, then offers Filmstrip / Contact / Grouped fixes —
 * all turning on rendering the real thumbnail. Picker is on the
 * window's chrome bar.
 */
export default function MacLibraryDayStudy() {
  return (
    <StudioPage
      eyebrow="Library · macOS · day digest · variant board"
      title="Library · Day"
      help="edit components/studies/MacLibraryDay.tsx · picker on the window chrome bar"
    >
      <div className="py-6 flex justify-center">
        <MacLibraryDay />
      </div>
    </StudioPage>
  );
}
