import { StudioPage } from "@/components/StudioPage";
import { IncrementalDeckStudy } from "./incremental-deck";

export default function Round3IncrementalStudy() {
  return (
    <StudioPage
      eyebrow="iPad · Round 3 · incumbent study"
      title="The current deck, six iPad takes"
      help="same controls · same states · same visual language"
    >
      <IncrementalDeckStudy />
    </StudioPage>
  );
}
