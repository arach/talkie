import { StudioPage } from "@/components/StudioPage";
import { CockpitCompactStudio } from "@/components/studies/CockpitCompact";

export default function CockpitCompactStudy() {
  return (
    <StudioPage
      eyebrow="Home · Cockpit Compact · how small can it get"
      title="Home · Cockpit Compact"
      help="edit components/studies/CockpitCompact.tsx · the one variable is VERTICAL FOOTPRINT — compact cockpit forms (Strip · Micro-Roll · Ticker · HUD Strip · Instrument) vs. the shipped Two-Row incumbent, each seated in a ghosted Home column so the Recents-above-the-fold trade-off is visible · Instrument recovers the v2 hardware charm (bezel + Life-in-Dots + 12-seg meter) at compact scale · the first-run standby is designed, not dimmed (Standby Voice + Ghost Cells + amber Today Seed) · settled amber-CRT Terminal + Roll material, frozen · static, no animation"
    >
      <div className="flex flex-col gap-12">
        <CockpitCompactStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat. This study keeps the SETTLED cockpit
// material (see /cockpit-grid) and varies only how tall the instrument sits on
// Home. New parts get named here so studio, Swift, and chat share the words.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Strip", "the compact cockpit's whole body — one dark-glass terminal band, no metal Chassis. The Message Line's own glass IS the instrument now; shedding the Chassis is the compaction. 36–38pt tall."],
    ["Chassis (dropped)", "the raised metal bezel that wraps the shipped cockpit. Most compact forms drop it — the Two-Row Baseline still carries it (which is what makes it 231pt), and the INSTRUMENT variant deliberately brings back a slimmer Bezel."],
    ["Bezel", "the thin metal wrap the INSTRUMENT variant reintroduces (BEZEL ON, 80pt). Judged against BEZEL OFF (glass only, 64pt) so the chassis question is decided separately from the dots/meter question."],
    ["Instrument", "the variant that recovers the v2 cockpit's hardware charm at compact scale: the settled Message Line + a slim 12-segment Meter (today vs 7-day average) + a right-docked Life-in-Dots module (last 12 days), a power-LED pip, all in the thin Bezel. 80pt bezel-on / 64pt glass-only."],
    ["Life-in-Dots", "the v2 6×2 dot module, borrowed unchanged: the last 12 days as dots (filled = captured, amber marker = today, outlined = empty), STRK n readout. Docked on the right of the INSTRUMENT strip."],
    ["Meter", "the INSTRUMENT's slim 12-segment bar — fill = today's activity, a brighter amber tick marks where the trailing 7-day average sits, so today reads against its own baseline. Honest twin of the v2 level bars."],
    ["Message Line", "unchanged — one derived fact on a single amber-CRT Terminal line (phosphor mono + scanlines + dither), Cursor when it fits, right-edge fade when it overflows. Fit by monospace advance."],
    ["Standby Voice", "the first-run copy, composed PER VARIANT so it never fades mid-word: STRIP/MICRO lead the full 'STANDING BY — ROLL TAPE TO BEGIN'; the gauge-narrowed HUD and the INSTRUMENT use 'STANDBY — ROLL TAPE'; the TICKER pages read 'STANDING BY' / 'ROLL TAPE TO BEGIN' / 'STRK 0 — START TODAY'."],
    ["Micro-Roll", "the Roll, collapsed to ONE row of the last 18 days at the same cell language — Streak Run lit amber, Today Marker at the right end, STRK n readout. Standby ⇒ Ghost Cells + the amber Today Seed + a 'DAY 1' readout. ~28pt."],
    ["Ghost Cells", "the designed standby treatment for every activity grid (Micro-Roll · HUD gauge · Instrument dots): faint OUTLINED cells sketching the grid that will fill in, with one amber Today Seed — a brighter, softly-lit ring — as the 'you are here' the streak grows from. Static, no animation."],
    ["Ticker Page", "one static page of the TICKER FUSION strip — the message, the freshest Take Log row, or the STRK readout. On device they'd alternate in place (no scroll); here the three page states are drawn side-by-side so nothing animates."],
    ["Streak Gauge", "the HUD STRIP invention — a right-docked lane on the SAME strip carrying a 7-day mini Streak Run + the STRK count, shown simultaneously with the message (not alternating). Its lane costs the message some width, so long lines fade sooner."],
    ["Fold Line", "the dashed red cut in the Context Board marking the bottom of the visible screen (minus the bottom mic-FAB chrome). Recents rows below it are lost — the taller the cockpit, the higher the fold eats into Recents."],
    ["Recents Visible", "the decision metric — how many 38pt Recents rows survive above the Fold Line for a given cockpit height. Printed per variant on the Context Board (INSTRUMENT prints both bezel-on and bezel-off). Home real estate, made countable."],
    ["Two-Row Baseline", "the shipped incumbent, kept for reference: Message Line over one Roll-height slot, inside the Chassis. The thing this study is trying to beat."],
    ["Standby", "the first-run / empty-library state — designed, not a dimmed husk. It leads with the Standby Voice, sketches the activity grids as Ghost Cells around the amber Today Seed, and (per its caption) routes a tap to the recorder rather than the Library, since there's nothing to browse yet."],
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
