"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacNotchSettings } from "@/components/studies/MacNotchSettings";

/**
 * Mac Notch Settings — interactive simplification prototype.
 *
 * Live React state, real toggles, live preview pane. Lets the
 * reviewer feel the consolidation rather than read about it.
 */
export default function MacNotchSettingsStudy() {
  return (
    <StudioPage
      eyebrow="Notch · macOS · Simplification prototype · interactive"
      title="Mac Notch Settings"
      help="edit components/studies/MacNotchSettings.tsx · ~10 main controls + Advanced disclosure per section"
    >
      <div className="py-6">
        <MacNotchSettings />
      </div>
    </StudioPage>
  );
}
