import { promises as fs } from "node:fs";
import path from "node:path";
import { StudioPage } from "@/components/StudioPage";
import { ParityAudit } from "@/components/studies/ParityAudit";

export const dynamic = "force-dynamic";

export default async function Parity() {
  const raw = await fs.readFile(
    path.resolve(process.cwd(), "data", "parity", "streams.json"),
    "utf8",
  );
  const streamsFile = JSON.parse(raw);

  return (
    <StudioPage
      eyebrow="Parity · Donor vs Next"
      title="Parity Audit"
      help="6-agent swarm review · 2026-05-21 · donor (master) vs Next (feat/ios-shell-phase-0)"
    >
      <ParityAudit streams={streamsFile.streams} />
    </StudioPage>
  );
}
