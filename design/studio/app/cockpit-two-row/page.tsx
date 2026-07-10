import { StudioPage } from "@/components/StudioPage";
import { CockpitTwoRowStudio } from "@/components/studies/CockpitTwoRow";

export default function CockpitTwoRowStudy() {
  return (
    <StudioPage
      eyebrow="Home · Cockpit Two-Row · the converged cockpit"
      title="Home · Cockpit Two-Row"
      help="edit components/studies/CockpitTwoRow.tsx · the convergence of /cockpit-compact — the BEZEL ON metal wrap (the frame) around the Message Line (no header — no TALKIE repeat, no clock, no status word) over a user-toggled big section: THE ROLL (18×7 calendar) ⁄ GAUGES (TAKES count + Meter · TIME m:ss + Meter · STRK Life-in-Dots — instruments, not a Take Log replay). A right-docked Docked Readout replaces the clock (STRK n / take count · shown with + without). The Toggle is a tiny hardware two-position Bay Selector; the studio is static so both positions are drawn side by side. The Message Line as a system travels ghosted non-Home contexts (Library · Ask AI · Settings). Header dropped → the Console comes in under the 231pt baseline. Settled amber-CRT Terminal + Roll + instrument material, frozen. Static."
    >
      <div className="flex flex-col gap-12">
        <CockpitTwoRowStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat. This study is a CONVERGENCE — it
// re-seats settled parts (see /cockpit-grid + /cockpit-compact) rather than
// redesigning them. The new composed parts get named here so studio, Swift, and
// chat share the words.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Console", "the whole converged instrument on Home — the BEZEL ON metal wrap (the frame the verdict kept) around the Message Line over the toggled big section. No header row: the Message Line goes straight on top. 220pt tall, under the old 231pt Two-Row Baseline."],
    ["Bezel", "the raised metal wrap around the screen — the frame. Kept verbatim from /cockpit-compact's INSTRUMENT (BEZEL ON): linear metal gradient, hairline dark border, inset top highlight. This is the hardware charm the user loved; it is not up for redesign."],
    ["Message Line", "unchanged — one derived fact on a single amber-CRT Terminal line (phosphor mono + scanlines + dither), a static block Cursor when it fits, a right-edge phosphor fade when it overflows. Sits straight on top of the Bay with NO header above it (iOS already shows a clock top-right)."],
    ["Docked Readout", "the small right-docked slot ON the Message Line that replaces the dropped clock with 'something useful' — HUD-strip vocabulary: a hairline-divided lane with a whisper of glass carrying STRK n or the day's take count. A toggleable option; shown with + without."],
    ["Toggle", "the tiny hardware two-position Bay Selector on the Bay's label row — a recessed dark track with ROLL ⁄ GAUGES segments, the active bay lit amber phosphor, the other dim. User-controlled on device; the studio is static, so both positions are drawn side by side with the affordance shown lit in each."],
    ["Bay", "the toggled big section under the Message Line — one recessed well, a fixed 144pt tall, that both pages fill so the Toggle swaps content with no layout shift. Its label row carries the Toggle + a contextual readout (STRK n on ROLL, TODAY · 7-DAY AVG on GAUGES)."],
    ["Roll Bay", "THE ROLL page — the 18×7 contribution calendar, as-is from /cockpit-grid: cell intensity = captures that day, the current Streak Run lit amber, the Today Marker at the newest cell, STRK n on the label row. Standby ⇒ Ghost Cells + the amber Today Seed."],
    ["Gauge Bay", "the GAUGES page — instrument content that reads gauge-like, NOT a Take Log replay (the list is dead; ENGINE stays killed). Three lanes: TAKES (count + 12-seg Meter vs 7-day avg + pace) · TIME (m:ss + Meter) · STRK (Life-in-Dots + count). Honest per-day sources, no placeholders."],
    ["Meter", "the settled slim 12-segment bar — fill = today's value, a brighter amber tick marks where the trailing 7-day average sits, so today reads against its own baseline. Reused by the TAKES + TIME gauges. Pace label ▲ ABOVE / = AT / ▼ BELOW AVG from the delta."],
    ["Life-in-Dots", "the v2 6×2 dot module, borrowed unchanged: the last 12 days as dots (filled = captured, amber = today, outlined = empty) + STRK n. It is the STRK gauge in the Gauge Bay."],
    ["Strip System", "the Message Line treated as a system, not a Home-only widget — the bare 36pt strip (no Bezel) seated in ghosted non-Home contexts (Library · Ask AI · Settings), each with contextual copy ('3 TAKES TODAY' · 'ASK ANYTHING — HOLD TO TALK' · 'PARAKEET READY'). One message area travelling the app."],
    ["Ghost Cells", "the designed standby treatment for every activity grid (Roll · Life-in-Dots · Meter): faint OUTLINED cells sketching the grid that will fill in, with one amber Today Seed — a brighter, softly-lit ring — as the 'you are here' the streak grows from. Static."],
    ["Standby Voice", "the first-run copy: the full 'STANDING BY — ROLL TAPE TO BEGIN' on the Message Line, DAY 1 on the readouts. The empty-library state is designed, not a dimmed husk — and it routes a tap to the recorder, not the Library, since there is nothing to browse yet."],
    ["Fold Line", "the dashed red cut in the Context Board marking the bottom of the visible screen (minus the bottom mic-FAB chrome). Recents rows below it are lost — the taller the Console, the higher the fold eats into Recents."],
    ["Recents Visible", "the decision metric — how many 38pt Recents rows survive above the Fold Line. The Console prints ~4.1 rows (vs the old 231pt baseline's 3.8, and the compact Instrument family's 7.8–8.2): the honest price of the rich two-row option."],
  ];
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em] text-stone-500">· names</span>
        <span className="italic text-stone-400" style={{ fontSize: 12 }}>
          one vocabulary for studio · Swift · chat
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      <div
        className="grid"
        style={{ gridTemplateColumns: "150px 1fr", rowGap: 8, columnGap: 18, padding: "16px 20px", background: "#FFFFFF", border: "0.5px solid #DEDEDD", borderRadius: 8 }}
      >
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-stone-700">{name}</span>
            <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{def}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
