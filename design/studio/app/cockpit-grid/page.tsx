import { StudioPage } from "@/components/StudioPage";
import { CockpitGridStudio } from "@/components/studies/CockpitGrid";

export default function CockpitGridStudy() {
  return (
    <StudioPage
      eyebrow="Home · Cockpit Grid · the converged composition"
      title="Home · Cockpit Grid"
      help="edit components/studies/CockpitGrid.tsx · three full-width rows — Message Line (Terminal, the settled treatment) over the Take Log (recent captures) over the Roll (full-width contribution calendar) · Matrix kept in ledBoard.tsx for /led-messenger, demoted here to a settled-decision reference · static, no animation"
    >
      <div className="flex flex-col gap-12">
        <CockpitGridStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat. The converged composition: same
// chassis / dark-screen material, recomposed as three full-width stacked rows —
// the Message Line (Terminal) over the Take Log over the Roll. Each part names
// what it is + what real iOS source feeds it.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Chassis", "the raised metal bezel around the instrument (bezelChassis metal matte #303030). Frozen — the shipped outer shell, carried from the cockpit."],
    ["Screen", "the always-dark instrument glass (#050505) with the TALKIE · status · clock header. Ignores light/dark so it reads as lit glass everywhere."],
    ["Composition", "the three full-width rows inside the screen, stacked: Message Line → Take Log → the Roll. No more 2-column grid. Layout is frozen; only the data + state change across scenarios."],
    ["Message Line (Terminal)", "the settled top row — one glyph row tall, ONE derived fact (LAST TAKE 2H AGO · ROLL TAPE TODAY · PARAKEET DOWNLOADING · STANDING BY…), rendered in the amber-CRT terminal. Fit by advance, then a right-edge fade when it overflows. Terminal is THE treatment — the exploration is closed; the shared Matrix LED board is kept in ledBoard.tsx only for /led-messenger and appears here just as a demoted reference row."],
    ["Scanline", "the thin dark horizontal raster lines over the terminal glass (Message Line + Take Log) — a repeating 1-in-3px dark band. Static, no roll."],
    ["Dither", "the faint Bayer-ish checkerboard alpha (screen-blended) that gives the terminal phosphor its low-fi grain. Uniform + static."],
    ["Phosphor", "the amber glow on the terminal text — soft text-shadow bloom + a radial screen glow, the warm-CRT tell. Shared by the Message Line + the Take Log rows. No flicker."],
    ["Cursor", "the static block cursor ▮ after a Message Line that fits; when the line overflows the cursor gives way to a right-edge phosphor fade."],
    ["Take Log", "the middle row — a tape-log readout replaying the most recent captures, up to three mono phosphor rows on the dark glass, newest first. Each row: short title (truncates) · age (2H · 1D) · duration (0:42). Fed by HomeFeed.recentItems / VoiceMemo (title, createdAt, duration) + KeyboardDictationStore. Empty library ⇒ a dim NO TAKES ON TAPE line."],
    ["the Roll", "the promoted, full-width bottom row — a GitHub-contribution calendar, 18 weeks × 7 days, column-major, at the same praised cell/marker language. Cell intensity = captures that day (2–3 brightness steps). Fed by createdAt across VoiceMemo + KeyboardDictationStore + CaptureStore. Was the right-column Almanac; promotion, not a rework."],
    ["Streak Run", "the current consecutive-capture-day run lit amber across the Roll, ending on today (or yesterday, when today has no capture yet). Length = the STRK n readout. Derived from the Roll's own days."],
    ["Today Marker", "the newest Roll cell given the marker treatment — amber + glow when captured today, an unlit amber ring when the day is still empty. Consistent with the Life-in-Dots marker dot."],
    ["Station Ident", "the header status readout (READY / STANDBY / PREP) + wall clock. Rolls up engine + systems state — the instrument's 'on air' tell. No REC/VU override in this study."],
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
