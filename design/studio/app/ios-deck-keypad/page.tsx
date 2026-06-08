import { StudioPage } from "@/components/StudioPage";
import { DeckKeypadStudy } from "@/components/studies/DeckKeypad";

export default function IOSDeckKeypadStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · keypad"
      title="iOS · Deck Keypad"
      help="edit components/studies/DeckKeypad.tsx · variants for the 4×4 TileGrid in DeckMirrorNext.swift"
    >
      <DeckKeypadStudy />
    </StudioPage>
  );
}
