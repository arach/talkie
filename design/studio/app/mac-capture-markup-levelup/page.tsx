"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCaptureMarkupLevelUp } from "@/components/studies/MacCaptureMarkup";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Capture Markup · Level Up — the leveled-up run feedback + composer.
 *
 * Focused offshoot of /mac-capture-markup (section 5). The full study
 * covers the whole markup window; this route isolates two upgrades so
 * they're arguable on their own and ready to port:
 *
 *   · WORK THREAD — a streaming run log on the RIGHT RAIL. As the agent
 *                   runs it writes a line per step (read · plan · then
 *                   each mark as it lands), a live node at the head;
 *                   when done it's the record, footed with the pass
 *                   summary + a single ↶ undo (no accept/cancel gate).
 *   · SPEAK STRIP v2 — the composer gains live states; recording turns the
 *                   prompt lane into a magnetic-tape waveform.
 *
 * Ports to CaptureMarkupPanelChrome.swift (the native band around the
 * WKWebView canvas).
 */
export default function MacCaptureMarkupLevelUpStudy() {
  return (
    <StudioPage
      eyebrow="Capture Markup · macOS · Level up · bottom band"
      title="Mac Capture Markup · Level Up"
      help="edit components/studies/MacCaptureMarkup.tsx · section 5 · ports to CaptureMarkupPanelChrome.swift"
    >
      <div className="py-6">
        <MacWindowFrame
          size={{ width: 1180, label: "Default", note: "work thread on the right · speak strip v2 at the foot" }}
          title="Talkie · Capture Markup · Level Up"
        >
          <MacCaptureMarkupLevelUp />
        </MacWindowFrame>
      </div>
    </StudioPage>
  );
}
