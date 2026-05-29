"use client";

/**
 * MacScreenshots — interactive screenshots gallery study.
 *
 * The earlier draft had three frozen panels (default / selection /
 * with inspector) and a lot of per-card chrome (REGION/WINDOW/FULLSCREEN
 * tag, dark C-ID label). Two problems:
 *   1. Read too decorated — every card was a template, not a screenshot.
 *   2. Selection was illustrated, not exercised. You couldn't feel the
 *      anchor / ⌘-toggle / shift-range model.
 *
 * This version collapses to one live surface:
 *   · single window, single grid, single status bar, single inspector
 *   · click a card to anchor; ⌘-click to toggle; shift-click to extend
 *   · status bar + inspector update from real state
 *   · cards carry only the content + minimal hover-revealed ID
 *
 * Donor: apps/macos/Talkie/Views/ScreenshotsScreen.swift — the same
 * selection model (selectedIDs / selectionAnchorID), here in a TSX
 * sketch you can actually click around in.
 */

import React, { useMemo, useState } from "react";
import { SCOPE } from "@/lib/scope-tokens";

const T = {
  page:        SCOPE.canvas,
  pane:        SCOPE.pane,
  chrome:      SCOPE.chrome,
  rail:        SCOPE.rail,
  ink:         SCOPE.ink,
  inkMid:      SCOPE.inkMid,
  inkFaint:    SCOPE.inkFaint,
  inkFainter:  SCOPE.inkFainter,
  inkRule:     SCOPE.rule,
  inkRuleS:    SCOPE.ruleSubtle,
  edge:        SCOPE.edge,
  amber:       SCOPE.amber,
  amberDeep:   SCOPE.amberDeep,
  amberFaint:  SCOPE.amberFaint,
  amberSoft:   SCOPE.amberSoft,
  brass:       SCOPE.brass,
  alert:       SCOPE.alert,
};

// ─── Data ────────────────────────────────────────────────────────────

type Tone = "log" | "table" | "doc" | "chat" | "calendar" | "code";
type Source = "region" | "window" | "fullscreen";

interface Capture {
  id: string;
  source: Source;
  tone: Tone;
  ageLabel: string;
  bytes: string;
  dims: string;
  app?: string;
  fresh?: boolean;
  annotated?: boolean;
}

const CAPTURES: Capture[] = [
  { id: "C-0021", source: "region",     tone: "log",      ageLabel: "just now",  bytes: "184 kB", dims: "1280 × 824",  app: "Xcode",     fresh: true                  },
  { id: "C-0020", source: "window",     tone: "table",    ageLabel: "12 min",    bytes: "421 kB", dims: "1440 × 900",  app: "Notion"                                  },
  { id: "C-0019", source: "region",     tone: "doc",      ageLabel: "27 min",    bytes: "92 kB",  dims: "820 × 540",   app: "Mail",                annotated: true     },
  { id: "C-0018", source: "fullscreen", tone: "chat",     ageLabel: "1h",        bytes: "1.1 MB", dims: "3024 × 1964", app: "Messages"                                },
  { id: "C-0017", source: "region",     tone: "log",      ageLabel: "1h",        bytes: "210 kB", dims: "1024 × 640",  app: "Terminal",            annotated: true     },
  { id: "C-0016", source: "window",     tone: "calendar", ageLabel: "2h",        bytes: "338 kB", dims: "1180 × 760",  app: "Calendar"                                },
  { id: "C-0015", source: "region",     tone: "table",    ageLabel: "3h",        bytes: "256 kB", dims: "960 × 600",   app: "Numbers"                                 },
  { id: "C-0014", source: "fullscreen", tone: "code",     ageLabel: "5h",        bytes: "1.4 MB", dims: "3024 × 1964", app: "Xcode"                                   },
  { id: "C-0013", source: "window",     tone: "log",      ageLabel: "yesterday", bytes: "180 kB", dims: "1280 × 768",  app: "Console"                                 },
  { id: "C-0012", source: "region",     tone: "chat",     ageLabel: "yesterday", bytes: "118 kB", dims: "720 × 480",   app: "Slack",               annotated: true     },
  { id: "C-0011", source: "region",     tone: "doc",      ageLabel: "yesterday", bytes: "144 kB", dims: "880 × 580",   app: "Pages"                                   },
  { id: "C-0010", source: "window",     tone: "code",     ageLabel: "2 days",    bytes: "402 kB", dims: "1200 × 760",  app: "Cursor"                                  },
];

// ─── Composition root ────────────────────────────────────────────────

export function MacScreenshots() {
  return (
    <div style={{ width: 1180, background: T.page }} className="flex flex-col">
      <StudyHeader />
      <LiveSurface />
      <NamesMarginalia />
      <StudyFooter />
    </div>
  );
}

// ─── Header / footer ─────────────────────────────────────────────────

function StudyHeader() {
  return (
    <div style={{ padding: "24px 40px 16px 40px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.32em]"
          style={{ color: T.inkFaint, fontSize: 9 }}
        >
          · SCREENSHOTS · interactive · live selection
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>
          click cards · ⌘-click to toggle · shift-click to extend
        </span>
        <div className="ml-auto">
          <Chip label="WORKING SKETCH" />
        </div>
      </div>
      <h2
        className="font-display tracking-tight"
        style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 10 }}
      >
        Screenshots
      </h2>
      <p
        className="font-display"
        style={{
          color: T.inkMid,
          fontSize: 14,
          lineHeight: 1.6,
          marginTop: 12,
          maxWidth: 680,
        }}
      >
        Focused gallery for captures. Cards stay quiet — content first,
        no per-card source badges or printed IDs — so the wall reads as
        screenshots, not as templated tiles. Source and metadata move
        into the inspector, where they earn the attention.
      </p>
    </div>
  );
}

function StudyFooter() {
  return (
    <div style={{ padding: "32px 40px 28px 40px" }}>
      <div style={{ height: 1, background: T.inkRuleS, marginBottom: 14 }} />
      <p
        className="font-display italic"
        style={{ color: T.inkFaint, fontSize: 12.5, lineHeight: 1.6, maxWidth: 720 }}
      >
        Donor: <code style={{ fontFamily: "ui-monospace, monospace", fontSize: 11.5, color: T.ink }}>ScreenshotsScreen.swift</code>.
        Same selection model (anchor + extended set), here as a live
        sketch so the studio can exercise it before Swift does.
      </p>
    </div>
  );
}

// ─── Live surface — single window, click-to-select ───────────────────

function LiveSurface() {
  const [selection, setSelection] = useState<Set<string>>(new Set([CAPTURES[0].id]));
  const [anchor, setAnchor] = useState<string>(CAPTURES[0].id);
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  // "gallery" → grid view. "preview" → clean Quick Look of the anchor
  // (read-only, image-forward). "markup" → the annotate editor. Mirrors
  // macOS: Open in Preview gives you Quick Look, and Markup is the
  // escalation from there. All three share the same window chrome so the
  // journey feels continuous (no panel swap).
  const [mode, setMode] = useState<"gallery" | "preview" | "markup">("gallery");

  const anchorCapture = useMemo(
    () => CAPTURES.find((c) => c.id === anchor) ?? null,
    [anchor]
  );

  function onCardClick(id: string, modifiers: { cmd: boolean; shift: boolean }) {
    if (modifiers.shift) {
      // Range from anchor → id (inclusive). Replace selection with the
      // range so a shift-click reads as "this is the band I want."
      const anchorIdx = CAPTURES.findIndex((c) => c.id === anchor);
      const targetIdx = CAPTURES.findIndex((c) => c.id === id);
      if (anchorIdx === -1 || targetIdx === -1) return;
      const [lo, hi] = anchorIdx < targetIdx ? [anchorIdx, targetIdx] : [targetIdx, anchorIdx];
      const next = new Set<string>();
      for (let i = lo; i <= hi; i++) next.add(CAPTURES[i].id);
      setSelection(next);
      return;
    }

    if (modifiers.cmd) {
      // Toggle membership; don't move the anchor unless we just added
      // the first member.
      const next = new Set(selection);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
        if (next.size === 1) setAnchor(id);
      }
      setSelection(next);
      return;
    }

    // Plain click — single-pick. Replace selection AND reset anchor.
    setSelection(new Set([id]));
    setAnchor(id);
  }

  function clearSelection() {
    setSelection(new Set());
    setAnchor("");
  }

  return (
    <div style={{ padding: "8px 40px 4px 40px" }}>
      <div
        style={{
          background: T.page,
          borderRadius: 8,
          border: `0.5px solid ${T.edge}`,
          boxShadow:
            "0 1px 0 rgba(255,255,255,0.55) inset, 0 12px 30px -8px rgba(0,0,0,0.10)",
          overflow: "hidden",
        }}
      >
        <WindowChrome
          title={
            mode === "markup" && anchorCapture
              ? `Markup · ${anchorCapture.id}`
              : mode === "preview" && anchorCapture
              ? `Preview · ${anchorCapture.id}`
              : "Screenshots"
          }
          subtitle={
            mode !== "gallery" && anchorCapture
              ? `${anchorCapture.app ?? anchorCapture.source} · ${anchorCapture.dims}`
              : `${CAPTURES.length} captures · ${
                  CAPTURES.filter(
                    (c) => c.ageLabel === "just now" || c.ageLabel.endsWith("min")
                  ).length
                } today`
          }
          trailing={
            mode !== "gallery" ? (
              <button
                onClick={() => setMode("gallery")}
                className="font-mono uppercase tracking-[0.18em]"
                style={{
                  fontSize: 9,
                  color: T.inkFaint,
                  background: "transparent",
                  border: `0.5px solid ${T.inkRule}`,
                  borderRadius: 3,
                  padding: "3px 8px",
                  cursor: "pointer",
                }}
                title="Back to Screenshots (Esc)"
              >
                ← back
              </button>
            ) : null
          }
        />

        {mode === "gallery" ? (
          <div className="flex" style={{ alignItems: "stretch" }}>
            <div className="flex flex-col" style={{ flex: 1, minWidth: 0 }}>
              <GridPane
                selection={selection}
                anchor={anchor}
                hoveredId={hoveredId}
                onHover={setHoveredId}
                onClick={onCardClick}
              />
              <StatusBar
                count={selection.size}
                anchor={anchorCapture}
                onClear={clearSelection}
                onOpenPreview={() => anchorCapture && setMode("preview")}
                onOpenMarkup={() => anchorCapture && setMode("markup")}
              />
            </div>
            <Inspector
              anchor={anchorCapture}
              multiCount={selection.size}
              onOpenPreview={() => anchorCapture && setMode("preview")}
              onOpenMarkup={() => anchorCapture && setMode("markup")}
            />
          </div>
        ) : mode === "preview" && anchorCapture ? (
          <PreviewView
            capture={anchorCapture}
            onClose={() => setMode("gallery")}
            onOpenMarkup={() => setMode("markup")}
          />
        ) : anchorCapture ? (
          <MarkupView capture={anchorCapture} onClose={() => setMode("gallery")} />
        ) : null}
      </div>
    </div>
  );
}

// ─── Grid pane ───────────────────────────────────────────────────────

function GridPane({
  selection,
  anchor,
  hoveredId,
  onHover,
  onClick,
}: {
  selection: Set<string>;
  anchor: string;
  hoveredId: string | null;
  onHover: (id: string | null) => void;
  onClick: (id: string, modifiers: { cmd: boolean; shift: boolean }) => void;
}) {
  return (
    <div
      style={{
        padding: 16,
        display: "grid",
        gridTemplateColumns: "repeat(3, 1fr)",
        gap: 12,
        background: T.rail,
        minHeight: 520,
        alignContent: "start",
      }}
    >
      {CAPTURES.map((c) => (
        <Card
          key={c.id}
          capture={c}
          isAnchor={c.id === anchor && selection.has(c.id)}
          isMulti={selection.has(c.id) && c.id !== anchor}
          isHovered={c.id === hoveredId}
          onHover={onHover}
          onClick={onClick}
        />
      ))}
    </div>
  );
}

// ─── Card — content first, hover-revealed ID ─────────────────────────

function Card({
  capture,
  isAnchor,
  isMulti,
  isHovered,
  onHover,
  onClick,
}: {
  capture: Capture;
  isAnchor: boolean;
  isMulti: boolean;
  isHovered: boolean;
  onHover: (id: string | null) => void;
  onClick: (id: string, modifiers: { cmd: boolean; shift: boolean }) => void;
}) {
  const ring =
    isAnchor ? T.amber : isMulti ? T.amberSoft : T.inkRuleS;
  const ringWidth = isAnchor ? 1.5 : isMulti ? 1 : 0.5;

  return (
    <button
      type="button"
      onMouseEnter={() => onHover(capture.id)}
      onMouseLeave={() => onHover(null)}
      onClick={(e) =>
        onClick(capture.id, {
          cmd: e.metaKey || e.ctrlKey,
          shift: e.shiftKey,
        })
      }
      style={{
        position: "relative",
        padding: 0,
        background: T.page,
        border: `${ringWidth}px solid ${ring}`,
        borderRadius: 4,
        aspectRatio: "4 / 3",
        boxShadow: isAnchor
          ? `0 0 0 3px ${T.amberFaint}`
          : isHovered
          ? "0 4px 12px rgba(0,0,0,0.10)"
          : "0 1px 2px rgba(0,0,0,0.04)",
        overflow: "hidden",
        cursor: "pointer",
        transition: "box-shadow 0.12s ease, border-color 0.12s ease",
        textAlign: "left",
      }}
    >
      <CardArtwork tone={capture.tone} />

      {/* Multi-select corner dot — small amber circle so the user knows
          a card is in the set without it stealing focus. */}
      {isMulti && (
        <span
          style={{
            position: "absolute",
            top: 6,
            right: 6,
            width: 7,
            height: 7,
            borderRadius: 999,
            background: T.amberDeep,
            boxShadow: `0 0 0 1.5px ${T.amberFaint}`,
          }}
        />
      )}

      {/* Anchor check — slightly larger ring around a filled amber dot.
          Only the anchor gets this; siblings get the smaller dot above. */}
      {isAnchor && (
        <span
          style={{
            position: "absolute",
            top: 5,
            right: 5,
            width: 12,
            height: 12,
            borderRadius: 999,
            background: T.amber,
            boxShadow: "0 0 0 2px rgba(255,255,255,0.85)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: "#fff",
            fontSize: 8.5,
            fontFamily: "ui-monospace, monospace",
            fontWeight: 700,
          }}
        >
          ✓
        </span>
      )}

      {/* Hover label — id only, lower-left. Fades in. No source badge,
          no dark gradient, no time. Quiet info that says "this is the
          one you're hovering" without dressing every card. */}
      <span
        style={{
          position: "absolute",
          left: 6,
          bottom: 4,
          fontFamily: "ui-monospace, monospace",
          fontSize: 8,
          letterSpacing: "0.18em",
          color: T.inkFainter,
          opacity: isHovered || isAnchor ? 1 : 0,
          transition: "opacity 0.12s ease",
          textTransform: "uppercase",
        }}
      >
        {capture.id}
      </span>

      {/* Annotated sliver — small amber tick on the leading edge if
          the capture's sidecar has markup. Lives outside the hover so
          you can scan the grid for already-annotated work. */}
      {capture.annotated && (
        <span
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            bottom: 0,
            width: 2,
            background: T.amberDeep,
            opacity: 0.55,
          }}
          title="Has markup layers"
        />
      )}
    </button>
  );
}

function CardArtwork({ tone }: { tone: Tone }) {
  if (tone === "log") {
    return (
      <div style={{ padding: 10 }}>
        {Array.from({ length: 7 }).map((_, i) => (
          <div
            key={i}
            style={{
              height: 3,
              background: i === 3 ? T.alert : T.inkFainter,
              opacity: i === 3 ? 0.55 : 0.28,
              borderRadius: 1,
              width: `${48 + ((i * 13) % 44)}%`,
              marginTop: 5,
            }}
          />
        ))}
      </div>
    );
  }
  if (tone === "table") {
    return (
      <div style={{ padding: 10 }}>
        {Array.from({ length: 5 }).map((_, r) => (
          <div key={r} className="flex" style={{ gap: 4, marginTop: 4 }}>
            {Array.from({ length: 4 }).map((_, c) => (
              <div
                key={c}
                style={{
                  flex: 1,
                  height: 6,
                  background: T.inkFainter,
                  opacity: r === 0 ? 0.38 : 0.22,
                  borderRadius: 1,
                }}
              />
            ))}
          </div>
        ))}
      </div>
    );
  }
  if (tone === "chat") {
    return (
      <div style={{ padding: 10, display: "flex", flexDirection: "column", gap: 6 }}>
        {[0, 1, 0, 1, 0].map((side, i) => (
          <div
            key={i}
            style={{
              alignSelf: side === 0 ? "flex-start" : "flex-end",
              width: `${42 + ((i * 7) % 25)}%`,
              height: 8,
              background: side === 0 ? T.inkFainter : T.amberFaint,
              opacity: 0.65,
              borderRadius: 3,
            }}
          />
        ))}
      </div>
    );
  }
  if (tone === "calendar") {
    return (
      <div style={{ padding: 10 }}>
        <div className="flex" style={{ gap: 4, marginBottom: 5 }}>
          {Array.from({ length: 7 }).map((_, i) => (
            <div
              key={i}
              style={{
                flex: 1,
                height: 4,
                background: T.inkFainter,
                opacity: 0.4,
                borderRadius: 1,
              }}
            />
          ))}
        </div>
        {Array.from({ length: 4 }).map((_, r) => (
          <div key={r} className="flex" style={{ gap: 4, marginTop: 4 }}>
            {Array.from({ length: 7 }).map((_, c) => (
              <div
                key={c}
                style={{
                  flex: 1,
                  height: 10,
                  background:
                    (r === 1 && c === 3) || (r === 2 && c === 5)
                      ? T.amberFaint
                      : T.inkFainter,
                  opacity:
                    (r === 1 && c === 3) || (r === 2 && c === 5) ? 0.9 : 0.18,
                  borderRadius: 1,
                }}
              />
            ))}
          </div>
        ))}
      </div>
    );
  }
  if (tone === "code") {
    return (
      <div style={{ padding: 10, display: "flex", flexDirection: "column", gap: 5 }}>
        {[0, 1, 2, 1, 2, 0, 1].map((indent, i) => (
          <div
            key={i}
            style={{
              marginLeft: indent * 9,
              height: 3,
              background: i % 3 === 1 ? T.brass : T.inkFainter,
              opacity: i % 3 === 1 ? 0.55 : 0.28,
              borderRadius: 1,
              width: `${42 + ((i * 11) % 30)}%`,
            }}
          />
        ))}
      </div>
    );
  }
  // doc
  return (
    <div style={{ padding: 10 }}>
      <div
        style={{
          height: 5,
          width: "58%",
          background: T.inkFainter,
          opacity: 0.42,
          borderRadius: 1,
          marginBottom: 7,
        }}
      />
      {Array.from({ length: 6 }).map((_, i) => (
        <div
          key={i}
          style={{
            height: 3,
            background: T.inkFainter,
            opacity: 0.28,
            borderRadius: 1,
            width: `${72 + ((i * 7) % 22)}%`,
            marginTop: 4,
          }}
        />
      ))}
    </div>
  );
}

// ─── Status bar — adapts to selection size ───────────────────────────

function StatusBar({
  count,
  anchor,
  onClear,
  onOpenPreview,
  onOpenMarkup,
}: {
  count: number;
  anchor: Capture | null;
  onClear: () => void;
  onOpenPreview: () => void;
  onOpenMarkup: () => void;
}) {
  if (count === 0) {
    return (
      <div
        className="flex items-center"
        style={{
          padding: "8px 14px",
          gap: 10,
          background: T.chrome,
          borderTop: `0.5px solid ${T.inkRuleS}`,
          height: 32,
        }}
      >
        <span
          className="font-mono uppercase tracking-[0.20em]"
          style={{ fontSize: 9, color: T.inkFainter }}
        >
          nothing selected · click a card to anchor
        </span>
        <span
          className="ml-auto font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFainter }}
        >
          ⌘-click multi · shift-click range
        </span>
      </div>
    );
  }

  if (count === 1 && anchor) {
    return (
      <div
        className="flex items-center"
        style={{
          padding: "8px 14px",
          gap: 10,
          background: T.chrome,
          borderTop: `0.5px solid ${T.inkRuleS}`,
          height: 32,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.20em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          1 selected
        </span>
        <span style={{ width: 1, height: 12, background: T.inkRuleS }} />
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFaint }}
        >
          {anchor.id} · {anchor.app ?? anchor.source}
        </span>
        <span className="ml-auto flex items-center" style={{ gap: 8 }}>
          <VerbButton label="preview" onClick={onOpenPreview} />
          <VerbButton label="markup" tone="primary" onClick={onOpenMarkup} />
          <Verb label="share" />
          <Verb label="reveal" />
          <Verb label="delete" tone="alert" />
          <button
            onClick={onClear}
            className="font-mono uppercase tracking-[0.18em]"
            style={{
              fontSize: 9,
              color: T.inkFainter,
              border: "none",
              background: "transparent",
              cursor: "pointer",
              padding: "3px 6px",
            }}
          >
            clear
          </button>
        </span>
      </div>
    );
  }

  // Bulk action mode — multi-select.
  return (
    <div
      className="flex items-center"
      style={{
        padding: "8px 14px",
        gap: 10,
        background: T.amberFaint,
        borderTop: `0.5px solid ${T.amberSoft}`,
        height: 32,
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.20em]"
        style={{ fontSize: 9, color: T.amberDeep }}
      >
        {count} selected
      </span>
      <span style={{ width: 1, height: 12, background: T.amberSoft }} />
      <span
        className="font-mono uppercase tracking-[0.18em]"
        style={{ fontSize: 9, color: T.amberDeep, opacity: 0.7 }}
      >
        bulk action
      </span>
      <span className="ml-auto flex items-center" style={{ gap: 8 }}>
        <Verb label="markup queue" tone="primary" />
        <Verb label="share" />
        <Verb label="delete" tone="alert" />
        <button
          onClick={onClear}
          className="font-mono uppercase tracking-[0.18em]"
          style={{
            fontSize: 9,
            color: T.amberDeep,
            border: "none",
            background: "transparent",
            cursor: "pointer",
            padding: "3px 6px",
            opacity: 0.7,
          }}
        >
          clear
        </button>
      </span>
    </div>
  );
}

// Clickable variant of Verb — fires onClick. Used for the markup CTA
// in single-select mode so the entire flow can be exercised from the
// status bar without going to the inspector.
function VerbButton({
  label,
  tone,
  onClick,
}: {
  label: string;
  tone?: "primary" | "alert";
  onClick: () => void;
}) {
  const color =
    tone === "primary"
      ? T.amberDeep
      : tone === "alert"
      ? T.alert
      : T.ink;
  const bg = tone === "primary" ? T.amberFaint : "transparent";
  const border =
    tone === "primary"
      ? T.amberSoft
      : tone === "alert"
      ? "rgba(208,58,28,0.30)"
      : T.inkRuleS;
  return (
    <button
      onClick={onClick}
      className="font-mono font-semibold uppercase tracking-[0.18em]"
      style={{
        fontSize: 9,
        color,
        padding: "3px 8px",
        background: bg,
        border: `0.5px solid ${border}`,
        borderRadius: 2,
        cursor: "pointer",
      }}
    >
      {label}
    </button>
  );
}

function Verb({
  label,
  tone,
}: {
  label: string;
  tone?: "primary" | "alert";
}) {
  const color =
    tone === "primary"
      ? T.amberDeep
      : tone === "alert"
      ? T.alert
      : T.ink;
  const bg = tone === "primary" ? T.amberFaint : "transparent";
  const border =
    tone === "primary"
      ? T.amberSoft
      : tone === "alert"
      ? "rgba(208,58,28,0.30)"
      : T.inkRuleS;
  return (
    <span
      className="font-mono font-semibold uppercase tracking-[0.18em]"
      style={{
        fontSize: 9,
        color,
        padding: "3px 8px",
        background: bg,
        border: `0.5px solid ${border}`,
        borderRadius: 2,
        cursor: "default",
      }}
    >
      {label}
    </span>
  );
}

// ─── Inspector — reacts to the anchor ────────────────────────────────

function Inspector({
  anchor,
  multiCount,
  onOpenPreview,
  onOpenMarkup,
}: {
  anchor: Capture | null;
  multiCount: number;
  onOpenPreview: () => void;
  onOpenMarkup: () => void;
}) {
  return (
    <aside
      style={{
        width: 280,
        flexShrink: 0,
        borderLeft: `0.5px solid ${T.inkRuleS}`,
        background: T.pane,
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        className="flex items-center"
        style={{
          height: 28,
          padding: "0 12px",
          background: T.chrome,
          borderBottom: `0.5px solid ${T.inkRuleS}`,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.22em]"
          style={{ fontSize: 9, color: T.inkFaint }}
        >
          · inspector
        </span>
        {multiCount > 1 && (
          <span
            className="ml-auto font-mono font-semibold uppercase tracking-[0.20em]"
            style={{ fontSize: 8.5, color: T.amberDeep }}
          >
            {multiCount} selected
          </span>
        )}
      </div>

      {anchor ? (
        <div style={{ padding: 14, display: "flex", flexDirection: "column", gap: 14 }}>
          {/* LargePreview — a denser render of the capture's content
              than the grid tile, with faux app chrome (title bar +
              traffic lights). Reads as "the actual screenshot," not
              the tile zoomed up. */}
          <LargePreview capture={anchor} />

          <div>
            <div
              className="font-mono font-semibold uppercase tracking-[0.20em]"
              style={{ fontSize: 9.5, color: T.ink }}
            >
              {anchor.id}
            </div>
            <div
              className="font-display"
              style={{ fontSize: 12, color: T.inkMid, marginTop: 2 }}
            >
              {anchor.app ?? "—"} · captured {anchor.ageLabel} ago
            </div>
          </div>

          <div className="flex flex-col" style={{ gap: 4 }}>
            <MetaRow label="source" value={anchor.source} />
            <MetaRow label="dimensions" value={anchor.dims} />
            <MetaRow label="size" value={anchor.bytes} />
            <MetaRow
              label="layers"
              value={anchor.annotated ? "yes · sidecar" : "—"}
              accent={anchor.annotated}
            />
          </div>

          {/* Open destinations — the two ways out of the gallery, side by
              side so the choice is legible. Preview = read-only Quick Look
              (system). Markup = the app's annotate editor (hero, amber). */}
          <div className="flex flex-col" style={{ gap: 8, marginTop: 2 }}>
            <span
              className="font-mono uppercase tracking-[0.20em]"
              style={{ fontSize: 8.5, color: T.inkFainter }}
            >
              open
            </span>
            <div className="flex" style={{ gap: 6 }}>
              <OpenButton label="Preview" glyph="◹" onClick={onOpenPreview} />
              <OpenButton label="Markup" glyph="✎" tone="primary" onClick={onOpenMarkup} />
            </div>
            <SecondaryCTA label="Reveal in Finder" />
            <SecondaryCTA label="Copy to clipboard" />
          </div>
        </div>
      ) : (
        <div style={{ padding: 18 }}>
          <p
            className="font-display italic"
            style={{ fontSize: 12, color: T.inkFaint, lineHeight: 1.55 }}
          >
            Nothing selected. Click a card to make it the anchor — the
            inspector shows its metadata and the two open destinations
            (Preview · Markup).
          </p>
        </div>
      )}
    </aside>
  );
}

function MetaRow({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between" style={{ gap: 10 }}>
      <span
        className="font-mono uppercase tracking-[0.20em]"
        style={{ fontSize: 9, color: T.inkFainter }}
      >
        {label}
      </span>
      <span
        className="font-mono"
        style={{
          fontSize: 11,
          color: accent ? T.amberDeep : T.ink,
          letterSpacing: "0.04em",
        }}
      >
        {value}
      </span>
    </div>
  );
}

// OpenButton — one of the two open destinations in the inspector. The
// primary tone (Markup) fills amber; the neutral tone (Preview) is an
// outlined card. Equal width so the pair reads as a clean choice.
function OpenButton({
  label,
  glyph,
  tone,
  onClick,
}: {
  label: string;
  glyph: string;
  tone?: "primary";
  onClick?: () => void;
}) {
  const primary = tone === "primary";
  return (
    <button
      onClick={onClick}
      className="flex items-center justify-center"
      style={{
        flex: 1,
        gap: 6,
        background: primary ? T.amber : T.page,
        color: primary ? "#fff" : T.inkMid,
        border: primary ? "none" : `0.5px solid ${T.inkRule}`,
        borderRadius: 3,
        padding: "9px 10px",
        cursor: "pointer",
        fontFamily: "ui-monospace, monospace",
        fontSize: 10,
        fontWeight: 600,
        textTransform: "uppercase",
        letterSpacing: "0.16em",
      }}
    >
      <span style={{ fontSize: 12, lineHeight: 1 }}>{glyph}</span>
      {label}
    </button>
  );
}

function SecondaryCTA({ label }: { label: string }) {
  return (
    <button
      style={{
        background: "transparent",
        color: T.inkMid,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 3,
        padding: "7px 12px",
        textAlign: "left",
        cursor: "pointer",
        fontFamily: "ui-monospace, monospace",
        fontSize: 10,
        fontWeight: 500,
        textTransform: "uppercase",
        letterSpacing: "0.18em",
      }}
    >
      {label}
    </button>
  );
}

// ─── LargePreview — denser render for the inspector ──────────────────
//
// The grid tile's CardArtwork is tuned for a 4:3 ~120pt cell; reusing
// it at inspector size reads as a stretched thumbnail. LargePreview
// adds faux app chrome (title bar with traffic lights + app name) and
// roughly doubles the content density so it reads as "looking at the
// actual screenshot," not "the tile, but bigger."

function LargePreview({ capture }: { capture: Capture }) {
  return (
    <div
      style={{
        aspectRatio: "4 / 3",
        background: T.page,
        borderRadius: 4,
        border: `0.5px solid ${T.inkRule}`,
        overflow: "hidden",
        boxShadow:
          "0 1px 0 rgba(255,255,255,0.6) inset, 0 8px 18px rgba(0,0,0,0.10)",
        position: "relative",
      }}
    >
      {/* Faux captured-app chrome */}
      <div
        className="flex items-center"
        style={{
          height: 16,
          padding: "0 6px",
          gap: 4,
          background: "#eceae6",
          borderBottom: `0.5px solid rgba(0,0,0,0.06)`,
        }}
      >
        <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
        <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
        <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
        <span
          className="ml-auto font-mono"
          style={{ fontSize: 7, color: T.inkFainter, letterSpacing: "0.12em" }}
        >
          {(capture.app ?? "Capture").toUpperCase()}
        </span>
      </div>
      <DenseArtwork tone={capture.tone} />
      {capture.annotated && (
        <span
          style={{
            position: "absolute",
            left: 6,
            top: 22,
            padding: "1px 5px",
            background: T.amberDeep,
            color: "#fff",
            fontFamily: "ui-monospace, monospace",
            fontSize: 7,
            letterSpacing: "0.16em",
            borderRadius: 1,
            textTransform: "uppercase",
          }}
        >
          markup
        </span>
      )}
    </div>
  );
}

function DenseArtwork({ tone }: { tone: Tone }) {
  if (tone === "log") {
    return (
      <div style={{ padding: "10px 12px" }}>
        {Array.from({ length: 12 }).map((_, i) => (
          <div
            key={i}
            style={{
              height: 3,
              background: i === 5 ? T.alert : T.inkFainter,
              opacity: i === 5 ? 0.7 : 0.3,
              borderRadius: 1,
              width: `${44 + ((i * 17) % 48)}%`,
              marginTop: 4,
            }}
          />
        ))}
      </div>
    );
  }
  if (tone === "table") {
    return (
      <div style={{ padding: "10px 12px" }}>
        <div className="flex" style={{ gap: 4 }}>
          {Array.from({ length: 5 }).map((_, c) => (
            <div
              key={c}
              style={{
                flex: 1,
                height: 5,
                background: T.inkFainter,
                opacity: 0.45,
                borderRadius: 1,
              }}
            />
          ))}
        </div>
        {Array.from({ length: 8 }).map((_, r) => (
          <div key={r} className="flex" style={{ gap: 4, marginTop: 4 }}>
            {Array.from({ length: 5 }).map((_, c) => (
              <div
                key={c}
                style={{
                  flex: 1,
                  height: 5,
                  background: T.inkFainter,
                  opacity: 0.22,
                  borderRadius: 1,
                }}
              />
            ))}
          </div>
        ))}
      </div>
    );
  }
  if (tone === "chat") {
    return (
      <div style={{ padding: "10px 12px", display: "flex", flexDirection: "column", gap: 6 }}>
        {[0, 1, 0, 1, 0, 1, 0].map((side, i) => (
          <div
            key={i}
            style={{
              alignSelf: side === 0 ? "flex-start" : "flex-end",
              width: `${42 + ((i * 11) % 32)}%`,
              height: 9,
              background: side === 0 ? T.inkFainter : T.amberFaint,
              opacity: 0.7,
              borderRadius: 4,
            }}
          />
        ))}
      </div>
    );
  }
  if (tone === "calendar") {
    return (
      <div style={{ padding: "10px 12px" }}>
        <div className="flex" style={{ gap: 4, marginBottom: 5 }}>
          {["S","M","T","W","T","F","S"].map((d, i) => (
            <span
              key={i}
              className="font-mono"
              style={{
                flex: 1,
                textAlign: "center",
                fontSize: 7,
                color: T.inkFainter,
                letterSpacing: "0.1em",
              }}
            >
              {d}
            </span>
          ))}
        </div>
        {Array.from({ length: 5 }).map((_, r) => (
          <div key={r} className="flex" style={{ gap: 4, marginTop: 4 }}>
            {Array.from({ length: 7 }).map((_, c) => {
              const isAccent = (r === 1 && c === 3) || (r === 2 && c === 5) || (r === 3 && c === 1);
              return (
                <div
                  key={c}
                  style={{
                    flex: 1,
                    height: 12,
                    background: isAccent ? T.amberFaint : T.inkFainter,
                    opacity: isAccent ? 0.9 : 0.18,
                    borderRadius: 1,
                  }}
                />
              );
            })}
          </div>
        ))}
      </div>
    );
  }
  if (tone === "code") {
    return (
      <div style={{ padding: "10px 12px", display: "flex", flexDirection: "column", gap: 5 }}>
        {[0, 1, 2, 2, 1, 2, 3, 2, 1, 0, 1].map((indent, i) => (
          <div
            key={i}
            style={{
              marginLeft: indent * 10,
              height: 3,
              background: i % 3 === 1 ? T.brass : T.inkFainter,
              opacity: i % 3 === 1 ? 0.6 : 0.3,
              borderRadius: 1,
              width: `${42 + ((i * 9) % 32)}%`,
            }}
          />
        ))}
      </div>
    );
  }
  // doc
  return (
    <div style={{ padding: "10px 12px" }}>
      <div
        style={{
          height: 6,
          width: "62%",
          background: T.inkFainter,
          opacity: 0.5,
          borderRadius: 1,
          marginBottom: 7,
        }}
      />
      {Array.from({ length: 10 }).map((_, i) => (
        <div
          key={i}
          style={{
            height: 3,
            background: T.inkFainter,
            opacity: 0.3,
            borderRadius: 1,
            width: `${68 + ((i * 7) % 26)}%`,
            marginTop: 4,
          }}
        />
      ))}
    </div>
  );
}

// ─── PreviewView — clean Quick Look (read-only) ──────────────────────
//
// What "Open in Preview" lands on. Deliberately quiet: no toolbar, no
// style stack, no composer — just the screenshot, centered and large,
// on a calm backdrop. The only chrome is a floating action cluster
// (Markup · Share · Reveal) and a thin metadata footer. Markup is the
// escalation from here, exactly as macOS Quick Look surfaces it.

function PreviewView({
  capture,
  onClose,
  onOpenMarkup,
}: {
  capture: Capture;
  onClose: () => void;
  onOpenMarkup: () => void;
}) {
  return (
    <div className="flex flex-col" style={{ background: T.page }}>
      <div
        style={{
          position: "relative",
          background: T.rail,
          padding: 36,
          minHeight: 460,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {/* The screenshot — image-forward, no annotation overlay. */}
        <div style={{ width: "78%", maxWidth: 720 }}>
          <div
            style={{
              position: "relative",
              aspectRatio: "4 / 3",
              background: T.page,
              borderRadius: 5,
              border: `0.5px solid ${T.inkRule}`,
              boxShadow:
                "0 1px 0 rgba(255,255,255,0.6) inset, 0 18px 44px -12px rgba(0,0,0,0.22)",
              overflow: "hidden",
            }}
          >
            <div
              className="flex items-center"
              style={{
                height: 18,
                padding: "0 8px",
                gap: 4,
                background: "#eceae6",
                borderBottom: `0.5px solid rgba(0,0,0,0.06)`,
              }}
            >
              <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
              <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
              <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
              <span
                className="ml-auto font-mono"
                style={{ fontSize: 7.5, color: T.inkFainter, letterSpacing: "0.14em" }}
              >
                {(capture.app ?? "Capture").toUpperCase()}
              </span>
            </div>
            <DenseArtwork tone={capture.tone} />
            {capture.annotated && (
              <span
                style={{
                  position: "absolute",
                  left: 8,
                  top: 26,
                  padding: "1px 5px",
                  background: T.amberDeep,
                  color: "#fff",
                  fontFamily: "ui-monospace, monospace",
                  fontSize: 7,
                  letterSpacing: "0.16em",
                  borderRadius: 1,
                  textTransform: "uppercase",
                }}
              >
                markup
              </span>
            )}
          </div>
        </div>

        {/* Floating Quick Look action cluster — Markup is the hero, with
            Share + Reveal as quiet siblings. */}
        <div
          className="flex items-center"
          style={{
            position: "absolute",
            bottom: 18,
            left: "50%",
            transform: "translateX(-50%)",
            gap: 2,
            padding: 4,
            background: "#fff",
            border: `0.5px solid ${T.inkRule}`,
            borderRadius: 8,
            boxShadow:
              "0 1px 0 rgba(255,255,255,0.55) inset, 0 6px 18px rgba(0,0,0,0.14)",
          }}
        >
          <button
            onClick={onOpenMarkup}
            className="flex items-center font-mono font-semibold uppercase tracking-[0.16em]"
            style={{
              gap: 6,
              fontSize: 9.5,
              color: "#fff",
              background: T.amber,
              border: "none",
              borderRadius: 5,
              padding: "7px 12px",
              cursor: "pointer",
            }}
          >
            <span style={{ fontSize: 12, lineHeight: 1 }}>✎</span>
            markup
          </button>
          <QuickLookVerb label="share" glyph="↗" />
          <QuickLookVerb label="reveal" glyph="◳" />
        </div>
      </div>

      {/* Footer rail — metadata + done, matching MarkupView's footer so
          the two destinations feel like one window. */}
      <div
        className="flex items-center"
        style={{
          padding: "6px 14px",
          gap: 10,
          background: T.chrome,
          borderTop: `0.5px solid ${T.inkRuleS}`,
          height: 30,
        }}
      >
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFainter }}
        >
          {capture.id} · {capture.source} · {capture.dims} · {capture.bytes}
        </span>
        <button
          onClick={onClose}
          className="ml-auto font-mono font-semibold uppercase tracking-[0.18em]"
          style={{
            fontSize: 9,
            color: T.inkFaint,
            background: "transparent",
            border: `0.5px solid ${T.inkRule}`,
            borderRadius: 3,
            padding: "4px 10px",
            cursor: "pointer",
          }}
        >
          done · back to screenshots
        </button>
      </div>
    </div>
  );
}

function QuickLookVerb({ label, glyph }: { label: string; glyph: string }) {
  return (
    <span
      className="flex items-center font-mono uppercase tracking-[0.16em]"
      style={{
        gap: 5,
        fontSize: 9,
        color: T.inkFaint,
        background: "transparent",
        borderRadius: 5,
        padding: "7px 10px",
        cursor: "default",
      }}
    >
      <span style={{ fontSize: 11, lineHeight: 1 }}>{glyph}</span>
      {label}
    </span>
  );
}

// ─── MarkupView — interactive open-in-markup surface ─────────────────
//
// Lives inside the same window as the gallery — replaces the gallery
// body when the user clicks "Open in Markup." Tool selection and style
// stack are stateful (clickable, visual feedback). No actual drawing
// on the canvas yet — the canvas is the LargePreview with a single
// pre-annotated rect to show what a layer looks like.

const MARKUP_TOOLS: { id: string; glyph: string; label: string }[] = [
  { id: "rect",  glyph: "▢", label: "Rect"  },
  { id: "arrow", glyph: "↗", label: "Arrow" },
  { id: "line",  glyph: "—", label: "Line"  },
  { id: "text",  glyph: "T", label: "Text"  },
  { id: "blur",  glyph: "▒", label: "Blur"  },
];

function MarkupView({
  capture,
  onClose,
}: {
  capture: Capture;
  onClose: () => void;
}) {
  const [activeTool, setActiveTool] = useState<string | null>("rect");
  const [strokeWidth, setStrokeWidth] = useState<number>(2);
  const [color, setColor] = useState<string>(T.amber);

  return (
    <div className="flex flex-col" style={{ background: T.page }}>
      <MarkupToolbar
        activeTool={activeTool}
        onTool={(t) => setActiveTool(activeTool === t ? null : t)}
        strokeWidth={strokeWidth}
        onStrokeWidth={setStrokeWidth}
        color={color}
        onColor={setColor}
      />

      {/* Canvas — large preview with annotation overlay + floating
          zoom cluster. Closer to the markup window than to a tile. */}
      <div
        style={{
          position: "relative",
          background: T.rail,
          padding: 26,
          minHeight: 420,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div style={{ width: "82%", maxWidth: 760 }}>
          <CanvasWithAnnotation capture={capture} color={color} strokeWidth={strokeWidth} />
        </div>
        <ZoomCluster />
      </div>

      {/* Speak strip — selection bar above mic + prompt + run. Mirrors
          the studio MacCaptureMarkup pattern. */}
      <SpeakStrip capture={capture} />

      {/* Footer rail — back button always visible, in addition to the
          chrome trailing button. */}
      <div
        className="flex items-center"
        style={{
          padding: "6px 14px",
          gap: 10,
          background: T.chrome,
          borderTop: `0.5px solid ${T.inkRuleS}`,
          height: 30,
        }}
      >
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFainter }}
        >
          {capture.id} · annotation autosaves · sidecar JSON
        </span>
        <button
          onClick={onClose}
          className="ml-auto font-mono font-semibold uppercase tracking-[0.18em]"
          style={{
            fontSize: 9,
            color: T.amberDeep,
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            borderRadius: 3,
            padding: "4px 10px",
            cursor: "pointer",
          }}
        >
          done · back to screenshots
        </button>
      </div>
    </div>
  );
}

function MarkupToolbar({
  activeTool,
  onTool,
  strokeWidth,
  onStrokeWidth,
  color,
  onColor,
}: {
  activeTool: string | null;
  onTool: (t: string) => void;
  strokeWidth: number;
  onStrokeWidth: (w: number) => void;
  color: string;
  onColor: (c: string) => void;
}) {
  const widths = [1, 2, 3, 5];
  const colors = [T.ink, T.alert, T.amber, T.brass, "#FFFFFF"];

  return (
    <div
      className="flex items-center"
      style={{
        height: 40,
        padding: "0 10px",
        gap: 4,
        background: T.chrome,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      {MARKUP_TOOLS.map((t) => {
        const on = t.id === activeTool;
        return (
          <button
            key={t.id}
            onClick={() => onTool(t.id)}
            className="flex items-center"
            style={{
              gap: 5,
              height: 26,
              padding: "0 8px",
              borderRadius: 3,
              background: on ? T.amberFaint : "transparent",
              border: on ? `0.5px solid ${T.amberSoft}` : "0.5px solid transparent",
              color: on ? T.amberDeep : T.inkFaint,
              cursor: "pointer",
            }}
          >
            <span className="font-mono" style={{ fontSize: 12 }}>
              {t.glyph}
            </span>
            <span
              className="font-mono uppercase tracking-[0.16em]"
              style={{ fontSize: 9 }}
            >
              {t.label}
            </span>
          </button>
        );
      })}

      <span style={{ width: 1, height: 20, background: T.inkRuleS, margin: "0 6px" }} />

      {/* Style stack — width pips + color swatches. Clickable, live. */}
      <span
        className="font-mono uppercase tracking-[0.20em]"
        style={{ fontSize: 8.5, color: T.inkFainter }}
      >
        width
      </span>
      <span className="flex items-center" style={{ gap: 3, marginLeft: 4 }}>
        {widths.map((w) => {
          const on = w === strokeWidth;
          return (
            <button
              key={w}
              onClick={() => onStrokeWidth(w)}
              style={{
                width: 22,
                height: 22,
                borderRadius: 3,
                background: on ? T.amberFaint : "transparent",
                border: on ? `0.5px solid ${T.amberSoft}` : `0.5px solid ${T.inkRuleS}`,
                cursor: "pointer",
                display: "inline-flex",
                alignItems: "center",
                justifyContent: "center",
                padding: 0,
              }}
            >
              <span
                style={{
                  display: "block",
                  width: 14,
                  height: w,
                  background: on ? T.amberDeep : T.inkFaint,
                  borderRadius: 1,
                }}
              />
            </button>
          );
        })}
      </span>

      <span style={{ width: 1, height: 14, background: T.inkRuleS, margin: "0 8px" }} />

      <span
        className="font-mono uppercase tracking-[0.20em]"
        style={{ fontSize: 8.5, color: T.inkFainter }}
      >
        color
      </span>
      <span className="flex items-center" style={{ gap: 3, marginLeft: 4 }}>
        {colors.map((c) => {
          const on = c === color;
          return (
            <button
              key={c}
              onClick={() => onColor(c)}
              style={{
                width: 16,
                height: 16,
                borderRadius: 999,
                background: c,
                border: c === "#FFFFFF" ? `0.5px solid ${T.inkRule}` : "none",
                outline: on ? `1.5px solid ${T.amberDeep}` : "none",
                outlineOffset: 1,
                cursor: "pointer",
                padding: 0,
                boxShadow: on
                  ? `0 0 0 2px ${T.amberFaint}`
                  : "0 1px 0 rgba(255,255,255,0.45) inset",
              }}
              title={c}
            />
          );
        })}
      </span>
    </div>
  );
}

function CanvasWithAnnotation({
  capture,
  color,
  strokeWidth,
}: {
  capture: Capture;
  color: string;
  strokeWidth: number;
}) {
  return (
    <div
      style={{
        position: "relative",
        aspectRatio: "4 / 3",
        background: T.page,
        borderRadius: 4,
        border: `0.5px solid ${T.inkRule}`,
        boxShadow: "0 6px 18px rgba(0,0,0,0.10)",
        overflow: "hidden",
      }}
    >
      <div
        className="flex items-center"
        style={{
          height: 18,
          padding: "0 8px",
          gap: 4,
          background: "#eceae6",
          borderBottom: `0.5px solid rgba(0,0,0,0.06)`,
        }}
      >
        <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
        <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
        <span style={{ width: 5, height: 5, borderRadius: 999, background: "#ddd" }} />
        <span
          className="ml-auto font-mono"
          style={{ fontSize: 7.5, color: T.inkFainter, letterSpacing: "0.14em" }}
        >
          {(capture.app ?? "Capture").toUpperCase()}
        </span>
      </div>
      <DenseArtwork tone={capture.tone} />

      {/* The drawn annotation — uses live color + strokeWidth from the
          toolbar so the user can see their picks land on a real layer. */}
      <div
        style={{
          position: "absolute",
          left: "8%",
          top: "44%",
          width: "78%",
          height: 14,
          border: `${strokeWidth}px solid ${color}`,
          borderRadius: 2,
          background: `${color}11`,
          transition: "border-color 0.12s ease, border-width 0.12s ease",
        }}
      />
      <span
        className="font-mono uppercase tracking-[0.18em]"
        style={{
          position: "absolute",
          left: "8%",
          top: "33%",
          fontSize: 8,
          padding: "2px 5px",
          background: "rgba(20,24,30,0.84)",
          color: "#fff",
          borderRadius: 1,
        }}
      >
        LAYER · L1
      </span>
    </div>
  );
}

function ZoomCluster() {
  return (
    <div
      className="flex items-center"
      style={{
        position: "absolute",
        bottom: 16,
        right: 16,
        gap: 1,
        padding: 3,
        background: "#fff",
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 5,
        boxShadow:
          "0 1px 0 rgba(255,255,255,0.55) inset, 0 4px 12px rgba(0,0,0,0.10)",
      }}
    >
      <span
        className="flex items-center justify-center font-mono"
        style={{ width: 22, height: 22, fontSize: 12, color: T.inkFaint }}
      >
        −
      </span>
      <span
        className="font-mono tabular-nums"
        style={{ fontSize: 9.5, color: T.inkMid, padding: "0 4px", minWidth: 38, textAlign: "center" }}
      >
        100%
      </span>
      <span
        className="flex items-center justify-center font-mono"
        style={{ width: 22, height: 22, fontSize: 12, color: T.inkFaint }}
      >
        +
      </span>
      <span style={{ width: 1, height: 14, background: T.inkRuleS, margin: "0 2px" }} />
      <span
        className="font-mono font-semibold uppercase tracking-[0.16em]"
        style={{ padding: "0 7px", fontSize: 8.5, color: T.inkFaint }}
      >
        FIT
      </span>
    </div>
  );
}

function SpeakStrip({ capture }: { capture: Capture }) {
  return (
    <div
      style={{
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        padding: "10px 14px",
      }}
    >
      {/* Selection bar — scope strip above the composer. */}
      <div
        className="flex items-stretch"
        style={{
          marginBottom: 8,
          background: T.pane,
          border: `0.5px solid ${T.inkRule}`,
          borderRadius: 3,
          overflow: "hidden",
        }}
      >
        <span style={{ width: 3, background: T.amber }} />
        <div className="flex items-center" style={{ flex: 1, padding: "5px 10px", gap: 8 }}>
          <span
            className="font-mono uppercase tracking-[0.20em]"
            style={{ fontSize: 9, color: T.inkFainter }}
          >
            · scope
          </span>
          <span
            className="font-mono font-semibold uppercase tracking-[0.16em]"
            style={{
              fontSize: 9,
              color: T.amberDeep,
              padding: "1px 5px",
              background: T.amberFaint,
              border: `0.5px solid ${T.amberSoft}`,
              borderRadius: 2,
            }}
          >
            {capture.id}
          </span>
          <span
            className="font-display"
            style={{ fontSize: 12, color: T.ink, fontWeight: 500 }}
          >
            {capture.app ?? capture.source} · {capture.dims}
          </span>
        </div>
      </div>

      {/* Mic + prompt + run */}
      <div className="flex items-center" style={{ gap: 10 }}>
        <span
          className="flex items-center justify-center"
          style={{
            width: 32,
            height: 32,
            borderRadius: 999,
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            color: T.amberDeep,
            flexShrink: 0,
          }}
        >
          <svg width={14} height={14} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round" strokeLinejoin="round">
            <rect x="6" y="2" width="4" height="7.5" rx="2" />
            <path d="M3.5 8 A 4.5 4.5 0 0 0 12.5 8" />
            <line x1="8" y1="12.5" x2="8" y2="14" />
            <line x1="5.5" y1="14" x2="10.5" y2="14" />
          </svg>
        </span>
        <div
          className="flex items-center"
          style={{
            flex: 1,
            background: T.page,
            border: `0.5px solid ${T.inkRule}`,
            borderRadius: 4,
            height: 32,
            padding: "0 12px",
            gap: 6,
          }}
        >
          <span
            className="font-display italic"
            style={{ fontSize: 12, color: T.inkFainter }}
          >
            tell the agent what to mark up…
          </span>
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 14,
              background: T.amber,
              animation: "promptcaret 1s steps(2) infinite",
            }}
          />
        </div>
        <button
          className="font-mono font-semibold uppercase tracking-[0.18em]"
          style={{
            background: T.amber,
            color: "#fff",
            padding: "8px 14px",
            border: "none",
            borderRadius: 3,
            fontSize: 9.5,
            cursor: "pointer",
          }}
        >
          run ⌘↵
        </button>
      </div>
      <style jsx>{`
        @keyframes promptcaret {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0; }
        }
      `}</style>
    </div>
  );
}

// ─── Vocabulary ──────────────────────────────────────────────────────

function NamesMarginalia() {
  const entries: [string, string][] = [
    ["Anchor",           "the single capture last plain-clicked. Drives the inspector."],
    ["Extended Set",     "the anchor + any ⌘-toggled or shift-range siblings."],
    ["Open Destinations","the inspector's Preview / Markup pair — read-only viewer vs. annotate editor."],
    ["Quick Look",       "the clean Preview surface. Image-forward, no toolbar; Markup is the escalation."],
    ["Bulk Action Bar",  "status bar's multi-select mode. Markup queue / share / delete."],
    ["Hover Reveal",     "card ID fades in on hover only. Quiet at rest."],
    ["Annotated Sliver", "amber tick on the card's leading edge when the sidecar has markup."],
    ["Inspector",        "right rail. Reacts to the anchor; collapses to a hint when empty."],
  ];
  return (
    <div style={{ padding: "28px 40px 4px 40px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.30em]"
          style={{ color: T.amber, fontSize: 9.5 }}
        >
          · names
        </span>
        <span
          className="font-display italic"
          style={{ color: T.inkFaint, fontSize: 12 }}
        >
          parts that show up across selection + chrome
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: T.inkRuleS }} />
      </div>
      <div
        style={{
          marginTop: 14,
          padding: "14px 18px 16px 18px",
          background: T.pane,
          border: `0.5px solid ${T.inkRuleS}`,
          borderRadius: 6,
          display: "grid",
          gridTemplateColumns: "180px 1fr",
          rowGap: 6,
          columnGap: 18,
        }}
      >
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span
              className="font-mono font-semibold uppercase tracking-[0.16em]"
              style={{ fontSize: 10, color: T.amberDeep }}
            >
              {name}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}
            >
              {def}
            </span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

// ─── Shared bits ─────────────────────────────────────────────────────

function WindowChrome({
  title,
  subtitle,
  trailing,
}: {
  title: string;
  subtitle?: string;
  trailing?: React.ReactNode;
}) {
  return (
    <div
      className="flex items-center"
      style={{
        height: 30,
        padding: "0 12px",
        gap: 8,
        background: T.chrome,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      <span className="flex items-center" style={{ gap: 4 }}>
        <span style={{ width: 8, height: 8, borderRadius: 999, background: "#FF5F57" }} />
        <span style={{ width: 8, height: 8, borderRadius: 999, background: "#FEBC2E" }} />
        <span style={{ width: 8, height: 8, borderRadius: 999, background: "#28C840" }} />
      </span>
      <span
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{ fontSize: 9, color: T.ink, marginLeft: 6 }}
      >
        {title}
      </span>
      {subtitle && (
        <span
          className="font-mono uppercase tracking-[0.16em]"
          style={{ fontSize: 8.5, color: T.inkFaint, marginLeft: 10 }}
        >
          {subtitle}
        </span>
      )}
      {trailing && (
        <span className="ml-auto flex items-center" style={{ gap: 6 }}>
          {trailing}
        </span>
      )}
    </div>
  );
}

function Chip({ label }: { label: string }) {
  return (
    <span
      className="font-mono uppercase tracking-[0.22em]"
      style={{
        fontSize: 9,
        fontWeight: 600,
        color: T.inkFaint,
        border: `1px solid ${T.inkRule}`,
        padding: "3px 8px",
        borderRadius: 2,
      }}
    >
      {label}
    </span>
  );
}
