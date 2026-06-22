"use client";

/**
 * MacLibraryDay — the Library "no-selection" detail pane, populated.
 *
 * Donor: apps/macos/Talkie/Views/Library/ScopeLibraryEmptyState.swift
 * (the `todaySection` path — NOT the literally-empty state). When the
 * day is dominated by *captures*, the shipped agenda reads poorly:
 *
 *   ① the type-mark renders a generic `photo` SF Symbol instead of the
 *      real screenshot → a wall of identical gray placeholder boxes
 *      (OverviewTypeMark, ScopeLibraryEmptyState.swift:369).
 *   ② `trailingMetric` returns a lonely "—" floating in dead space for
 *      captures with no duration/words (line 513).
 *   ③ the 4-cell DaySignalStrip shows dead "VOICE 0 · WORDS 0" zeros on
 *      a captures-only day.
 *   ④ titles + meta repeat verbatim ("Google Chrome capture" ×8).
 *
 * This board reproduces the SHIP state honestly, then offers three
 * fixes that all share one core move: render the actual thumbnail, so
 * the captures differentiate themselves and the chrome can quiet down.
 *
 * Variants (picker, top-right):
 *   · Ship       — faithful reproduction of today's render.
 *   · Filmstrip  — minimal-change port: real wide thumbnails, dimensions
 *                  in the trailing slot, adaptive signal strip, dimmed
 *                  repeated source. The recommended path to Swift.
 *   · Contact    — captures are visual; show them as a contact sheet.
 *   · Grouped    — collapse runs of the same app into a source block.
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
  capture:    "#5C5E5C",
};

// ─── Data ────────────────────────────────────────────────────────────
// A captures-dominated day, mirroring the real screenshot: mostly
// Google Chrome + iTerm2, with a Lattices run and a stray Figma. Pure
// captures (no voice / no words) — so the dead-zero signal cells the
// Ship variant exposes are real, not invented.

type Shot = "browser" | "terminal" | "lattice" | "design" | "doc";

interface Item {
  id: string;
  time: string;          // wall-clock, 12h
  app: string;           // source app — drives the meta eyebrow
  shot: Shot;            // synthetic thumbnail kind
  dims: string;          // pixel dimensions of the capture
  bytes: string;         // file size
  seed: number;          // varies the synthetic art so shots differ
  fresh?: boolean;
}

const DAY = { headline: "20 Jun", dow: "Saturday" };

const ITEMS: Item[] = [
  { id: "C-241", time: "12:18 AM", app: "Google Chrome", shot: "browser",  dims: "1280 × 757", bytes: "412 kB", seed: 3 },
  { id: "C-240", time: "12:20 AM", app: "iTerm2",        shot: "terminal", dims: "1024 × 668", bytes: "188 kB", seed: 7 },
  { id: "C-239", time: "12:18 PM", app: "Google Chrome", shot: "browser",  dims: "1440 × 900", bytes: "521 kB", seed: 11 },
  { id: "C-238", time: "12:36 PM", app: "Google Chrome", shot: "browser",  dims: "1440 × 900", bytes: "498 kB", seed: 2 },
  { id: "C-237", time: "12:38 PM", app: "Google Chrome", shot: "browser",  dims: "1280 × 757", bytes: "377 kB", seed: 14 },
  { id: "C-236", time: "1:09 PM",  app: "Lattices",      shot: "lattice",  dims: "1112 × 712", bytes: "264 kB", seed: 5 },
  { id: "C-235", time: "1:11 PM",  app: "Lattices",      shot: "lattice",  dims: "1112 × 712", bytes: "271 kB", seed: 9 },
  { id: "C-234", time: "1:13 PM",  app: "Google Chrome", shot: "browser",  dims: "1280 × 757", bytes: "402 kB", seed: 6 },
  { id: "C-233", time: "1:31 PM",  app: "Figma",         shot: "design",   dims: "1840 × 1124", bytes: "1.2 MB", seed: 12 },
  { id: "C-232", time: "2:33 PM",  app: "iTerm2",        shot: "terminal", dims: "1024 × 668", bytes: "203 kB", seed: 8 },
  { id: "C-231", time: "4:02 PM",  app: "Google Chrome", shot: "browser",  dims: "1440 × 900", bytes: "456 kB", seed: 4, fresh: true },
];

const APP_TINT: Record<string, string> = {
  "Google Chrome": "#3A7BD0",
  iTerm2:          "#1F8A52",
  Lattices:        "#8A5BD0",
  Figma:           "#C45A2A",
  Mail:            "#3A7BD0",
};

// ─── Synthetic thumbnail ─────────────────────────────────────────────
// CSS-only "fake window" art so the board reads as real screenshots
// without shipping binary assets. `seed` perturbs the layout so eight
// Chrome shots don't render identically — the whole point of the fix.

function rand(seed: number, i: number) {
  const x = Math.sin(seed * 99.13 + i * 12.9898) * 43758.5453;
  return x - Math.floor(x);
}

function ShotArt({ kind, seed, radius = 4 }: { kind: Shot; seed: number; radius?: number }) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: radius,
        overflow: "hidden",
        background: kind === "terminal" ? "#17191B" : "#FCFCFB",
      }}
    >
      {kind === "browser" && <BrowserArt seed={seed} />}
      {kind === "terminal" && <TerminalArt seed={seed} />}
      {kind === "lattice" && <LatticeArt seed={seed} />}
      {kind === "design" && <DesignArt seed={seed} />}
      {kind === "doc" && <DocArt seed={seed} />}
    </div>
  );
}

function BrowserArt({ seed }: { seed: number }) {
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column" }}>
      {/* tab + url chrome */}
      <div style={{ height: "22%", background: "#ECEDEE", display: "flex", alignItems: "center", gap: "3%", padding: "0 6%" }}>
        <span style={{ width: 4, height: 4, borderRadius: 9, background: "#CBCDCF" }} />
        <span style={{ flex: "0 0 32%", height: "34%", borderRadius: 9, background: "#FCFCFB" }} />
        <span style={{ flex: 1, height: "34%", borderRadius: 9, background: "#DDDEE0" }} />
      </div>
      {/* page content */}
      <div style={{ flex: 1, padding: "8% 7%", display: "flex", flexDirection: "column", gap: "7%" }}>
        <div style={{ height: "16%", width: `${44 + rand(seed, 1) * 30}%`, borderRadius: 2, background: "#2A2B2C", opacity: 0.78 }} />
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} style={{ height: "8%", width: `${60 + rand(seed, i + 2) * 36}%`, borderRadius: 2, background: T.inkFainter }} />
        ))}
        <div style={{ flex: 1, marginTop: "3%", borderRadius: 3, background: `${APP_TINT["Google Chrome"]}22`, border: `0.5px solid ${APP_TINT["Google Chrome"]}33` }} />
      </div>
    </div>
  );
}

function TerminalArt({ seed }: { seed: number }) {
  const colors = ["#5FE3A1", "#7FC7FF", "#E8C66B", "#9FB0B8"];
  return (
    <div style={{ position: "absolute", inset: 0, padding: "10% 8%", display: "flex", flexDirection: "column", gap: "8%" }}>
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} style={{ display: "flex", gap: "4%", alignItems: "center" }}>
          <span style={{ width: "6%", height: 3, borderRadius: 2, background: "#3A6B4E" }} />
          <span style={{ width: `${30 + rand(seed, i) * 55}%`, height: 3, borderRadius: 2, background: colors[i % colors.length], opacity: 0.85 }} />
        </div>
      ))}
      <div style={{ display: "flex", gap: "4%", alignItems: "center", marginTop: "2%" }}>
        <span style={{ width: "6%", height: 4, borderRadius: 2, background: "#5FE3A1" }} />
        <span style={{ width: "8%", height: 5, background: "#5FE3A1", opacity: 0.7 }} />
      </div>
    </div>
  );
}

function LatticeArt({ seed }: { seed: number }) {
  const cols = 7, rows = 5;
  return (
    <div style={{ position: "absolute", inset: 0, padding: "9%", display: "grid", gridTemplateColumns: `repeat(${cols}, 1fr)`, gridTemplateRows: `repeat(${rows}, 1fr)`, gap: "5%" }}>
      {Array.from({ length: cols * rows }).map((_, i) => {
        const on = rand(seed, i) > 0.62;
        return (
          <div key={i} style={{ borderRadius: 1.5, border: `0.5px solid ${T.inkSubtle}`, background: on ? `${APP_TINT.Lattices}55` : "transparent" }} />
        );
      })}
    </div>
  );
}

function DesignArt({ seed }: { seed: number }) {
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex" }}>
      <div style={{ flex: "0 0 16%", background: "#F0F0EF", borderRight: `0.5px solid ${T.ruleSoft}` }} />
      <div style={{ flex: 1, position: "relative", background: "#F6F6F5" }}>
        <div style={{ position: "absolute", left: "18%", top: "20%", width: "40%", height: "34%", borderRadius: 3, background: `${APP_TINT.Figma}33`, border: `0.5px solid ${APP_TINT.Figma}55` }} />
        <div style={{ position: "absolute", left: `${50 + rand(seed, 1) * 10}%`, top: "48%", width: "22%", height: "22%", borderRadius: 999, background: "#E8C66B55", border: "0.5px solid #E8C66B" }} />
      </div>
      <div style={{ flex: "0 0 14%", background: "#F0F0EF", borderLeft: `0.5px solid ${T.ruleSoft}` }} />
    </div>
  );
}

function DocArt({ seed }: { seed: number }) {
  return (
    <div style={{ position: "absolute", inset: 0, padding: "10% 9%", display: "flex", flexDirection: "column", gap: "7%" }}>
      <div style={{ height: "14%", width: "52%", borderRadius: 2, background: "#2A2B2C", opacity: 0.72 }} />
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} style={{ height: "7%", width: `${66 + rand(seed, i) * 30}%`, borderRadius: 2, background: T.inkFainter }} />
      ))}
    </div>
  );
}

/** Framed thumbnail — the shot inside a bordered, shadowed card.
 *  `fill` makes it stretch to its parent (for aspect-ratio grid cells). */
function Thumb({ item, w, h, radius = 5, fill = false }: { item: Item; w?: number; h?: number; radius?: number; fill?: boolean }) {
  return (
    <div
      style={{
        position: "relative",
        width: fill ? "100%" : w,
        height: fill ? "100%" : h,
        borderRadius: radius,
        background: T.canvas,
        border: `0.5px solid ${T.edge}`,
        boxShadow: "0 1px 3px rgba(35,36,35,0.08)",
        flexShrink: 0,
      }}
    >
      <ShotArt kind={item.shot} seed={item.seed} radius={radius - 0.5} />
      {item.fresh && (
        <span style={{ position: "absolute", top: 4, right: 4, width: 5, height: 5, borderRadius: 9, background: T.amber, boxShadow: "0 0 0 2px rgba(248,248,247,0.9)" }} />
      )}
    </div>
  );
}

// ─── Frontispiece (shared) ───────────────────────────────────────────

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

// ─── Signal strip (shared, cells parameterized) ──────────────────────

interface Cell { label: string; value: string; detail: string; dim?: boolean }

function SignalStrip({ cells }: { cells: Cell[] }) {
  return (
    <div
      className="flex"
      style={{ marginTop: 20, padding: "11px 0", borderTop: `0.5px solid ${T.ruleSubtle}`, borderBottom: `0.5px solid ${T.ruleSubtle}` }}
    >
      {cells.map((c, i) => (
        <div
          key={c.label}
          className="flex flex-col"
          style={{ flex: 1, padding: "0 16px", gap: 3, borderLeft: i === 0 ? "none" : `0.5px solid ${T.ruleSubtle}`, opacity: c.dim ? 0.42 : 1 }}
        >
          <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.inkFaint }}>
            {c.label}
          </span>
          <span className="flex items-baseline" style={{ gap: 6 }}>
            <span className="font-display" style={{ fontSize: 21, fontWeight: 500, color: T.ink, fontVariantNumeric: "tabular-nums" }}>
              {c.value}
            </span>
            <span className="font-mono" style={{ fontSize: 10, letterSpacing: "0.04em", color: T.inkFainter }}>
              {c.detail}
            </span>
          </span>
        </div>
      ))}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · SHIP — faithful reproduction of today's render
// ════════════════════════════════════════════════════════════════════

function ShipPane() {
  return (
    <div style={{ padding: "44px 56px" }}>
      <Frontispiece byline={`${DAY.dow} · 24 items · 0:00 elapsed · 0 words`} />
      <SignalStrip
        cells={[
          { label: "VOICE", value: "0", detail: "0s", dim: true },
          { label: "CAPTURES", value: "24", detail: "25 media" },
          { label: "WORDS", value: "0", detail: "0 text", dim: true },
          { label: "SOURCES", value: "1", detail: "mac" },
        ]}
      />
      <div style={{ marginTop: 8 }}>
        {ITEMS.map((it) => (
          <div
            key={it.id}
            className="flex items-center"
            style={{ gap: 14, padding: "11px 6px", borderBottom: `0.5px solid ${T.ruleSubtle}` }}
          >
            <span className="font-mono" style={{ width: 62, fontSize: 10, letterSpacing: "0.06em", color: T.inkFaint }}>
              {it.time}
            </span>
            {/* generic placeholder mark — the eyesore */}
            <div
              style={{ width: 42, height: 28, borderRadius: 5, background: T.canvas, border: `0.55px solid ${T.edge}`, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}
            >
              <PhotoGlyph />
            </div>
            <div className="flex flex-col" style={{ flex: 1, gap: 2, minWidth: 0 }}>
              <span className="font-display" style={{ fontSize: 17, color: T.ink, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {it.app} capture
              </span>
              <span className="font-mono uppercase" style={{ fontSize: 9.5, letterSpacing: "0.08em", color: T.inkFainter }}>
                Capture · {it.app}
              </span>
            </div>
            <span className="font-mono" style={{ width: 52, textAlign: "right", fontSize: 10, color: T.inkFaint }}>
              —
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function PhotoGlyph() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={T.capture} strokeOpacity="0.55" strokeWidth="1.6">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="8.5" cy="10" r="1.6" />
      <path d="M4 17l5-5 4 4 3-3 4 4" />
    </svg>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · FILMSTRIP — real thumbnails, dimensions, adaptive strip
// ════════════════════════════════════════════════════════════════════

function FilmstripPane() {
  return (
    <div style={{ padding: "44px 56px" }}>
      <Frontispiece byline={`${DAY.dow} · 24 captures · 4 apps · 9.4 MB`} />
      <SignalStrip
        cells={[
          { label: "CAPTURES", value: "24", detail: "25 media" },
          { label: "APPS", value: "4", detail: "chrome ·" },
          { label: "SPAN", value: "16h", detail: "00:18–16:02" },
          { label: "SIZE", value: "9.4", detail: "MB" },
        ]}
      />
      <div style={{ marginTop: 8 }}>
        {ITEMS.map((it, i) => {
          const sameApp = i > 0 && ITEMS[i - 1].app === it.app;
          return (
            <div
              key={it.id}
              className="flex items-center group"
              style={{ gap: 14, padding: "9px 6px", borderBottom: `0.5px solid ${T.ruleSubtle}` }}
            >
              <span className="font-mono" style={{ width: 62, fontSize: 10, letterSpacing: "0.06em", color: T.inkFaint }}>
                {it.time}
              </span>
              <Thumb item={it} w={64} h={40} />
              <div className="flex flex-col" style={{ flex: 1, gap: 2, minWidth: 0 }}>
                <span className="font-display" style={{ fontSize: 17, color: T.ink, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                  {it.app} capture
                </span>
                <span className="font-mono uppercase" style={{ fontSize: 9.5, letterSpacing: "0.08em", display: "flex", gap: 6 }}>
                  <span style={{ color: T.inkFainter }}>Capture</span>
                  <span style={{ color: sameApp ? T.inkSubtle : APP_TINT[it.app] ?? T.inkFainter }}>· {it.app}</span>
                </span>
              </div>
              <div className="flex flex-col items-end" style={{ width: 86, gap: 2 }}>
                <span className="font-mono" style={{ fontSize: 10, color: T.inkFaint, fontVariantNumeric: "tabular-nums" }}>
                  {it.dims}
                </span>
                <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.06em", color: T.inkFainter }}>
                  {it.bytes}
                </span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · CONTACT — captures as a contact sheet
// ════════════════════════════════════════════════════════════════════

function ContactPane() {
  return (
    <div style={{ padding: "44px 56px" }}>
      <Frontispiece byline={`${DAY.dow} · 24 captures · contact sheet`} />
      <SignalStrip
        cells={[
          { label: "CAPTURES", value: "24", detail: "25 media" },
          { label: "APPS", value: "4", detail: "chrome ·" },
          { label: "SPAN", value: "16h", detail: "00:18–16:02" },
          { label: "SIZE", value: "9.4", detail: "MB" },
        ]}
      />
      <div
        style={{ marginTop: 26, display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 18 }}
      >
        {ITEMS.map((it) => (
          <div key={it.id} className="flex flex-col" style={{ gap: 8 }}>
            <div style={{ position: "relative", width: "100%", paddingBottom: "62%" }}>
              <div style={{ position: "absolute", inset: 0 }}>
                <Thumb item={it} fill radius={6} />
              </div>
            </div>
            <div className="flex items-baseline" style={{ gap: 7 }}>
              <span className="font-mono" style={{ fontSize: 10, color: T.inkMid, fontVariantNumeric: "tabular-nums" }}>
                {it.time}
              </span>
              <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.08em", color: APP_TINT[it.app] ?? T.inkFainter, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {it.app}
              </span>
              <span className="font-mono" style={{ marginLeft: "auto", fontSize: 9, color: T.inkFainter }}>
                {it.dims.split(" ")[0]}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Variant · GROUPED — collapse runs of the same app
// ════════════════════════════════════════════════════════════════════

function GroupedPane() {
  // Group preserving first-seen order; merge non-adjacent runs of one app
  // into a single block (the real win: one "Google Chrome" header, not 8).
  const order: string[] = [];
  const byApp = new Map<string, Item[]>();
  for (const it of ITEMS) {
    if (!byApp.has(it.app)) { byApp.set(it.app, []); order.push(it.app); }
    byApp.get(it.app)!.push(it);
  }
  return (
    <div style={{ padding: "44px 56px" }}>
      <Frontispiece byline={`${DAY.dow} · 24 captures · 4 apps`} />
      <SignalStrip
        cells={[
          { label: "CAPTURES", value: "24", detail: "25 media" },
          { label: "APPS", value: "4", detail: "chrome ·" },
          { label: "SPAN", value: "16h", detail: "00:18–16:02" },
          { label: "SIZE", value: "9.4", detail: "MB" },
        ]}
      />
      <div style={{ marginTop: 24, display: "flex", flexDirection: "column", gap: 26 }}>
        {order.map((app) => {
          const items = byApp.get(app)!;
          const tint = APP_TINT[app] ?? T.inkFaint;
          return (
            <div key={app}>
              <div className="flex items-baseline" style={{ gap: 10, marginBottom: 12 }}>
                <span style={{ width: 7, height: 7, borderRadius: 9, background: tint }} />
                <span className="font-mono uppercase" style={{ fontSize: 11, letterSpacing: "0.14em", color: T.ink }}>
                  {app}
                </span>
                <span className="font-display italic" style={{ fontSize: 13, color: T.inkFaint }}>
                  {items.length} capture{items.length === 1 ? "" : "s"} · {items[0].time}–{items[items.length - 1].time}
                </span>
                <div style={{ flex: 1, height: 0.5, background: T.ruleSubtle, marginLeft: 4 }} />
              </div>
              <div className="flex" style={{ gap: 14, flexWrap: "wrap" }}>
                {items.map((it) => (
                  <div key={it.id} className="flex flex-col" style={{ gap: 6, width: 150 }}>
                    <Thumb item={it} w={150} h={94} radius={6} />
                    <span className="font-mono" style={{ fontSize: 9.5, color: T.inkFaint, fontVariantNumeric: "tabular-nums" }}>
                      {it.time}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Variant board root ──────────────────────────────────────────────

type VariantKey = "ship" | "filmstrip" | "contact" | "grouped";

const VARIANTS: { key: VariantKey; label: string; note: string }[] = [
  { key: "contact",   label: "Contact",   note: "Captures are visual, so show them: a 4-up contact sheet with time · app · width captions. Best when a day is almost all screenshots. ★ chosen direction." },
  { key: "filmstrip", label: "Filmstrip", note: "Real wide thumbnails + dimensions in the trailing slot. Adaptive signal strip drops the dead VOICE / WORDS zeros for capture-relevant signals. Repeated source dims. Minimal change to the agenda IA." },
  { key: "grouped",   label: "Grouped",   note: "Collapse runs of one app into a single source block with a count + time-span header. Kills the “Google Chrome ×8” repetition outright." },
  { key: "ship",      label: "Ship",      note: "Today's render, reproduced honestly: generic photo glyph for every shot, a lonely “—” trailing each row, and a signal strip showing VOICE 0 / WORDS 0 on a captures-only day." },
];

function initialVariant(): VariantKey {
  return "contact";
}

function variantFromSearch(): VariantKey | null {
  if (typeof window === "undefined") return null;
  const v = new URLSearchParams(window.location.search).get("v");
  return (["ship", "filmstrip", "contact", "grouped"] as const).includes(v as VariantKey)
    ? (v as VariantKey)
    : null;
}

export function MacLibraryDay() {
  const [variant, setVariant] = useState<VariantKey>(initialVariant);
  const active = VARIANTS.find((v) => v.key === variant)!;

  useEffect(() => {
    setVariant(variantFromSearch() ?? "contact");
  }, []);

  return (
    <div style={{ width: 1100, background: T.canvas }} className="flex flex-col">
      <StudyHeader />

      {/* The pane, inside a slim Mac window frame */}
      <div style={{ padding: "0 40px" }}>
        <div style={{ borderRadius: 10, overflow: "hidden", border: `0.5px solid ${T.edge}`, boxShadow: "0 18px 50px rgba(35,36,35,0.12)" }}>
          {/* chrome bar — carries the variant picker */}
          <div
            className="flex items-center"
            style={{ height: 36, padding: "0 12px", gap: 10, background: T.chrome, borderBottom: `0.5px solid ${T.ruleSoft}` }}
          >
            <span className="flex items-center" style={{ gap: 5 }}>
              <span style={{ width: 9, height: 9, borderRadius: 999, background: "#FF5F57" }} />
              <span style={{ width: 9, height: 9, borderRadius: 999, background: "#FEBC2E" }} />
              <span style={{ width: 9, height: 9, borderRadius: 999, background: "#28C840" }} />
            </span>
            <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.inkFaint, marginLeft: 6 }}>
              Talkie · Library — detail pane
            </span>
            <div style={{ marginLeft: "auto" }}>
              <Picker variant={variant} onChange={setVariant} />
            </div>
          </div>

          {/* the pane */}
          <div style={{ background: T.canvas }}>
            {variant === "ship" && <ShipPane />}
            {variant === "filmstrip" && <FilmstripPane />}
            {variant === "contact" && <ContactPane />}
            {variant === "grouped" && <GroupedPane />}
          </div>
        </div>

        {/* active-variant note */}
        <p className="font-display italic" style={{ fontSize: 13, lineHeight: 1.6, color: T.inkMid, maxWidth: 760, marginTop: 16 }}>
          <span className="font-mono uppercase not-italic" style={{ fontSize: 10, letterSpacing: "0.14em", color: T.amberDeep, marginRight: 8 }}>
            {active.label}
          </span>
          {active.note}
        </p>
      </div>

      <NamesMarginalia />
      <StudyFooter />
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
            style={{
              fontSize: 9.5,
              letterSpacing: "0.10em",
              padding: "4px 11px",
              borderRadius: 4,
              color: on ? T.ink : T.inkFaint,
              background: on ? T.canvas : "transparent",
              boxShadow: on ? "0 1px 2px rgba(35,36,35,0.10)" : "none",
              border: on ? `0.5px solid ${T.edge}` : "0.5px solid transparent",
            }}
          >
            {v.label}
          </button>
        );
      })}
    </div>
  );
}

// ─── Study header / footer / marginalia ──────────────────────────────

function StudyHeader() {
  const fixes = ["THUMBNAILS", "TRAILING", "SIGNAL STRIP", "REPETITION"];
  return (
    <div style={{ padding: "24px 40px 16px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 12 }}>
        <span className="font-mono font-semibold uppercase" style={{ fontSize: 9, letterSpacing: "0.32em", color: T.inkFaint }}>
          · LIBRARY · day digest · no-selection pane
        </span>
        <span className="font-display italic" style={{ fontSize: 13, color: T.inkFaint }}>
          pick a register — the picker lives on the window's chrome bar
        </span>
        <span className="ml-auto font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.amberDeep, border: `0.5px solid ${T.amberSoft}`, borderRadius: 3, padding: "2px 7px" }}>
          CONCEPT
        </span>
      </div>
      <h2 className="font-display tracking-tight" style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 12 }}>
        The captures-day pane
      </h2>
      <p className="font-display" style={{ color: T.inkMid, fontSize: 14, lineHeight: 1.6, marginTop: 12, maxWidth: 720 }}>
        When the day is mostly screenshots, the shipped agenda renders a
        wall of identical gray placeholder boxes — the type-mark draws a
        generic <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 12 }}>photo</code> glyph instead of the real capture. Every fix
        here turns on one move: <span style={{ color: T.ink }}>render the actual thumbnail</span>, then let the
        chrome quiet down around it.
      </p>
      <div className="flex" style={{ gap: 8, marginTop: 14 }}>
        {fixes.map((f) => (
          <span key={f} className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.14em", color: T.inkFaint, background: T.pane, border: `0.5px solid ${T.ruleSoft}`, borderRadius: 3, padding: "3px 8px" }}>
            {f}
          </span>
        ))}
      </div>
    </div>
  );
}

function NamesMarginalia() {
  const entries: [string, string][] = [
    ["Frontispiece",  "the monumental serif date + italic byline. Anchors the pane; survives every variant."],
    ["Signal Strip",  "the 4-cell stat band under the date. Adaptive: dead VOICE / WORDS cells drop on a captures day."],
    ["Capture Mark",  "the per-row thumbnail. The fix: a real 64×40 shot, not a generic photo glyph."],
    ["Agenda Row",    "time · mark · title · meta · trailing. Trailing carries dimensions + size, never a lonely “—”."],
    ["Contact Card",  "contact-sheet cell — thumbnail over a time · app · width caption."],
    ["Source Block",  "grouped-variant header collapsing one app's run: dot · APP · count · time-span."],
  ];
  return (
    <div style={{ padding: "30px 40px 4px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 12 }}>
        <span className="font-mono font-semibold uppercase" style={{ color: T.amber, fontSize: 9.5, letterSpacing: "0.30em" }}>
          · names
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 12 }}>
          shared vocabulary for studio · Swift · chat
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: T.ruleSoft }} />
      </div>
      <div
        style={{ marginTop: 14, padding: "14px 18px 16px 18px", background: T.pane, border: `0.5px solid ${T.ruleSoft}`, borderRadius: 6, display: "grid", gridTemplateColumns: "150px 1fr", rowGap: 6, columnGap: 18 }}
      >
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span className="font-mono font-semibold uppercase" style={{ fontSize: 10, letterSpacing: "0.14em", color: T.amberDeep }}>
              {name}
            </span>
            <span className="font-display italic" style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}>
              {def}
            </span>
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
        Donor: <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScopeLibraryEmptyState.swift</code> (the
        populated <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>todaySection</code> path). The real fix lands in
        <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}> OverviewTypeMark</code> (thumbnail), <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>trailingMetric</code> (dimensions),
        and <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>DaySignalStrip</code> (adaptive cells). Thumbnails are synthetic CSS — the shipping mark reuses <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScopeLibraryMediaThumbnail</code>.
      </p>
    </div>
  );
}
