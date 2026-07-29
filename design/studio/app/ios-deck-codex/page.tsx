import { StudioPage } from "@/components/StudioPage";
import { CodexDeckBridgeBarStudy } from "@/components/studies/CodexDeckBridgeBar";

export default function IOSDeckCodexBridgeBarStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · Codex bridge"
      title="iOS · Deck/Host Bridge Bar & Live Turn Context"
      help="edit components/studies/CodexDeckBridgeBar.tsx · decisions in app/ios-deck-codex/NOTES.md"
      back={{ href: "/ios-deck", label: "Deck" }}
    >
      <CodexDeckBridgeBarStudy />
    </StudioPage>
  );
}
