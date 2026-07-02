"use client";

/**
 * iOS · Home Layout — a better starting point for the iPhone home.
 *
 * Brief (from the field): the shipped home "feels too wide and too
 * squished at the same time," carries "a lot of empty space," and the
 * top row ("0 MEMOS TODAY · 0 DICTATIONS T… · 0 ITEMS TODAY") is "too
 * many words." All three symptoms share one root: bands that bleed
 * edge-to-edge with cramped content, a stat strip that repeats the
 * period three times, and a zero-state that wasn't designed on purpose.
 *
 * The screenshot is the EMPTY / first-run state, so this study shows
 * the redesign empty AND populated — the layout has to look right
 * before there's any content, then scale once the feed fills.
 *
 * Rendered in Scope (the cream default) to match the device.
 *
 * Port target: apps/ios/Talkie iOS/Views/Next/HomeNextView.swift
 */

const C = {
  canvas: "var(--theme-canvas)",
  paper: "var(--theme-paper)",
  paperAlt: "var(--theme-canvas-alt)",
  ink: "var(--theme-ink)",
  inkDim: "var(--theme-ink-dim)",
  inkMuted: "var(--theme-ink-muted)",
  inkFaint: "var(--theme-ink-faint)",
  inkSubtle: "var(--theme-ink-subtle)",
  amber: "var(--theme-amber)",
  amberFaint: "var(--theme-amber-faint)",
  edge: "var(--theme-edge-faint)",
  edgeSub: "var(--theme-edge-subtle)",
  mono: "var(--theme-font-mono)",
  body: "var(--theme-font-body)",
  serif: "var(--theme-font-display)",
};

const CARD_SHADOW =
  "var(--theme-card-shadow-strong, 0 1px 0 rgba(255,255,255,0.5), 0 4px 12px -6px rgba(20,16,12,0.10))";

type Source = "dictation" | "typed" | "link" | "scan";

const RECENT: Array<{ source: Source; title: string; time: string }> = [
  { source: "dictation", title: "Scope dashboard design notes", time: "9:34" },
  { source: "dictation", title: "Meeting notes — product roadmap", time: "7:34" },
  { source: "typed", title: "Conference bio", time: "Yest" },
  { source: "link", title: "Keyboard configurator reference", time: "Yest" },
  { source: "scan", title: "Whiteboard — Q3 plan", time: "Mon" },
];

const QUICK: Array<{ label: string; icon: GlyphName }> = [
  { label: "RECORD", icon: "wave" },
  { label: "COMPOSE", icon: "pencil" },
  { label: "SCAN", icon: "camera" },
  { label: "ASK AI", icon: "spark" },
];

// As-shipped grab-bag (for the "Current" contrast): setup + nav +
// power features all flattened into one strip.
const EXPLORE: Array<{ label: string; icon: GlyphName }> = [
  { label: "Pair Mac", icon: "qr" },
  { label: "Library", icon: "books" },
  { label: "Workflows", icon: "flow" },
  { label: "Terminal", icon: "term" },
];

// Solidified rail: the Mac-bridge slot (Pair Mac → Deck) plus the two
// destinations worth a permanent tap. Library lives behind "ALL ›";
// keyboard activation lives in Settings.
const CURATED_EXPLORE: Array<{ label: string; icon: GlyphName }> = [
  { label: "Pair Mac", icon: "qr" },
  { label: "Workflows", icon: "flow" },
  { label: "Terminal", icon: "term" },
];

// ───────────────────────────────────────────────────────────── study

export function IOSHomeLayout() {
  return (
    <div className="flex flex-col gap-12">
      <Group
        heading="First run · empty"
        sub="The Today row drops out on a quiet day, Quick becomes a 2×2 hero, and the Explore rail keeps its chip treatment but is curated down to what's worth a tap: the Mac-bridge slot, Workflows, and Terminal."
      >
        <Phone label="Current" caption="as shipped" tone="muted">
          <CurrentHome populated={false} />
        </Phone>
        <Phone
          label="Redesign · Quiet"
          caption="no Today row · Quick is the hero"
          tone="accent"
        >
          <QuietHome populated={false} />
        </Phone>
      </Group>

      <Group
        heading="Active day · populated"
        sub="Once there's activity, the Today row appears as one glanceable numerals line (period named once, no repeated words), Quick goes compact 1×4, and the recent list owns the screen."
      >
        <Phone label="Current" caption="as shipped" tone="muted">
          <CurrentHome populated={true} />
        </Phone>
        <Phone
          label="Redesign · Quiet"
          caption="Today numerals line + compact Quick + recent list"
          tone="accent"
        >
          <QuietHome populated={true} />
        </Phone>
      </Group>

      <ReviewNotes />
    </div>
  );
}

// ───────────────────────────────────────────────────────── current

/** Faithful recreation of the shipped HomeNextView — for honest contrast. */
function CurrentHome({ populated }: { populated: boolean }) {
  const stats = populated
    ? [
        { n: 3, label: "MEMOS TODAY", icon: "wave" as GlyphName },
        { n: 1, label: "DICTATIONS TODAY", icon: "keyboard" as GlyphName },
        { n: 2, label: "ITEMS TODAY", icon: "tray" as GlyphName },
      ]
    : [
        { n: 0, label: "MEMOS TODAY", icon: "wave" as GlyphName },
        { n: 0, label: "DICTATIONS TODAY", icon: "keyboard" as GlyphName },
        { n: 0, label: "ITEMS TODAY", icon: "tray" as GlyphName },
      ];

  return (
    <Screen>
      <Header />
      <main className="flex min-h-0 flex-1 flex-col gap-3 px-3 pt-1">
        {/* Today strip — full-bleed 3-cell, the word TODAY ×3, truncates. */}
        <div
          className="flex h-[42px] items-stretch overflow-hidden rounded-[10px]"
          style={{ background: C.paper, border: `0.5px solid ${C.edge}` }}
        >
          {stats.map((s, i) => (
            <div
              key={s.label}
              className="flex flex-1 items-center justify-center gap-1.5 px-2"
              style={
                i < 2 ? { borderRight: `0.5px solid ${C.edge}` } : undefined
              }
            >
              <span style={{ color: C.amber }}>
                <Glyph name={s.icon} size={11} />
              </span>
              <span
                className="truncate"
                style={{
                  color: C.inkMuted,
                  fontFamily: C.mono,
                  fontSize: 9.5,
                  fontWeight: 600,
                  letterSpacing: "0.08em",
                }}
              >
                {s.n} {s.label}
              </span>
            </div>
          ))}
        </div>

        <Eyebrow>Quick</Eyebrow>
        <QuickRow />

        <div className="flex items-center gap-2 px-1">
          <span
            style={{
              color: C.amber,
              fontFamily: C.mono,
              fontSize: 10,
              fontWeight: 600,
              letterSpacing: "0.22em",
            }}
          >
            · RECENT · {populated ? RECENT.length : 0}
          </span>
          <span
            className="ml-auto"
            style={{
              color: C.inkFaint,
              fontFamily: C.mono,
              fontSize: 10,
              letterSpacing: "0.18em",
            }}
          >
            ALL ›
          </span>
        </div>

        {populated ? (
          <Card pad={false}>
            {RECENT.map((r, i) => (
              <RecentRow key={r.title} row={r} divider={i > 0} />
            ))}
          </Card>
        ) : (
          <Card pad>
            <div className="flex flex-col items-center gap-2 py-10">
              <span style={{ color: C.inkFaint }}>
                <Glyph name="tray" size={26} />
              </span>
              <span
                style={{
                  color: C.inkMuted,
                  fontFamily: C.mono,
                  fontSize: 10,
                  fontWeight: 600,
                  letterSpacing: "0.2em",
                }}
              >
                · NOTHING RECENT
              </span>
              <span
                className="px-6 text-center"
                style={{ color: C.inkFaint, fontFamily: C.body, fontSize: 14 }}
              >
                Record, dictate, compose, or scan to start your feed.
              </span>
            </div>
          </Card>
        )}

        <Eyebrow>Explore</Eyebrow>
        <ExploreChips />
        <div className="flex-1" />
      </main>
      <BottomBar />
    </Screen>
  );
}

// ───────────────────────────────────────────────── redesign · quiet

/**
 * Quiet — minimal-intervention fix that keeps the same bands:
 *  · Today collapses to ONE line. Period stated once; numerals (no
 *    repeated words) when populated, a calm "nothing yet" when empty.
 *  · Quick becomes the hero of the empty state (2×2, real presence),
 *    and a compact 1×4 once the list needs the room.
 *  · The empty Recent card is small and intentional, not a void.
 *  · Consistent 16px margins so nothing reads as edge-to-edge.
 */
function QuietHome({ populated }: { populated: boolean }) {
  return (
    <Screen>
      <Header />
      <main className="flex min-h-0 flex-1 flex-col gap-[18px] px-4 pt-2 pb-1">
        {/* Today drops out on a quiet day — it only earns space when
            there's something to count. */}
        {populated && <TodayLine />}

        <Section label="Quick">
          {populated ? <QuickRow /> : <QuickGrid />}
        </Section>

        <Section
          label="Recent"
          count={populated ? RECENT.length : undefined}
          trailing="ALL ›"
        >
          {populated ? (
            <Card pad={false}>
              {RECENT.map((r, i) => (
                <RecentRow key={r.title} row={r} divider={i > 0} />
              ))}
            </Card>
          ) : (
            <EmptyRecent />
          )}
        </Section>

        {/* Same chip treatment, curated contents: the Mac-bridge slot
            (Pair Mac → Deck) plus the two destinations worth a tap —
            Workflows and Terminal. Library lives behind "ALL ›". */}
        {!populated && (
          <Section label="Explore">
            <ExploreChips items={CURATED_EXPLORE} />
          </Section>
        )}

        <div className="flex-1" />
      </main>
      <BottomBar />
    </Screen>
  );
}

/** One quiet line, shown only on active days. Period named once; the
 *  numerals (icon + count) carry the value — no per-cell "TODAY". */
function TodayLine() {
  return (
    <div className="flex items-center gap-3 px-1">
      <span
        style={{
          color: C.inkFaint,
          fontFamily: C.mono,
          fontSize: 10,
          fontWeight: 600,
          letterSpacing: "0.24em",
        }}
      >
        · TODAY
      </span>
      <div className="ml-auto flex items-center gap-3.5">
        <NumStat icon="wave" n={3} />
        <NumStat icon="keyboard" n={1} />
        <NumStat icon="tray" n={2} />
      </div>
    </div>
  );
}

function NumStat({ icon, n }: { icon: GlyphName; n: number }) {
  return (
    <span className="flex items-center gap-1.5">
      <span style={{ color: C.amber }}>
        <Glyph name={icon} size={12} />
      </span>
      <span
        className="tabular-nums"
        style={{
          color: C.ink,
          fontFamily: C.serif,
          fontWeight: 500,
          fontSize: 17,
          lineHeight: 1,
        }}
      >
        {n}
      </span>
    </span>
  );
}

/** 2×2 grid — gives the primary verbs presence when the feed is empty. */
function QuickGrid() {
  return (
    <div
      className="grid grid-cols-2 overflow-hidden rounded-[12px]"
      style={{ background: C.paper, border: `0.5px solid ${C.edge}`, boxShadow: CARD_SHADOW }}
    >
      {QUICK.map((q, i) => (
        <button
          key={q.label}
          className="flex flex-col items-center justify-center gap-2"
          style={{
            height: 76,
            borderRight: i % 2 === 0 ? `0.5px solid ${C.edge}` : undefined,
            borderBottom: i < 2 ? `0.5px solid ${C.edge}` : undefined,
          }}
        >
          <span style={{ color: C.amber }}>
            <Glyph name={q.icon} size={20} />
          </span>
          <span
            style={{
              color: C.inkMuted,
              fontFamily: C.mono,
              fontSize: 11,
              fontWeight: 600,
              letterSpacing: "0.16em",
            }}
          >
            {q.label}
          </span>
        </button>
      ))}
    </div>
  );
}

function EmptyRecent() {
  return (
    <Card pad>
      <div className="flex flex-col items-center gap-2 py-7">
        <span style={{ color: C.inkSubtle }}>
          <Glyph name="tray" size={22} />
        </span>
        <span
          style={{
            color: C.inkMuted,
            fontFamily: C.body,
            fontSize: 14,
          }}
        >
          Nothing here yet
        </span>
        <span
          className="px-6 text-center"
          style={{ color: C.inkSubtle, fontFamily: C.body, fontSize: 12.5 }}
        >
          Captures land here as you go.
        </span>
      </div>
    </Card>
  );
}

// ─────────────────────────────────────────────── shared components

function Screen({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col" style={{ background: C.canvas }}>
      <StatusBarRow />
      {children}
    </div>
  );
}

function StatusBarRow() {
  return (
    <div
      className="relative flex items-center justify-between px-5 pt-2.5 pb-1.5"
      style={{ color: C.ink, fontFamily: "-apple-system, sans-serif", height: 38 }}
    >
      <span className="text-[12px] font-semibold">5:41</span>
      <span
        className="absolute left-1/2 top-2 -translate-x-1/2 rounded-[14px]"
        style={{ width: 88, height: 22, background: "#000" }}
      />
      <span className="flex items-center gap-1.5">
        <span className="inline-flex items-end gap-[1.5px]" style={{ height: 10 }}>
          {[3, 5, 7, 10].map((h, i) => (
            <i key={i} className="block w-[2.5px] rounded-[0.5px]" style={{ height: h, background: C.ink }} />
          ))}
        </span>
        <svg width={13} height={9} viewBox="0 0 16 11" fill="none" style={{ color: C.ink }}>
          <path d="M8 9.5a.9.9 0 100-1.8.9.9 0 000 1.8zM4 6.2a5.5 5.5 0 018 0M2 4a8.5 8.5 0 0112 0" stroke="currentColor" strokeWidth={1.1} strokeLinecap="round" />
        </svg>
        <span className="relative inline-block rounded-[3px] p-[1.5px]" style={{ width: 22, height: 11, border: `1px solid ${C.ink}` }}>
          <span className="block h-full rounded-[1px]" style={{ width: "82%", background: C.ink }} />
        </span>
      </span>
    </div>
  );
}

function Header() {
  return (
    <div className="flex items-center justify-between" style={{ padding: "4px 16px 6px" }}>
      <ChromeCircle>
        <Glyph name="deck" size={15} />
      </ChromeCircle>
      <span
        style={{
          color: C.ink,
          fontFamily: C.mono,
          fontWeight: 700,
          fontSize: 13,
          letterSpacing: "0.28em",
        }}
      >
        TALKIE
      </span>
      <ChromeCircle>
        <Glyph name="gear" size={15} />
      </ChromeCircle>
    </div>
  );
}

function ChromeCircle({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="flex items-center justify-center rounded-full"
      style={{
        width: 36,
        height: 36,
        background: C.paper,
        border: `0.5px solid ${C.edge}`,
        color: C.inkMuted,
        boxShadow: "0 2px 5px -2px rgba(20,16,12,0.18)",
      }}
    >
      {children}
    </span>
  );
}

function BottomBar() {
  return (
    <div className="relative flex items-end justify-center pb-6 pt-2">
      <span
        className="absolute bottom-7 left-6 flex items-center justify-center rounded-full"
        style={{
          width: 48,
          height: 48,
          background: C.paper,
          border: `0.5px solid ${C.edge}`,
          color: C.inkMuted,
          boxShadow: "0 2px 6px -2px rgba(20,16,12,0.16)",
        }}
      >
        <Glyph name="ambient" size={18} />
      </span>
      <span
        className="flex items-center justify-center rounded-full"
        style={{ width: 64, height: 64, background: C.amber, color: C.paper }}
      >
        <Glyph name="mic" size={26} />
      </span>
    </div>
  );
}

function Section({
  label,
  count,
  trailing,
  children,
}: {
  label: string;
  count?: number;
  trailing?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-2">
      <div className="flex items-center gap-2 px-1">
        <Eyebrow accent={label === "Recent"}>
          {label}
          {count !== undefined ? ` · ${count}` : ""}
        </Eyebrow>
        {trailing ? (
          <span
            className="ml-auto"
            style={{
              color: C.inkFaint,
              fontFamily: C.mono,
              fontSize: 10,
              letterSpacing: "0.18em",
            }}
          >
            {trailing}
          </span>
        ) : null}
      </div>
      {children}
    </section>
  );
}

function Eyebrow({ children, accent }: { children: React.ReactNode; accent?: boolean }) {
  return (
    <span
      style={{
        color: accent ? C.amber : C.inkFaint,
        fontFamily: C.mono,
        fontSize: 10,
        fontWeight: 600,
        letterSpacing: "0.24em",
        textTransform: "uppercase",
      }}
    >
      · {children}
    </span>
  );
}

function Card({ children, pad }: { children: React.ReactNode; pad: boolean }) {
  return (
    <div
      className={`overflow-hidden rounded-[12px] ${pad ? "" : ""}`}
      style={{ background: C.paper, border: `0.5px solid ${C.edge}`, boxShadow: CARD_SHADOW }}
    >
      {children}
    </div>
  );
}

/** Compact 1×4 quick action row (used in populated + current). */
function QuickRow() {
  return (
    <div
      className="flex h-[56px] items-stretch overflow-hidden rounded-[12px]"
      style={{ background: C.paper, border: `0.5px solid ${C.edge}`, boxShadow: CARD_SHADOW }}
    >
      {QUICK.map((q, i) => (
        <button
          key={q.label}
          className="flex flex-1 flex-col items-center justify-center gap-1"
          style={i < 3 ? { borderRight: `0.5px solid ${C.edge}` } : undefined}
        >
          <span style={{ color: C.amber }}>
            <Glyph name={q.icon} size={14} />
          </span>
          <span
            style={{
              color: C.inkMuted,
              fontFamily: C.mono,
              fontSize: 9.5,
              fontWeight: 600,
              letterSpacing: "0.12em",
            }}
          >
            {q.label}
          </span>
        </button>
      ))}
    </div>
  );
}

function RecentRow({ row, divider }: { row: (typeof RECENT)[number]; divider: boolean }) {
  return (
    <div className="relative flex items-center gap-2.5 px-3.5" style={{ height: 44 }}>
      {divider ? (
        <span aria-hidden className="absolute left-11 right-0 top-0 h-px" style={{ background: C.edgeSub }} />
      ) : null}
      <span className="flex h-4 w-4 flex-none items-center justify-center" style={{ color: C.inkFaint }}>
        <Glyph name={sourceGlyph(row.source)} size={14} />
      </span>
      <span
        className="min-w-0 flex-1 truncate"
        style={{ color: C.ink, fontFamily: C.body, fontSize: 15 }}
      >
        {row.title}
      </span>
      <span
        className="flex-none tabular-nums"
        style={{ color: C.inkFaint, fontFamily: C.mono, fontSize: 11 }}
      >
        {row.time}
      </span>
    </div>
  );
}

function ExploreChips({ items = EXPLORE }: { items?: typeof EXPLORE }) {
  return (
    <div className="flex gap-2 overflow-hidden px-1">
      {items.map((c) => (
        <span
          key={c.label}
          className="flex flex-none items-center gap-1.5 rounded-full px-3 py-2"
          style={{ background: C.paper, border: `0.5px solid ${C.edge}` }}
        >
          <span style={{ color: C.amber }}>
            <Glyph name={c.icon} size={12} />
          </span>
          <span style={{ color: C.inkMuted, fontFamily: C.body, fontSize: 13 }}>{c.label}</span>
        </span>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────── study chrome

function Group({
  heading,
  sub,
  children,
}: {
  heading: string;
  sub: string;
  children: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <h2 className="m-0 text-[12px] font-semibold uppercase tracking-eyebrow text-studio-ink">
          · {heading}
        </h2>
        <p className="m-0 max-w-2xl text-[12px] leading-snug text-studio-ink-muted">{sub}</p>
      </div>
      <div className="flex flex-wrap items-start gap-8">{children}</div>
    </section>
  );
}

const FRAME_STYLE: React.CSSProperties = {
  width: "340px",
  aspectRatio: "9 / 19.5",
  background: "#0a0a0a",
  borderRadius: "40px",
  padding: "7px",
  boxShadow:
    "0 0 0 1px rgba(0,0,0,0.2), 0 14px 36px -10px rgba(20,16,12,0.22), 0 30px 80px -20px rgba(20,16,12,0.10)",
  position: "relative",
  flex: "0 0 auto",
};
const SCREEN_STYLE: React.CSSProperties = {
  width: "100%",
  height: "100%",
  borderRadius: "33px",
  overflow: "hidden",
  position: "relative",
};
const NOTCH_STYLE: React.CSSProperties = {
  position: "absolute",
  top: "13px",
  left: "50%",
  transform: "translateX(-50%)",
  width: "88px",
  height: "22px",
  background: "#000",
  borderRadius: "999px",
  zIndex: 2,
};

function Phone({
  label,
  caption,
  tone,
  children,
}: {
  label: string;
  caption: string;
  tone: "accent" | "muted";
  children: React.ReactNode;
}) {
  return (
    <div data-theme="scope" className="flex flex-col gap-3">
      <div className="flex items-baseline gap-2 pl-1">
        <span
          className={`text-[11px] font-semibold uppercase tracking-eyebrow ${
            tone === "accent" ? "text-studio-amber" : "text-studio-ink"
          }`}
        >
          {label}
        </span>
        <span className="text-[11px] text-studio-ink-faint">{caption}</span>
      </div>
      <div style={FRAME_STYLE}>
        <div style={NOTCH_STYLE} />
        <div style={SCREEN_STYLE}>{children}</div>
      </div>
    </div>
  );
}

function ReviewNotes() {
  const notes: [string, string][] = [
    [
      "Today drops when low",
      "On a quiet day the Today row is gone entirely — no zeros to read. It only appears once there’s something to count, as one numerals line (· TODAY 〰3 ⌨1 ▦2): period named once, no repeated words, no truncation.",
    ],
    [
      "Empty is a design, not an absence",
      "With Today gone, Quick becomes a 2×2 hero so the first-run screen has a deliberate center of gravity instead of three zeros and a dead bottom third.",
    ],
    [
      "Consistent 16pt margins",
      "Every band shares one inset. Cards stop reading as edge-to-edge, and the inner content gets room — fixing both “too wide” and “too squished.”",
    ],
    [
      "One skeleton, two states",
      "(Today) → Quick → Recent → (Next) holds empty and full. Quick is 2×2 when the feed is empty, 1×4 once the list needs the screen.",
    ],
    [
      "Explore, solidified",
      "Same chip treatment, curated contents. The rail is the Mac-bridge slot (Pair Mac → Deck) plus the two destinations worth a permanent tap — Workflows and Terminal. Library lives behind “ALL ›”; keyboard activation lives in Settings.",
    ],
    [
      "Breathe between sections",
      "18pt between bands (was 12), eyebrows still hug their cards at 8pt. Clear grouping without feeling sparse — fixes the “a little squished” read.",
    ],
  ];
  return (
    <section className="max-w-4xl">
      <h2 className="mb-3 text-[11px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        · Review
      </h2>
      <dl className="grid grid-cols-1 gap-x-8 gap-y-3 sm:grid-cols-2">
        {notes.map(([name, desc]) => (
          <div key={name} className="flex flex-col gap-1">
            <dt className="text-[12px] font-medium text-studio-ink">{name}</dt>
            <dd className="text-[12px] leading-snug text-studio-ink-muted">{desc}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

// ───────────────────────────────────────────────────────── glyphs

type GlyphName =
  | "deck"
  | "gear"
  | "wave"
  | "keyboard"
  | "pencil"
  | "camera"
  | "spark"
  | "tray"
  | "qr"
  | "books"
  | "flow"
  | "term"
  | "mic"
  | "ambient"
  | "link"
  | "scan";

function sourceGlyph(s: Source): GlyphName {
  switch (s) {
    case "dictation":
      return "wave";
    case "typed":
      return "keyboard";
    case "link":
      return "link";
    case "scan":
      return "scan";
  }
}

function Glyph({ name, size }: { name: GlyphName; size: number }) {
  const p = { stroke: "currentColor", strokeLinecap: "round" as const, strokeLinejoin: "round" as const, fill: "none" };
  switch (name) {
    case "deck":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g fill="currentColor">
            {[3, 8, 13].map((x) =>
              [3, 8, 13].map((y) => <circle key={`${x}-${y}`} cx={x} cy={y} r={1.1} />)
            )}
          </g>
        </svg>
      );
    case "gear":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <circle cx={8} cy={8} r={2} strokeWidth={1} {...p} />
          <path
            d="M8 1.5 8 3.3M8 12.7 8 14.5M1.5 8 3.3 8M12.7 8 14.5 8M3.2 3.2 4.5 4.5M11.5 11.5 12.8 12.8M3.2 12.8 4.5 11.5M11.5 4.5 12.8 3.2"
            strokeWidth={1}
            {...p}
          />
        </svg>
      );
    case "wave":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.1} {...p}>
            <line x1={2} y1={8} x2={2} y2={8} />
            <line x1={4.4} y1={6} x2={4.4} y2={10} />
            <line x1={6.8} y1={3} x2={6.8} y2={13} />
            <line x1={9.2} y1={5} x2={9.2} y2={11} />
            <line x1={11.6} y1={2.5} x2={11.6} y2={13.5} />
            <line x1={14} y1={6.5} x2={14} y2={9.5} />
          </g>
        </svg>
      );
    case "keyboard":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <rect x={1.7} y={4.3} width={12.6} height={7.4} rx={1.2} strokeWidth={0.95} {...p} />
          <g strokeWidth={0.85} {...p}>
            <line x1={4} y1={7} x2={4.2} y2={7} />
            <line x1={6.7} y1={7} x2={6.9} y2={7} />
            <line x1={9.4} y1={7} x2={9.6} y2={7} />
            <line x1={12} y1={7} x2={12.2} y2={7} />
            <line x1={4.6} y1={9.5} x2={11.4} y2={9.5} />
          </g>
        </svg>
      );
    case "pencil":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.05} {...p}>
            <path d="M9.5 3.2 12.8 6.5 6 13.3 2.7 13.3 2.7 10z" />
            <line x1={8.3} y1={4.4} x2={11.6} y2={7.7} />
          </g>
        </svg>
      );
    case "camera":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.05} {...p}>
            <path d="M2.3 5.5h2l1-1.4h5.4l1 1.4h1a1 1 0 0 1 1 1V11a1 1 0 0 1-1 1H2.3a1 1 0 0 1-1-1V6.5a1 1 0 0 1 1-1z" />
            <circle cx={8} cy={8.4} r={2.2} />
          </g>
        </svg>
      );
    case "spark":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.05} {...p}>
            <path d="M9 2.5c0 2 .8 2.8 2.8 2.8-2 0-2.8.8-2.8 2.8 0-2-.8-2.8-2.8-2.8 2 0 2.8-.8 2.8-2.8z" />
            <path d="M4.6 8.8c0 1.4.6 2 2 2-1.4 0-2 .6-2 2 0-1.4-.6-2-2-2 1.4 0 2-.6 2-2z" />
          </g>
        </svg>
      );
    case "tray":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.05} {...p}>
            <path d="M2 9.5 4 4.2h8L14 9.5v2.3a.8.8 0 0 1-.8.8H2.8a.8.8 0 0 1-.8-.8z" />
            <path d="M2 9.5h3.3l.9 1.4h3.6l.9-1.4H14" />
          </g>
        </svg>
      );
    case "qr":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1} {...p}>
            <path d="M3 5.2V3.2h2M11 3.2h2v2M13 10.8v2h-2M5 12.8H3v-2" />
          </g>
          <g fill="currentColor">
            <rect x={6} y={6} width={2} height={2} />
            <rect x={8.4} y={8.4} width={1.6} height={1.6} />
          </g>
        </svg>
      );
    case "books":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.05} {...p}>
            <rect x={2.6} y={3.5} width={2.6} height={9} rx={0.5} />
            <rect x={6.4} y={3.5} width={2.6} height={9} rx={0.5} />
            <path d="M10.4 4.2 12.9 3.6 13.9 12.3 11.4 12.9z" />
          </g>
        </svg>
      );
    case "flow":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.05} {...p}>
            <line x1={4} y1={4} x2={11} y2={4} />
            <line x1={5} y1={8} x2={12} y2={8} />
            <line x1={4} y1={12} x2={11} y2={12} />
          </g>
          <g fill="currentColor">
            <circle cx={3} cy={4} r={1.4} />
            <circle cx={13} cy={8} r={1.4} />
            <circle cx={3} cy={12} r={1.4} />
          </g>
        </svg>
      );
    case "term":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <rect x={2} y={3.2} width={12} height={9.6} rx={1.4} strokeWidth={1} {...p} />
          <path d="M4.6 6.4 6.6 8 4.6 9.6M8 9.8h3" strokeWidth={1} {...p} />
        </svg>
      );
    case "mic":
      return (
        <svg viewBox="0 0 32 32" width={size} height={size}>
          <g strokeWidth={2.1} {...p}>
            <rect x={11} y={4} width={10} height={17} rx={5} />
            <path d="M7 15a9 9 0 0 0 18 0" />
            <path d="M16 24v4M11 28h10" />
          </g>
        </svg>
      );
    case "ambient":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={1.1} {...p}>
            <path d="M4 4a5 5 0 0 0 0 8" />
            <path d="M12 4a5 5 0 0 1 0 8" />
            <path d="M6 6a2.5 2.5 0 0 0 0 4" />
            <path d="M10 6a2.5 2.5 0 0 1 0 4" />
          </g>
          <circle cx={8} cy={8} r={1.3} fill="currentColor" />
        </svg>
      );
    case "link":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <path
            d="M6 9 10 5M5.2 8.5a2.2 2.2 0 0 1 0-3.1l1.2-1.2a2.2 2.2 0 0 1 3.1 3.1l-.5.5M9.8 6.5a2.2 2.2 0 0 1 0 3.1l-1.2 1.2a2.2 2.2 0 0 1-3.1-3.1l.5-.5"
            strokeWidth={0.95}
            {...p}
          />
        </svg>
      );
    case "scan":
      return (
        <svg viewBox="0 0 16 16" width={size} height={size}>
          <g strokeWidth={0.95} {...p}>
            <path d="M3 5V3h2M11 3h2v2M3 11v2h2M11 13h2v-2" />
            <line x1={3} y1={8} x2={13} y2={8} />
          </g>
        </svg>
      );
  }
}
