import { StudioPage } from "@/components/StudioPage";
import { ArchitectureMap } from "@/components/studies/ArchitectureMap";

export default function Architecture() {
  return (
    <StudioPage
      eyebrow="Architecture · Site map"
      title="Architecture"
      help="every routable Next surface · domain-grouped · inbound + outbound entry counts · orphans flagged · proposed wires below. v2 (in-flight via codex-talkie-canvas) upgrades this to a canvas-based journey map with embedded mini-views."
    >
      <ArchitectureMap />
    </StudioPage>
  );
}
