"use client";

/**
 * Mac Agent Home (Shell) — the TalkieAgent home / library surface.
 *
 * Built ON the canonical SCOPE substrate (cool-gray instrument case),
 * with the KPI row rendered as the Talkie Mac Home **Agent Bay** — the
 * warm-paper instrument panel (runtime rail · divided stat cells with
 * sparklines · signal-path footer) that already represents the agent in
 * Talkie's home. Donor: components/studies/Bay.tsx + MacHome.tsx +
 * AgentHomeShellView.swift.
 *
 * The bay's top rail carries the agent identity ("RUNNING · AG-01 /
 * TALKIE.AGENT"), so we drop the separate page header entirely and land
 * straight in the bay. Serif is the studio's `font-display` (Newsreader)
 * → app's Cormorant.
 */

import React from "react";
import { SCOPE } from "@/lib/scope-tokens";
import { OpsIcon, type OpsIconName } from "./primitives/OpsIcon";

const OPS = {
  bg: SCOPE.canvas, // #F8F8F7 frosted instrument case
  chrome: SCOPE.chrome, // #E7E7E6 rail + footer strips
  surface: SCOPE.white, // card fill
  ink: SCOPE.ink, // #232423 cool dark
  muted: SCOPE.inkMid, // #3A3A38 secondary text
  dim: SCOPE.inkFaint, // rgba .55 labels
  hairline: SCOPE.edge, // #DEDEDD
  hairlineSubtle: SCOPE.edgeSubtle, // #E6E6E5
  amber: SCOPE.amber, // #C47D1C
  amberFaint: SCOPE.amberFaint,
  amberSoft: SCOPE.amberSoft,
  brass: SCOPE.brass, // #9A6A22
};

// Agent Bay — warm paper instrument panel (CHIFFON-family) on the cool case.
const BAY = {
  bg: "#F3EFE2", // warm paper
  strip: "#EDE8D6", // top / bottom rails
  edge: "#E2DAC6", // warm dividers + border
  accent: "#9A6A22", // brass — dot + sparklines
  glow: "rgba(154,106,34,0.40)",
  ink: SCOPE.ink, // numbers
  inkFaint: SCOPE.inkFaint, // labels / runtime
  inkSubtle: SCOPE.inkFainter, // right-rail captions / time
};

const MONO = '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace';
// Inter = the studio body sans. The home study labels its sections with a
// faint, wide-tracked uppercase eyebrow in this voice (e.g. "· AGENT") —
// editorial chrome, distinct from the bay's internal mono.
const SANS = "Inter, ui-sans-serif, system-ui, -apple-system, sans-serif";

export type AgentHomeVariant = "history" | "home";

type StatSpec = { value: string; label: string };

// The Agent Bay lives ONLY on the Home page — it's the runtime "instrument"
// moment. History is a plain read-only recordings list with no bay, so the
// surfaces don't feel like the same screen twice.
const HOME_BAY: {
  runtime: string;
  runtimeRight: string;
  footer: string;
  time: string;
  stats: StatSpec[];
} = {
  runtime: "Running · AG-01 / TALKIE.AGENT",
  runtimeRight: "Local only · No telemetry",
  footer: "· Trig · Live · Signal Path · Local",
  time: "10:29 AM",
  // Three-column bay (vs Talkie's wider home bay) — the agent's own tally:
  // dictations + captures it owns, plus a streak so it reads "live".
  stats: [
    { value: "3,919", label: "Dictations" },
    { value: "342", label: "Captures" },
    { value: "12", label: "Day Streak" },
  ],
};

export function MacAgentHomeShell({
  variant = "history",
}: {
  variant?: AgentHomeVariant;
}) {
  const isHome = variant === "home";

  return (
    <div
      className="grid"
      style={{
        gridTemplateColumns: "44px minmax(0,1fr)",
        background: OPS.bg,
        color: OPS.ink,
        fontFamily: MONO,
        minHeight: 600,
        WebkitFontSmoothing: "antialiased",
        MozOsxFontSmoothing: "grayscale",
      }}
    >
      <Rail active={isHome ? "home" : "history"} />

      <div className="flex flex-col" style={{ minWidth: 0 }}>
        <main className="flex-1 flex flex-col" style={{ padding: "18px 28px 24px" }}>
          {isHome ? (
            <>
              {/* Home leads with the Agent Bay — the runtime instrument moment. */}
              <SectionLabel>Agent</SectionLabel>
              <AgentBay
                runtime={HOME_BAY.runtime}
                runtimeRight={HOME_BAY.runtimeRight}
                footer={HOME_BAY.footer}
                time={HOME_BAY.time}
                stats={HOME_BAY.stats}
              />
              <div style={{ height: 20 }} />
              <SectionLabel>Recent</SectionLabel>
              <RecentLibrary />
            </>
          ) : (
            <>
              {/* History is the read-only recordings list — no bay. */}
              <SectionLabel>History</SectionLabel>
              <RecentLibrary fill />
            </>
          )}
        </main>
        <StatusBar />
      </div>
    </div>
  );
}

// ── Left rail (instrument case strip) ─────────────────────────────────

const RAIL_ITEMS: { id: string; icon: OpsIconName }[] = [
  { id: "home", icon: "home" },
  { id: "history", icon: "history" },
  { id: "chat", icon: "chat" },
  { id: "shield", icon: "shield" },
  { id: "docs", icon: "docs" },
  { id: "more", icon: "more" },
];

function Rail({ active }: { active: string }) {
  return (
    <aside
      className="flex flex-col items-center"
      style={{
        background: OPS.chrome,
        borderRight: `1px solid ${OPS.hairline}`,
        paddingTop: 8,
        paddingBottom: 8,
        gap: 3,
      }}
    >
      <div
        className="flex items-center justify-center font-display"
        style={{
          width: 26,
          height: 26,
          borderRadius: 7,
          background: OPS.amber,
          color: "#FFF",
          fontSize: 15,
          marginBottom: 6,
        }}
      >
        t
      </div>
      {RAIL_ITEMS.map((it) => {
        const on = it.id === active;
        return (
          <div
            key={it.id}
            className="flex items-center justify-center"
            style={{
              width: 30,
              height: 30,
              borderRadius: 7,
              color: on ? OPS.amber : OPS.dim,
              background: on ? OPS.amberSoft : "transparent",
            }}
          >
            <OpsIcon name={it.icon} size={16} />
          </div>
        );
      })}
      <div style={{ flex: 1 }} />
      <div
        className="flex items-center justify-center"
        style={{ width: 30, height: 30, color: OPS.dim }}
      >
        <OpsIcon name="gear" size={16} />
      </div>
    </aside>
  );
}

// ── Section label — the home study's "· AGENT" eyebrow treatment ──────
// One word, all caps, wide tracking, faint Inter, with a leading dot.
// Matches SectionBlock in MacHome.tsx so the agent surface labels its
// sections in the same editorial voice as Talkie's home.

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        fontFamily: SANS,
        fontSize: 9,
        fontWeight: 600,
        letterSpacing: "0.22em",
        textTransform: "uppercase",
        color: OPS.dim,
        marginBottom: 8,
      }}
    >
      · {children}
    </div>
  );
}

// ── Agent Bay — instrument panel KPI strip (donor: Bay.tsx) ───────────

function AgentBay({
  runtime,
  runtimeRight,
  footer,
  time,
  stats,
}: {
  runtime: string;
  runtimeRight: string;
  footer: string;
  time: string;
  stats: StatSpec[];
}) {
  const railText: React.CSSProperties = {
    fontFamily: MONO,
    fontSize: 8.5,
    fontWeight: 600,
    letterSpacing: "0.16em",
    textTransform: "uppercase",
  };
  return (
    <div
      style={{
        background: BAY.bg,
        border: `1px solid ${BAY.edge}`,
        borderRadius: 10,
        overflow: "hidden",
        // The home study's `shadow-artifact` lift (0 6px 14px /.18) plus an
        // inset top highlight, so the bay reads as a raised instrument panel.
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.5), 0 6px 14px rgba(0,0,0,0.18)",
      }}
    >
      {/* Top rail — runtime identity */}
      <div
        className="flex items-center"
        style={{
          background: BAY.strip,
          padding: "7px 14px",
          borderBottom: `1px solid ${BAY.edge}`,
          gap: 8,
        }}
      >
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: 999,
            background: BAY.accent,
            boxShadow: `0 0 4px ${BAY.glow}`,
          }}
        />
        <span style={{ ...railText, color: BAY.inkFaint }}>{runtime}</span>
        <span style={{ ...railText, marginLeft: "auto", color: BAY.inkSubtle }}>
          {runtimeRight}
        </span>
      </div>

      {/* Divided stat cells */}
      <div className="flex" style={{ padding: "2px 4px" }}>
        {stats.map((s, i) => (
          <div
            key={s.label}
            className="flex flex-col justify-center"
            style={{
              flex: 1,
              gap: 4,
              padding: "14px 16px",
              borderRight:
                i < stats.length - 1 ? `1px solid ${BAY.edge}` : "none",
            }}
          >
            <div
              className="font-display"
              style={{
                fontSize: 28,
                lineHeight: 1,
                letterSpacing: "-0.01em",
                color: BAY.ink,
              }}
            >
              {s.value}
            </div>
            <div
              style={{
                fontFamily: MONO,
                fontSize: 8.5,
                fontWeight: 700,
                letterSpacing: "0.13em",
                textTransform: "uppercase",
                color: BAY.inkFaint,
              }}
            >
              {s.label}
            </div>
            <svg
              width="100%"
              height="11"
              viewBox="0 0 60 12"
              preserveAspectRatio="none"
              style={{ marginTop: 2 }}
              aria-hidden
            >
              <path
                d={sparklinePath(i)}
                fill="none"
                stroke={BAY.accent}
                strokeOpacity={0.65}
                strokeWidth={1}
              />
            </svg>
          </div>
        ))}
      </div>

      {/* Bottom rail — signal path */}
      <div
        className="flex items-center"
        style={{
          background: BAY.strip,
          padding: "7px 14px",
          borderTop: `1px solid ${BAY.edge}`,
        }}
      >
        <span style={{ ...railText, color: BAY.inkFaint }}>{footer}</span>
        <span style={{ ...railText, marginLeft: "auto", color: BAY.inkSubtle }}>
          {time}
        </span>
      </div>
    </div>
  );
}

function sparklineSamples(seed: number) {
  const out: number[] = [];
  for (let i = 0; i < 7; i++) {
    const phase = seed * 0.9;
    const sine = Math.sin(i * 0.85 + phase) * 0.3 + 0.55;
    const jitter = (((seed * 31 + i * 17) & 0xff) / 255) * 0.18;
    out.push(Math.min(0.95, Math.max(0.08, sine + jitter - 0.09)));
  }
  return out;
}

function sparklinePath(seed: number, w = 60, h = 12) {
  const samples = sparklineSamples(seed);
  const step = w / (samples.length - 1);
  return samples
    .map((v, i) => {
      const x = i * step;
      const y = h - v * h;
      return (i === 0 ? "M" : "L") + x.toFixed(1) + " " + y.toFixed(1);
    })
    .join(" ");
}

// ── Recent Library card (list / detail split) ─────────────────────────

function RecentLibrary({ fill }: { fill?: boolean }) {
  const rows = [
    {
      kind: "DICTATION · CODEX",
      title: "Yeah, I mean I don't mind off…",
      ago: "41M AGO",
      meta: "0:15 · 32W",
      badge: "D",
      active: true,
    },
    {
      kind: "CAPTURE · CODEX",
      title: "Codex capture",
      ago: "41M AGO",
      meta: "",
      badge: "C",
      active: false,
    },
    {
      kind: "DICTATION · CODEX",
      title: "Alright, thank you.",
      ago: "42M AGO",
      meta: "0:24 · 57W",
      badge: "D",
      active: false,
    },
  ];

  return (
    <div
      style={{
        background: OPS.surface,
        border: `1px solid ${OPS.hairline}`,
        borderRadius: 12,
        overflow: "hidden",
        // Subtler than the bay — a flat-ish card so the instrument bay above
        // stays the deepest element on the page (as in the home study).
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.7), 0 2px 6px rgba(35,36,35,0.05)",
        // When it's the only content (History), grow to fill the window.
        ...(fill
          ? { flex: 1, display: "flex", flexDirection: "column", minHeight: 0 }
          : {}),
      }}
    >
      <div className="flex items-start" style={{ padding: 14, gap: 10 }}>
        <span style={{ color: OPS.amber, marginTop: 1 }}>
          <OpsIcon name="history" size={15} />
        </span>
        <div className="flex flex-col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: OPS.ink }}>
            Library
          </span>
          <span style={{ fontSize: 11, color: OPS.muted }}>
            Memos, dictations, notes, captures, and selections from Talkie.
          </span>
        </div>
        <Btn icon="external">Open in Talkie</Btn>
        <Btn icon="drive" ghost>
          Storage
        </Btn>
      </div>

      <div style={{ height: 1, background: OPS.hairlineSubtle }} />

      <div
        className="flex"
        style={fill ? { flex: 1, minHeight: 0 } : { minHeight: 196 }}
      >
        <div style={{ width: 420, borderRight: `1px solid ${OPS.hairlineSubtle}` }}>
          <div
            className="flex items-center justify-between"
            style={{ padding: "8px 14px" }}
          >
            <span
              style={{
                fontFamily: MONO,
                fontSize: 9.5,
                fontWeight: 700,
                letterSpacing: "0.14em",
                color: OPS.dim,
              }}
            >
              · TODAY
            </span>
            <span style={{ fontFamily: MONO, fontSize: 10, color: OPS.dim }}>
              120
            </span>
          </div>
          {rows.map((r, i) => (
            <Row key={i} {...r} />
          ))}
        </div>

        <Detail />
      </div>
    </div>
  );
}

function Row({
  kind,
  title,
  ago,
  meta,
  badge,
  active,
}: {
  kind: string;
  title: string;
  ago: string;
  meta: string;
  badge: string;
  active?: boolean;
}) {
  return (
    <div
      className="flex items-center"
      style={{
        gap: 10,
        padding: "9px 14px",
        background: active ? OPS.amberFaint : "transparent",
        borderLeft: `2px solid ${active ? OPS.amber : "transparent"}`,
      }}
    >
      <div
        className="flex items-center justify-center font-display"
        style={{
          width: 34,
          height: 34,
          borderRadius: 7,
          background: OPS.ink,
          color: "#FFF",
          fontSize: 13,
        }}
      >
        {badge}
      </div>
      <div className="flex flex-col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
        <span
          style={{
            fontSize: 12.5,
            color: OPS.ink,
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
          }}
        >
          {title}
        </span>
        <span
          style={{
            fontFamily: MONO,
            fontSize: 9,
            letterSpacing: "0.08em",
            color: OPS.dim,
          }}
        >
          {kind}
        </span>
      </div>
      <div className="flex flex-col items-end" style={{ gap: 2 }}>
        <span style={{ fontFamily: MONO, fontSize: 9, color: OPS.dim }}>{ago}</span>
        {meta ? (
          <span style={{ fontFamily: MONO, fontSize: 9, color: OPS.dim }}>
            {meta}
          </span>
        ) : null}
      </div>
    </div>
  );
}

function Detail() {
  return (
    <div style={{ flex: 1, minWidth: 0, padding: 14 }}>
      <div className="flex items-center" style={{ gap: 8, marginBottom: 10 }}>
        <span style={{ color: SCOPE.dictTint }}>
          <OpsIcon name="wave" size={15} />
        </span>
        <div className="flex flex-col">
          <span
            style={{
              fontFamily: MONO,
              fontSize: 9.5,
              fontWeight: 700,
              letterSpacing: "0.12em",
              color: OPS.dim,
            }}
          >
            DICTATION
          </span>
          <span style={{ fontSize: 11, color: OPS.muted }}>41 mins, 5 secs.</span>
        </div>
      </div>
      <div
        className="font-display"
        style={{ fontSize: 19, lineHeight: 1.25, color: OPS.ink, marginBottom: 12 }}
      >
        Yeah, I mean I don't mind off black, off white, that's fine.
      </div>
      <div className="flex" style={{ gap: 8 }}>
        <Btn icon="external">Open in Talkie</Btn>
        <Btn icon="copy" ghost>
          Copy Text
        </Btn>
      </div>
    </div>
  );
}

// ── Bits ──────────────────────────────────────────────────────────────

function Btn({
  children,
  icon,
  ghost,
}: {
  children: React.ReactNode;
  icon?: OpsIconName;
  ghost?: boolean;
}) {
  return (
    <span
      className="flex items-center"
      style={{
        gap: 5,
        // Actions read in the sans — mono is reserved for instrument readouts
        // and metadata (bay labels, status, row meta), not action buttons.
        fontFamily: SANS,
        fontSize: 11.5,
        fontWeight: 600,
        color: ghost ? OPS.muted : OPS.ink,
        background: ghost ? "transparent" : OPS.surface,
        border: `1px solid ${OPS.hairline}`,
        borderRadius: 7,
        padding: "5px 10px",
        whiteSpace: "nowrap",
      }}
    >
      {icon ? <OpsIcon name={icon} size={13} /> : null}
      {children}
    </span>
  );
}

function StatusBar() {
  return (
    <div
      className="flex items-center justify-between"
      style={{
        borderTop: `1px solid ${OPS.hairline}`,
        background: OPS.chrome,
        padding: "6px 14px",
        fontFamily: MONO,
        fontSize: 10,
        color: OPS.dim,
      }}
    >
      <span style={{ color: OPS.muted }}>Talkie Agent · Ready</span>
      <span>BUILD Jun 17 20:32:24</span>
    </div>
  );
}
