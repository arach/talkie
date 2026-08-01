import { StudioPage } from "@/components/StudioPage";
import { DetentHubStudy } from "@/components/studies/DetentHubStudy";

export default function IOSDeckDetentHubStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · instrument study"
      title="iOS · Detent Hub"
      help="Twin-core refinement · two resolved 64pt treatments for keys 01 + 04"
    >
      <DetentHubStudy />
    </StudioPage>
  );
}
