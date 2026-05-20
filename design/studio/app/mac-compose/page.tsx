"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCompose } from "@/components/studies/MacCompose";
import { MacWindowGrid } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Compose at three widths.
 *
 * The Swift source (`ScopeDraftsScreen.swift`) currently has no
 * `GeometryReader` — its layout is whatever flex + fixed paddings
 * produce at the chosen window size. This study models that honestly
 * at 820 / 1180 / 1440 so we can see where Compose actually needs a
 * real breakpoint:
 *
 *   - At 820, the pipeline pin labels are hidden (S1·S2·S3·S4 only),
 *     the action chip row truncates to 2 + overflow, and the action
 *     grid falls from 4 to 2 columns.
 *   - At 1180, everything fits cleanly — this is the "designed" width.
 *   - At 1440, the editor bay starts to feel airy; the question is
 *     whether the textarea should grow or stay at a content measure.
 */
export default function MacComposeStudy() {
  return (
    <StudioPage
      eyebrow="Compose · macOS · Composition study · 3-up"
      title="Mac Compose"
      help="edit components/studies/MacCompose.tsx · Swift has no GeometryReader yet — study reveals where it needs one"
    >
      <div className="py-6">
        <MacWindowGrid
          title="Talkie · Compose"
          render={(size) => <MacCompose width={size.width} />}
        />
      </div>
    </StudioPage>
  );
}
