"use client";

import { StudioPage } from "@/components/StudioPage";
import { TetheredTable } from "./tethered-table";

/**
 * Round 2 · Kimi — The Tethered Table.
 *
 * One task lies open on the table as a full sheet; the rest wait as a
 * fanned deck of slips at the left thumb; Talkie's voice disc sits at the
 * right thumb, tied to the open task by a thread. Voice targeting is the
 * thread — traceable in every state, with the text blurred.
 *
 * Scenes (switcher above the device): Working · Result ready ·
 * Mac unreachable. Hold the disc to talk; tap a slip to swap tasks.
 */
export default function Round2KimiStudy() {
  return (
    <StudioPage
      eyebrow="iPad · Round 2 · Kimi"
      title="The Tethered Table"
      help="hold the disc · tap a slip · scenes above the device"
    >
      <TetheredTable />
    </StudioPage>
  );
}
