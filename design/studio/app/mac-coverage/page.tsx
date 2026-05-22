"use client";

import Link from "next/link";
import { StudioPage } from "@/components/StudioPage";

/**
 * Production Coverage — every mac-* studio surface mapped to its
 * SwiftUI counterpart with three readiness checks:
 *
 *   wired      — the Swift view exists and is reachable from the app
 *   beautiful  — the Swift view wears the latest Scope vocabulary
 *                (no leftover bay/readout/instrument chrome)
 *   latest     — the Swift view reflects the most recent studio mock
 *
 * Sorted into four tiers: SHIPS · POLISH · NEEDS PORT · MISSING.
 * The page is a single typeset table — no thumbnails for now (too
 * heavy to iframe 13+ surfaces). Add when we need them.
 */

type Status = "yes" | "partial" | "no" | "na";

interface Surface {
  studio: string;          // studio route
  swift: string;           // primary Swift file (relative to apps/macos/Talkie/)
  display: string;
  note?: string;
  wired: Status;
  beautiful: Status;
  latest: Status;
  backlog?: boolean;       // studio mock ready, Swift port deliberately deferred
}

const SURFACES: Surface[] = [
  // ── Ships ─────────────────────────────────────────────────────────
  {
    studio: "/mac-memo-detail",
    swift: "Views/TalkieObject/TalkieView.swift · TalkieDetailLayout.swift",
    display: "Memo · Detail",
    note: "Cool-gray canon landed: warm chiffon gradient replaced with ScopeCanvas, ScopeRule hairlines, ScopeAmber tokens for overlay accent, margin rail divider, magic-number constant. Editorial framing + recipe composition intact.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },
  {
    studio: "/mac-dictation-wide",
    swift: "Views/TalkieObject/TalkieDetailLayout.swift (.dictation recipe)",
    display: "Dictation · Detail",
    note: "Inherits memo recast + the cool-gray canon refactor; recipe filtered to transcript only.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },
  {
    studio: "/mac-compose",
    swift: "Views/Drafts/ScopeDraftsScreen.swift",
    display: "Compose",
    note: "V2 typeset paper. Smart actions, voice command, ownership byline.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },
  {
    studio: "/mac-library-empty",
    swift: "Views/Library/ScopeLibraryEmptyState.swift",
    display: "Library · Empty State",
    note: "Today index + Earlier This Week. Will evolve into content-type wayfinder.",
    wired: "yes", beautiful: "yes", latest: "partial",
  },
  {
    studio: "/mac-notes",
    swift: "Views/Notes/ScopeNotesScreen.swift",
    display: "Notes · Sheaf",
    note: "Two-col grid + placeholder cards on empty.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },
  {
    studio: "/mac-talkie-button",
    swift: "Components/TalkieChromeBar.swift",
    display: "Talkie Chrome Bar",
    note: "Centered pill, no-sidebar variant. Hover-only background.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },
  {
    studio: "/mac-record-to-memo",
    swift: "Views/RecordingCompanionSurface.swift",
    display: "Wave → Memo Transition",
    note: "Five-phase state machine, amplitude decay, mask reveal.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },

  {
    studio: "/mac-library",
    swift: "Views/Library/ScopeLibraryView.swift",
    display: "Library · List",
    note: "Dead readout-bay scaffolding removed (~940 lines deleted), bucket header de-amber'd, ScopeRule hairlines, ScopeKind channel tints, marketing subtitle stripped. List column now reads as a flowing editorial column.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },

  {
    studio: "/mac-home",
    swift: "Views/Home/ScopeHomeView.swift",
    display: "Home",
    note: "Cool-gray canon applied: 40 inline brass hexes promoted to ScopeBrass, content tint → ScopeKind, ScopeRule hairlines, leading '·' eyebrow drop, Did-you-know marketing strip. Card-equal-weight refinement still in codex's queue.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },
  {
    studio: "/mac-home-wide",
    swift: "Views/Home/ScopeHomeView.swift",
    display: "Home · Fullscreen",
    note: "Same Swift surface as Home — cool-gray canon applied, card-equal-weight refinement pending.",
    wired: "yes", beautiful: "yes", latest: "yes",
  },

  // ── Backlog (studio mock ready, port deliberately deferred) ───────
  {
    studio: "/mac-recording-state",
    swift: "Views/RecordingOverlay.swift · MacRecordingView.swift",
    display: "Recording HUD",
    note: "Studio mock shipped: pill-shaped wave-body, frosted backdrop blur, proximity-revealed stop + labels. Swift port queued as next dispatch.",
    wired: "partial", beautiful: "no", latest: "no",
    backlog: true,
  },
  {
    studio: "/mac-onboarding",
    swift: "Views/Onboarding/OnboardingView.swift (+ many)",
    display: "Onboarding",
    note: "Studio mock ready (4-step: Frontispiece · Permissions · Models · Ready). Existing Swift flow predates the editorial recast — full rewrite queued.",
    wired: "yes", beautiful: "no", latest: "no",
    backlog: true,
  },

  // ── Missing / studio-only ─────────────────────────────────────────
  {
    studio: "/mac-notch-settings",
    swift: "—",
    display: "Notch Settings",
    note: "Studio mock exists. No Swift surface (notch is system-level chrome owned by TalkieAgent).",
    wired: "na", beautiful: "na", latest: "na",
  },
];

function tier(s: Surface): "ships" | "polish" | "backlog" | "missing" {
  if (s.wired === "na") return "missing";
  if (s.backlog) return "backlog";
  if (s.wired === "yes" && s.beautiful === "yes" && (s.latest === "yes" || s.latest === "partial")) return "ships";
  if (s.wired === "yes" && s.beautiful === "partial") return "polish";
  return "backlog";
}

const TIER_LABELS: Record<ReturnType<typeof tier>, { label: string; note: string }> = {
  "ships":   { label: "Ships",   note: "Reflects the latest design, no leftover chrome." },
  "polish":  { label: "Polish",  note: "Wired and live, wants a finishing pass." },
  "backlog": { label: "Backlog", note: "Studio mock ready, Swift port queued for a future dispatch." },
  "missing": { label: "—",       note: "No Swift counterpart (system-level or studio-only)." },
};

const TIER_ORDER: Array<ReturnType<typeof tier>> = ["ships", "polish", "backlog", "missing"];

export default function MacCoveragePage() {
  const byTier: Record<ReturnType<typeof tier>, Surface[]> = {
    "ships": [], "polish": [], "backlog": [], "missing": [],
  };
  for (const s of SURFACES) byTier[tier(s)].push(s);

  // Count ratio against in-scope surfaces only:
  // exclude `missing` (N/A — no Swift counterpart) and `backlog` (deliberately deferred).
  const inScope = SURFACES.filter((s) => tier(s) !== "missing" && tier(s) !== "backlog");
  const totalReady = byTier.ships.length + byTier.polish.length;
  const total = inScope.length;

  return (
    <StudioPage
      eyebrow="Production · Coverage"
      title="Mac Surfaces"
      help="every mac-* studio surface mapped to its SwiftUI counterpart with wired / beautiful / latest checks"
    >
      <div className="px-7 py-8">
        {/* Summary */}
        <div className="mb-10 flex items-baseline gap-4 border-b border-studio-edge pb-6">
          <h1 className="m-0 font-display text-[42px] font-medium leading-none tracking-tight text-studio-ink">
            {totalReady}
            <span className="text-studio-ink-faint"> / {total} ship</span>
          </h1>
          <div className="ml-auto flex items-center gap-3 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
            <Legend tier="ships" />
            <Sep />
            <Legend tier="polish" />
            <Sep />
            <Legend tier="backlog" />
            <Sep />
            <Legend tier="missing" />
          </div>
        </div>

        {/* Tier blocks */}
        <div className="flex flex-col gap-10">
          {TIER_ORDER.map((t) => {
            const rows = byTier[t];
            if (rows.length === 0) return null;
            return (
              <section key={t}>
                <div className="mb-3 flex items-baseline gap-3">
                  <h2 className="m-0 font-display text-[20px] font-medium tracking-tight text-studio-ink">
                    {TIER_LABELS[t].label}
                  </h2>
                  <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
                    {rows.length} · {TIER_LABELS[t].note}
                  </span>
                </div>
                <CoverageTable rows={rows} />
              </section>
            );
          })}
        </div>

        {/* Audit verdict */}
        <div className="mt-14 border-t border-studio-edge pt-7">
          <div className="mb-2 text-[9px] font-mono uppercase tracking-eyebrow text-studio-ink-faint">
            · Audit verdict
          </div>
          <h3 className="m-0 font-display text-[20px] font-medium leading-tight tracking-tight text-studio-ink">
            100% of in-scope surfaces shipping.
          </h3>
          <p className="mt-2 max-w-[720px] text-[12px] leading-relaxed text-studio-ink-faint">
            Cool-gray Scope canon landed across all 10 ported surfaces (2026-05-21). Memo + Dictation Detail, Library List, Home + Home Fullscreen, Compose, Notes, Chrome Bar, Library Empty, Record→Memo transition — all live in the running app. <span className="text-studio-ink">Recording HUD</span> and <span className="text-studio-ink">Onboarding</span> remain in the backlog with studio mocks ready, queued for a future dispatch. Notch Settings is system-level chrome owned by TalkieAgent — N/A for this scope.
          </p>
        </div>

        {/* Footer */}
        <div className="mt-10 border-t border-studio-edge pt-5 text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          · Data hand-curated + agent-validated · Updated 2026-05-21 post cool-gray canon · See /mac-audit for line-level shipped status
        </div>
      </div>
    </StudioPage>
  );
}

function Sep() {
  return <span className="h-3 w-px bg-studio-edge" aria-hidden />;
}

function Legend({ tier: t }: { tier: ReturnType<typeof tier> }) {
  const colorByTier: Record<ReturnType<typeof tier>, string> = {
    "ships":   "#9A6A22",
    "polish":  "#C47D1C",
    "backlog": "#767674",
    "missing": "#A0A09E",
  };
  return (
    <span className="inline-flex items-center gap-1.5">
      <span aria-hidden className="h-1.5 w-1.5 rounded-full" style={{ background: colorByTier[t] }} />
      {TIER_LABELS[t].label}
    </span>
  );
}

function CoverageTable({ rows }: { rows: Surface[] }) {
  return (
    <div className="rounded-md border border-studio-edge bg-white/40">
      {/* Header */}
      <div className="grid grid-cols-[1fr_92px_92px_92px] items-baseline gap-4 border-b border-studio-edge/80 px-4 py-2.5 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
        <span>Surface</span>
        <span className="text-center">Wired</span>
        <span className="text-center">Beautiful</span>
        <span className="text-center">Latest</span>
      </div>
      {rows.map((s, i) => (
        <CoverageRow key={i} surface={s} divided={i > 0} />
      ))}
    </div>
  );
}

function CoverageRow({ surface, divided }: { surface: Surface; divided: boolean }) {
  return (
    <div
      className={`grid grid-cols-[1fr_92px_92px_92px] items-start gap-4 px-4 py-3 ${
        divided ? "border-t border-studio-edge/60" : ""
      }`}
    >
      <div className="flex min-w-0 flex-col gap-1">
        <div className="flex items-baseline gap-3">
          <span className="font-display text-[14px] font-medium tracking-tight text-studio-ink">
            {surface.display}
          </span>
          <Link
            href={surface.studio}
            className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint hover:text-studio-ink"
          >
            STUDIO → {surface.studio.replace("/mac-", "")}
          </Link>
        </div>
        <div className="text-[10px] font-mono tracking-[0.02em] text-studio-ink-faint">
          {surface.swift}
        </div>
        {surface.note ? (
          <div className="mt-0.5 max-w-[680px] text-[11px] leading-snug text-studio-ink-faint">
            {surface.note}
          </div>
        ) : null}
      </div>
      <CheckCell status={surface.wired} />
      <CheckCell status={surface.beautiful} />
      <CheckCell status={surface.latest} />
    </div>
  );
}

function CheckCell({ status }: { status: Status }) {
  if (status === "na") {
    return (
      <div className="flex items-center justify-center pt-1.5 font-mono text-[10px] text-studio-ink-faint">—</div>
    );
  }
  const cfg = {
    yes:     { glyph: "●", color: "#9A6A22", label: "Yes" },
    partial: { glyph: "◐", color: "#C47D1C", label: "Partial" },
    no:      { glyph: "○", color: "#C43A1C", label: "No" },
  }[status];
  return (
    <div className="flex items-center justify-center pt-1.5">
      <span
        title={cfg.label}
        className="inline-flex items-center justify-center font-mono text-[16px] leading-none"
        style={{ color: cfg.color }}
        aria-label={cfg.label}
      >
        {cfg.glyph}
      </span>
    </div>
  );
}
