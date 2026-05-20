import Link from "next/link";

const STUDIES = [
  {
    slug: "themes",
    name: "Themes",
    kind: "Articulation",
    blurb:
      "The 4 iOS themes (Scope / Midnight / Tactical / Ghost) — typography spec, palette swatches, behavior flags, identity. Read first.",
  },
  {
    slug: "home",
    name: "Home",
    kind: "Theme study",
    blurb:
      "Talkie's canonical home — STATION card, Live Action Bus, Recent list, ambient voice button. The screen where the voice-pivot pattern lives at rest.",
  },
  {
    slug: "library",
    name: "Library",
    kind: "Theme study",
    blurb:
      "Library screen mocked across all 4 themes. Soft underline tabs, transcript preview line, integrated search, variant leading icons by source.",
  },
  {
    slug: "compose",
    name: "Compose",
    kind: "Theme + state study",
    blurb:
      "Text-editing turns on existing content (a conference bio). State machine: idle / dictating / voice command / generating / diff.",
  },
  {
    slug: "complications",
    name: "Complications",
    kind: "Layout study",
    blurb:
      "Action-placement language for iPhone. Compare the current 4-corners-plus-FAB pattern against a 3-slot liquid-glass tray and a hybrid — across all themes.",
  },
  {
    slug: "recording-sheet",
    name: "Recording Sheet",
    kind: "Scheme study",
    blurb:
      "iPhone recording sheet — waveform style (sparkle / printout / brass / phosphor / hybrid) × 9 material schemes.",
  },
  {
    slug: "iphone-themes",
    name: "iPhone Themes",
    kind: "Scaffold",
    blurb:
      "Multi-theme iPhone mock shell with empty PhoneFrame slots. Use this when scaffolding a new iOS screen study before promoting it to its own route.",
  },
  {
    slug: "agent-bay",
    name: "Agent Bay",
    kind: "Scheme study (macOS)",
    blurb:
      "Color schemes and treatment toggles for the macOS Home agent bay. 9 schemes × 6 treatments.",
  },
  {
    slug: "settings",
    name: "Settings",
    kind: "Pattern study",
    blurb:
      "Three directional sketches for Talkie's Settings surface — Console (dense single scroll), Stations (spatial card grid), Inspector (desktop-style chips + panel). Fresh ideas, no donor crutch.",
  },
];

export default function Landing() {
  return (
    <main className="mx-auto max-w-page px-7 py-8">
      <div className="border-b border-studio-edge pb-5 mb-8">
        <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          · Talkie · Design Studio
        </div>
        <h1 className="font-display text-[28px] font-medium leading-none tracking-tight text-studio-ink mt-1">
          Studies
        </h1>
      </div>

      <ul className="grid gap-3">
        {STUDIES.map((s) => (
          <li key={s.slug}>
            <Link
              href={`/${s.slug}`}
              className="group block border border-studio-edge rounded-md px-5 py-4 transition-colors hover:border-studio-ink"
            >
              <div className="flex items-baseline gap-3">
                <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint group-hover:text-studio-ink transition-colors">
                  ·
                </div>
                <div className="font-display text-[19px] font-medium tracking-tight text-studio-ink">
                  {s.name}
                </div>
                <div className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
                  {s.kind}
                </div>
              </div>
              <p className="text-[13px] leading-relaxed text-studio-ink-faint mt-1.5 ml-5">
                {s.blurb}
              </p>
            </Link>
          </li>
        ))}
      </ul>

      <p className="mt-12 text-[11px] leading-relaxed text-studio-ink-faint max-w-[640px]">
        Each study is a Next route. Shared primitives (
        <code className="font-mono text-[10px] text-studio-ink">
          SchemeCard
        </code>
        ,{" "}
        <code className="font-mono text-[10px] text-studio-ink">
          PhoneFrame
        </code>
        , <code className="font-mono text-[10px] text-studio-ink">ToggleBar</code>
        ) live in <code className="font-mono text-[10px] text-studio-ink">components/</code>;
        scheme + theme data live in{" "}
        <code className="font-mono text-[10px] text-studio-ink">lib/</code>. Add
        a new study by dropping a route in{" "}
        <code className="font-mono text-[10px] text-studio-ink">app/</code> and
        composing the primitives.
      </p>
    </main>
  );
}
