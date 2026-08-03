import { StudioPage } from "@/components/StudioPage";
import { DeckKeyMaterialStudy } from "@/components/studies/DeckKeyMaterial";

export default function IOSDeckKeyMaterialStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · key material"
      title="iOS · Deck Key Lift & Inactive Grammar"
      help="edit components/studies/DeckKeyMaterial.tsx · decisions in app/ios-deck-key-material/NOTES.md"
      back={{ href: "/ios-deck", label: "Deck" }}
    >
      <DeckKeyMaterialStudy />
    </StudioPage>
  );
}
