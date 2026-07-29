import { Suspense } from "react";
import { StudioPage } from "@/components/StudioPage";
import { CodexStatusDocumentStudy } from "@/components/studies/CodexStatusDocument";

export default function IOSCodexStatusDocumentStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · task status · server document"
      title="iOS · Codex Task Dossier"
      help="3 treatments · shared IA · representative data from 7e2c14d8"
      back={{ href: "/ios-deck-codex", label: "Codex Deck" }}
    >
      <Suspense fallback={null}>
        <CodexStatusDocumentStudy />
      </Suspense>
    </StudioPage>
  );
}
