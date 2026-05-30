"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCaptureMarkup } from "@/components/studies/MacCaptureMarkup";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Capture Markup — voice + image annotation surface.
 *
 * No Swift source yet. Upstream of any port — picks the shape for the
 * markup surface before committing to a build.
 *
 * Thesis: markup is delegated to CleanShot X today (TrayViewer.swift
 * line 1090). The Talkie-native path is voice + image. Two states only —
 *   1. ASK     — screenshot dominant, single voice/text input below.
 *   2. TOUCH UP — agent applied markup; manual tools + layer popover
 *                 handle the last 20%.
 *
 * Earlier draft tried three framings (receipt bay / agent attachment /
 * voice-during-dictation) plus a coda. Operator review collapsed it:
 * those are invocation modes, not separate surfaces.
 *
 * Architecture (unchanged from the prior draft): ephemeral WKWebView
 * panel, spawn on demand, discard on accept/cancel. Not surfaced as a
 * visual motif — just "the markup window."
 */
export default function MacCaptureMarkupStudy() {
  return (
    <StudioPage
      eyebrow="Capture Markup · macOS · Voice + image · 2-state"
      title="Mac Capture Markup"
      help="edit components/studies/MacCaptureMarkup.tsx · pre-Swift · ask → touch up"
    >
      <div className="py-6">
        <MacWindowFrame
          size={{ width: 1180, label: "Default", note: "ask · then touch up · one surface, two states" }}
          title="Talkie · Capture Markup"
        >
          <MacCaptureMarkup />
        </MacWindowFrame>
      </div>
    </StudioPage>
  );
}
