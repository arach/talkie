"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCaptureMarkupStripRedesign } from "@/components/studies/MacCaptureMarkupStrip";

/**
 * Mac Capture Markup · Speak Strip — bottom-band redesign.
 *
 * Isolated re-think of CaptureMarkupInputBarView (the native band around
 * the WKWebView canvas in CaptureMarkupPanelChrome.swift). Addresses the
 * shipped bar's three pain points: the marooned corner mic, the keycap-
 * noisy RUN, and the three competing context zones up top. See the
 * component header for the full critique + the redesign rationale.
 */
export default function MacCaptureMarkupStripStudy() {
  return (
    <StudioPage
      eyebrow="Capture Markup · macOS · bottom band · redesign"
      title="Mac Capture Markup · Speak Strip"
      help="edit components/studies/MacCaptureMarkupStrip.tsx · ports to CaptureMarkupPanelChrome.swift · CaptureMarkupInputBarView"
    >
      <MacCaptureMarkupStripRedesign />
    </StudioPage>
  );
}
