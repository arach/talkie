import { StudioPage } from "@/components/StudioPage";
import { ArchitectureMap } from "@/components/studies/ArchitectureMap";

export default function Architecture() {
  return (
    <StudioPage
      eyebrow="Architecture · Site map"
      title="Architecture"
      help="every routable Next surface · zoomable canvas journey map · embedded mini-views · inbound + outbound flows · orphans flagged · proposed wires below."
    >
      <ArchitectureMap />
    </StudioPage>
  );
}
