import { StudioPage } from "@/components/StudioPage";
import { HomeCockpitStudio } from "@/components/studies/HomeCockpit";

export default function HomeCockpitStudy() {
  return (
    <StudioPage
      eyebrow="Home · Cockpit v2 · content pass"
      title="Home · Cockpit v2"
      help="edit components/studies/HomeCockpit.tsx · content/material swap over HomeCockpit in HomeNextView.swift (453-791) · layout frozen"
    >
      <div className="flex flex-col gap-12">
        <HomeCockpitStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat. Cockpit v2 keeps the shipped
// geometry (chassis / screen / three lanes / right module / one detail line);
// only the CONTENT and the material of the detail line change. Each part
// names what it is + what real iOS source feeds it.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Chassis", "the raised metal bezel around the instrument (bezelChassis metal matte #303030). Frozen — the shipped outer shell, unchanged in v2."],
    ["Screen", "the always-dark instrument glass (#050505) with the TALKIE · status · clock header. Ignores light/dark so it reads as lit glass everywhere."],
    ["Lane · TAKES", "row 1 — today's capture activity. LABEL · value · META over a Meter. Fed by HomeFeed.todayStats + VoiceMemo.duration sums."],
    ["Lane · ENGINE", "row 2 — on-device transcription engine. Value = Parakeet / Apple Speech; META = HOT/COLD/LOADING/DL n% / PROCESSING n. Fed by ParakeetModelManager.shared.state + .isWarmedUp."],
    ["Lane · SYSTEMS", "row 3 — dictation readiness roll-up. Value = All go / first blocker; META = GO/WARN/HOLD. Fed by DictationReadinessChecker.readiness (5 checks)."],
    ["Meter", "the 12-segment level bar under each lane. Semantics per lane: TAKES = today vs 7-day avg · ENGINE = warmth / download progress · SYSTEMS = fraction of checks passing. Frozen geometry."],
    ["Life-in-Dots", "the right-hand 6×2 dot grid, repurposed: 12 dots = last 12 days (filled = captured that day), amber marker on today. Readout = STRK n (streak). Fed by createdAt across the three stores."],
    ["Marquee", "the LED dot-matrix line under the screen (replaces the plain detail text) — true 5×7 dot glyphs, amber on dark, rotating real messages. Empty library ⇒ STANDING BY leads. Derived line."],
    ["REC Override", "recording state — the whole screen goes live: Meters become mag-tape VU (amber centerline + tape-head marker), header flips to REC + elapsed. Gated by RecordingSheetController.isPresented + DictationMicMonitor.level."],
    ["Station Ident", "the header status readout (READY / STANDBY / PREP / HOLD / REC) + time-of-day marquee idents (DAY SHIFT / NIGHT DESK). Rolls up engine + systems + clock — the instrument's 'on air' tell."],
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
