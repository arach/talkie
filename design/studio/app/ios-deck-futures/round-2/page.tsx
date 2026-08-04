import { StudioPage } from "@/components/StudioPage";

import { RoundTwoGallery } from "./round-two-gallery";

export default function RoundTwoDesignField() {
  return (
    <StudioPage
      eyebrow="iPad · Round 2 · artifact field"
      title="Three serious at-bats"
      help="live proposals first · composition probes below"
      back={{ href: "/ios-deck-futures", label: "Deck futures" }}
    >
      <RoundTwoGallery />
    </StudioPage>
  );
}
