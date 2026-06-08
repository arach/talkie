import { StudioPage } from "@/components/StudioPage";
import { DeckTreatmentsStudio } from "@/components/studies/DeckPlayground";

export default function IOSDeckStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · material treatments"
      title="iOS · Deck"
      help="edit components/studies/IOSDeck.tsx (treatments) · DeckPlayground.tsx (harness) · port of DeckMirrorNext.swift"
    >
      <div className="flex flex-col gap-12">
        <DeckTreatmentsStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat. Full-bleed pass: the deck
// IS the app — chassis edge to edge, the keybed fills a recessed well.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Chassis", "the full-bleed instrument face — runs corner to corner as the app surface, faint anodized sheen top→bottom. No framing canvas, no bounded plate; the deck is the screen."],
    ["Masthead", "the slim app title bar on a silkscreen hairline rule — Accent Chip + TALKIE/DECK wordmark + close. No model-number gadget tell."],
    ["Accent Chip", "the one functional color up top — a 7px solid square in the theme accent. Color = information, never decoration."],
    ["Device Row", "what you're controlling (MAC MINI ⌄) + connection status pill (LIVE / DICTATING), riding on the chassis under the masthead."],
    ["Display", "the one black glass readout (tape diagonals + last-result echo / live transcript). Black is reserved here so it never reads as a key."],
    ["Control Strip", "the esc/⌘/arrows/↵ row — the SAME keytop as the keybed, one key system; esc↔col 1, ↵↔col 4."],
    ["Silkscreen", "the printed legend line (KEYBED · 16 · SAFARI) at the top of the well; names the module + what the bindings target."],
    ["Key Well", "the full-bleed recessed field filling the bottom of the app — darker than the chassis, depth via inset groove, bleeds to the side + bottom edges."],
    ["Keybed", "the 16-key macro field filling the well edge to edge — no pocket of its own; the well is its recess."],
    ["Keytop", "one key raised in the well — how it catches light (gradient + lift + sheen) is the Treatment's job. Always a flat-topped tile, never a bubble dome."],
    ["Treatment", "a swappable MATERIAL skin (Milled · Brushed · Glass · Polished · Relief). Changes only texture — chassis metal, well depth, keycap gloss/lift/sheen. Layout + proportions are frozen across all of them."],
    ["Lift", "how far a keytop stands off the surface — its drop shadow. The fix for 'too carved / one texture': keys are figure, the deck is ground."],
    ["Sheen", "the glassy specular reflection across the top of a cap (Glass/Polished only). A flat pane catching directional light, not a curved highlight."],
    ["Empty Well", "an unbound slot — a dimple/socket in the floor (no key seated), faint + glyph. Its read varies by treatment."],
    ["Index", "the tiny corner number 01–16 — TE step/pad numbering; low-contrast so it reads as a system, not clutter."],
    ["Active Key", "fired / armed state — amber-tinted top + 1px amber rim + glow + a half-pixel lift. The dictation key shown lit while dictating."],
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
