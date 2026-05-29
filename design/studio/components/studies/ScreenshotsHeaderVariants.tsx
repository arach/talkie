"use client";

/**
 * ScreenshotsHeaderVariants — the header, in place, two directions.
 *
 * Not an abstract anatomy: each variant is the real Screenshots surface —
 * window chrome, header, the actual grid underneath — so the header is
 * judged in context, against the tiles it sits over.
 *
 *   A · Serif standard  — eyebrow + serif title + mono tags (the Learn look).
 *   B · Mono instrument — no serif at all; the header is mono chrome, the
 *                         same register as the preview / inspector / status
 *                         bar that already feels good.
 *
 * Donor: apps/macos/Talkie/Views/ScreenshotsScreen.swift
 */

import React from "react";
import { SCOPE } from "@/lib/scope-tokens";

const T = {
  page:       SCOPE.canvas,
  pane:       SCOPE.pane,
  chrome:     SCOPE.chrome,
  rail:       SCOPE.rail,
  ink:        SCOPE.ink,
  inkMid:     SCOPE.inkMid,
  inkFaint:   SCOPE.inkFaint,
  inkFainter: SCOPE.inkFainter,
  rule:       SCOPE.rule,
  ruleSubtle: SCOPE.ruleSubtle,
  edge:       SCOPE.edge,
  amber:      SCOPE.amber,
  amberDeep:  SCOPE.amberDeep,
  amberFaint: SCOPE.amberFaint,
  amberSoft:  SCOPE.amberSoft,
  brass:      SCOPE.brass,
};

export function ScreenshotsHeaderVariants() {
  return (
    <div style={{ width: 1180, background: T.page }} className="flex flex-col" >
      <StudyHeader />

      <VariantBlock
        tag="A"
        label="serif standard"
        caption="eyebrow + serif title + mono tags — the Learn look"
      >
        <Surface header={<SerifHeader />} />
      </VariantBlock>

      <VariantBlock
        tag="B"
        label="mono instrument"
        caption="no serif — header is mono chrome, same register as the preview / inspector"
      >
        <Surface header={<MonoHeader />} />
      </VariantBlock>

      <StudyFooter />
    </div>
  );
}

// ─── The two header directions ───────────────────────────────────────

function SerifHeader() {
  return (
    <div className="flex items-end justify-between" style={{ gap: 16, padding: "16px 18px 14px 18px" }}>
      <div className="flex flex-col">
        <span className="flex items-center" style={{ gap: 6 }}>
          <span style={{ width: 5, height: 5, borderRadius: 999, background: T.amber }} />
          <span className="font-mono uppercase" style={{ color: T.inkFaint, fontSize: 9.5, letterSpacing: "0.30em" }}>
            capture · macos
          </span>
        </span>
        <h3 className="font-display tracking-tight" style={{ color: T.ink, fontSize: 30, fontWeight: 500, lineHeight: 1.05, marginTop: 7 }}>
          Screenshots
        </h3>
        <TagRow />
      </div>
      <Controls />
    </div>
  );
}

function MonoHeader() {
  return (
    <div className="flex items-center justify-between" style={{ gap: 16, padding: "18px 18px 16px 18px" }}>
      <div className="flex items-center" style={{ gap: 12 }}>
        <span style={{ width: 6, height: 6, borderRadius: 999, background: T.amber }} />
        <span
          className="font-mono font-semibold uppercase"
          style={{ color: T.ink, fontSize: 15, letterSpacing: "0.28em" }}
        >
          Screenshots
        </span>
        <span style={{ width: 1, height: 16, background: T.rule, margin: "0 2px" }} />
        <span className="font-mono uppercase" style={{ color: T.inkFaint, fontSize: 9.5, letterSpacing: "0.20em" }}>
          12 captures · 2 today
        </span>
      </div>
      <Controls />
    </div>
  );
}

function TagRow() {
  const tags = ["12 captures", "2 today"];
  return (
    <div className="flex items-center" style={{ gap: 8, marginTop: 8 }}>
      {tags.map((tag, i) => (
        <React.Fragment key={tag}>
          {i > 0 && <span style={{ color: T.inkFainter, fontSize: 9 }}>·</span>}
          <span
            className="font-mono uppercase"
            style={{ color: i === 0 ? T.amberDeep : T.inkFaint, fontSize: 9, letterSpacing: "0.20em" }}
          >
            {tag}
          </span>
        </React.Fragment>
      ))}
    </div>
  );
}

function Controls() {
  return (
    <div className="flex items-center" style={{ gap: 8 }}>
      <div className="flex items-center" style={{ gap: 2, padding: 2, background: T.chrome, border: `0.5px solid ${T.rule}`, borderRadius: 6 }}>
        <span className="flex items-center justify-center" style={{ width: 24, height: 18, borderRadius: 4, background: T.amberFaint, border: `0.5px solid ${T.amberSoft}` }}>
          <GridGlyph />
        </span>
        <span className="flex items-center justify-center" style={{ width: 24, height: 18, borderRadius: 4 }}>
          <ListGlyph />
        </span>
      </div>
      <div className="flex items-center" style={{ gap: 6, padding: "4px 10px", width: 150, background: T.chrome, border: `0.5px solid ${T.rule}`, borderRadius: 6 }}>
        <span style={{ width: 9, height: 9, borderRadius: 999, border: `1.2px solid ${T.inkFainter}` }} />
        <span className="font-display italic" style={{ fontSize: 11.5, color: T.inkFainter }}>Search…</span>
      </div>
    </div>
  );
}

function GridGlyph() {
  return (
    <span style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 1.5, width: 10, height: 10 }}>
      {[0, 1, 2, 3].map((i) => (
        <span key={i} style={{ background: T.amberDeep, borderRadius: 0.5 }} />
      ))}
    </span>
  );
}

function ListGlyph() {
  return (
    <span className="flex flex-col" style={{ gap: 2, width: 11 }}>
      {[0, 1, 2].map((i) => (
        <span key={i} style={{ height: 1.5, background: T.inkFainter, borderRadius: 1 }} />
      ))}
    </span>
  );
}

// ─── Surface — window chrome + header slot + real grid ───────────────

function Surface({ header }: { header: React.ReactNode }) {
  return (
    <div
      style={{
        background: T.page,
        borderRadius: 8,
        border: `0.5px solid ${T.edge}`,
        boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset, 0 12px 30px -8px rgba(0,0,0,0.10)",
        overflow: "hidden",
      }}
    >
      {/* macOS window strip */}
      <div className="flex items-center" style={{ height: 28, padding: "0 12px", gap: 6, background: T.chrome, borderBottom: `0.5px solid ${T.ruleSubtle}` }}>
        <span style={{ width: 8, height: 8, borderRadius: 999, background: "#FF5F57" }} />
        <span style={{ width: 8, height: 8, borderRadius: 999, background: "#FEBC2E" }} />
        <span style={{ width: 8, height: 8, borderRadius: 999, background: "#28C840" }} />
      </div>

      {/* The header under test */}
      <div style={{ borderBottom: `0.5px solid ${T.ruleSubtle}` }}>{header}</div>

      {/* Real grid beneath, so the header is judged in context */}
      <div
        style={{
          padding: 16,
          background: T.rail,
          display: "grid",
          gridTemplateColumns: "repeat(6, 1fr)",
          gap: 12,
        }}
      >
        {Array.from({ length: 12 }).map((_, i) => (
          <Tile key={i} kind={i % 4} />
        ))}
      </div>
    </div>
  );
}

function Tile({ kind }: { kind: number }) {
  return (
    <div
      style={{
        aspectRatio: "4 / 3",
        background: T.page,
        border: `0.5px solid ${T.ruleSubtle}`,
        borderRadius: 4,
        boxShadow: "0 1px 2px rgba(0,0,0,0.04)",
        overflow: "hidden",
        padding: 8,
      }}
    >
      {kind === 0 &&
        Array.from({ length: 5 }).map((_, i) => (
          <div key={i} style={{ height: 3, background: T.inkFainter, opacity: 0.28, borderRadius: 1, width: `${50 + ((i * 13) % 40)}%`, marginTop: 4 }} />
        ))}
      {kind === 1 &&
        Array.from({ length: 4 }).map((_, r) => (
          <div key={r} className="flex" style={{ gap: 3, marginTop: 3 }}>
            {Array.from({ length: 4 }).map((_, c) => (
              <div key={c} style={{ flex: 1, height: 5, background: T.inkFainter, opacity: r === 0 ? 0.34 : 0.2, borderRadius: 1 }} />
            ))}
          </div>
        ))}
      {kind === 2 && (
        <div className="flex flex-col" style={{ gap: 4 }}>
          {[0, 1, 0, 1].map((side, i) => (
            <div key={i} style={{ alignSelf: side === 0 ? "flex-start" : "flex-end", width: `${42 + ((i * 9) % 28)}%`, height: 7, background: side === 0 ? T.inkFainter : T.amberFaint, opacity: 0.6, borderRadius: 3 }} />
          ))}
        </div>
      )}
      {kind === 3 &&
        [0, 1, 2, 1, 2].map((indent, i) => (
          <div key={i} style={{ marginLeft: indent * 7, height: 3, background: i % 3 === 1 ? T.brass : T.inkFainter, opacity: i % 3 === 1 ? 0.5 : 0.26, borderRadius: 1, width: `${40 + ((i * 11) % 28)}%`, marginTop: 4 }} />
        ))}
    </div>
  );
}

// ─── Frame bits ──────────────────────────────────────────────────────

function VariantBlock({ tag, label, caption, children }: { tag: string; label: string; caption: string; children: React.ReactNode }) {
  return (
    <div style={{ padding: "8px 40px 8px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 10, marginBottom: 12 }}>
        <span
          className="font-mono font-semibold"
          style={{ fontSize: 11, color: "#fff", background: T.amber, borderRadius: 3, padding: "2px 8px" }}
        >
          {tag}
        </span>
        <span className="font-mono font-semibold uppercase" style={{ color: T.amber, fontSize: 9.5, letterSpacing: "0.26em" }}>
          {label}
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 12 }}>{caption}</span>
        <div className="flex-1" style={{ height: 1, background: T.ruleSubtle }} />
      </div>
      {children}
    </div>
  );
}

function StudyHeader() {
  return (
    <div style={{ padding: "24px 40px 4px 40px" }}>
      <div className="flex items-baseline gap-3">
        <span className="font-mono font-semibold uppercase" style={{ color: T.inkFaint, fontSize: 9, letterSpacing: "0.32em" }}>
          · SCREENSHOTS HEADER · in place · two directions
        </span>
      </div>
      <h2 className="font-display tracking-tight" style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 10 }}>
        Header, in context
      </h2>
      <p className="font-display" style={{ color: T.inkMid, fontSize: 14, lineHeight: 1.6, marginTop: 12, maxWidth: 700 }}>
        The same surface — window chrome, header, the real grid — with two
        header directions so you can judge them over the tiles, not in the
        abstract. A keeps the serif title; B drops it entirely for the mono
        instrument register the preview and inspector already use.
      </p>
    </div>
  );
}

function StudyFooter() {
  return (
    <div style={{ padding: "24px 40px 28px 40px" }}>
      <div style={{ height: 1, background: T.ruleSubtle, marginBottom: 14 }} />
      <p className="font-display italic" style={{ color: T.inkFaint, fontSize: 12.5, lineHeight: 1.6, maxWidth: 720 }}>
        Donor: <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScreenshotsScreen.swift</code>. Pick a
        direction and I port it to the live header.
      </p>
    </div>
  );
}
