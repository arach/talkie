import { Suspense } from "react";
import { StudioPage } from "@/components/StudioPage";
import { CodexDeckKimiStudy } from "@/components/studies/CodexDeckKimi";

export default function IOSDeckCodexKimiStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · Codex bridge · alternate"
      title="iOS · Codex Deck — One Display, One Scale, One Keyboard"
      help="edit components/studies/CodexDeckKimi.tsx · decisions in app/ios-deck-codex-kimi/NOTES.md"
      back={{ href: "/ios-deck-codex", label: "Codex Deck" }}
    >
      <Suspense fallback={null}>
        <CodexDeckKimiStudy />
      </Suspense>
    </StudioPage>
  );
}
