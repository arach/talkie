"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacScreenshots } from "@/components/studies/MacScreenshots";

/**
 * Mac Screenshots — focused gallery for captures.
 *
 * Swift donor: apps/macos/Talkie/Views/ScreenshotsScreen.swift. The
 * legacy view is a grid pane + resizable detail pane on the right,
 * driven by `selectedIDs: Set<String>` + `selectionAnchorID` (single
 * click anchors; ⌘-click toggles; shift-click extends a range). Bulk
 * actions live in a status footer ("3 selected · MARKUP · SHARE ·
 * DELETE"). This study is the visual-language seat for that surface
 * before any port-level change ships.
 *
 * The /mac-capture-flow study still inlines a mini gallery panel for
 * its three-step storyboard; this route owns the full-fat version so
 * the gallery has its own iteration surface independent of the flow.
 */
export default function MacScreenshotsStudy() {
  return (
    <StudioPage
      eyebrow="Screenshots · macOS · gallery + inspector · multi-select"
      title="Mac Screenshots"
      help="edit components/studies/MacScreenshots.tsx · donor: ScreenshotsScreen.swift"
    >
      <div className="py-6">
        <MacScreenshots />
      </div>
    </StudioPage>
  );
}
