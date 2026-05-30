"use client";

/**
 * TopBandSystem — ONE top-band component, four fixed slots, a variant per view.
 *
 * The top strip across every screen is the same component. It owns four
 * slots at fixed positions so the wordmark, title, TALKIE pill, and
 * complications never drift between screens:
 *
 *   ◧ WORDMARK   TITLE CLUSTER  ……   ◉ TALKIE (centered)   ……   COMPLICATIONS
 *
 * Only the TITLE CLUSTER and the COMPLICATIONS change per view — that's the
 * "variant." Wordmark and pill are invariant (size + position locked), which
 * is what gives the logo / title / pill the stable relationship.
 *
 * Donors: ScopeTopBand (title slot) · TalkieChromeBar (pill) · the per-screen
 * complications. This formalizes them into one organized component.
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
};

const BAND_HEIGHT = 52;

export function TopBandSystem() {
  return (
    <div style={{ width: 1120, background: T.page }} className="flex flex-col">
      <StudyHeader />
      <Anatomy />
      <VariantMatrix />
      <InPlace />
      <NamesMarginalia />
    </div>
  );
}

// ─── The one component ───────────────────────────────────────────────

/**
 * The band. Three zones in a row — left (wordmark + title cluster) and
 * right (complications) anchor the edges; the TALKIE pill is absolutely
 * centered so it never moves regardless of what the variant puts on either
 * side.
 */
function Band({
  title,
  complications,
  showWordmark = true,
}: {
  title: React.ReactNode;
  complications?: React.ReactNode;
  showWordmark?: boolean;
}) {
  return (
    <div
      style={{ position: "relative", height: BAND_HEIGHT }}
      className="flex items-center"
    >
      {/* Left: wordmark + title cluster */}
      <div className="flex items-center" style={{ gap: 14 }}>
        {showWordmark && <Wordmark />}
        {title}
      </div>

      {/* Center: TALKIE pill — absolutely centered, invariant */}
      <div style={{ position: "absolute", left: "50%", transform: "translateX(-50%)" }}>
        <TalkiePill />
      </div>

      {/* Right: complications */}
      <div className="ml-auto flex items-center" style={{ gap: 8 }}>
        {complications}
      </div>
    </div>
  );
}

function Wordmark() {
  return (
    <span
      className="flex items-center justify-center"
      style={{ width: 22, height: 22, borderRadius: 6, background: T.ink }}
    >
      <span style={{ width: 7, height: 7, borderRadius: 999, background: T.amber }} />
    </span>
  );
}

function TalkiePill() {
  return (
    <span
      className="flex items-center"
      style={{ gap: 6, padding: "5px 12px", borderRadius: 999, background: "#1A1714" }}
    >
      <span style={{ width: 5, height: 5, borderRadius: 999, background: T.amber }} />
      <span className="font-mono font-semibold uppercase" style={{ fontSize: 9.5, letterSpacing: "0.24em", color: "#F3EEE6" }}>
        Talkie
      </span>
    </span>
  );
}

// ─── Title-cluster variants (the part that changes) ──────────────────

function MonoTitleCluster({ name, chrome }: { name: string; chrome?: string }) {
  return (
    <span className="flex items-center" style={{ gap: 10 }}>
      <span style={{ width: 5, height: 5, borderRadius: 999, background: T.amber }} />
      <span className="font-mono font-semibold uppercase" style={{ fontSize: 11, letterSpacing: "0.20em", color: T.inkMid }}>
        {name}
      </span>
      {chrome && (
        <>
          <span style={{ width: 1, height: 12, background: T.rule }} />
          <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.inkFaint }}>
            {chrome}
          </span>
        </>
      )}
    </span>
  );
}

function SerifTitleCluster({ name, eyebrow, chrome }: { name: string; eyebrow?: string; chrome?: string }) {
  return (
    <span className="flex items-baseline" style={{ gap: 10 }}>
      {eyebrow && (
        <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.26em", color: T.inkFaint }}>
          {eyebrow}
        </span>
      )}
      <span className="font-display" style={{ fontSize: 21, fontWeight: 500, color: T.ink, letterSpacing: 0 }}>
        {name}
      </span>
      {chrome && (
        <span className="font-mono uppercase" style={{ fontSize: 9, letterSpacing: "0.18em", color: T.inkFaint }}>
          {chrome}
        </span>
      )}
    </span>
  );
}

// ─── Complications (right slot) ──────────────────────────────────────

function CompToggle() {
  return (
    <span className="flex items-center" style={{ gap: 2, padding: 2, background: T.chrome, border: `0.5px solid ${T.rule}`, borderRadius: 6 }}>
      <span style={{ width: 22, height: 17, borderRadius: 4, background: T.amberFaint, border: `0.5px solid ${T.amberSoft}` }} />
      <span style={{ width: 22, height: 17, borderRadius: 4 }} />
    </span>
  );
}

function CompSearch({ width = 150 }: { width?: number }) {
  return (
    <span className="flex items-center" style={{ gap: 6, padding: "4px 9px", width, background: T.chrome, border: `0.5px solid ${T.rule}`, borderRadius: 6 }}>
      <span style={{ width: 9, height: 9, borderRadius: 999, border: `1.2px solid ${T.inkFainter}` }} />
      <span className="font-display italic" style={{ fontSize: 11, color: T.inkFainter }}>Search…</span>
    </span>
  );
}

function CompTag({ text }: { text: string }) {
  return (
    <span className="font-mono uppercase" style={{ fontSize: 8.5, letterSpacing: "0.2em", color: T.inkFaint }}>
      {text}
    </span>
  );
}

function CompIcon() {
  return <span style={{ width: 24, height: 22, borderRadius: 5, background: T.chrome, border: `0.5px solid ${T.rule}` }} />;
}

// ─── Anatomy ─────────────────────────────────────────────────────────

function Anatomy() {
  return (
    <Section label="the component" caption="four slots · fixed positions">
      <Frame>
        <Band
          title={<MonoTitleCluster name="Screenshots" chrome="358 captures · 80 today" />}
          complications={<><CompToggle /><CompSearch /><CompIcon /></>}
        />
      </Frame>
      <div className="flex" style={{ marginTop: 10, gap: 0 }}>
        <SlotTag x="left" label="① Wordmark" note="invariant · size + position locked" />
        <SlotTag x="left2" label="② Title cluster" note="the variant — mono or serif + chrome" />
        <SlotTag x="center" label="③ TALKIE" note="invariant · always centered" />
        <SlotTag x="right" label="④ Complications" note="per-view tools — search / toggle / status" />
      </div>
    </Section>
  );
}

function SlotTag({ label, note }: { x: string; label: string; note: string }) {
  return (
    <div className="flex flex-col" style={{ flex: 1, paddingRight: 14 }}>
      <span className="font-mono font-semibold uppercase" style={{ fontSize: 9, letterSpacing: "0.14em", color: T.amberDeep }}>
        {label}
      </span>
      <span className="font-display italic" style={{ fontSize: 11, color: T.inkMid, lineHeight: 1.35, marginTop: 2 }}>
        {note}
      </span>
    </div>
  );
}

// ─── Variant matrix ──────────────────────────────────────────────────

function VariantMatrix() {
  const rows: [string, string, string, string][] = [
    ["Screenshots", "gallery", "mono · counts", "toggle · search · tray · folder"],
    ["Console / Actions", "list", "mono · counts", "status · refresh"],
    ["Learn / Skills", "reading", "serif · eyebrow", "search"],
    ["Models", "list", "serif · counts", "—"],
    ["Dictations", "library", "serif · date chrome", "search · mic"],
    ["Context / Drafts", "tabbed", "serif + tab row", "at-a-glance"],
  ];
  return (
    <Section label="variants" caption="each view picks one — only title + complications change">
      <Frame pad>
        <MatrixRow cells={["view", "variant", "title cluster", "complications"]} head />
        {rows.map((r) => (
          <MatrixRow key={r[0]} cells={r} />
        ))}
      </Frame>
    </Section>
  );
}

function MatrixRow({ cells, head }: { cells: string[]; head?: boolean }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "180px 120px 200px 1fr", gap: 12, padding: "8px 0", borderBottom: head ? "none" : `0.5px solid ${T.ruleSubtle}` }}>
      {cells.map((c, i) => (
        <span
          key={i}
          className="font-mono"
          style={{
            fontSize: head ? 8.5 : 10.5,
            textTransform: head ? "uppercase" : "none",
            letterSpacing: head ? "0.2em" : "0.02em",
            color: head ? T.inkFainter : i === 1 ? T.amberDeep : i === 0 ? T.ink : T.inkMid,
          }}
        >
          {c}
        </span>
      ))}
    </div>
  );
}

// ─── In place ────────────────────────────────────────────────────────

function InPlace() {
  return (
    <Section label="in place" caption="same component, three variants">
      <div className="flex flex-col" style={{ gap: 10 }}>
        <PlacedBand
          tag="gallery"
          band={
            <Band
              title={<MonoTitleCluster name="Screenshots" chrome="358 captures · 80 today" />}
              complications={<><CompToggle /><CompSearch /><CompIcon /></>}
            />
          }
        />
        <PlacedBand
          tag="reading"
          band={
            <Band
              title={<SerifTitleCluster name="Learn" eyebrow="ASK · EXPLORE · REVISIT" />}
              complications={<><CompSearch width={130} /><CompTag text="agent · interstitial" /></>}
            />
          }
        />
        <PlacedBand
          tag="library"
          band={
            <Band
              title={<SerifTitleCluster name="Dictations" chrome="28 May · 33 memos" />}
              complications={<><CompSearch width={130} /><CompIcon /></>}
            />
          }
        />
      </div>
    </Section>
  );
}

function PlacedBand({ tag, band }: { tag: string; band: React.ReactNode }) {
  return (
    <div style={{ background: T.page, border: `0.5px solid ${T.edge}`, borderRadius: 8, overflow: "hidden", boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset, 0 8px 20px -8px rgba(0,0,0,0.08)" }}>
      <div className="flex items-center" style={{ height: 22, padding: "0 12px", gap: 6, background: T.chrome, borderBottom: `0.5px solid ${T.ruleSubtle}` }}>
        <span style={{ width: 7, height: 7, borderRadius: 999, background: "#FF5F57" }} />
        <span style={{ width: 7, height: 7, borderRadius: 999, background: "#FEBC2E" }} />
        <span style={{ width: 7, height: 7, borderRadius: 999, background: "#28C840" }} />
        <span className="ml-auto font-mono uppercase" style={{ fontSize: 8, letterSpacing: "0.2em", color: T.amberDeep, background: T.amberFaint, border: `0.5px solid ${T.amberSoft}`, borderRadius: 2, padding: "1px 6px" }}>
          {tag}
        </span>
      </div>
      <div style={{ padding: "0 16px" }}>{band}</div>
    </div>
  );
}

// ─── Frame + section ─────────────────────────────────────────────────

function Frame({ children, pad }: { children: React.ReactNode; pad?: boolean }) {
  return (
    <div style={{ background: T.pane, border: `0.5px solid ${T.ruleSubtle}`, borderRadius: 8, padding: pad ? "6px 18px 12px 18px" : "0 16px" }}>
      {children}
    </div>
  );
}

function Section({ label, caption, children }: { label: string; caption: string; children: React.ReactNode }) {
  return (
    <div style={{ padding: "8px 40px 16px 40px" }}>
      <div className="flex items-baseline" style={{ gap: 10, marginBottom: 12 }}>
        <span className="font-mono font-semibold uppercase" style={{ color: T.amber, fontSize: 9.5, letterSpacing: "0.30em" }}>· {label}</span>
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
          · TOP BAND · foundations
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>one component · a variant per view</span>
      </div>
      <h2 className="font-display" style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 10, letterSpacing: 0 }}>
        Top Band
      </h2>
      <p className="font-display" style={{ color: T.inkMid, fontSize: 14, lineHeight: 1.6, marginTop: 12, maxWidth: 720 }}>
        Every screen's top strip is the same component with four fixed slots.
        Wordmark and TALKIE pill are invariant — same size, same position — so
        the logo / title / pill relationship is stable everywhere. A view only
        chooses its title-cluster register (mono or serif) and its
        complications. That's the variant.
      </p>
    </div>
  );
}

function NamesMarginalia() {
  const entries: [string, string][] = [
    ["Band", "the one top component. Fixed height, four slots."],
    ["Wordmark", "slot ① — invariant logo, locked size + position."],
    ["Title cluster", "slot ② — the variant. Mono (instrument) or serif (reading) + optional chrome."],
    ["TALKIE", "slot ③ — invariant, always centered."],
    ["Complications", "slot ④ — per-view tools: search, view toggle, status, actions."],
    ["Variant", "the (title register + complications) a view selects. Everything else is fixed."],
  ];
  return (
    <div style={{ padding: "8px 40px 28px 40px" }}>
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
