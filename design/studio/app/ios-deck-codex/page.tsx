import { StudioPage } from "@/components/StudioPage";
import { CodexDeckLaneSignalsStudy } from "@/components/studies/CodexDeckLaneSignals";

export default function IOSDeckCodexLaneSignalsStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · Codex lanes"
      title="iOS · Codex Lane Picker & Host Signals"
      help="edit components/studies/CodexDeckLaneSignals.tsx · decisions in app/ios-deck-codex/NOTES.md"
      back={{ href: "/ios-deck", label: "Deck" }}
    >
      <CodexDeckLaneSignalsStudy />
    </StudioPage>
  );
}
