"use client";

import { DetailPane, LibraryListGutter } from "@/components/studies/MacMemoDetail";
import { IconRail } from "@/components/studies/primitives/IconRail";

/**
 * Mac Memo — fullscreen one-pager canvas with library companion.
 *
 * Two stacked viewports at 2560 × 100vh so the window-height story is
 * honest:
 *
 *   1. Long memo — current sample data, demonstrates how the document
 *      and player rail breathe when content fills the body.
 *   2. Short memo — same chrome, abbreviated content, demonstrates the
 *      "most of the screen is empty" problem we need a treatment for.
 *
 * Sticky-bottom player rail: DetailPane already uses `mt-auto` on the
 * PlayerRail, so as long as its parent is `100vh`, the player anchors
 * to the viewport bottom regardless of body length.
 */

const FULLSCREEN_WIDTH = 2560;

export default function MacMemoWideStudy() {
  return (
    <div className="overflow-x-auto" style={{ background: "#FBFBFA" }}>
      <FullscreenSection
        label="LONG MEMO · meaty content · DetailPane reads as designed"
      >
        <WideSplitView>
          <DetailPane />
        </WideSplitView>
      </FullscreenSection>

      <FullscreenSection
        label="SHORT MEMO · 2 paragraphs · what does the empty canvas want to be?"
      >
        <WideSplitView>
          <ShortMemoSheet />
        </WideSplitView>
      </FullscreenSection>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Fullscreen section: 100vh-tall window at 2560 wide. The annotation
// band sits flush at the top of each section so we can label what we're
// looking at without breaking the artifact.

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

// ──────────────────────────────────────────────────────────────────────
// Wide split view: icon rail (52pt) + library list gutter (300pt) +
// detail pane (flex-1). Replicates the shipping three-pane composition
// at fullscreen width.

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
// Short memo sheet — an abbreviated DetailPane to demonstrate the
// "empty canvas" problem at fullscreen. Toolbar + masthead + 1-paragraph
// body + player rail. Player rail uses mt-auto so it anchors to the
// viewport bottom, exposing the vast empty middle.
//
// Intentionally inline (not parameterizing DetailPane) so the empty-
// canvas exploration stays localized to this study page until we know
// what treatment we want.

function ShortMemoSheet() {
  return (
    <article
      className="flex flex-col"
      style={{
        flex: 1,
        background:
          "linear-gradient(180deg, #FAF7EF 0%, #FAF6EB 60%, #F7F2E5 100%)",
      }}
    >
      {/* Toolbar slug — printer's signature */}
      <div
        className="flex items-center gap-3 border-b px-9 py-3"
        style={{ borderColor: "rgba(26,22,18,0.08)" }}
      >
        <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          M-0188 · DICTATION
        </span>
        <span className="ml-auto text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          SHARE · EXPORT · ⋯
        </span>
      </div>

      {/* Masthead */}
      <header className="px-9 pt-8 pb-6">
        <div className="flex items-baseline gap-3">
          <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
            · CH-02 · DICTATION
          </span>
          <span className="h-px flex-1" style={{ background: "rgba(26,22,18,0.12)" }} />
          <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
            Today · 11:14 AM
          </span>
        </div>

        <h1
          className="m-0 mt-3 font-display text-[34px] font-medium leading-[1.12] tracking-tight text-studio-ink"
          style={{ letterSpacing: "-0.018em" }}
        >
          Quick note to self
        </h1>

        <div className="mt-3 flex flex-wrap items-baseline gap-x-2 gap-y-1 text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
          <span className="text-studio-ink">iTerm2</span>
          <span>·</span>
          <span className="text-studio-ink">0:18</span>
        </div>
      </header>

      {/* Body — single paragraph */}
      <div className="px-9 pb-10">
        <div className="grid grid-cols-[1fr_220px] gap-10">
          <div className="relative">
            <div
              aria-hidden
              className="absolute -left-5 top-1 bottom-1 w-px"
              style={{ background: "rgba(154,106,34,0.30)" }}
            />
            <p
              className="m-0 font-display text-[18px] leading-[1.55] text-studio-ink"
              style={{ letterSpacing: "-0.005em" }}
            >
              <span className="mr-2 font-mono text-[10px] uppercase tracking-[0.20em] text-[#9A6A22]">
                0:00 ·
              </span>
              Remember to switch the bay scheme to chiffon before recording the next demo — porcelain reads too cold on the new canvas.
            </p>

            <div className="mt-10 flex items-center gap-3">
              <span className="h-px w-6" style={{ background: "rgba(26,22,18,0.20)" }} />
              <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
                end · 0:18 · 21 words
              </span>
              <span className="h-px flex-1" style={{ background: "rgba(26,22,18,0.10)" }} />
            </div>
          </div>

          <aside className="flex flex-col gap-5 pt-2">
            <div className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
              · CAPTURE
            </div>
            <div className="text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
              No metadata yet
            </div>
          </aside>
        </div>
      </div>

      {/* Player rail — sticks to viewport bottom via mt-auto */}
      <div
        className="mt-auto flex items-center gap-5 px-9 py-4"
        style={{
          background: "#F2EDDE",
          borderTop: "0.5px solid rgba(26,22,18,0.18)",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,0.6)",
        }}
      >
        <div className="font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint">
          0:00 · 0:18
        </div>
        <div className="flex-1 h-1.5 rounded-full" style={{ background: "rgba(26,22,18,0.10)" }}>
          <div className="h-1.5 rounded-full" style={{ width: "0%", background: "#C47D1C" }} />
        </div>
        <div className="font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
          ▶ PLAY
        </div>
      </div>
    </article>
  );
}
