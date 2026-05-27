import Link from "next/link";

type Platform = "macOS" | "iOS" | "Shared";

interface Study {
  slug: string;
  name: string;
  kind: string;
  platform: Platform;
  blurb: string;
}

const STUDIES: Study[] = [
  // — macOS —
  {
    slug: "mac-home",
    name: "Home",
    kind: "Composition study",
    platform: "macOS",
    blurb:
      "Full macOS Home composition. Reintegrates the original component taxonomy (stats / actions / activity / discovery / status) into the simplified Scope design language.",
  },
  {
    slug: "mac-learn",
    name: "Learn",
    kind: "Composition study",
    platform: "macOS",
    blurb:
      "Replacement for the data-listing Stats page — an interstitial that surfaces what Talkie can do. Hero · Ask Talkie agent box · Did-you-know feature recap · feature atlas · integrations · what's new.",
  },
  {
    slug: "mac-memo-detail",
    name: "Memo Detail",
    kind: "Composition study",
    platform: "macOS",
    blurb:
      "Right-hand pane of the Library split view, redesigned as an editorial document. Masthead replaces the metric pills + four-column grid; transcript gets gutter timecodes + margin highlights; player rail sits as a typesetter's bar at the foot.",
  },
  {
    slug: "agent-bay",
    name: "Agent Bay",
    kind: "Scheme study",
    platform: "macOS",
    blurb:
      "Color schemes and treatment toggles for the macOS Home agent bay. 9 schemes × 6 treatments.",
  },
  {
    slug: "mac-skills",
    name: "Skills",
    kind: "Composition study",
    platform: "macOS",
    blurb:
      "Committed shape for the macOS Skills surface. One tab, one page, the whole loop — starters below, editor bay (chat ↔ markup) above, console under it, your skills at the foot. Semantic skill syntax (WHEN / WITH / DO / THEN). Pre-Swift.",
  },
  {
    slug: "mac-skill-forge",
    name: "Skill Forge",
    kind: "Framing study (archive)",
    platform: "macOS",
    blurb:
      "Earlier framing comparison that produced mac-skills — markup-primary, chat-driven, and trifold layouts. Kept as a record of the alternatives considered.",
  },
  {
    slug: "mac-workflows",
    name: "Workflows",
    kind: "Composition study",
    platform: "macOS",
    blurb:
      "Three-column workflows surface — list · step sheet · run inspector. Theme-aware (dark amber + light bone). v0 strips the donor's embellishment (prompt bodies, cost meter, multi-tab inspector) for a readable skeleton; embellishments earn their way back in. Pre-Swift.",
  },

  // — iOS —
  {
    slug: "themes",
    name: "Themes",
    kind: "Articulation",
    platform: "iOS",
    blurb:
      "The 4 iOS themes (Scope / Midnight / Tactical / Ghost) — typography spec, palette swatches, behavior flags, identity. Read first.",
  },
  {
    slug: "home",
    name: "Home",
    kind: "Theme study",
    platform: "iOS",
    blurb:
      "Talkie's canonical iOS home — STATION card, Live Action Bus, Recent list, ambient voice button. The screen where the voice-pivot pattern lives at rest.",
  },
  {
    slug: "library",
    name: "Library",
    kind: "Theme study",
    platform: "iOS",
    blurb:
      "Library screen mocked across all 4 themes. Soft underline tabs, transcript preview line, integrated search, variant leading icons by source.",
  },
  {
    slug: "compose",
    name: "Compose",
    kind: "Theme + state study",
    platform: "iOS",
    blurb:
      "Text-editing turns on existing content (a conference bio). State machine: idle / dictating / voice command / generating / diff.",
  },
  {
    slug: "complications",
    name: "Complications",
    kind: "Layout study",
    platform: "iOS",
    blurb:
      "Action-placement language for iPhone. Compare the current 4-corners-plus-FAB pattern against a 3-slot liquid-glass tray and a hybrid — across all themes.",
  },
  {
    slug: "recording-sheet",
    name: "Recording Sheet",
    kind: "Scheme study",
    platform: "iOS",
    blurb:
      "iPhone recording sheet — waveform style (sparkle / printout / brass / phosphor / hybrid) × 9 material schemes.",
  },
  {
    slug: "iphone-themes",
    name: "iPhone Themes",
    kind: "Scaffold",
    platform: "iOS",
    blurb:
      "Multi-theme iPhone mock shell with empty PhoneFrame slots. Use this when scaffolding a new iOS screen study before promoting it to its own route.",
  },
  {
    slug: "agent-bay",
    name: "Agent Bay",
    kind: "Scheme study (macOS)",
    platform: "macOS",
    blurb:
      "Color schemes and treatment toggles for the macOS Home agent bay. 9 schemes × 6 treatments.",
  },
  {
    slug: "settings",
    name: "Settings",
    kind: "Pattern study",
    platform: "iOS",
    blurb:
      "Three directional sketches for Talkie's Settings surface — Console (dense single scroll), Stations (spatial card grid), Inspector (desktop-style chips + panel). Fresh ideas, no donor crutch.",
  },
  {
    slug: "terminal",
    name: "Terminal",
    kind: "Surface study",
    platform: "iOS",
    blurb:
      "SSH session list — saved hosts with status dots, last-connected timestamps, source labels. Populated + empty states. Mirrors iOS TerminalNext.",
  },
  {
    slug: "bridge-detail",
    name: "Mac Bridge Detail",
    kind: "Surface study",
    platform: "iOS",
    blurb:
      "Replaces the legacy BridgeSettingsView sheet. Status + link-health metric strip + saved sessions + actions. Paired and unpaired states. Mirrors iOS BridgeDetailNext.",
  },
  {
    slug: "camera",
    name: "Camera",
    kind: "Surface study",
    platform: "iOS",
    blurb:
      "Full-screen camera capture with cropping marks, status pill, shutter FAB. Preview / captured / denied states. Mirrors iOS CameraCaptureNext.",
  },
  {
    slug: "ask-ai",
    name: "Ask AI",
    kind: "Surface study",
    platform: "iOS",
    blurb:
      "Agentic loop surface — multi-turn prompt/response with channel-labelled turns (T01/T02…), agent presets, telemetry meta. Idle / thinking / multi-turn states.",
  },
  {
    slug: "read-aloud",
    name: "Read Aloud",
    kind: "Surface study",
    platform: "iOS",
    blurb:
      "TTS playback surface — instrument-style transport, voice / rate / pitch controls, source picker, multi-item queue. Idle / playing / queue states. Audio-output counterpart to Camera.",
  },
  {
    slug: "architecture",
    name: "Architecture",
    kind: "Site map",
    platform: "Shared",
    blurb:
      "Every routable surface in the Next shell, grouped by domain. Inbound + outbound entry counts, orphan flags, proposed wires to close gaps. v2 (in flight): canvas-based UX journey map with embedded mini-views.",
  },
  {
    slug: "completion",
    name: "Feature Completion",
    kind: "Roadmap",
    platform: "Shared",
    blurb:
      "Release-train view of the rebuild — M1 (Next shell + Phase 1 + Phase 2) shipped, M2 entry-point wires queued, M3 polish, M4 missing donor surfaces, M5 new scope (share ext, widget, watch), M6 system polish.",
  },
  {
    slug: "parity",
    name: "Parity Audit",
    kind: "Donor vs Next",
    platform: "Shared",
    blurb:
      "6-agent swarm review comparing master (donor) vs feat/ios-shell-phase-0 (Next) across 6 clusters — home/library, capture, compose/memo, settings/onboarding/sign-in, bridge/deck, recording/workflows/ask AI. Tagged MISSING / STUB / CHANGED / NEW.",
  },
];

const PLATFORMS: Platform[] = ["macOS", "iOS"];

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

      {PLATFORMS.map((platform) => {
        const studies = STUDIES.filter((s) => s.platform === platform);
        if (studies.length === 0) return null;
        return (
          <section key={platform} className="mb-10">
            <div className="mb-3 flex items-baseline gap-3">
              <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
                · {platform}
              </div>
              <div className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
                {studies.length} {studies.length === 1 ? "study" : "studies"}
              </div>
              <div className="ml-3 h-px flex-1 bg-studio-edge" />
            </div>
            <ul className="grid gap-3">
              {studies.map((s) => (
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
          </section>
        );
      })}

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
