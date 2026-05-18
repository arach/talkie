import { StudioPage } from "@/components/StudioPage";
import { MacLearn } from "@/components/studies/MacLearn";

export default function MacLearnStudy() {
  return (
    <StudioPage
      eyebrow="Learn · macOS · Composition study"
      title="Mac Learn"
      help="edit components/studies/MacLearn.tsx · agent interstitial that replaces the data-listing Stats page"
    >
      <div className="py-4">
        <MacLearn />
      </div>
    </StudioPage>
  );
}
