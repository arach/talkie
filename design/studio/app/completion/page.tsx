import { StudioPage } from "@/components/StudioPage";
import { CompletionMap } from "@/components/studies/CompletionMap";

export default function Completion() {
  return (
    <StudioPage
      eyebrow="Completion · Roadmap"
      title="Feature Completion"
      help="release-train view of the Talkie iOS rebuild · M1 shipped (Next shell + Phase 1 + Phase 2) · M2 entry-point wires · M3 polish · M4 missing donor surfaces · M5 new scope · M6 system polish"
    >
      <CompletionMap />
    </StudioPage>
  );
}
