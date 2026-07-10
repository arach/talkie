import { StudioPage } from "@/components/StudioPage";
import { LEDMessengerStudio } from "@/components/studies/LEDMessenger";

export default function LEDMessengerStudy() {
  return (
    <StudioPage
      eyebrow="Home · LED Messenger · a place to write to the user"
      title="LED Messenger"
      help="edit components/studies/LEDMessenger.tsx · shares the 5×7 glyph table in components/studies/ledFont.ts with /home-cockpit · static, no animation"
    >
      <div className="flex flex-col gap-12">
        <LEDMessengerStudio />
        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

// One vocabulary for studio · Swift · chat. A non-animating dot-matrix message
// board — its only job is to write a short greeting to the user in a generated
// LED font. Each part names what it is; the material knobs change texture only,
// never the frozen Board geometry.
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Board", "the dark-glass message panel at true iPhone content width (366). Its one job is to write a short message to the user. Frozen geometry — a piece of hardware, not a layout that reflows. Static, always."],
    ["Screen", "the always-dark instrument glass (#050505) the dots sit on, framed by the metal chassis. Ignores light/dark so it reads as lit glass everywhere — same substrate as the cockpit."],
    ["Cell", "one dot in the matrix. Round or square (Cell shape), size set by Pitch. The atom the whole board is built from."],
    ["Glyph", "one 5×7 character painted in lit Cells — amber on the ghost grid. Drawn from the shared LED font (components/studies/ledFont.ts), the same table the cockpit marquee uses."],
    ["Pitch", "dot diameter + gap (Fine / Medium / Coarse) — a material knob. Also the axis Fit shrinks along: when a message overflows, Pitch steps down before anything clips."],
    ["Ghost Grid", "the unlit dot field faintly visible behind the glyphs (amber ~6%) — the tell of a real dot-matrix panel. Toggles off to pure dark, so the message floats on black."],
    ["Bloom", "the soft amber glow around each lit Cell — the phosphor spill. Toggles to flat (no shadow) for a hard-pixel read."],
    ["Writer", "the live text input that renders straight to the Board. The core of the study — 'a place to write to the user.' Unknown characters render as a Placeholder, not a crash."],
    ["Placeholder", "a dim hollow box drawn for any character the font can't render, so unsupported input reads as 'unsupported' instead of clipping or vanishing."],
    ["Fit", "the wrap + shrink logic that keeps any message inside the frozen Board: greedy word-wrap to more lines first, then step Pitch down until it fits. The caption reports what it did (WRAPPED · SHRUNK TO FIT)."],
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
