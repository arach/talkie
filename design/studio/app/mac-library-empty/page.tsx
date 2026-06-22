"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacLibraryEmpty } from "@/components/studies/MacLibraryEmpty";

/**
 * Mac Library · no-selection content area, reframed.
 *
 * The shipped pane reprinted the rail's list — a second list of the same
 * items, no new context, not much pretty. This board replaces that with
 * variants that each do something the rail CAN'T (Overview / Mosaic /
 * Featured), plus the genuine zero-state (Empty) the file always
 * promised. Picker is on the window's chrome bar; a faint rail stub on
 * the left keeps the "don't echo me" point legible.
 */
export default function MacLibraryEmptyStudy() {
  return (
    <StudioPage
      eyebrow="Library · macOS · no-selection pane · variant board"
      title="Library · No Selection"
      help="edit components/studies/MacLibraryEmpty.tsx · picker on the window chrome bar"
    >
      <div className="py-6 flex justify-center">
        <MacLibraryEmpty />
      </div>
    </StudioPage>
  );
}
