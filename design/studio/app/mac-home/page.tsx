import { StudioPage } from "@/components/StudioPage";
import { MacHome } from "@/components/studies/MacHome";

export default function MacHomeStudy() {
  return (
    <StudioPage
      eyebrow="Home · macOS · Composition study"
      title="Mac Home"
      help="edit components/studies/MacHome.tsx · reintegrates the original HomeGrid taxonomy into the Scope language"
    >
      <div className="py-4">
        <MacHome />
      </div>
    </StudioPage>
  );
}
