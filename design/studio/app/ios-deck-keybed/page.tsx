import { StudioPage } from "@/components/StudioPage";
import { DeckKeyBedStudy } from "@/components/studies/DeckKeyBed";

export default function IOSDeckKeyBedStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · key bed"
      title="iOS · Deck Key Bed"
      help="edit components/studies/DeckKeyBed.tsx · variants for DeckCockpitSurface.keyRow in DeckMirrorNext.swift"
    >
      <DeckKeyBedStudy />
    </StudioPage>
  );
}
