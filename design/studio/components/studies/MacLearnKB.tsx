"use client";

/**
 * Mac Learn KB — embedded article reader.
 *
 * What this is
 * ------------
 * The article-detail body that renders INSIDE a local `WKWebView` hosted
 * by the SwiftUI Learn KB shell. The native shell owns navigation,
 * search, sidebar, history. This view owns one article at a time —
 * hero, metadata ledger, shortcut strip, prose, callouts, ordered steps,
 * related surfaces, and bridge action rows that deep-link back into the
 * app (`talkie://...`).
 *
 * Tokens
 * ------
 * Driven entirely by `--theme-*` CSS variables defined in
 * `app/globals.css`. The same component repaints under any
 * `data-theme="..."` bundle. Used in this study under "scope",
 * "midnight", and "tactical".
 *
 * Why a web view at all
 * ---------------------
 * Article content is markdown/HTML rendered once; the agent populating
 * KB content can iterate on copy without recompiling Swift. The shell
 * around it (search, sidebar) stays SwiftUI so it inherits the native
 * sidebar/back behaviors. The web view is a content slab, not an app.
 */

import type { ReactNode } from "react";

// ────────────────────────────────────────────────────────────────────
// Article data model

export type ArticleBlock =
  | { kind: "para"; text: string }
  | { kind: "subhead"; text: string }
  | { kind: "callout"; tone: "note" | "tip" | "warn"; title: string; text: string }
  | { kind: "steps"; items: { title: string; text: string }[] }
  | {
      kind: "related";
      items: { title: string; topic: string; href: string }[];
    }
  | {
      kind: "bridge";
      items: { label: string; href: string; detail: string }[];
    };

export interface KBKey {
  /** Visual symbol (⌘ ⌃ ⌥ ⇧ ⇪) or letter ("S"). */
  glyph: string;
  /** Human name for the key — used as the small-caps label under the cap. */
  name?: string;
}

export interface KBShortcut {
  /** Combo to press — keys are AND'd together. */
  combo: KBKey[];
  /** Then-keys — disjoint follow-up choices (e.g. A / S / D). */
  thenAny?: KBKey[];
  /** One-line description of what the chord does. */
  describe: string;
}

export interface KBArticle {
  slug: string;
  topic: string;
  title: string;
  dek: string;
  updated: string;
  readingTime: string;
  /** Author or maintainer credit shown small in the ledger. */
  maintained: string;
  shortcuts?: KBShortcut[];
  body: ArticleBlock[];
}

// ────────────────────────────────────────────────────────────────────
// Theme labels — for the small badge above each preview in the study

const THEME_BADGE: Record<string, { name: string; tone: string }> = {
  scope: { name: "SCOPE", tone: "LIGHT" },
  midnight: { name: "MIDNIGHT", tone: "DARK" },
  tactical: { name: "TACTICAL", tone: "DARK" },
  ghost: { name: "GHOST", tone: "LIGHT" },
};

// ────────────────────────────────────────────────────────────────────
// Public root — two articles × multiple themes, framed as the WKWebView
// content slab (no native chrome — that's SwiftUI).

export function MacLearnKB() {
  return (
    <div className="flex flex-col gap-10">
      <PreviewRow
        caption="Same article · light vs dark. The reader is theme-passive — it inherits whatever bundle Swift hands it."
        previews={[
          { theme: "scope", article: ARTICLE_HYPER_S },
          { theme: "midnight", article: ARTICLE_HYPER_S },
        ]}
      />
      <PreviewRow
        caption="A second article shape — fewer shortcut chords, more procedural steps + cross-surface bridges."
        previews={[
          { theme: "scope", article: ARTICLE_CONTEXT_RULES },
          { theme: "tactical", article: ARTICLE_CONTEXT_RULES },
        ]}
      />
    </div>
  );
}

function PreviewRow({
  caption,
  previews,
}: {
  caption: string;
  previews: { theme: string; article: KBArticle }[];
}) {
  return (
    <section className="flex flex-col gap-3">
      <p className="text-[12px] leading-relaxed text-studio-ink-faint max-w-[760px]">
        {caption}
      </p>
      <div className="grid grid-cols-2 gap-5">
        {previews.map((p, i) => (
          <ThemedPreview key={i} theme={p.theme} article={p.article} />
        ))}
      </div>
    </section>
  );
}

function ThemedPreview({
  theme,
  article,
}: {
  theme: string;
  article: KBArticle;
}) {
  const badge = THEME_BADGE[theme] ?? { name: theme.toUpperCase(), tone: "" };
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-baseline gap-2 px-1">
        <span className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
          · {badge.name}
        </span>
        <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
          {badge.tone}
        </span>
        <span className="ml-auto text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          WKWebView · {article.slug}
        </span>
      </div>
      <div
        data-theme={theme}
        className="overflow-hidden rounded-[6px] border"
        style={{
          borderColor: "var(--theme-edge)",
          boxShadow: "0 4px 14px rgba(0,0,0,0.08)",
        }}
      >
        <KBArticleView article={article} />
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// The actual article reader.
//
// Visual budget:
//   - Editorial Newsreader display, generous line-height
//   - Inter body @ 14px/1.65
//   - Mono JetBrains for ledger, eyebrows, shortcuts, bridge links
//   - Thin --theme-edge-faint hairlines between ledger cells & steps
//   - Brass/amber accent reserved for: topic eyebrow, callout fill,
//     bridge action rows. Restraint is the point.

export function KBArticleView({ article }: { article: KBArticle }) {
  return (
    <article
      className="flex flex-col"
      style={{
        background: "var(--theme-canvas)",
        color: "var(--theme-ink)",
        fontFamily: "var(--theme-font-body)",
      }}
    >
      {/* Single global rule for the per-theme eyebrow leader glyph
       *  (·, —, ›). `content: var(--name)` is widely supported, but
       *  must live in a style sheet — not inline. Hoisting here keeps
       *  the component self-contained while emitting exactly one rule. */}
      <style>{`.kb-eyebrow-leader::before { content: var(--theme-eyebrow-leader); }`}</style>
      <Hero article={article} />
      <MetadataLedger article={article} />
      {article.shortcuts && article.shortcuts.length > 0 ? (
        <ShortcutStrip shortcuts={article.shortcuts} />
      ) : null}
      <Body blocks={article.body} />
    </article>
  );
}

// ────────────────────────────────────────────────────────────────────
// Hero — topic eyebrow + display title + dek
//
// Anchored top-left; no centered alignment, no marketing rhetoric.
// Reads as the first column of a printed feature.

function Hero({ article }: { article: KBArticle }) {
  return (
    <header
      className="flex flex-col gap-3 px-8 pt-9 pb-7"
      style={{
        borderBottom: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
      }}
    >
      <div
        className="flex items-center gap-2.5 text-[9px] uppercase"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.26em",
        }}
      >
        <span aria-hidden style={{ opacity: 0.85 }}>
          {/* `var(--theme-eyebrow-leader)` is a CSS variable; emit via ::before */}
          <EyebrowLeader />
        </span>
        <span>{article.topic}</span>
        <span style={{ color: "var(--theme-ink-faint)" }}>·</span>
        <span style={{ color: "var(--theme-ink-faint)" }}>Knowledge Base</span>
      </div>
      <h1
        className="m-0 text-[34px] leading-[1.08]"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-display)",
          fontWeight: "var(--theme-display-weight)" as unknown as number,
          letterSpacing: "var(--theme-display-tracking)",
        }}
      >
        {article.title}
      </h1>
      <p
        className="m-0 max-w-[58ch] text-[14.5px] leading-[1.6]"
        style={{
          color: "var(--theme-ink-muted)",
        }}
      >
        {article.dek}
      </p>
    </header>
  );
}

/**
 * Eyebrow leader — the per-theme glyph (·, —, ›) lives only in the CSS
 * variable. The `.kb-eyebrow-leader::before` rule is defined once at
 * the article root; this component just emits the trigger element.
 */
function EyebrowLeader() {
  return <span className="kb-eyebrow-leader" aria-hidden />;
}

// ────────────────────────────────────────────────────────────────────
// Metadata ledger — small-caps mono row beneath the hero
//
// Inspired by editorial mastheads: a thin top + bottom rule encloses a
// row of UPDATED / READING / MAINTAINED cells, each separated by a
// hairline rule. This is the "ledger" treatment.

function MetadataLedger({ article }: { article: KBArticle }) {
  const cells: { label: string; value: ReactNode }[] = [
    { label: "Updated", value: article.updated },
    { label: "Reading", value: article.readingTime },
    { label: "Maintained", value: article.maintained },
    { label: "Article", value: article.slug },
  ];
  return (
    <div
      className="grid grid-cols-4"
      style={{
        borderBottom: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
        background: "var(--theme-canvas-alt)",
      }}
    >
      {cells.map((c, i) => (
        <div
          key={c.label}
          className="flex flex-col gap-1 px-5 py-3"
          style={{
            borderLeft:
              i === 0
                ? undefined
                : "var(--theme-hairline-w) solid var(--theme-edge-faint)",
          }}
        >
          <div
            className="text-[8.5px] uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.22em",
            }}
          >
            {c.label}
          </div>
          <div
            className="text-[11.5px]"
            style={{
              color: "var(--theme-ink)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.04em",
            }}
          >
            {c.value}
          </div>
        </div>
      ))}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Shortcut strip — keycaps + "then any of" disjoint
//
// Lives BELOW the ledger so the chord is the first scannable artifact
// after metadata. Keycaps are tiny: 18×22, 0.5px stroke, mono glyph.

function ShortcutStrip({ shortcuts }: { shortcuts: KBShortcut[] }) {
  return (
    <div
      className="flex flex-col gap-3 px-8 pt-5 pb-6"
      style={{
        borderBottom: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
      }}
    >
      <SectionEyebrow label="Shortcut" />
      <div className="flex flex-col gap-3">
        {shortcuts.map((sc, idx) => (
          <div key={idx} className="flex flex-wrap items-center gap-3">
            <KeyCapRow keys={sc.combo} />
            {sc.thenAny && sc.thenAny.length > 0 ? (
              <>
                <span
                  className="text-[9.5px] uppercase"
                  style={{
                    color: "var(--theme-ink-faint)",
                    fontFamily: "var(--theme-font-mono)",
                    letterSpacing: "0.22em",
                  }}
                >
                  then any of
                </span>
                <KeyCapRow keys={sc.thenAny} divider />
              </>
            ) : null}
            <span
              className="text-[12.5px]"
              style={{ color: "var(--theme-ink-muted)" }}
            >
              {sc.describe}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function KeyCapRow({ keys, divider = false }: { keys: KBKey[]; divider?: boolean }) {
  return (
    <div className="flex items-center gap-1">
      {keys.map((k, i) => (
        <span key={i} className="flex items-center gap-1">
          <KeyCap k={k} />
          {divider && i < keys.length - 1 ? (
            <span
              className="text-[10px]"
              style={{ color: "var(--theme-ink-faint)" }}
            >
              /
            </span>
          ) : null}
        </span>
      ))}
    </div>
  );
}

function KeyCap({ k }: { k: KBKey }) {
  return (
    <span
      className="inline-flex h-[22px] min-w-[24px] items-center justify-center px-1.5 text-[11px]"
      style={{
        color: "var(--theme-ink)",
        background: "var(--theme-paper)",
        border: "var(--theme-hairline-w) solid var(--theme-edge)",
        borderRadius: "var(--theme-chrome-corner)",
        fontFamily: "var(--theme-font-mono)",
        boxShadow: "var(--theme-card-shadow)",
      }}
      title={k.name ?? k.glyph}
    >
      {k.glyph}
    </span>
  );
}

// ────────────────────────────────────────────────────────────────────
// Body — block-driven prose

function Body({ blocks }: { blocks: ArticleBlock[] }) {
  return (
    <div className="flex flex-col gap-5 px-8 py-7 max-w-[720px]">
      {blocks.map((b, i) => (
        <Block key={i} block={b} />
      ))}
    </div>
  );
}

function Block({ block }: { block: ArticleBlock }) {
  switch (block.kind) {
    case "para":
      return (
        <p
          className="m-0 text-[14px] leading-[1.7]"
          style={{ color: "var(--theme-ink-muted)" }}
        >
          {block.text}
        </p>
      );
    case "subhead":
      return (
        <h2
          className="m-0 mt-2 text-[19px] leading-tight"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-display)",
            fontWeight: "var(--theme-display-weight)" as unknown as number,
            letterSpacing: "var(--theme-display-tracking)",
          }}
        >
          {block.text}
        </h2>
      );
    case "callout":
      return <Callout block={block} />;
    case "steps":
      return <Steps items={block.items} />;
    case "related":
      return <Related items={block.items} />;
    case "bridge":
      return <BridgeRows items={block.items} />;
  }
}

// Callout — warm amber-faint fill, brass left bar, small-caps label.
// Reserved for note / tip / warn — no other prose blocks use the
// accent fill.
function Callout({
  block,
}: {
  block: Extract<ArticleBlock, { kind: "callout" }>;
}) {
  const labelMap = { note: "NOTE", tip: "TIP", warn: "WATCH OUT" } as const;
  return (
    <aside
      className="flex gap-3 px-4 py-3"
      style={{
        background: "var(--theme-amber-faint)",
        borderLeft: "2px solid var(--theme-amber)",
        borderRadius: "var(--theme-chrome-corner)",
      }}
    >
      <div className="flex flex-col gap-1">
        <div
          className="text-[8.5px] uppercase"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.26em",
          }}
        >
          {labelMap[block.tone]} · {block.title}
        </div>
        <p
          className="m-0 text-[13px] leading-[1.6]"
          style={{ color: "var(--theme-ink-muted)" }}
        >
          {block.text}
        </p>
      </div>
    </aside>
  );
}

// Steps — numbered ordered list with hairline rules and tiny channel
// indices (S01, S02…), so the step numbers act like channel labels and
// not generic ol-li dots.
function Steps({ items }: { items: { title: string; text: string }[] }) {
  return (
    <ol
      className="m-0 flex flex-col"
      style={{
        borderTop: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
        listStyle: "none",
        padding: 0,
      }}
    >
      {items.map((step, i) => (
        <li
          key={i}
          className="grid grid-cols-[64px_1fr] gap-4 py-4"
          style={{
            borderBottom:
              "var(--theme-hairline-w) solid var(--theme-edge-faint)",
          }}
        >
          <div
            className="text-[10px] uppercase"
            style={{
              color: "var(--theme-amber)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.20em",
            }}
          >
            S{(i + 1).toString().padStart(2, "0")}
          </div>
          <div className="flex flex-col gap-1.5">
            <div
              className="text-[14px]"
              style={{
                color: "var(--theme-ink)",
                fontWeight: 500,
              }}
            >
              {step.title}
            </div>
            <p
              className="m-0 text-[13px] leading-[1.65]"
              style={{ color: "var(--theme-ink-muted)" }}
            >
              {step.text}
            </p>
          </div>
        </li>
      ))}
    </ol>
  );
}

// Related — ledger rows with topic on the right, title on the left.
// Same visual rhythm as ScopeRule rows in the donor app. Hover lifts the
// row faintly. Clicking would route to another article in the KB
// (handled by the SwiftUI shell intercepting the link).
function Related({
  items,
}: {
  items: { title: string; topic: string; href: string }[];
}) {
  return (
    <section className="flex flex-col gap-2">
      <SectionEyebrow label="Related" />
      <div
        className="flex flex-col"
        style={{
          borderTop: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
        }}
      >
        {items.map((r, i) => (
          <a
            key={i}
            href={r.href}
            className="grid grid-cols-[1fr_auto] items-baseline gap-4 px-1 py-2.5 transition-colors"
            style={{
              borderBottom:
                "var(--theme-hairline-w) solid var(--theme-edge-faint)",
              color: "var(--theme-ink)",
              textDecoration: "none",
            }}
          >
            <span className="text-[13px]" style={{ color: "var(--theme-ink)" }}>
              {r.title}
            </span>
            <span
              className="text-[9.5px] uppercase"
              style={{
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.20em",
              }}
            >
              {r.topic}
            </span>
          </a>
        ))}
      </div>
    </section>
  );
}

// Bridge action rows — the heart of the KB → app handshake. Each row
// is a `talkie://` deep-link. Visually the most accent-emphatic block
// on the page so the reader knows what to do next.
function BridgeRows({
  items,
}: {
  items: { label: string; href: string; detail: string }[];
}) {
  return (
    <section className="flex flex-col gap-2">
      <SectionEyebrow label="Open in Talkie" tone="amber" />
      <div className="flex flex-col gap-2">
        {items.map((b, i) => (
          <a
            key={i}
            href={b.href}
            className="grid grid-cols-[1fr_auto] items-center gap-4 px-4 py-3 transition-colors"
            style={{
              background: "var(--theme-paper)",
              border: "var(--theme-hairline-w) solid var(--theme-amber-soft)",
              borderRadius: "var(--theme-chrome-corner)",
              textDecoration: "none",
              boxShadow: "var(--theme-card-shadow)",
            }}
          >
            <div className="flex flex-col gap-1">
              <span
                className="text-[13.5px]"
                style={{ color: "var(--theme-ink)", fontWeight: 500 }}
              >
                {b.label}
              </span>
              <span
                className="text-[10.5px]"
                style={{
                  color: "var(--theme-ink-faint)",
                  fontFamily: "var(--theme-font-mono)",
                  letterSpacing: "0.04em",
                }}
              >
                {b.href}
              </span>
              <span
                className="text-[12px] leading-snug"
                style={{ color: "var(--theme-ink-muted)" }}
              >
                {b.detail}
              </span>
            </div>
            <span
              aria-hidden
              className="text-[16px]"
              style={{
                color: "var(--theme-amber)",
                textShadow: "0 0 var(--theme-glow-radius) var(--theme-amber-glow)",
              }}
            >
              →
            </span>
          </a>
        ))}
      </div>
    </section>
  );
}

function SectionEyebrow({
  label,
  tone = "neutral",
}: {
  label: string;
  tone?: "neutral" | "amber";
}) {
  return (
    <div
      className="flex items-center gap-2 text-[8.5px] uppercase"
      style={{
        color:
          tone === "amber" ? "var(--theme-amber)" : "var(--theme-ink-faint)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.26em",
      }}
    >
      <span aria-hidden>
        <EyebrowLeader />
      </span>
      <span>{label}</span>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Sample articles — these are studio fakes that exercise every block
// type. Real content lives in `apps/macos/Talkie/Resources/Learn/...`
// and is OUT OF SCOPE for this design route.

const ARTICLE_HYPER_S: KBArticle = {
  slug: "hyper-s-capture-with-audio",
  topic: "Shortcuts",
  title: "Hyper+S — Capture with audio",
  dek:
    "The screen-grab chord that attaches the resulting image to the recording in progress. Sound and surface, captured together.",
  updated: "2026-05-18",
  readingTime: "3 min",
  maintained: "Talkie team",
  shortcuts: [
    {
      combo: [
        { glyph: "⌃", name: "Control" },
        { glyph: "⌥", name: "Option" },
        { glyph: "⌘", name: "Command" },
        { glyph: "S", name: "S" },
      ],
      thenAny: [
        { glyph: "A", name: "Region" },
        { glyph: "S", name: "Fullscreen" },
        { glyph: "D", name: "Window" },
      ],
      describe:
        "Triggers the screenshot chord; pick a region, full screen, or active window.",
    },
  ],
  body: [
    {
      kind: "para",
      text:
        "Hyper+S is the capture chord. Hold the four-key modifier, tap S, then choose what to grab — a marquee region, the full screen, or the focused window. The image is held in memory until the next recording closes, at which point it's stitched onto the same memo as an inline attachment.",
    },
    {
      kind: "callout",
      tone: "tip",
      title: "While recording",
      text:
        "If a memo is already recording when you fire the chord, the screenshot attaches in real time — no need to remember to pull it in later. The tray shows a small attachment glyph beside the elapsed counter.",
    },
    { kind: "subhead", text: "How to use it" },
    {
      kind: "steps",
      items: [
        {
          title: "Start a recording",
          text:
            "Use the tray button or your bound dictation hotkey. The capture chord can fire any time, but attaches only while a memo is active.",
        },
        {
          title: "Hold the Hyper modifier",
          text:
            "Control + Option + Command. The four-finger chord is intentional — accidental Hyper+S almost never happens.",
        },
        {
          title: "Tap S, then A / S / D",
          text:
            "A marquees a region, S grabs the full screen, D grabs the focused window. Esc abandons the capture; the recording is unaffected.",
        },
        {
          title: "Finish the recording",
          text:
            "Stop the memo from the tray. The screenshot lands in the same memo, pinned where it was captured on the transcript timeline.",
        },
      ],
    },
    {
      kind: "callout",
      tone: "note",
      title: "Permissions",
      text:
        "Screen Recording must be granted in System Settings ▸ Privacy & Security. Talkie surfaces a single-step prompt the first time you fire the chord.",
    },
    {
      kind: "related",
      items: [
        {
          title: "Bind your own capture chord",
          topic: "Shortcuts",
          href: "/learn/customize-hyper-keys",
        },
        {
          title: "Where attachments live in a memo",
          topic: "Library",
          href: "/learn/memo-anatomy",
        },
        {
          title: "Workflows that act on captured images",
          topic: "Workflows",
          href: "/learn/image-workflows",
        },
      ],
    },
    {
      kind: "bridge",
      items: [
        {
          label: "Open the tray",
          href: "talkie://tray",
          detail:
            "Drop down the recording tray to see in-flight memos and their attachment counters.",
        },
        {
          label: "Configure Hyper keys",
          href: "talkie://settings/surface",
          detail:
            "Rebind the chord, swap A/S/D assignments, or disable individual capture types.",
        },
      ],
    },
  ],
};

const ARTICLE_CONTEXT_RULES: KBArticle = {
  slug: "context-rules-scope-to-app",
  topic: "Workflows",
  title: "Scope a workflow to one app",
  dek:
    "Context rules read the foreground app at trigger time. Use them to keep workflows on the surface that needs them — and out of the ones that don't.",
  updated: "2026-05-20",
  readingTime: "4 min",
  maintained: "Talkie team",
  body: [
    {
      kind: "para",
      text:
        "Every workflow can be gated by a context rule. The rule is evaluated the moment a trigger fires — recording finished, hotkey pressed, manual run — and reads the bundle identifier of whatever app is in the foreground. If the rule doesn't match, the workflow stays asleep. No notification, no telemetry, no surprise.",
    },
    { kind: "subhead", text: "Three matcher shapes" },
    {
      kind: "steps",
      items: [
        {
          title: "Exactly this app",
          text:
            "Pick one bundle ID. The rule fires only when that app is forward. Useful for narrow integrations — a Compose tweak that only ever runs in Mail.",
        },
        {
          title: "Any of a list",
          text:
            "Pick several bundle IDs. The rule fires when any of them is forward. Useful for IDE families (VS Code, Cursor, Zed) where the workflow is identical.",
        },
        {
          title: "Everywhere except",
          text:
            "Inverse match — fires anywhere the foreground app is NOT one of the listed IDs. Useful for global dictation that should stay out of password managers and meeting apps.",
        },
      ],
    },
    {
      kind: "callout",
      tone: "warn",
      title: "Bundle IDs, not display names",
      text:
        "Apps can rename themselves without changing identity. The matcher uses bundle identifier (com.example.app) so a renamed app still matches — and a different app with the same display name does not slip through.",
    },
    { kind: "subhead", text: "When the rule rejects" },
    {
      kind: "para",
      text:
        "A rejected workflow is silent on purpose — surfacing skipped runs would clutter the console with non-events. Open the workflow in the editor to see its last-run timestamp; if a trigger fired but the rule rejected, the run row is annotated 'gated'.",
    },
    {
      kind: "related",
      items: [
        {
          title: "How triggers work",
          topic: "Workflows",
          href: "/learn/workflow-triggers",
        },
        {
          title: "Console run log",
          topic: "Console",
          href: "/learn/console-runs",
        },
        {
          title: "Compose ↔ Workflow handoffs",
          topic: "Compose",
          href: "/learn/compose-workflow-handoff",
        },
      ],
    },
    {
      kind: "bridge",
      items: [
        {
          label: "Open Workflows",
          href: "talkie://open/workflows",
          detail:
            "Jump to the workflow editor with the context-rule panel pre-expanded.",
        },
        {
          label: "Manage surface bindings",
          href: "talkie://settings/surface",
          detail:
            "Adjust which surfaces (tray, hotkey, menubar) can trigger context-gated workflows.",
        },
        {
          label: "Open the tray",
          href: "talkie://tray",
          detail:
            "See whether the current foreground app would pass any of your active workflow rules.",
        },
      ],
    },
  ],
};
