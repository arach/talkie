import { StudioPage } from "@/components/StudioPage";
import { LibraryCTAStudio } from "@/components/studies/LibraryCTA";

export default function IOSLibraryCTAStudy() {
  return (
    <StudioPage
      eyebrow="Library · contextual action"
      title="iOS · Library CTA"
      help="edit components/studies/LibraryCTA.tsx · port of LibraryCTA in LibraryNextView.swift"
    >
      <div className="flex flex-col gap-12">
        <LibraryCTAStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["CTA", "the one round primary action floating at the bottom-center of the Library. Swaps with the active tab; the shell's bottom-left Summon stays separate."],
    ["Material", "the swappable skin: Accent (filled, shipped) · Glass (dark, matches Summon) · Ring (ghost outline). Layout + size are frozen across all three."],
    ["Tab glyph", "what the CTA does, by tab: Memos → mic (record) · Dictations → keyboard (type) · Items → viewfinder (grab a capture)."],
    ["Sheen", "the top specular on the cap — light from above. Strong on Accent, faint on Glass, none on Ring."],
    ["Lift", "the CTA's drop shadow — an accent glow + a tight contact, the same two-layer lift as the deck keycaps. Ring is flat (no lift)."],
    ["Label", "an optional tiny mono caption under the icon (RECORD · DICTATE · CAPTURE). Off by default — the glyph carries it; the caption is doubtful and may not survive."],
    ["Center of gravity", "the CTA shares the bottom-left Summon's vertical center (both 40pt up) so the two bottom buttons sit on one line."],
    ["Summon-aware", "when the Summon chrome is up, the center CTA steps aside (fades out) so there's one highlighted button on screen, not two competing ones."],
  ];
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em] text-stone-500">
          · names
        </span>
        <span className="italic text-stone-400" style={{ fontSize: 12 }}>
          one vocabulary for studio · Swift · chat
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      <div
        className="grid"
        style={{
          gridTemplateColumns: "150px 1fr",
          rowGap: 8,
          columnGap: 18,
          padding: "16px 20px",
          background: "#FFFFFF",
          border: "0.5px solid #DEDEDD",
          borderRadius: 8,
        }}
      >
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-stone-700">
              {name}
            </span>
            <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>
              {def}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
