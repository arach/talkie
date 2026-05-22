"use client";

/**
 * Mac Memo Detail — the right-hand pane of the Library split view.
 *
 * The shipping pane (see screenshot in /tmp/talkie-home.png) reads as a
 * dashboard crashed into a content header: three metric pills, a four-
 * column metadata grid, a wall of mono transcript, a utilitarian player.
 * Nothing on the page tells your eye where to land.
 *
 * This study reframes the pane as **a sheet of paper opened on a desk**.
 * Editorial masthead at the top — eyebrow / serif headline / one factual
 * byline. The transcript becomes a real document: lead paragraph at a
 * larger size, comfortable measure, paragraph breaks. A thin marginal
 * rule on the left, like the gutter of a printed page. The player rail
 * sits at the foot of the document like a typesetter's bar — present
 * but not loud.
 *
 * Scope-first. The whole composition lives on the studio's cream canvas
 * (no scheme vars). A future v2 can layer the scheme picker.
 *
 * See `app/mac-memo-detail/NOTES.md` for the decision log.
 */

// ──────────────────────────────────────────────────────────────────────
// Stub content — Talkie-flavored. A memo dictated while debugging a bay
// scheme rebuild, with realistic asides and self-correction. Mono-blob-
// in / paragraph-out is the editorial work we want the design to do.

const MEMO = {
  // Eyebrow line — channel + date stamp + sequence.
  channel: "CH-02 · DICTATION",
  date: "Today",
  time: "10:58 AM",
  sequence: "M-0421",
  // Derived headline. Talkie pulls this from the first salient noun
  // phrase, falling back to the timestamp. Here, hand-authored.
  title: "Re-grounding the bay against the chiffon canvas",
  // Single editorial byline that replaces the four-column grid.
  // Order: provenance, duration, words, device, model.
  byline: {
    provenance: "iTerm2",
    duration: "6:14",
    words: 412,
    device: "MacBook Pro",
    model: "Parakeet v3",
  },
  // Transcript as paragraphs — what the procedural processor would
  // emit when given chunked recording. Three paragraphs is enough to
  // show rhythm without overwhelming the page.
  paragraphs: [
    "Okay, so the chiffon scheme is closer than I thought. The problem isn't the scheme, it's that I was reading the bay against the wrong floor. Once I dropped it onto the cream studio canvas instead of pure white, the brass amber stopped fighting and started reading like a real instrument bay. The bay wants to sit on warm paper. That's the whole insight.",
    "Next thing — the system status rail. Right now it follows the bay's scheme, which means when I'm in chiffon I get this very pale rail that reads as almost invisible. That might be correct, actually. The rail is health information, not feature surface. If it disappears into the page when everything's green, that's exactly what I want. We only need it loud when something's wrong.",
    "One thing I want to come back to — the ownership strip at the bottom. Three columns, your devices, your iCloud, external models. The copy is fine but the visual weight is wrong. It's the most editorial line on the page right now and I think that's punching above its station. Let me look at whether it needs to be smaller, or whether it actually deserves to be the page's closing chord.",
  ],
};

// Right-margin metadata — the editorial caption. Useful-but-not-core
// technical data, grouped and beautifully typeset. Replaces the
// dashboard-style four-column textProvenance card the redesign was
// moving away from. Real fields are sourced from DictationMetadata
// (transcriptionModel, language, confidence, perfEngineMs, perfEndToEndMs,
// perfInAppMs, peakAmplitude, averageAmplitude, audioFilename, plus
// activeAppName / terminalWorkingDir for context).
const METADATA: {
  title: string;
  rows: { label: string; value: string; accent?: boolean }[];
}[] = [
  {
    title: "Transcription",
    rows: [
      { label: "model", value: "Parakeet v3", accent: true },
      { label: "confidence", value: "94.2%" },
    ],
  },
  {
    title: "Timing",
    rows: [
      { label: "end-to-end", value: "1.34 s" },
      { label: "in-app", value: "528 ms" },
    ],
  },
];

// Player rail — waveform peaks, timecode, scrubber. Static composition.
// 56 columns chosen so the bars read as a transcript rhythm strip, not
// a hi-fi visualization.
const WAVEFORM_PEAKS = [
  4, 6, 9, 12, 8, 14, 11, 7, 5, 9, 13, 16, 12, 10, 15, 18, 14, 11, 8, 6,
  10, 13, 9, 7, 11, 14, 17, 13, 10, 8, 12, 15, 11, 9, 6, 8, 11, 14, 10,
  7, 5, 9, 12, 15, 11, 8, 6, 4, 7, 10, 13, 9, 6, 8, 11, 7,
];

// ──────────────────────────────────────────────────────────────────────
// Composition root.

import { IconRail } from "./primitives/IconRail";

export function MacMemoDetail({
  empty = false,
  withRail = false,
}: {
  empty?: boolean;
  withRail?: boolean;
} = {}) {
  return (
    <div className="mx-auto flex flex-col items-center gap-6">
      {/* Context strip — a faint reminder of the left list edge so the
          panel reads as "the right pane in context", not floating in a
          void. Renders a single hairline list row at the left edge of
          the artifact, suggesting the split. Studio-only affordance.
          With `withRail`, the 52pt icon-rail prepends the gutter so we
          can see what the detail pane looks like with persistent nav. */}
      <PaneFrame nothingSelected={empty} withRail={withRail}>
        {empty ? <EmptyDetailPane /> : <DetailPane />}
      </PaneFrame>

      <Footnote />
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Pane frame — the studio's window-chrome wrapper. Renders a hint of
// the library list on the left (compressed to a thin gutter) and the
// detail pane on the right at realistic split-view proportions. When
// `withRail` is true, prepends the 52pt icon-rail so the three-pane
// shape (nav rail + list + detail) reads as the real shipping chrome.

function PaneFrame({
  children,
  nothingSelected = false,
  withRail = false,
}: {
  children: React.ReactNode;
  nothingSelected?: boolean;
  withRail?: boolean;
}) {
  return (
    <div
      className="rounded-md overflow-hidden"
      style={{
        width: "1180px",
        background: "#F8F8F7",
        boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
        border: "0.5px solid #DEDEDD",
      }}
    >
      <WindowChrome />
      <div className="flex" style={{ minHeight: "780px" }}>
        {withRail && <IconRail selected="library" minHeight={780} />}
        <LibraryListGutter nothingSelected={nothingSelected} />
        <div className="flex-1" style={{ background: "#F1F1F0" }}>
          {children}
        </div>
      </div>
    </div>
  );
}

// macOS traffic-light row + window title. Faint, so the artifact reads
// as embedded chrome, not the focal point.

function WindowChrome() {
  return (
    <div
      className="flex items-center gap-2 border-b px-4 py-2.5"
      style={{ borderColor: "#DEDEDD", background: "#E7E7E6" }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
      </div>
      <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
        Talkie · Library
      </div>
      <div className="ml-auto" />
    </div>
  );
}

// Library list gutter — compressed hint of the list pane. Real Library
// row design lives in `components/studies/Library.tsx`; here we just
// indicate "there's a list on the left, this is the right side".

export function LibraryListGutter({ nothingSelected = false }: { nothingSelected?: boolean }) {
  const ROWS = [
    { title: "Hey, anything?", time: "10:58", current: false },
    { title: "Okay, do you want to switch?", time: "10:42", current: false },
    { title: "Re-grounding the bay against…", time: "10:38", current: !nothingSelected },
    { title: "And then maybe separately…", time: "10:14", current: false },
    { title: "yes, please feel free to drift…", time: "9:51", current: false },
    { title: "That sounds good. Let's do it.", time: "9:34", current: false },
    { title: "All right, let's wire the home…", time: "9:18", current: false },
    { title: "Awesome, any results?", time: "9:04", current: false },
  ];
  return (
    <div
      className="flex flex-col border-r"
      style={{ width: "300px", background: "#F8F8F7", borderColor: "#DEDEDD" }}
    >
      <div
        className="flex items-center gap-2 border-b px-4 py-3"
        style={{ borderColor: "#DEDEDD" }}
      >
        <div className="font-display text-[15px] font-medium tracking-tight text-studio-ink">
          Library
        </div>
        <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          436 · 7D
        </div>
      </div>
      <div className="px-3 py-2">
        <div
          className="flex items-center gap-2 rounded-[3px] border px-2.5 py-1.5"
          style={{ borderColor: "#DEDEDD", background: "#FFFFFF" }}
        >
          <span className="font-mono text-[10px] text-studio-ink-faint">⌕</span>
          <span className="text-[11px] text-studio-ink-faint">Search the library…</span>
        </div>
      </div>
      <div className="flex flex-col">
        {ROWS.map((r, i) => (
          <div
            key={i}
            className="flex items-baseline gap-3 border-b px-4 py-2.5 last:border-b-0"
            style={{
              borderColor: "#DEDEDD",
              background: r.current ? "#EAEAE9" : "transparent",
            }}
          >
            <span
              className="font-mono text-[8px] uppercase tracking-[0.20em]"
              style={{ color: r.current ? "#9A6A22" : "#A4A4A6" }}
            >
              D
            </span>
            <span
              className="flex-1 truncate text-[12px]"
              style={{
                color: r.current ? "#232423" : "#5A554C",
                fontWeight: r.current ? 500 : 400,
              }}
            >
              {r.title}
            </span>
            <span className="font-mono text-[9px] tracking-[0.06em] text-studio-ink-faint">
              {r.time}
            </span>
          </div>
        ))}
        <div
          className="mt-2 px-4 py-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint"
          style={{ borderTop: "0.5px solid #DEDEDD" }}
        >
          · Earlier · this week
        </div>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Detail pane — the focus of this study. Sits on a warmer cream than
// the studio canvas so it reads as paper lifted from the desk.

export function DetailPane() {
  return (
    <article
      className="flex h-full flex-col"
      style={{
        // Warm chiffon paper — the same family as the canonical Scope
        // bay floor, but a touch warmer to read as "document" rather
        // than "surface".
        background:
          "linear-gradient(180deg, #F1F1F0 0%, #EFEFEE 60%, #E9E9E8 100%)",
      }}
    >
      <Toolbar />
      <Masthead />
      <Body />
      <PlayerRail />
    </article>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Empty detail pane — what the right pane shows before a memo is
// selected. The same warm paper, the same printer's-slug toolbar, but
// no masthead / body / player. A quiet centered group carries today's
// factual data (count, words, minutes) instead of a hero. No marketing
// copy — the data IS the empty state.

function EmptyDetailPane() {
  return (
    <article
      className="flex h-full flex-col"
      style={{
        background:
          "linear-gradient(180deg, #F1F1F0 0%, #EFEFEE 60%, #E9E9E8 100%)",
      }}
    >
      <EmptyToolbar />
      <div className="flex flex-1 items-center justify-center px-9">
        <EmptyCue />
      </div>
    </article>
  );
}

// Same toolbar shape so the chrome reads as continuous, but the
// sequence slot becomes a placeholder and the actions go disabled.

function EmptyToolbar() {
  return (
    <div
      className="flex items-center gap-3 px-9 py-3"
      style={{ borderBottom: "0.5px solid rgba(26,22,18,0.10)" }}
    >
      <div
        className="text-[9px] font-mono uppercase tracking-[0.22em]"
        style={{ color: "rgba(26,22,18,0.28)" }}
      >
        — — — —
      </div>
      <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        · LIBRARY
      </div>

      <div className="ml-auto flex items-center gap-1" style={{ opacity: 0.35 }}>
        <ToolButton label="Star" />
        <ToolButton label="Pin" />
        <ToolButton label="Share" />
        <ToolButton label="Export" />
        <span className="mx-2 h-3 w-px" style={{ background: "rgba(26,22,18,0.16)" }} />
        <ToolButton label="More" trailing="⋯" />
      </div>
    </div>
  );
}

// Centered editorial cue. Mono-caps eyebrow → italic serif fall-line →
// thin rule → today's factual recap → keyboard shortcut hint. Reads
// like a paper sleeve waiting for content, not an error message.

function EmptyCue() {
  return (
    <div className="flex max-w-[480px] flex-col items-center gap-6 text-center">
      <div className="text-[10px] font-mono uppercase tracking-[0.28em] text-studio-ink-faint">
        · ready · nothing selected ·
      </div>

      <div
        className="font-display text-[22px] italic leading-tight"
        style={{ color: "rgba(26,22,18,0.50)", letterSpacing: "-0.012em" }}
      >
        Select a memo to read.
      </div>

      <div
        className="h-px w-24"
        style={{ background: "rgba(154,106,34,0.32)" }}
      />

      <div className="flex items-baseline gap-3 text-[10px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
        <span>· 8 today</span>
        <span style={{ color: "rgba(26,22,18,0.22)" }}>·</span>
        <span>412 words</span>
        <span style={{ color: "rgba(26,22,18,0.22)" }}>·</span>
        <span>47 min recorded</span>
      </div>

      <div className="text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        or <span style={{ color: "#9A6A22" }}>⌃⇧⌘ D</span> to capture
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Toolbar — top-of-pane controls. Quiet, factual; lives above the
// masthead like a printer's slug line.

function Toolbar() {
  return (
    <div
      className="flex items-center gap-3 px-9 py-3"
      style={{ borderBottom: "0.5px solid rgba(26,22,18,0.10)" }}
    >
      <div className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
        {MEMO.sequence}
      </div>
      <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        · DICTATION
      </div>

      <div className="ml-auto flex items-center gap-1">
        <ToolButton label="Star" />
        <ToolButton label="Pin" />
        <ToolButton label="Share" />
        <ToolButton label="Export" />
        <span className="mx-2 h-3 w-px" style={{ background: "rgba(26,22,18,0.16)" }} />
        <ToolButton label="More" trailing="⋯" />
      </div>
    </div>
  );
}

function ToolButton({ label, trailing }: { label: string; trailing?: string }) {
  return (
    <button
      className="rounded-[3px] px-2 py-1 text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint transition-colors hover:text-studio-ink"
      style={{ letterSpacing: "0.18em" }}
    >
      {trailing ? <span className="text-[12px]">{trailing}</span> : label}
    </button>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Masthead — editorial header. Replaces the three metric pills + the
// four-column metadata grid with a single editorial composition:
//
//   eyebrow line   (channel · date · time)
//   serif headline (derived title; falls back to timestamp)
//   byline line    (provenance · duration · words · device · model)
//
// The byline reads left-to-right as a single factual sentence, with
// `·` separators. Density per character is higher than the four-column
// grid; the page weight is much lighter.

function Masthead() {
  const { provenance, duration } = MEMO.byline;
  return (
    <header className="px-9 pt-8 pb-6">
      {/* Eyebrow */}
      <div className="flex items-baseline gap-3">
        <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          · {MEMO.channel}
        </span>
        <span className="h-px flex-1" style={{ background: "rgba(26,22,18,0.12)" }} />
        <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          {MEMO.date} · {MEMO.time}
        </span>
      </div>

      {/* Serif headline. Newsreader 500 / tracking -0.018em (Scope
          display spec). Sits as the page's eye-magnet — the byline
          below carries the factual load. */}
      <h1
        className="m-0 mt-3 font-display text-[34px] font-medium leading-[1.12] tracking-tight text-studio-ink"
        style={{ letterSpacing: "-0.018em" }}
      >
        {MEMO.title}
      </h1>

      {/* Byline — just the two marquee fields the eye expects under a
          magazine standfirst: provenance and runtime. The deeper
          technical metadata (model, confidence, perf, audio) lives in
          the right margin. */}
      <div className="mt-3 flex flex-wrap items-baseline gap-x-2 gap-y-1 text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
        <span className="text-studio-ink">{provenance}</span>
        <Sep />
        <span className="text-studio-ink">{duration}</span>
      </div>
    </header>
  );
}

function Sep() {
  return <span className="text-studio-ink-faint">·</span>;
}

// ──────────────────────────────────────────────────────────────────────
// Body — the transcript as an editorial document.
//
// Editorial moves applied:
//   - Lead paragraph rendered larger, in the serif display face.
//   - Subsequent paragraphs in the body sans at a comfortable measure
//     (~62ch).
//   - Thin marginal rule on the left — printed-page gutter.
//   - Right-margin metadata column at wider widths — useful-but-not-core
//     technical particulars (model, perf, audio, context), grouped and
//     beautifully typeset rather than crammed into a dashboard card.
//   - First line of the lead carries a small-caps drop-in (channel +
//     timecode), so the document looks like it begins, not just starts.

function Body() {
  return (
    <div className="px-9 pb-10">
      <div className="grid grid-cols-[1fr_220px] gap-10">
        <div className="relative">
          {/* Marginal rule — printed-page gutter. */}
          <div
            aria-hidden
            className="absolute -left-5 top-1 bottom-1 w-px"
            style={{ background: "rgba(154,106,34,0.30)" }}
          />

          {/* Lead — serif, larger, with a small-caps timecode opener.
              The opener reads "0:00 — …" like an interview transcript
              cue. */}
          <p
            className="m-0 font-display text-[18px] leading-[1.55] text-studio-ink"
            style={{ letterSpacing: "-0.005em" }}
          >
            <span className="mr-2 font-mono text-[10px] uppercase tracking-[0.20em] text-[#9A6A22]">
              0:00 ·
            </span>
            {MEMO.paragraphs[0]}
          </p>

          {/* Body paragraphs — sans, comfortable measure. Each
              paragraph carries its own timecode in the gutter for
              scrub-by-paragraph. */}
          {MEMO.paragraphs.slice(1).map((p, i) => {
            const cues = ["2:14", "4:47"];
            return (
              <div key={i} className="mt-6 grid grid-cols-[40px_1fr] gap-3">
                <div className="pt-1 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
                  {cues[i]}
                </div>
                <p
                  className="m-0 text-[14px] leading-[1.7] text-studio-ink"
                  style={{ fontFamily: "Inter, -apple-system, sans-serif" }}
                >
                  {p}
                </p>
              </div>
            );
          })}

          {/* End-of-document slug — small mark that the transcript
              has reached its end. Editorial closer, not a status
              indicator. */}
          <div className="mt-10 flex items-center gap-3">
            <span className="h-px w-6" style={{ background: "rgba(26,22,18,0.20)" }} />
            <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
              end · 6:14 · {MEMO.byline.words} words
            </span>
            <span className="h-px flex-1" style={{ background: "rgba(26,22,18,0.10)" }} />
          </div>
        </div>

        {/* Right-margin metadata column. Grouped technical particulars
            from DictationMetadata, typeset as an editor's caption.
            Mono-caps group headers, mono-cased label / right-aligned
            value rows. The brass accent only lands on the marquee
            value (model) so the column reads quietly. Useful-but-not-
            core data, made beautiful. */}
        <aside className="flex flex-col gap-5 pt-2">
          {METADATA.map((group, gi) => (
            <div key={gi} className="flex flex-col gap-2">
              <div className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
                · {group.title}
              </div>
              <div className="flex flex-col gap-1">
                {group.rows.map((row, ri) => (
                  <div
                    key={ri}
                    className="flex items-baseline justify-between gap-3"
                  >
                    <span className="text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
                      {row.label}
                    </span>
                    <span
                      className="text-[11px] font-mono tabular-nums text-studio-ink"
                      style={
                        row.accent
                          ? { color: "#9A6A22", letterSpacing: "-0.005em" }
                          : { letterSpacing: "-0.005em" }
                      }
                    >
                      {row.value}
                    </span>
                  </div>
                ))}
              </div>
              {gi < METADATA.length - 1 && (
                <div
                  className="mt-1 h-px"
                  style={{ background: "rgba(26,22,18,0.08)" }}
                />
              )}
            </div>
          ))}
        </aside>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Player rail — a typesetter's bar at the foot of the document. Three
// regions: transport (play/skip), waveform + scrubber + timecode, and
// trailing speed/volume affordances. Wears the cream palette, not the
// black "media player" register.

function PlayerRail() {
  // Scrub position — illustrative only.
  const PROGRESS = 0.18;

  return (
    <div
      className="mt-auto flex items-center gap-5 px-9 py-4"
      style={{
        background: "#DCDCDB",
        borderTop: "0.5px solid rgba(26,22,18,0.18)",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.6)",
      }}
    >
      {/* Transport */}
      <div className="flex items-center gap-1.5">
        <TransportButton label="−15" />
        <PlayButton />
        <TransportButton label="+15" />
      </div>

      {/* Time elapsed (mono, ink). */}
      <div className="font-mono text-[11px] tracking-[0.08em] text-studio-ink">
        1:08
      </div>

      {/* Waveform — bars at the rail height. Brass amber for the
          played region, faint ink for the remainder. */}
      <div
        className="relative flex flex-1 items-center gap-[2px]"
        style={{ height: "32px" }}
      >
        {WAVEFORM_PEAKS.map((p, i) => {
          const played = i / WAVEFORM_PEAKS.length < PROGRESS;
          return (
            <span
              key={i}
              className="block"
              style={{
                width: "3px",
                height: `${p * 1.6}px`,
                background: played ? "#C47D1C" : "rgba(26,22,18,0.22)",
                borderRadius: "1px",
              }}
            />
          );
        })}
        {/* Scrubber head */}
        <span
          aria-hidden
          className="absolute top-1/2 -translate-y-1/2"
          style={{
            left: `calc(${PROGRESS * 100}% - 1px)`,
            width: "2px",
            height: "36px",
            background: "#C47D1C",
            boxShadow: "0 0 6px rgba(196,125,28,0.55)",
          }}
        />
      </div>

      {/* Time total. */}
      <div className="font-mono text-[11px] tracking-[0.08em] text-studio-ink-faint">
        6:14
      </div>

      {/* Trailing controls. Speed pill + volume glyph. */}
      <div className="flex items-center gap-3">
        <button
          className="rounded-[3px] border px-2 py-1 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint transition-colors hover:text-studio-ink"
          style={{ borderColor: "rgba(26,22,18,0.20)" }}
        >
          1.0×
        </button>
        <button
          className="text-[14px] text-studio-ink-faint transition-colors hover:text-studio-ink"
          aria-label="Volume"
        >
          ♪
        </button>
      </div>
    </div>
  );
}

function PlayButton() {
  return (
    <button
      className="flex h-9 w-9 items-center justify-center rounded-full border transition-colors hover:bg-[#F1F1F0]"
      style={{
        borderColor: "rgba(26,22,18,0.30)",
        background: "#FBFAF4",
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.7), 0 1px 2px rgba(26,22,18,0.08)",
      }}
      aria-label="Play"
    >
      <svg width="11" height="12" viewBox="0 0 11 12" aria-hidden>
        <path d="M 1 0.5 L 10 6 L 1 11.5 Z" fill="#232423" />
      </svg>
    </button>
  );
}

function TransportButton({ label }: { label: string }) {
  return (
    <button
      className="flex h-9 min-w-[36px] items-center justify-center rounded-[3px] border px-2 transition-colors hover:bg-[#F1F1F0]"
      style={{
        borderColor: "rgba(26,22,18,0.16)",
        background: "transparent",
      }}
      aria-label={`Skip ${label}`}
    >
      <span className="font-mono text-[9px] uppercase tracking-[0.12em] text-studio-ink-faint">
        {label}
      </span>
    </button>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Studio footnote — a quiet annotation under the artifact, calling
// out what to look at first. Studio-only, never ports.

function Footnote() {
  return (
    <div className="mx-auto max-w-[1180px] flex items-start gap-3 px-2 text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
      <span>· READ</span>
      <span className="flex-1 normal-case tracking-normal font-sans text-[12px] leading-relaxed text-studio-ink-faint">
        The masthead replaces the metric pills + four-column grid with an editorial
        header — eyebrow / serif headline / single-line byline. The transcript reads
        as a document with a lead paragraph and gutter timecodes; the right margin
        carries the deeper metadata (model, timing, audio, context) as a quiet
        editor's caption. The player rail sits at the foot as a typesetter's bar,
        not as media-app chrome.
      </span>
    </div>
  );
}
