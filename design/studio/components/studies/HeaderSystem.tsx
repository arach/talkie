"use client";

/**
 * HeaderSystem — shared atoms, composed into a few header SHAPES, each
 * shown in place on its screen.
 *
 * The app's screens don't want one header — they want a system: the same
 * atoms (dot · eyebrow · title · tags · tabs · controls) arranged into the
 * shape that fits the surface.
 *
 *   Gallery   (Screenshots) — dot · mono title · tags · controls   [dense wall]
 *   Reading   (Learn)       — eyebrow · serif title · tags          [doc / KB]
 *   Library   (Dictations)  — eyebrow · serif title · date tags     [grouped list]
 *   Tabbed    (Context)     — dot · mono title · tab bar            [multi-section]
 *
 * Title register is the lever: mono for instrument/dense surfaces, serif
 * for reading surfaces — but always bracketed by mono chrome.
 *
 * Donors: ScreenshotsScreen.swift · ScopeLibraryView.swift ("28 May") ·
 * ScopeLearnScreen.swift · ScopeContextView.swift · CompactScopePageHeader.
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

export function HeaderSystem() {
  return (
    <div style={{ width: 1160, background: T.page }} className="flex flex-col">
      <StudyHeader />
      <AtomsLegend />

      <Shape
        screen="Screenshots"
        role="gallery"
        atoms={["dot", "mono title", "tags", "controls"]}
        header={<GalleryHeader />}
        body={<TilesBody />}
      />
      <Shape
        screen="Learn"
        role="reading"
        atoms={["eyebrow", "serif title", "tags"]}
        header={<ReadingHeader />}
        body={<DocBody />}
      />
      <Shape
        screen="Dictations"
        role="library"
        atoms={["eyebrow", "serif title", "date tags"]}
        header={<LibraryHeader />}
        body={<ListBody />}
      />
      <Shape
        screen="Context"
        role="tabbed"
        atoms={["dot", "mono title", "tab bar"]}
        header={<TabbedHeader />}
        body={<CardsBody />}
      />

      <NamesMarginalia />
      <StudyFooter />
    </div>
  );
}

// ─── Shared atoms ────────────────────────────────────────────────────

function Dot({ size = 6 }: { size?: number }) {
  return <span style={{ width: size, height: size, borderRadius: 999, background: T.amber, flexShrink: 0 }} />;
}

function Eyebrow({ text }: { text: string }) {
  return (
    <span className="flex items-center" style={{ gap: 6 }}>
      <Dot size={5} />
      <span className="font-mono uppercase" style={{ color: T.inkFaint, fontSize: 9.5, letterSpacing: "0.30em" }}>
        {text}
      </span>
    </span>
  );
}

function SerifTitle({ children }: { children: React.ReactNode }) {
  return (
    <h3 className="font-display tracking-tight" style={{ color: T.ink, fontSize: 28, fontWeight: 500, lineHeight: 1.05, marginTop: 7 }}>
      {children}
    </h3>
  );
}

function MonoTitle({ children }: { children: React.ReactNode }) {
  return (
    <span className="font-mono font-semibold uppercase" style={{ color: T.ink, fontSize: 14, letterSpacing: "0.28em" }}>
      {children}
    </span>
  );
}

function Tags({ items, marginTop = 8 }: { items: string[]; marginTop?: number }) {
  return (
    <div className="flex items-center" style={{ gap: 8, marginTop }}>
      {items.map((tag, i) => (
        <React.Fragment key={tag}>
          {i > 0 && <span style={{ color: T.inkFainter, fontSize: 9 }}>·</span>}
          <span className="font-mono uppercase" style={{ color: i === 0 ? T.amberDeep : T.inkFaint, fontSize: 9, letterSpacing: "0.20em" }}>
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
        <span style={{ width: 22, height: 17, borderRadius: 4, background: T.amberFaint, border: `0.5px solid ${T.amberSoft}` }} />
        <span style={{ width: 22, height: 17, borderRadius: 4 }} />
      </div>
      <div className="flex items-center" style={{ gap: 6, padding: "4px 9px", width: 130, background: T.chrome, border: `0.5px solid ${T.rule}`, borderRadius: 6 }}>
        <span style={{ width: 8, height: 8, borderRadius: 999, border: `1.2px solid ${T.inkFainter}` }} />
        <span className="font-display italic" style={{ fontSize: 11, color: T.inkFainter }}>Search…</span>
      </div>
    </div>
  );
}

function TabBar({ tabs, active }: { tabs: string[]; active: number }) {
  return (
    <div className="flex items-center" style={{ gap: 18 }}>
      {tabs.map((t, i) => (
        <span key={t} className="flex flex-col items-center" style={{ gap: 4 }}>
          <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: i === active ? T.amberDeep : T.inkFaint }}>
            {t}
          </span>
          <span style={{ width: "100%", height: 1.5, background: i === active ? T.amber : "transparent", borderRadius: 1 }} />
        </span>
      ))}
    </div>
  );
}

// ─── Header shapes ───────────────────────────────────────────────────

function GalleryHeader() {
  return (
    <div className="flex items-center justify-between" style={{ gap: 16, padding: "16px 18px" }}>
      <div className="flex items-center" style={{ gap: 12 }}>
        <Dot />
        <MonoTitle>Screenshots</MonoTitle>
        <span style={{ width: 1, height: 16, background: T.rule, margin: "0 2px" }} />
        <span className="font-mono uppercase" style={{ color: T.inkFaint, fontSize: 9.5, letterSpacing: "0.20em" }}>
          12 captures · 2 today
        </span>
      </div>
      <Controls />
    </div>
  );
}

function ReadingHeader() {
  return (
    <div className="flex flex-col" style={{ padding: "16px 18px 14px 18px" }}>
      <Eyebrow text="ask · explore · revisit" />
      <SerifTitle>Learn</SerifTitle>
      <Tags items={["knowledge base", "12 articles"]} />
    </div>
  );
}

function LibraryHeader() {
  return (
    <div className="flex items-end justify-between" style={{ gap: 16, padding: "16px 18px 14px 18px" }}>
      <div className="flex flex-col">
        <Eyebrow text="library · dictations" />
        <SerifTitle>Dictations</SerifTitle>
        <Tags items={["28 may", "33 memos", "1.4k words"]} />
      </div>
      <Controls />
    </div>
  );
}

function TabbedHeader() {
  return (
    <div className="flex flex-col" style={{ padding: "16px 18px 0 18px", gap: 14 }}>
      <div className="flex items-center" style={{ gap: 12 }}>
        <Dot />
        <MonoTitle>Context</MonoTitle>
        <span style={{ width: 1, height: 16, background: T.rule, margin: "0 2px" }} />
        <span className="font-mono uppercase" style={{ color: T.inkFaint, fontSize: 9.5, letterSpacing: "0.20em" }}>
          5 rules · 2 active
        </span>
      </div>
      <TabBar tabs={["overview", "apps", "cleanup", "dictation", "settings"]} active={0} />
    </div>
  );
}

// ─── In-place bodies (a hint of the real surface) ────────────────────

function TilesBody() {
  return (
    <div style={{ padding: 14, background: T.rail, display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 10 }}>
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} style={{ aspectRatio: "4 / 3", background: T.page, border: `0.5px solid ${T.ruleSubtle}`, borderRadius: 4 }} />
      ))}
    </div>
  );
}

function DocBody() {
  return (
    <div style={{ padding: "16px 18px", background: T.page, display: "flex", flexDirection: "column", gap: 7 }}>
      <div style={{ height: 4, width: "30%", background: T.inkFainter, opacity: 0.4, borderRadius: 1 }} />
      {Array.from({ length: 4 }).map((_, i) => (
        <div key={i} style={{ height: 3, width: `${70 + ((i * 7) % 24)}%`, background: T.inkFainter, opacity: 0.26, borderRadius: 1 }} />
      ))}
    </div>
  );
}

function ListBody() {
  return (
    <div style={{ background: T.page }}>
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="flex items-center" style={{ gap: 10, padding: "9px 18px", borderTop: i ? `0.5px solid ${T.ruleSubtle}` : "none" }}>
          <span style={{ width: 18, height: 18, borderRadius: 3, border: `0.5px solid ${T.rule}` }} />
          <div className="flex flex-col" style={{ gap: 4, flex: 1 }}>
            <div style={{ height: 4, width: `${44 + ((i * 11) % 30)}%`, background: T.inkFainter, opacity: 0.4, borderRadius: 1 }} />
            <div style={{ height: 3, width: "26%", background: T.inkFainter, opacity: 0.22, borderRadius: 1 }} />
          </div>
        </div>
      ))}
    </div>
  );
}

function CardsBody() {
  return (
    <div style={{ padding: 14, background: T.page, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginTop: 14, borderTop: `0.5px solid ${T.ruleSubtle}` }}>
      {Array.from({ length: 2 }).map((_, i) => (
        <div key={i} style={{ height: 54, background: T.pane, border: `0.5px solid ${T.ruleSubtle}`, borderRadius: 5, padding: 10 }}>
          <div style={{ height: 3, width: "20%", background: T.amberDeep, opacity: 0.5, borderRadius: 1 }} />
          <div style={{ height: 4, width: "44%", background: T.inkFainter, opacity: 0.4, borderRadius: 1, marginTop: 7 }} />
        </div>
      ))}
    </div>
  );
}

// ─── Shape frame ─────────────────────────────────────────────────────

function Shape({
  screen,
  role,
  atoms,
  header,
  body,
}: {
  screen: string;
  role: string;
  atoms: string[];
  header: React.ReactNode;
  body: React.ReactNode;
}) {
  return (
    <div style={{ padding: "8px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 10, marginBottom: 10 }}>
        <span className="font-mono font-semibold uppercase" style={{ color: T.ink, fontSize: 10, letterSpacing: "0.18em" }}>
          {screen}
        </span>
        <span className="font-mono uppercase" style={{ color: T.amberDeep, fontSize: 8.5, letterSpacing: "0.18em", background: T.amberFaint, border: `0.5px solid ${T.amberSoft}`, borderRadius: 2, padding: "1px 6px" }}>
          {role}
        </span>
        <span className="font-mono" style={{ color: T.inkFainter, fontSize: 9, letterSpacing: "0.06em" }}>
          {atoms.join(" · ")}
        </span>
        <div className="flex-1" style={{ height: 1, background: T.ruleSubtle }} />
      </div>
      <div style={{ background: T.page, borderRadius: 8, border: `0.5px solid ${T.edge}`, boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset, 0 10px 24px -8px rgba(0,0,0,0.10)", overflow: "hidden" }}>
        <div className="flex items-center" style={{ height: 26, padding: "0 12px", gap: 6, background: T.chrome, borderBottom: `0.5px solid ${T.ruleSubtle}` }}>
          <span style={{ width: 8, height: 8, borderRadius: 999, background: "#FF5F57" }} />
          <span style={{ width: 8, height: 8, borderRadius: 999, background: "#FEBC2E" }} />
          <span style={{ width: 8, height: 8, borderRadius: 999, background: "#28C840" }} />
        </div>
        <div style={{ borderBottom: `0.5px solid ${T.ruleSubtle}` }}>{header}</div>
        {body}
      </div>
    </div>
  );
}

// ─── Atoms legend + frame bits ───────────────────────────────────────

function AtomsLegend() {
  const atoms: [string, string][] = [
    ["Dot", "amber status dot"],
    ["Eyebrow", "mono caps · context"],
    ["Title", "mono (instrument) or serif (reading)"],
    ["Tags", "mono caps · counts / date / state"],
    ["Tab bar", "mono caps · active underline"],
    ["Controls", "search · view toggle · actions"],
  ];
  return (
    <div style={{ padding: "6px 40px 12px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 10, marginBottom: 12 }}>
        <span className="font-mono font-semibold uppercase" style={{ color: T.amber, fontSize: 9.5, letterSpacing: "0.30em" }}>· atoms</span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 12 }}>the shared parts every shape is built from</span>
        <div className="flex-1" style={{ height: 1, background: T.ruleSubtle }} />
      </div>
      <div className="flex flex-wrap" style={{ gap: 8 }}>
        {atoms.map(([name, note]) => (
          <span key={name} className="flex items-baseline" style={{ gap: 6, padding: "5px 10px", background: T.pane, border: `0.5px solid ${T.ruleSubtle}`, borderRadius: 5 }}>
            <span className="font-mono font-semibold uppercase" style={{ fontSize: 9, letterSpacing: "0.16em", color: T.amberDeep }}>{name}</span>
            <span className="font-display italic" style={{ fontSize: 11.5, color: T.inkMid }}>{note}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

function StudyHeader() {
  return (
    <div style={{ padding: "24px 40px 4px 40px" }}>
      <div className="flex items-baseline gap-3">
        <span className="font-mono font-semibold uppercase" style={{ color: T.inkFaint, fontSize: 9, letterSpacing: "0.32em" }}>
          · HEADER SYSTEM · foundations
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>shared atoms · a few shapes · each in place</span>
      </div>
      <h2 className="font-display tracking-tight" style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 10 }}>
        Header System
      </h2>
      <p className="font-display" style={{ color: T.inkMid, fontSize: 14, lineHeight: 1.6, marginTop: 12, maxWidth: 720 }}>
        One header doesn't fit every screen — a gallery, a doc, a grouped list,
        and a tabbed panel all want different shapes. The system is the shared
        atoms; each screen composes the shape that fits. Mono title for
        instrument surfaces, serif for reading — always framed by mono chrome.
      </p>
    </div>
  );
}

function NamesMarginalia() {
  const entries: [string, string][] = [
    ["Shape", "a header arrangement for one kind of screen — gallery / reading / library / tabbed."],
    ["Title register", "mono = instrument/dense; serif = reading. The one lever that changes per shape."],
    ["Mono frame", "eyebrow / tags / tab bar. The serif only ever appears inside it."],
    ["Controls", "search · view toggle · actions — ride the title baseline, never replace the title."],
  ];
  return (
    <div style={{ padding: "20px 40px 4px 40px" }}>
      <div className="flex items-baseline gap-3">
        <span className="font-mono font-semibold uppercase" style={{ color: T.amber, fontSize: 9.5, letterSpacing: "0.30em" }}>· names</span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 12 }}>shared vocabulary for studio · swift · chat</span>
        <div className="ml-3 flex-1" style={{ height: 1, background: T.ruleSubtle }} />
      </div>
      <div style={{ marginTop: 14, padding: "14px 18px 16px 18px", background: T.pane, border: `0.5px solid ${T.ruleSubtle}`, borderRadius: 6, display: "grid", gridTemplateColumns: "150px 1fr", rowGap: 6, columnGap: 18 }}>
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span className="font-mono font-semibold uppercase" style={{ fontSize: 10, letterSpacing: "0.16em", color: T.amberDeep }}>{name}</span>
            <span className="font-display italic" style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}>{def}</span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

function StudyFooter() {
  return (
    <div style={{ padding: "24px 40px 28px 40px" }}>
      <div style={{ height: 1, background: T.ruleSubtle, marginBottom: 14 }} />
      <p className="font-display italic" style={{ color: T.inkFaint, fontSize: 12.5, lineHeight: 1.6, maxWidth: 740 }}>
        Donors: <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScreenshotsScreen</code>,{" "}
        <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScopeLearnScreen</code>,{" "}
        <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScopeLibraryView</code>,{" "}
        <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScopeContextView</code>. The shared atoms become
        one Swift header component; each screen picks its shape.
      </p>
    </div>
  );
}
