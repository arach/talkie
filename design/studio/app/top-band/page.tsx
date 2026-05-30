"use client";

import { StudioPage } from "@/components/StudioPage";
import { TopBandSystem } from "@/components/studies/TopBandSystem";

/**
 * Top Band — one component, four fixed slots, a variant per view.
 * Wordmark + TALKIE pill invariant; title cluster + complications vary.
 */
export default function TopBandStudy() {
  return (
    <StudioPage
      eyebrow="Foundations · chrome · top band"
      title="Top Band"
      help="edit components/studies/TopBandSystem.tsx · donors: ScopeTopBand · TalkieChromeBar"
    >
      <div className="py-6">
        <TopBandSystem />
      </div>
    </StudioPage>
  );
}
