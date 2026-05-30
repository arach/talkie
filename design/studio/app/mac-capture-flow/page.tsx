"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCaptureFlow } from "@/components/studies/MacCaptureFlow";

/**
 * Mac Capture Flow — the full end-to-end story.
 *
 * Walks the user journey across three surfaces that previously lived
 * as isolated studies:
 *   1. Library view        — entry · the screenshot lives in the Scope
 *                            library alongside memos / dictations / notes.
 *   2. Screenshots view    — focused gallery · a grid of all captures,
 *                            ready for browse / pick / multi-select.
 *   3. Markup (Annotation) — single capture, drawing tools + agent voice.
 *
 * Each panel is a small representation of its donor surface (not a 1:1
 * render). The point is the path between them — arrows + verbs make the
 * transitions explicit so we can argue about flow without re-rendering
 * full mocks every time.
 */
export default function MacCaptureFlowStudy() {
  return (
    <StudioPage
      eyebrow="Capture Flow · macOS · Library → Screenshots → Markup"
      title="Mac Capture Flow"
      help="edit components/studies/MacCaptureFlow.tsx · storyboard, not pixel-perfect mocks"
    >
      <div className="py-6">
        <MacCaptureFlow />
      </div>
    </StudioPage>
  );
}
