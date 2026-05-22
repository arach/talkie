import { StudioPage } from "@/components/StudioPage";
import { MacMemoDetail } from "@/components/studies/MacMemoDetail";

export default function MacMemoDetailEmptyStudy() {
  return (
    <StudioPage
      eyebrow="Memo · macOS · Composition study"
      title="Mac Memo Detail · Empty"
      help="before a memo is selected — same chrome, no masthead/body/player. Factual recap (count · words · minutes) carries the empty state instead of marketing copy."
    >
      <div className="py-4">
        <MacMemoDetail empty />
      </div>
    </StudioPage>
  );
}
