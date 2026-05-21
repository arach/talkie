import { StudioPage } from "@/components/StudioPage";
import { ParityAudit } from "@/components/studies/ParityAudit";

export default function Parity() {
  return (
    <StudioPage
      eyebrow="Parity · Donor vs Next"
      title="Parity Audit"
      help="6-agent swarm review · 2026-05-21 · donor (master) vs Next (feat/ios-shell-phase-0)"
    >
      <ParityAudit />
    </StudioPage>
  );
}
