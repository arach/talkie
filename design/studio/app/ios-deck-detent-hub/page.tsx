import { StudioPage } from "@/components/StudioPage";
import { DetentHubStudy } from "@/components/studies/DetentHubStudy";

export default function IOSDeckDetentHubStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · instrument study"
      title="iOS · Detent Hub"
      help="Grok A refinement · two 60pt permutations for keys 01 + 04"
    >
      <DetentHubStudy />
    </StudioPage>
  );
}
