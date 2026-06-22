"use client";

/**
 * MacLibraryEmpty — the Library "no-selection" content area, reframed.
 *
 * Donor: apps/macos/Talkie/Views/Library/ScopeLibraryEmptyState.swift.
 *
 * The core problem (user, 20 Jun): the left rail is already a list of
 * the day's items. The shipped no-selection pane then renders *another*
 * list of mostly the same items — "0 new context or value, and not a
 * lot of pretty either." A detail pane that mirrors the rail is wasted
 * canvas.
 *
 * Principle for every variant here: do something the chronological rail
 * CAN'T. Never reprint it row-for-row.
 *
 *   · Overview — an editorial front page. Synthesizes the day: an
 *                activity tape, a one-line "by the numbers", and 2–3
 *                *curated* highlights (not all 29 items). Value = shape
 *                + curation the rail can't give.
 *   · Mosaic   — captures are visual; show them big. The rail's marks
 *                are 42×28 — here you can actually read the screenshots.
 *   · Featured — resurface a single item as a monumental hero. Value =
 *                serendipity / "pick up where you left off."
 *   · Empty    — the TRUE zero-state the title always promised. Fresh
 *                install, nothing recorded: a quiet, inviting canvas.
 *   · Private  — screenshots and waveform tiles can take the same
 *                intentional blur treatment when a user marks an item
 *                private. Privacy should feel deliberate, not like
 *                missing media.
 */

import React, { useEffect, useState } from "react";
import { SCOPE } from "@/lib/scope-tokens";

const T = {
  canvas:     SCOPE.canvas,
  pane:       SCOPE.pane,
  canvasAlt:  SCOPE.canvasAlt,
  chrome:     SCOPE.chrome,
  rail:       SCOPE.rail,
  ink:        SCOPE.ink,
  inkMid:     SCOPE.inkMid,
  inkFaint:   SCOPE.inkFaint,
  inkFainter: SCOPE.inkFainter,
  inkSubtle:  SCOPE.inkSubtle,
  rule:       SCOPE.rule,
  ruleSubtle: SCOPE.ruleSubtle,
  ruleSoft:   SCOPE.ruleSoft,
  edge:       SCOPE.edge,
  amber:      SCOPE.amber,
  amberDeep:  SCOPE.amberDeep,
  amberFaint: SCOPE.amberFaint,
  amberSoft:  SCOPE.amberSoft,
  brass:      SCOPE.brass,
};

const APP_TINT: Record<string, string> = {
  "Google Chrome": "#3A7BD0",
  iTerm2:          "#1F8A52",
  Lattices:        "#8A5BD0",
  Figma:           "#C45A2A",
};

// ─── Data ────────────────────────────────────────────────────────────
// A real, mixed June day: captures-dominant but with voice + notes so
// the digest has cross-channel context to synthesize. The whole point
// is that the pane reads the day as a *whole*, not item by item.

const DAY = { headline: "20 Jun", dow: "Saturday" };

type Shot = "browser" | "terminal" | "lattice" | "design";

interface Capture { id: string; time: string; app: string; shot: Shot; dims: string; seed: number; fresh?: boolean }

const CAPTURES: Capture[] = [
  { id: "C-241", time: "12:18 AM", app: "Google Chrome", shot: "browser",  dims: "1280 × 757", seed: 3 },
  { id: "C-240", time: "12:20 AM", app: "iTerm2",        shot: "terminal", dims: "1024 × 668", seed: 7 },
  { id: "C-239", time: "9:42 AM",  app: "Google Chrome", shot: "browser",  dims: "1440 × 900", seed: 11 },
  { id: "C-238", time: "10:06 AM", app: "Figma",         shot: "design",   dims: "1840 × 1124", seed: 2, fresh: true },
  { id: "C-237", time: "11:31 AM", app: "Lattices",      shot: "lattice",  dims: "1112 × 712", seed: 14 },
  { id: "C-236", time: "1:09 PM",  app: "Lattices",      shot: "lattice",  dims: "1112 × 712", seed: 5 },
  { id: "C-235", time: "1:13 PM",  app: "Google Chrome", shot: "browser",  dims: "1280 × 757", seed: 9 },
  { id: "C-234", time: "2:33 PM",  app: "iTerm2",        shot: "terminal", dims: "1024 × 668", seed: 8 },
  { id: "C-233", time: "4:02 PM",  app: "Google Chrome", shot: "browser",  dims: "1440 × 900", seed: 6 },
];

// Channel tallies for the day (whole library, not the captures filter).
const CHANNELS = [
  { key: "Captures",   count: 24, tint: "#5C5E5C" },
  { key: "Dictations", count: 3,  tint: "#C47D1C" },
  { key: "Notes",      count: 2,  tint: "#767674" },
];

const TOP_APPS = [
  { app: "Google Chrome", n: 14 },
  { app: "Lattices",      n: 6 },
  { app: "iTerm2",        n: 4 },
];

// Hour buckets (0–23) → activity intensity, for the tape ribbon.
const RHYTHM = [1,0,0,0,0,0,0,0,0,2,3,2,0,3,1,0,2,1,0,0,0,0,0,1];

const HIGHLIGHTS = [
  {
    kind: "capture" as const,
    eyebrow: "FRESHEST CAPTURE", app: "Figma", time: "10:06 AM",
    title: "Bay variant comparison — 9 schemes", meta: "Figma · 1840 × 1124 · 1.2 MB",
    shot: "design" as Shot, seed: 2,
  },
  {
    kind: "voice" as const,
    eyebrow: "LONGEST DICTATION", app: "iTerm2", time: "10:58 AM",
    title: "Re-grounding the bay against the chiffon canvas", meta: "Dictation · 6:14 · 412 words",
  },
  {
    kind: "note" as const,
    eyebrow: "PINNED NOTE", app: "Markdown", time: "3:20 PM",
    title: "Shipped chiffon canonical for Scope theme", meta: "Note · 142 words",
  },
];

// ─── Synthetic thumbnail (self-contained) ────────────────────────────

function rand(seed: number, i: number) {
  const x = Math.sin(seed * 99.13 + i * 12.9898) * 43758.5453;
  return x - Math.floor(x);
}

function ShotArt({ kind, seed }: { kind: Shot; seed: number }) {
  return (
    <div style={{ position: "absolute", inset: 0, background: kind === "terminal" ? "#17191B" : "#FCFCFB" }}>
      {kind === "browser" && (
        <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column" }}>
          <div style={{ height: "20%", background: "#ECEDEE", display: "flex", alignItems: "center", gap: "3%", padding: "0 6%" }}>
            <span style={{ width: 4, height: 4, borderRadius: 9, background: "#CBCDCF" }} />
            <span style={{ flex: "0 0 30%", height: "30%", borderRadius: 9, background: "#FCFCFB" }} />
            <span style={{ flex: 1, height: "30%", borderRadius: 9, background: "#DDDEE0" }} />
          </div>
          <div style={{ flex: 1, padding: "7% 7%", display: "flex", flexDirection: "column", gap: "6%" }}>
            <div style={{ height: "13%", width: `${44 + rand(seed, 1) * 30}%`, borderRadius: 2, background: "#2A2B2C", opacity: 0.78 }} />
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} style={{ height: "7%", width: `${58 + rand(seed, i + 2) * 38}%`, borderRadius: 2, background: T.inkFainter }} />
            ))}
            <div style={{ flex: 1, marginTop: "2%", borderRadius: 3, background: `${APP_TINT["Google Chrome"]}22`, border: `0.5px solid ${APP_TINT["Google Chrome"]}33` }} />
          </div>
        </div>
      )}
      {kind === "terminal" && (
        <div style={{ position: "absolute", inset: 0, padding: "9% 8%", display: "flex", flexDirection: "column", gap: "7%" }}>
          {Array.from({ length: 7 }).map((_, i) => {
            const colors = ["#5FE3A1", "#7FC7FF", "#E8C66B", "#9FB0B8"];
            return (
              <div key={i} style={{ display: "flex", gap: "4%", alignItems: "center" }}>
                <span style={{ width: "6%", height: 3, borderRadius: 2, background: "#3A6B4E" }} />
                <span style={{ width: `${30 + rand(seed, i) * 55}%`, height: 3, borderRadius: 2, background: colors[i % colors.length], opacity: 0.85 }} />
              </div>
            );
          })}
        </div>
      )}
      {kind === "lattice" && (
        <div style={{ position: "absolute", inset: 0, padding: "8%", display: "grid", gridTemplateColumns: "repeat(8, 1fr)", gridTemplateRows: "repeat(6, 1fr)", gap: "5%" }}>
          {Array.from({ length: 48 }).map((_, i) => (
            <div key={i} style={{ borderRadius: 1.5, border: `0.5px solid ${T.inkSubtle}`, background: rand(seed, i) > 0.62 ? `${APP_TINT.Lattices}55` : "transparent" }} />
          ))}
        </div>
      )}
      {kind === "design" && (
        <div style={{ position: "absolute", inset: 0, display: "flex" }}>
          <div style={{ flex: "0 0 14%", background: "#F0F0EF", borderRight: `0.5px solid ${T.ruleSoft}` }} />
          <div style={{ flex: 1, position: "relative", background: "#F6F6F5" }}>
            <div style={{ position: "absolute", left: "16%", top: "20%", width: "42%", height: "36%", borderRadius: 3, background: `${APP_TINT.Figma}33`, border: `0.5px solid ${APP_TINT.Figma}55` }} />
            <div style={{ position: "absolute", left: `${52 + rand(seed, 1) * 8}%`, top: "46%", width: "24%", height: "26%", borderRadius: 999, background: "#E8C66B55", border: "0.5px solid #E8C66B" }} />
          </div>
          <div style={{ flex: "0 0 12%", background: "#F0F0EF", borderLeft: `0.5px solid ${T.ruleSoft}` }} />
        </div>
      )}
    </div>
  );
}

function Thumb({ shot, seed, fill = false, w, h, radius = 6, fresh, privateMode = false }: { shot: Shot; seed: number; fill?: boolean; w?: number; h?: number; radius?: number; fresh?: boolean; privateMode?: boolean }) {
  return (
    <div style={{ position: "relative", width: fill ? "100%" : w, height: fill ? "100%" : h, borderRadius: radius, overflow: "hidden", background: T.canvas, border: `0.5px solid ${T.edge}`, boxShadow: "0 1px 4px rgba(35,36,35,0.10)", flexShrink: 0 }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          filter: privateMode ? "blur(11px) saturate(0.58)" : "none",
          transform: privateMode ? "scale(1.07)" : "none",
          transition: "filter 180ms ease, transform 180ms ease",
        }}
      >
        <ShotArt kind={shot} seed={seed} />
      </div>
      {fresh && <span style={{ position: "absolute", top: 6, right: 6, width: 6, height: 6, borderRadius: 9, background: T.amber, boxShadow: "0 0 0 2px rgba(248,248,247,0.9)" }} />}
      {privateMode && <PrivacyScrim label="Private" />}
    </div>
  );
}

function PrivacyScrim({ label }: { label: string }) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "rgba(248,248,247,0.48)",
        boxShadow: "inset 0 0 0 999px rgba(35,36,35,0.06)",
        backdropFilter: "blur(2px)",
      }}
    >
      <span
        className="font-mono uppercase"
        style={{
          fontSize: 9,
          letterSpacing: "0.18em",
          color: T.inkMid,
          background: "rgba(248,248,247,0.74)",
          border: `0.5px solid ${T.ruleSoft}`,
          borderRadius: 999,
          padding: "4px 9px",
          boxShadow: "0 1px 5px rgba(35,36,35,0.08)",
        }}
      >
        {label}
      </span>
    </div>
  );
}

// ─── Shared editorial bits ───────────────────────────────────────────

function Frontispiece({ byline }: { byline: string }) {
  return (
    <div className="flex items-baseline" style={{ gap: 22 }}>
      <span className="font-display" style={{ fontSize: 54, fontWeight: 500, letterSpacing: -1, color: T.ink, lineHeight: 1 }}>
        {DAY.headline}
      </span>
      <span className="font-display italic" style={{ fontSize: 16, color: T.inkFaint }}>
        {byline}
      </span>
    </div>
  );
}

function Eyebrow({ children }: { children: React.ReactNode }) {
  return (
    <span className="font-mono font-semibold uppercase" style={{ fontSize: 9.5, letterSpacing: "0.30em", color: T.inkFaint }}>
      {children}
    </span>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · OVERVIEW — editorial front page (synthesis, not a list)
// ════════════════════════════════════════════════════════════════════

function OverviewPane({ privateMode }: { privateMode: boolean }) {
  return (
    <div style={{ padding: "44px 56px" }}>
      <Frontispiece byline={`${DAY.dow} · 29 items across 3 channels`} />

      {/* activity strip — temporal shape, kept quiet (no instrument chrome) */}
      <div style={{ marginTop: 22 }}>
        <div className="flex items-baseline" style={{ gap: 10, marginBottom: 10 }}>
          <Eyebrow>· activity</Eyebrow>
          <span className="font-mono" style={{ fontSize: 9, color: T.inkFainter, letterSpacing: "0.06em" }}>busiest 10 AM–2 PM</span>
        </div>
        <ActivityStrip />
      </div>

      {/* by the numbers + top apps — two quiet editorial columns */}
      <div className="flex" style={{ gap: 40, marginTop: 26 }}>
        <div style={{ flex: 1 }}>
          <Eyebrow>· channels</Eyebrow>
          <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 9 }}>
            {CHANNELS.map((c) => (
              <div key={c.key} className="flex items-center" style={{ gap: 10 }}>
                <span className="font-mono uppercase" style={{ fontSize: 10, letterSpacing: "0.10em", color: T.inkMid, width: 78 }}>{c.key}</span>
                <div style={{ flex: 1, height: 6, borderRadius: 3, background: T.ruleSubtle, overflow: "hidden" }}>
                  <div style={{ width: `${(c.count / 24) * 100}%`, height: "100%", background: c.tint, opacity: 0.7 }} />
                </div>
                <span className="font-display" style={{ fontSize: 15, color: T.ink, width: 26, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{c.count}</span>
              </div>
            ))}
          </div>
        </div>
        <div style={{ flex: 1 }}>
          <Eyebrow>· top sources</Eyebrow>
          <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 9 }}>
            {TOP_APPS.map((a) => (
              <div key={a.app} className="flex items-center" style={{ gap: 10 }}>
                <span style={{ width: 7, height: 7, borderRadius: 9, background: APP_TINT[a.app] ?? T.inkFaint }} />
                <span className="font-mono uppercase" style={{ fontSize: 10, letterSpacing: "0.10em", color: T.inkMid, flex: 1 }}>{a.app}</span>
                <span className="font-display" style={{ fontSize: 15, color: T.ink, fontVariantNumeric: "tabular-nums" }}>{a.n}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* curated highlights — 3 cards, NOT the full 29 */}
      <div style={{ marginTop: 30 }}>
        <div className="flex items-baseline" style={{ gap: 10, marginBottom: 14 }}>
          <Eyebrow>· highlights</Eyebrow>
          <span className="font-display italic" style={{ fontSize: 12, color: T.inkFaint }}>what stood out — not everything</span>
          <div style={{ flex: 1, height: 0.5, background: T.ruleSubtle, marginLeft: 4 }} />
        </div>
        <div className="flex" style={{ gap: 16 }}>
          {HIGHLIGHTS.map((h) => (
            <HighlightCard key={h.title} h={h} privateMode={privateMode} />
          ))}
        </div>
      </div>
    </div>
  );
}

// Quiet activity sparkline: faint gray bars on a hairline baseline.
// No box, no centerline, no amber — it reads the day's shape without
// pretending to be an instrument.
function ActivityStrip() {
  return (
    <div style={{ position: "relative", height: 32 }}>
      {/* baseline + noon tick */}
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 12, height: 0.5, background: T.ruleSubtle }} />
      <div style={{ position: "absolute", left: "50%", bottom: 12, width: 0.5, height: 4, background: T.inkSubtle }} />
      {/* bars per active hour */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 12, display: "flex", alignItems: "flex-end" }}>
        {RHYTHM.map((v, h) => (
          <div key={h} style={{ flex: 1, height: "100%", display: "flex", justifyContent: "center", alignItems: "flex-end" }}>
            {v > 0 && <div style={{ width: 3, height: `${42 + v * 24}%`, borderRadius: 1, background: T.inkFaint }} />}
          </div>
        ))}
      </div>
      {/* end labels */}
      <span className="font-mono" style={{ position: "absolute", left: 0, bottom: 0, fontSize: 8, color: T.inkFainter, letterSpacing: "0.06em" }}>12 AM</span>
      <span className="font-mono" style={{ position: "absolute", left: "50%", transform: "translateX(-50%)", bottom: 0, fontSize: 8, color: T.inkFainter, letterSpacing: "0.06em" }}>NOON</span>
      <span className="font-mono" style={{ position: "absolute", right: 0, bottom: 0, fontSize: 8, color: T.inkFainter, letterSpacing: "0.06em" }}>11 PM</span>
    </div>
  );
}

function HighlightCard({ h, privateMode }: { h: (typeof HIGHLIGHTS)[number]; privateMode: boolean }) {
  return (
    <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 10 }}>
      <div style={{ position: "relative", width: "100%", paddingBottom: "60%" }}>
        <div style={{ position: "absolute", inset: 0 }}>
          {h.kind === "capture" ? (
            <Thumb shot={h.shot!} seed={h.seed!} fill radius={7} fresh privateMode={privateMode} />
          ) : (
            <PaperTile kind={h.kind} privateMode={privateMode} />
          )}
        </div>
      </div>
      <div>
        <div className="flex items-center" style={{ gap: 7, marginBottom: 5 }}>
          <span className="font-mono uppercase" style={{ fontSize: 8.5, letterSpacing: "0.14em", color: T.amberDeep }}>{h.eyebrow}</span>
          <span className="font-mono" style={{ fontSize: 9, color: T.inkFainter, marginLeft: "auto" }}>{h.time}</span>
        </div>
        <div className="font-display" style={{ fontSize: 15, lineHeight: 1.25, color: T.ink, marginBottom: 4 }}>{h.title}</div>
        <div className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.08em", color: T.inkFainter }}>{h.meta}</div>
      </div>
    </div>
  );
}

// A "paper" tile for non-visual highlights (voice / note) — a quiet
// editorial surface instead of a thumbnail.
function PaperTile({ kind, privateMode = false }: { kind: "voice" | "note"; privateMode?: boolean }) {
  return (
    <div style={{ position: "absolute", inset: 0, borderRadius: 7, overflow: "hidden", background: T.pane, border: `0.5px solid ${T.ruleSoft}` }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: "14% 14%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          gap: "8%",
          filter: privateMode ? "blur(9px) saturate(0.62)" : "none",
          transform: privateMode ? "scale(1.05)" : "none",
          transition: "filter 180ms ease, transform 180ms ease",
        }}
      >
        {kind === "voice" ? (
          <div className="flex items-center" style={{ gap: 2, height: "46%" }}>
            {Array.from({ length: 22 }).map((_, i) => {
              const hgt = 18 + Math.abs(Math.sin(i * 1.7)) * 78;
              return <div key={i} style={{ flex: 1, height: `${hgt}%`, borderRadius: 1, background: i % 3 === 0 ? T.amber : T.brass, opacity: 0.7 }} />;
            })}
          </div>
        ) : (
          <>
            {[68, 92, 80, 54].map((w, i) => (
              <div key={i} style={{ height: 4, width: `${w}%`, borderRadius: 2, background: T.inkFainter }} />
            ))}
          </>
        )}
      </div>
      {privateMode && <PrivacyScrim label="Private" />}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · MOSAIC — captures, shown big
// ════════════════════════════════════════════════════════════════════

function MosaicPane({ privateMode }: { privateMode: boolean }) {
  return (
    <div style={{ padding: "44px 56px" }}>
      <Frontispiece byline={`${DAY.dow} · 24 captures · seen, not listed`} />
      <div className="flex items-baseline" style={{ gap: 10, margin: "22px 0 16px" }}>
        <Eyebrow>· recent captures</Eyebrow>
        <span className="font-display italic" style={{ fontSize: 12, color: T.inkFaint }}>the rail shows 42×28 marks — here you can read them</span>
        <div style={{ flex: 1, height: 0.5, background: T.ruleSubtle, marginLeft: 4 }} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 18 }}>
        {CAPTURES.map((c) => (
          <div key={c.id} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <div style={{ position: "relative", width: "100%", paddingBottom: "62%" }}>
              <div style={{ position: "absolute", inset: 0 }}>
                <Thumb shot={c.shot} seed={c.seed} fill radius={7} fresh={c.fresh} privateMode={privateMode} />
              </div>
            </div>
            <div className="flex items-baseline" style={{ gap: 8 }}>
              <span className="font-mono" style={{ fontSize: 10, color: T.inkMid, fontVariantNumeric: "tabular-nums" }}>{c.time}</span>
              <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.08em", color: APP_TINT[c.app] ?? T.inkFainter }}>{c.app}</span>
              <span className="font-mono" style={{ marginLeft: "auto", fontSize: 9, color: T.inkFainter }}>{c.dims.split(" ")[0]}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · FEATURED — one monumental resurfaced hero
// ════════════════════════════════════════════════════════════════════

function FeaturedPane({ privateMode }: { privateMode: boolean }) {
  const f = HIGHLIGHTS[0];
  return (
    <div style={{ padding: "44px 56px", minHeight: 560, display: "flex", flexDirection: "column" }}>
      <div className="flex items-baseline" style={{ gap: 10 }}>
        <Eyebrow>· pick up where you left off</Eyebrow>
        <span className="font-mono" style={{ fontSize: 9, color: T.inkFainter, marginLeft: "auto" }}>{DAY.headline} · {f.time}</span>
      </div>
      <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", padding: "32px 0" }}>
        <div style={{ width: 560, maxWidth: "100%" }}>
          <div style={{ position: "relative", width: "100%", paddingBottom: "58%" }}>
            <div style={{ position: "absolute", inset: 0 }}>
              <Thumb shot={f.shot!} seed={f.seed!} fill radius={10} fresh privateMode={privateMode} />
            </div>
          </div>
          <div style={{ marginTop: 20, textAlign: "center" }}>
            <div className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.amberDeep, marginBottom: 8 }}>{f.eyebrow}</div>
            <div className="font-display" style={{ fontSize: 26, lineHeight: 1.2, color: T.ink, marginBottom: 8 }}>{f.title}</div>
            <div className="font-mono uppercase" style={{ fontSize: 10, letterSpacing: "0.10em", color: T.inkFaint }}>{f.meta}</div>
          </div>
        </div>
      </div>
      <div style={{ height: 0.5, background: T.ruleSubtle }} />
      <div className="flex items-center" style={{ paddingTop: 12, gap: 8 }}>
        <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.16em", color: T.inkFaint }}>↵ open</span>
        <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.16em", color: T.inkFaint, marginLeft: "auto" }}>→ next feature</span>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · EMPTY — the true zero-state (fresh install, nothing yet)
// ════════════════════════════════════════════════════════════════════

function EmptyPane() {
  return (
    <div style={{ padding: "44px 56px", minHeight: 560, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", textAlign: "center" }}>
      <Eyebrow>· library</Eyebrow>

      {/* tape at rest — flat centerline, the signature held quiet */}
      <div style={{ width: 220, height: 30, position: "relative", margin: "26px 0 30px" }}>
        <div style={{ position: "absolute", left: 0, right: 0, top: "50%", height: 1.5, background: T.amber, opacity: 0.45 }} />
        <span style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)", width: 9, height: 9, borderRadius: 9, background: T.canvas, border: `1.5px solid ${T.amberDeep}` }} />
      </div>

      <h2 className="font-display" style={{ fontSize: 40, fontWeight: 500, letterSpacing: -0.5, color: T.ink, lineHeight: 1.05, margin: 0 }}>
        Nothing here yet.
      </h2>
      <p className="font-display italic" style={{ fontSize: 16, color: T.inkFaint, marginTop: 12, maxWidth: 380, lineHeight: 1.5 }}>
        Your memos, dictations, notes, and captures will collect here as you go.
      </p>

      {/* two quiet affordances */}
      <div className="flex" style={{ gap: 12, marginTop: 30 }}>
        <StartChip glyph="●" label="Record" hint="⌘N" primary />
        <StartChip glyph="▢" label="Capture" hint="⇧⌘4" />
      </div>

      <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.22em", color: T.inkFainter, marginTop: 40 }}>
        or press the Talkie pill anytime
      </span>
    </div>
  );
}

function StartChip({ glyph, label, hint, primary }: { glyph: string; label: string; hint: string; primary?: boolean }) {
  return (
    <div className="flex items-center" style={{ gap: 9, padding: "9px 16px", borderRadius: 8, background: primary ? T.amberFaint : T.pane, border: `0.5px solid ${primary ? T.amberSoft : T.ruleSoft}` }}>
      <span style={{ fontSize: 11, color: primary ? T.amberDeep : T.inkFaint }}>{glyph}</span>
      <span className="font-display" style={{ fontSize: 15, color: T.ink }}>{label}</span>
      <span className="font-mono" style={{ fontSize: 9.5, letterSpacing: "0.06em", color: T.inkFainter, marginLeft: 4 }}>{hint}</span>
    </div>
  );
}

// ─── Variant board root ──────────────────────────────────────────────

type VariantKey = "overview" | "mosaic" | "featured" | "empty";

const VARIANTS: { key: VariantKey; label: string; note: string }[] = [
  { key: "overview", label: "Overview", note: "An editorial front page: an activity tape for the day's shape, a channel + top-source read, and 2–3 curated highlights — not all 29 items. Value = synthesis + curation the chronological rail can't give." },
  { key: "mosaic",   label: "Mosaic",   note: "Captures are visual; the rail's marks are 42×28. Here they're big enough to actually read. Same items, but the presentation is the value the rail can't deliver." },
  { key: "featured", label: "Featured", note: "Resurface one item as a monumental hero — “pick up where you left off.” A single beat, never a list. Rotates so opening Library is never the same page twice." },
  { key: "empty",    label: "Empty",    note: "The TRUE zero-state the title always promised: fresh install, nothing recorded. A quiet inviting canvas — tape at rest + Record / Capture affordances — not a sad placeholder." },
];

function initialVariant(): VariantKey {
  return "overview";
}

function variantFromSearch(): VariantKey | null {
  if (typeof window === "undefined") return null;
  const v = new URLSearchParams(window.location.search).get("v");
  return (["overview", "mosaic", "featured", "empty"] as const).includes(v as VariantKey) ? (v as VariantKey) : null;
}

function privacyModeFromSearch(): boolean {
  if (typeof window === "undefined") return false;
  const v = new URLSearchParams(window.location.search).get("privacy");
  return v === "1" || v === "true" || v === "private";
}

export function MacLibraryEmpty() {
  const [variant, setVariant] = useState<VariantKey>(initialVariant);
  const [privateMode, setPrivateMode] = useState(false);
  const active = VARIANTS.find((v) => v.key === variant)!;

  useEffect(() => {
    setVariant(variantFromSearch() ?? "overview");
    setPrivateMode(privacyModeFromSearch());
  }, []);

  return (
    <div style={{ width: 1100, background: T.canvas }} className="flex flex-col">
      <StudyHeader />

      <div style={{ padding: "0 40px" }}>
        {/* split mock: a thin rail stub + the content pane, so the
            "don't reprint the rail" point is legible at a glance */}
        <div style={{ borderRadius: 10, overflow: "hidden", border: `0.5px solid ${T.edge}`, boxShadow: "0 18px 50px rgba(35,36,35,0.12)" }}>
          <div className="flex items-center" style={{ height: 36, padding: "0 12px", gap: 10, background: T.chrome, borderBottom: `0.5px solid ${T.ruleSoft}` }}>
            <span className="flex items-center" style={{ gap: 5 }}>
              <span style={{ width: 9, height: 9, borderRadius: 999, background: "#FF5F57" }} />
              <span style={{ width: 9, height: 9, borderRadius: 999, background: "#FEBC2E" }} />
              <span style={{ width: 9, height: 9, borderRadius: 999, background: "#28C840" }} />
            </span>
            <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.inkFaint, marginLeft: 6 }}>
              Talkie · Library — no selection
            </span>
            <div className="flex items-center" style={{ marginLeft: "auto", gap: 8 }}>
              <PrivacyToggle on={privateMode} onChange={setPrivateMode} />
              <Picker variant={variant} onChange={setVariant} />
            </div>
          </div>

          <div className="flex" style={{ background: T.canvas }}>
            <RailStub dim={variant !== "empty"} empty={variant === "empty"} />
            <div style={{ flex: 1, minWidth: 0, borderLeft: `0.5px solid ${T.ruleSoft}` }}>
              {variant === "overview" && <OverviewPane privateMode={privateMode} />}
              {variant === "mosaic" && <MosaicPane privateMode={privateMode} />}
              {variant === "featured" && <FeaturedPane privateMode={privateMode} />}
              {variant === "empty" && <EmptyPane />}
            </div>
          </div>
        </div>

        <p className="font-display italic" style={{ fontSize: 13, lineHeight: 1.6, color: T.inkMid, maxWidth: 760, marginTop: 16 }}>
          <span className="font-mono uppercase not-italic" style={{ fontSize: 10, letterSpacing: "0.14em", color: T.amberDeep, marginRight: 8 }}>{active.label}</span>
          {active.note}
        </p>
      </div>

      <NamesMarginalia />
      <StudyFooter />
    </div>
  );
}

// The left list rail, drawn as a faint stub — present so the content
// pane's job ("don't reprint me") reads at a glance.
function RailStub({ dim, empty }: { dim: boolean; empty: boolean }) {
  return (
    <div style={{ width: 150, flexShrink: 0, background: T.canvasAlt, padding: "16px 12px", opacity: dim ? 0.5 : 0.35 }}>
      <div className="font-mono uppercase" style={{ fontSize: 8, letterSpacing: "0.2em", color: T.inkFainter, marginBottom: 12 }}>· today</div>
      {empty ? (
        <div className="font-mono" style={{ fontSize: 9, color: T.inkSubtle, lineHeight: 1.6 }}>—</div>
      ) : (
        Array.from({ length: 9 }).map((_, i) => (
          <div key={i} className="flex items-center" style={{ gap: 6, marginBottom: 11 }}>
            <div style={{ width: 22, height: 15, borderRadius: 2, background: T.ruleSoft, flexShrink: 0 }} />
            <div style={{ flex: 1 }}>
              <div style={{ height: 4, width: `${60 + ((i * 13) % 35)}%`, borderRadius: 2, background: T.inkSubtle, marginBottom: 4 }} />
              <div style={{ height: 3, width: "40%", borderRadius: 2, background: T.ruleSoft }} />
            </div>
          </div>
        ))
      )}
    </div>
  );
}

function Picker({ variant, onChange }: { variant: VariantKey; onChange: (v: VariantKey) => void }) {
  return (
    <div className="flex" style={{ padding: 2, borderRadius: 6, background: T.canvasAlt, border: `0.5px solid ${T.ruleSoft}` }}>
      {VARIANTS.map((v) => {
        const on = v.key === variant;
        return (
          <button
            key={v.key}
            onClick={() => onChange(v.key)}
            className="font-mono uppercase"
            style={{ fontSize: 9.5, letterSpacing: "0.10em", padding: "4px 11px", borderRadius: 4, color: on ? T.ink : T.inkFaint, background: on ? T.canvas : "transparent", boxShadow: on ? "0 1px 2px rgba(35,36,35,0.10)" : "none", border: on ? `0.5px solid ${T.edge}` : "0.5px solid transparent" }}
          >
            {v.label}
          </button>
        );
      })}
    </div>
  );
}

function PrivacyToggle({ on, onChange }: { on: boolean; onChange: (value: boolean) => void }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={() => onChange(!on)}
      className="font-mono uppercase"
      style={{
        display: "flex",
        alignItems: "center",
        gap: 7,
        height: 26,
        padding: "0 10px",
        borderRadius: 6,
        border: `0.5px solid ${on ? T.amberSoft : T.ruleSoft}`,
        background: on ? T.amberFaint : T.canvasAlt,
        color: on ? T.amberDeep : T.inkFaint,
        fontSize: 9,
        letterSpacing: "0.12em",
        boxShadow: on ? "0 1px 2px rgba(35,36,35,0.08)" : "none",
      }}
    >
      <span
        style={{
          width: 10,
          height: 10,
          borderRadius: 2,
          border: `0.6px solid ${on ? T.amberDeep : T.inkSubtle}`,
          background: on ? `repeating-linear-gradient(135deg, ${T.amberSoft}, ${T.amberSoft} 2px, transparent 2px, transparent 4px)` : "transparent",
        }}
      />
      Private
    </button>
  );
}

// ─── Study header / marginalia / footer ──────────────────────────────

function StudyHeader() {
  return (
    <div style={{ padding: "24px 40px 16px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 12 }}>
        <span className="font-mono font-semibold uppercase" style={{ fontSize: 9, letterSpacing: "0.32em", color: T.inkFaint }}>
          · LIBRARY · no-selection content area
        </span>
        <span className="font-display italic" style={{ fontSize: 13, color: T.inkFaint }}>
          stop reprinting the rail — earn the canvas — blur on demand
        </span>
        <span className="ml-auto font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.amberDeep, border: `0.5px solid ${T.amberSoft}`, borderRadius: 3, padding: "2px 7px" }}>
          CONCEPT
        </span>
      </div>
      <h2 className="font-display tracking-tight" style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 12 }}>
        Don't mirror the list
      </h2>
      <p className="font-display" style={{ color: T.inkMid, fontSize: 14, lineHeight: 1.6, marginTop: 12, maxWidth: 720 }}>
        The rail already lists the day's items. The shipped pane reprinted
        them — a second list with no new context and not much pretty. Each
        variant here does something the rail <span style={{ color: T.ink }}>can't</span>: synthesize the day,
        show captures big, resurface one beat, or — when there's truly
        nothing — invite the first one. The faint rail stub on the left is
        there so you can see the pane isn't echoing it. The Private
        toggle in the window chrome applies the same deliberate privacy
        treatment to screenshots and waveform tiles.
      </p>
    </div>
  );
}

function NamesMarginalia() {
  const entries: [string, string][] = [
    ["Rail Stub",     "the faint left list, drawn so the content pane's job — not echoing it — reads at a glance."],
    ["Activity Strip", "quiet sparkline of the day's shape — faint gray bars on a hairline, no box/amber. Temporal context the list can't show; deliberately not an instrument."],
    ["Channel Read",  "captures / dictations / notes as proportion bars — the day as a whole, not item by item."],
    ["Highlight",     "a curated hero card (freshest capture, longest dictation, pinned note). Curation = value; 3 of them, never 29."],
    ["Paper Tile",    "stand-in art for non-visual highlights — a quiet waveform (voice) or ruled lines (note) instead of a thumbnail."],
    ["Privacy Scrim", "the intentional blur/tint layer for screenshots and waveforms when an item is marked private. It hides content without reading as broken media."],
    ["Rest Tape",     "the zero-state signature: the tape held flat with a single head marker. Quiet, not sad."],
  ];
  return (
    <div style={{ padding: "30px 40px 4px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 12 }}>
        <span className="font-mono font-semibold uppercase" style={{ color: T.amber, fontSize: 9.5, letterSpacing: "0.30em" }}>· names</span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 12 }}>shared vocabulary for studio · Swift · chat</span>
        <div className="ml-3 flex-1" style={{ height: 1, background: T.ruleSoft }} />
      </div>
      <div style={{ marginTop: 14, padding: "14px 18px 16px 18px", background: T.pane, border: `0.5px solid ${T.ruleSoft}`, borderRadius: 6, display: "grid", gridTemplateColumns: "150px 1fr", rowGap: 6, columnGap: 18 }}>
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span className="font-mono font-semibold uppercase" style={{ fontSize: 10, letterSpacing: "0.14em", color: T.amberDeep }}>{name}</span>
            <span className="font-display italic" style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}>{def}</span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

function StudyFooter() {
  return (
    <div style={{ padding: "30px 40px 28px 40px" }}>
      <div style={{ height: 1, background: T.ruleSoft, marginBottom: 14 }} />
      <p className="font-display italic" style={{ color: T.inkFaint, fontSize: 12.5, lineHeight: 1.6, maxWidth: 760 }}>
        Donor: <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScopeLibraryEmptyState.swift</code>. The
        shipped <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>todaySection</code> + <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>weekSection</code> reprint the
        rail; this replaces them with a pane that earns its own keep, and
        adds the genuine empty case the file's name promised but never drew.
        The privacy state is visual-only in Studio until the data model has
        a persisted private flag.
      </p>
    </div>
  );
}
