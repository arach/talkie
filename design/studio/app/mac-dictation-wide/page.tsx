"use client";

import { LibraryListGutter } from "@/components/studies/MacMemoDetail";
import { IconRail } from "@/components/studies/primitives/IconRail";

/**
 * Mac Dictation — fullscreen one-pager canvas with library companion.
 *
 * Dictations diverge from memos: typically short, transcript-first,
 * audio is transient (you dictated something, the text is the output).
 * No rich player rail — just a tiny capture footer or none at all.
 *
 * Two stacked viewports at 2560 × 100vh:
 *
 *   1. Typical dictation — a few short paragraphs, transcript-centric.
 *   2. Tiny dictation — one sentence. Shows the empty-canvas problem
 *      starkly: a 2560 × 100vh window holding a single sentence.
 */

const FULLSCREEN_WIDTH = 2560;

export default function MacDictationWideStudy() {
  return (
    <div className="overflow-x-auto" style={{ background: "#FBFBFA" }}>
      <FullscreenSection
        label="DICTATION · ~80 words · transcript-first reading"
      >
        <WideSplitView>
          <DictationSheet
            channel="CH-02"
            sequence="D-3401"
            title="Pick up oat milk and figure out whether the new pour-over is worth the counter space"
            elapsed="0:42"
            words={58}
            paragraphs={[
              "Pick up oat milk. Also reconsider the pour-over — it's been sitting on the counter unused for three weeks and I'm not sure it earns the space anymore.",
              "If we ditch it, the burr grinder still makes sense. The chemex would go too. That clears a whole eight-inch lane of counter, which the dish rack should probably reclaim.",
            ]}
          />
        </WideSplitView>
      </FullscreenSection>

      <FullscreenSection
        label="TINY DICTATION · 1 sentence · empty canvas at fullscreen"
      >
        <WideSplitView>
          <DictationSheet
            channel="CH-02"
            sequence="D-3402"
            title="Move the meeting to Thursday"
            elapsed="0:07"
            words={7}
            paragraphs={[
              "Move the meeting to Thursday.",
            ]}
          />
        </WideSplitView>
      </FullscreenSection>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────

function FullscreenSection({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <section style={{ width: FULLSCREEN_WIDTH, minHeight: "100vh" }} className="flex flex-col">
      <div
        className="flex items-baseline justify-between border-b border-studio-edge px-7 py-2 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint"
        style={{ background: "#F4F1EA" }}
      >
        <span>· {label}</span>
        <span>{FULLSCREEN_WIDTH}px × 100vh</span>
      </div>
      <div className="flex-1 flex">{children}</div>
    </section>
  );
}

function WideSplitView({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex flex-1" style={{ minHeight: 0 }}>
      <IconRail selected="library" />
      <LibraryListGutter />
      <div className="flex-1 flex flex-col" style={{ background: "#FAF7EF", minHeight: 0 }}>
        {children}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// DictationSheet — pure transcript-first composition. No player rail
// (audio is transient), no metadata sidebar by default. The body is the
// document. Whatever's beneath is intentional whitespace — the empty
// canvas IS the design at this scale.

function DictationSheet({
  channel,
  sequence,
  title,
  elapsed,
  words,
  paragraphs,
}: {
  channel: string;
  sequence: string;
  title: string;
  elapsed: string;
  words: number;
  paragraphs: string[];
}) {
  return (
    <article
      className="flex flex-col"
      style={{
        flex: 1,
        background:
          "linear-gradient(180deg, #FAF7EF 0%, #FAF6EB 60%, #F7F2E5 100%)",
      }}
    >
      {/* Toolbar slug */}
      <div
        className="flex items-center gap-3 border-b px-9 py-3"
        style={{ borderColor: "rgba(26,22,18,0.08)" }}
      >
        <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          {sequence} · DICTATION
        </span>
        <span className="ml-auto text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          COPY · EXPORT · ⋯
        </span>
      </div>

      {/* Masthead */}
      <header className="px-9 pt-8 pb-6">
        <div className="flex items-baseline gap-3">
          <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
            · {channel} · DICTATION
          </span>
          <span className="h-px flex-1" style={{ background: "rgba(26,22,18,0.12)" }} />
          <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
            Today · 11:14 AM
          </span>
        </div>

        <h1
          className="m-0 mt-3 font-display text-[34px] font-medium leading-[1.18] tracking-tight text-studio-ink"
          style={{ letterSpacing: "-0.018em" }}
        >
          {title}
        </h1>

        <div className="mt-3 flex flex-wrap items-baseline gap-x-2 gap-y-1 text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
          <span className="text-studio-ink">iTerm2</span>
          <span>·</span>
          <span className="text-studio-ink">{elapsed}</span>
          <span>·</span>
          <span className="text-studio-ink">{words} words</span>
        </div>
      </header>

      {/* Body — paragraphs only, no sidebar */}
      <div className="px-9 pb-10">
        <div className="max-w-[720px]">
          <div className="relative">
            <div
              aria-hidden
              className="absolute -left-5 top-1 bottom-1 w-px"
              style={{ background: "rgba(154,106,34,0.30)" }}
            />

            {paragraphs.map((p, i) => (
              <p
                key={i}
                className={`m-0 ${i === 0 ? "" : "mt-6"} ${i === 0 ? "font-display text-[18px]" : "text-[14px]"} leading-[1.65] text-studio-ink`}
                style={i === 0 ? { letterSpacing: "-0.005em" } : { fontFamily: "Inter, -apple-system, sans-serif" }}
              >
                {i === 0 && (
                  <span className="mr-2 font-mono text-[10px] uppercase tracking-[0.20em] text-[#9A6A22]">
                    0:00 ·
                  </span>
                )}
                {p}
              </p>
            ))}

            <div className="mt-10 flex items-center gap-3">
              <span className="h-px w-6" style={{ background: "rgba(26,22,18,0.20)" }} />
              <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
                end · {elapsed} · {words} words
              </span>
              <span className="h-px flex-1" style={{ background: "rgba(26,22,18,0.10)" }} />
            </div>
          </div>
        </div>
      </div>

      {/* No player rail — dictation audio is transient. Whitespace
          below this point is intentional and is THE design question we
          need to solve. */}
    </article>
  );
}
