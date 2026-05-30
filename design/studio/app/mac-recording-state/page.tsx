"use client";

import React from "react";
import { StudioPage } from "@/components/StudioPage";
import { KeyframeStyles } from "./shared";
import { DraftingSheet } from "./drafting-sheet";
import { LightInstrument } from "./light-instrument";

/**
 * Mac Talkie — Recording state · two-finalist comparison.
 *
 * After a five-direction fan-out, the toolbox lands on two takes:
 *
 *   1. Drafting sheet     editorial paper, mid-draft. Italic-serif
 *                         placeholder, brass marginal rule, em-dash
 *                         that doubles as the wave — now sitting on
 *                         a hairline magnetic-tape sliver with
 *                         scrolling amber bars and sprocket rails.
 *                         Folds into the memo row on settle.
 *
 *   2. Light instrument   the current treatment dialed down. Glass
 *                         disc near-invisible; cancel + REC float as
 *                         text marginalia above the disc, source +
 *                         STOP below it, both pairs on a single
 *                         baseline. STOP is the only pilled (committed)
 *                         affordance.
 *
 * The Heavy Instrument · Margin Pen · Tape Strip directions were
 * shipped to the studio, evaluated, and removed — the instrument bay
 * lives on /mac-walkie, and the tape DNA is now grafted into the
 * drafting sheet. Both finalists render on the same paper homescreen
 * substrate so comparisons stay honest. See `./shared`.
 */

export default function MacRecordingStateStudy() {
  return (
    <StudioPage
      eyebrow="Recording state · finalists"
      title="Mac Talkie — Recording, two ways"
      help="drafting sheet · light instrument"
    >
      <KeyframeStyles />
      <div className="flex flex-col gap-14 py-6">
        <DraftingSheet />
        <LightInstrument />
      </div>
    </StudioPage>
  );
}
