"use client";

/**
 * MacCaptureFlow — the screenshot's journey, told as an editorial
 * walkthrough rather than a flat row of small mocks.
 *
 * Shape:
 *
 *   1. StudyHeader              — the narrative setup. Who, why, in what mood.
 *   2. LoopDiagram              — small cycle that compresses the whole flow
 *                                 into one image: capture → library → screenshots
 *                                 → markup → back to library.
 *   3. WhyThreeSurfaces         — the division-of-labor argument. Each surface
 *                                 earns its place by owning a different job.
 *   4. JourneyTimeline (Acts 1-5) — the vertical walkthrough. Each Act gets a
 *                                 scene caption, a generously-sized panel, and
 *                                 right-margin annotations describing the state
 *                                 transition (what gets selected, what
 *                                 persists, what the next gesture is).
 *   5. AlternatePath            — the bulk-select flow, which diverges from
 *                                 the canonical path at Act 3.
 *   6. NamesMarginalia          — vocabulary shared across studio / Swift / chat.
 *   7. StudyFooter              — provenance + how to reach each surface for
 *                                 the full version.
 */

import React from "react";
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

const KIND_COLOR = {
  memo:    "#9A6A22",
  dict:    "#E89A3C",
  note:    "#767674",
  capture: "#5C5E5C",
};

// ─── Composition root ────────────────────────────────────────────────

export function MacCaptureFlow() {
  return (
    <div style={{ width: 1180, background: T.page }} className="flex flex-col">
      <StudyHeader />
      <WhyThreeSurfaces />
      <JourneyTimeline />
      <AlternatePath />
      <NamesMarginalia />
      <StudyFooter />
    </div>
  );
}

// ─── Study header ────────────────────────────────────────────────────

function StudyHeader() {
  return (
    <div style={{ padding: "24px 40px 18px 40px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.32em]"
          style={{ color: T.inkFaint, fontSize: 9 }}
        >
          · CAPTURE FLOW · the round trip
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>
          one screenshot, four surfaces, ninety seconds
        </span>
        <div className="ml-auto">
          <Chip label="STORYBOARD" />
        </div>
      </div>
      <h2
        className="font-display tracking-tight"
        style={{ color: T.ink, fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 10 }}
      >
        Capture Flow
      </h2>
      <p
        className="font-display"
        style={{
          color: T.inkMid,
          fontSize: 14.5,
          lineHeight: 1.65,
          marginTop: 12,
          maxWidth: 720,
        }}
      >
        A screenshot lives across four surfaces. It is born in the
        <Em> Capture HUD</Em>, settles into the <Em>Library</Em>
        alongside memos and dictations, gets its own gallery in the
        <Em> Screenshots</Em> view when the work is visual, and goes
        into the <Em>Markup window</Em> when it needs annotation.
        Then it loops back to the Library carrying its sidecar of
        layers — same object, now richer.
      </p>
      <p
        className="font-display italic"
        style={{
          color: T.inkFaint,
          fontSize: 13,
          lineHeight: 1.6,
          marginTop: 10,
          maxWidth: 720,
        }}
      >
        This study is the walk between those surfaces. Each one is
        already its own study; this one argues the journey.
      </p>
    </div>
  );
}

function Em({ children }: { children: React.ReactNode }) {
  return (
    <span style={{ color: T.ink, fontStyle: "normal", fontWeight: 500 }}>
      {children}
    </span>
  );
}

// ─── Division of labor ───────────────────────────────────────────────

function WhyThreeSurfaces() {
  const surfaces: { name: string; owns: string; not: string; tone: string }[] = [
    {
      name: "Library",
      owns: "Cross-content browse, search, recall. The neutral home where every kind of object lives.",
      not: "Not a visual surface. Lists, not grids. If the work is visual, the Library hands off.",
      tone: T.brass,
    },
    {
      name: "Screenshots",
      owns: "Visual triage. Browse a wall of captures, multi-select for batch action, send several to markup at once.",
      not: "Not the place to read transcripts or compose. Grid + bulk verbs only.",
      tone: T.amber,
    },
    {
      name: "Markup",
      owns: "Focused single-capture editing. Voice or drawing. The agent runs passes here; the user touches up.",
      not: "Not a navigation surface. One capture at a time, full attention.",
      tone: T.alert,
    },
  ];

  return (
    <div style={{ padding: "32px 40px 8px 40px" }}>
      <SubHeader label="division of labor" hint="why three surfaces and not one" />
      <div
        style={{
          marginTop: 14,
          display: "grid",
          gridTemplateColumns: "1fr 1fr 1fr",
          gap: 14,
        }}
      >
        {surfaces.map((s) => (
          <div
            key={s.name}
            style={{
              padding: "16px 18px 18px 18px",
              background: T.pane,
              border: `0.5px solid ${T.inkRuleS}`,
              borderRadius: 6,
              borderTop: `2px solid ${s.tone}`,
            }}
          >
            <div
              className="font-mono font-semibold uppercase tracking-[0.22em]"
              style={{ fontSize: 10, color: T.ink }}
            >
              {s.name}
            </div>
            <div
              className="font-display"
              style={{
                fontSize: 12,
                color: T.inkMid,
                lineHeight: 1.55,
                marginTop: 8,
              }}
            >
              <span
                className="font-mono uppercase tracking-[0.18em]"
                style={{ fontSize: 8.5, color: T.amberDeep, marginRight: 6 }}
              >
                owns
              </span>
              {s.owns}
            </div>
            <div
              className="font-display italic"
              style={{
                fontSize: 11.5,
                color: T.inkFaint,
                lineHeight: 1.5,
                marginTop: 8,
              }}
            >
              <span
                className="font-mono uppercase tracking-[0.18em]"
                style={{
                  fontSize: 8.5,
                  color: T.inkFainter,
                  marginRight: 6,
                  fontStyle: "normal",
                }}
              >
                not
              </span>
              {s.not}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Journey timeline — the five acts, full width ────────────────────

function JourneyTimeline() {
  return (
    <div style={{ padding: "32px 40px 4px 40px" }}>
      <SubHeader label="the journey" hint="acts I–V · vertical walkthrough" />
      <div style={{ marginTop: 18 }}>
        <Act
          number="I"
          verb="capture"
          scene="3:42 PM. The build just failed; the user hits ⌃⇧⌘S, drags a region around the error trace."
          persists="C-0017 written to disk. Sidecar JSON empty. TrayItem mounted."
          next="Capture HUD fades; user returns to whatever they were doing."
        >
          <CaptureMoment />
        </Act>

        <ActConnector verb="lands" sub="the capture takes its seat" />

        <Act
          number="II"
          verb="library"
          scene="A minute later the user opens the Library to find what they just grabbed. The capture sits at the top of the list — alongside today's memos and dictations — because everything lives here first."
          persists="No selection yet. Library is the neutral home."
          next="User taps the Screenshots filter to narrow down to captures."
        >
          <LibrarySurface />
        </Act>

        <ActConnector verb="filter" sub="library narrows to captures" />

        <Act
          number="III"
          verb="screenshots"
          scene="Now in the Screenshots gallery. The grid lays the captures out visually — easier to scan than a list when the work is visual. C-0017 is on top; the user double-clicks."
          persists="Inspector pane shows C-0017 metadata. Selection anchor set."
          next="Double-click → Markup window opens. ⌘-click would add siblings to the selection for batch action."
        >
          <ScreenshotsSurface />
        </Act>

        <ActConnector verb="open" sub="markup window appears" />

        <Act
          number="IV"
          verb="markup"
          scene="Markup window — focused, one capture at a time. The user draws a rect around the error and asks the agent to label it. Style stack picks color and stroke; speak strip dispatches the agent pass."
          persists="Layers stream into the sidecar JSON. Original PNG never re-encoded."
          next="When the markup reads, the user closes the window. No accept gate — the sidecar saved as it went."
        >
          <MarkupSurface />
        </Act>

        <ActConnector verb="save" sub="back to the library, richer" />

        <Act
          number="V"
          verb="back to library"
          scene="The same library row, now with an annotated badge. The screenshot is still itself; the markup rides as sidecar metadata. A click reopens it with all layers intact, ready for another pass."
          persists="C-0017 + C-0017.markup.json. Identity unchanged."
          next="Loop closed. New capture starts a new journey."
        >
          <LibrarySurfaceAnnotated />
        </Act>
      </div>
    </div>
  );
}

function Act({
  number,
  verb,
  scene,
  persists,
  next,
  children,
}: {
  number: string;
  verb: string;
  scene: string;
  persists: string;
  next: string;
  children: React.ReactNode;
}) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "120px 1fr 240px", gap: 24, padding: "8px 0" }}>
      {/* Left rail — act number + verb */}
      <div className="flex flex-col" style={{ paddingTop: 4 }}>
        <span
          className="font-display"
          style={{
            fontSize: 48,
            fontWeight: 400,
            color: T.amber,
            lineHeight: 1,
            letterSpacing: "-0.02em",
          }}
        >
          {number}
        </span>
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 10, color: T.ink, marginTop: 8 }}
        >
          {verb}
        </span>
      </div>

      {/* Center — the panel + scene caption */}
      <div className="flex flex-col">
        <div
          className="font-display"
          style={{
            fontSize: 14,
            color: T.inkMid,
            lineHeight: 1.6,
            marginBottom: 14,
            maxWidth: 620,
          }}
        >
          {scene}
        </div>
        <div
          style={{
            background: T.page,
            border: `0.5px solid ${T.edge}`,
            borderRadius: 8,
            boxShadow:
              "0 1px 0 rgba(255,255,255,0.55) inset, 0 12px 28px -8px rgba(0,0,0,0.10)",
            overflow: "hidden",
          }}
        >
          {children}
        </div>
      </div>

      {/* Right rail — what persists, what's next */}
      <div className="flex flex-col" style={{ paddingTop: 4, gap: 14 }}>
        <MarginAnnotation eyebrow="persists" body={persists} />
        <MarginAnnotation eyebrow="next" body={next} />
      </div>
    </div>
  );
}

function MarginAnnotation({ eyebrow, body }: { eyebrow: string; body: string }) {
  return (
    <div>
      <span
        className="font-mono font-semibold uppercase tracking-[0.22em]"
        style={{ fontSize: 9, color: T.amberDeep }}
      >
        · {eyebrow}
      </span>
      <p
        className="font-display"
        style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.55, marginTop: 4 }}
      >
        {body}
      </p>
    </div>
  );
}

function ActConnector({ verb, sub }: { verb: string; sub: string }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "120px 1fr 240px", gap: 24, padding: "6px 0" }}>
      <div />
      <div className="flex items-center" style={{ gap: 12 }}>
        <svg width={18} height={28} viewBox="0 0 18 28" fill="none">
          <line x1={9} y1={0} x2={9} y2={22} stroke={T.amber} strokeWidth={1.2} strokeLinecap="round" />
          <path
            d="M3 20 L 9 26 L 15 20"
            stroke={T.amber}
            strokeWidth={1.2}
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
          />
        </svg>
        <span
          className="font-mono font-semibold uppercase tracking-[0.22em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          {verb}
        </span>
        <span
          className="font-display italic"
          style={{ fontSize: 11.5, color: T.inkFaint }}
        >
          {sub}
        </span>
      </div>
      <div />
    </div>
  );
}

// ─── Act surfaces — the actual mocked panels ─────────────────────────

// Act I · Capture HUD moment
function CaptureMoment() {
  return (
    <div
      style={{
        height: 220,
        background:
          "linear-gradient(135deg, #2a2c2e 0%, #1c1d1f 100%)",
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Faux desktop pattern */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage:
            "radial-gradient(circle at 20% 30%, rgba(255,255,255,0.04) 0%, transparent 50%), radial-gradient(circle at 80% 70%, rgba(196,125,28,0.08) 0%, transparent 50%)",
        }}
      />
      {/* Capture rectangle marquee */}
      <div
        style={{
          position: "absolute",
          left: "30%",
          top: "30%",
          width: "40%",
          height: "40%",
          border: `1.5px dashed ${T.amber}`,
          background: "rgba(196,125,28,0.06)",
          borderRadius: 2,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: "30%",
          top: "calc(30% - 18px)",
          fontFamily: "ui-monospace, monospace",
          fontSize: 9,
          color: "#fff",
          padding: "2px 6px",
          background: T.amber,
          borderRadius: 2,
          letterSpacing: "0.12em",
        }}
      >
        REGION · 720×432
      </div>
      {/* HUD chip bottom-center */}
      <div
        style={{
          position: "absolute",
          bottom: 14,
          left: "50%",
          transform: "translateX(-50%)",
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "5px 12px",
          background: "rgba(255,255,255,0.94)",
          border: `0.5px solid rgba(0,0,0,0.10)`,
          borderRadius: 999,
          boxShadow: "0 6px 18px rgba(0,0,0,0.32)",
        }}
      >
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: 999,
            background: T.alert,
            boxShadow: `0 0 5px ${T.alert}`,
          }}
        />
        <span
          className="font-mono font-semibold uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.ink }}
        >
          captured · C-0017
        </span>
        <span
          className="font-mono uppercase tracking-[0.14em]"
          style={{ fontSize: 9, color: T.inkFaint }}
        >
          ⌥+click → markup
        </span>
      </div>
    </div>
  );
}

// Act II · Library (capture lands at top)
function LibrarySurface() {
  return (
    <>
      <WindowChrome title="Library · All" subtitle="92 items · 18 captures" />
      <FilterRibbon active="all" />
      <div>
        <LibraryRow
          kind="capture"
          letter="S"
          title="Talkie Capture · 15:42"
          meta="capture · region · just now"
          fresh
        />
        <LibraryRow
          kind="memo"
          letter="M"
          title="Q1 plan revisit · weekly sync"
          meta="memo · 0:42 · 12 min ago"
        />
        <LibraryRow
          kind="dict"
          letter="D"
          title="Refactor migration script"
          meta="dictation · agent · 23 min ago"
        />
        <LibraryRow
          kind="note"
          letter="N"
          title="Hiring pipeline notes"
          meta="note · 4 paragraphs · 1h ago"
        />
      </div>
    </>
  );
}

// Act V · Library (with the annotated badge)
function LibrarySurfaceAnnotated() {
  return (
    <>
      <WindowChrome title="Library · All" subtitle="92 items · 18 captures" />
      <FilterRibbon active="all" />
      <div>
        <LibraryRow
          kind="capture"
          letter="S"
          title="Talkie Capture · 15:42"
          meta="capture · region · 4 layers · just now"
          annotated
        />
        <LibraryRow
          kind="memo"
          letter="M"
          title="Q1 plan revisit · weekly sync"
          meta="memo · 0:42 · 12 min ago"
        />
        <LibraryRow
          kind="dict"
          letter="D"
          title="Refactor migration script"
          meta="dictation · agent · 23 min ago"
        />
        <LibraryRow
          kind="note"
          letter="N"
          title="Hiring pipeline notes"
          meta="note · 4 paragraphs · 1h ago"
        />
      </div>
    </>
  );
}

function FilterRibbon({ active }: { active: string }) {
  const pills: { id: string; label: string; count: string }[] = [
    { id: "all",         label: "All",          count: "92" },
    { id: "memos",       label: "Memos",        count: "23" },
    { id: "dictations",  label: "Dictations",   count: "41" },
    { id: "screenshots", label: "Screenshots",  count: "18" },
    { id: "notes",       label: "Notes",        count: "10" },
  ];
  return (
    <div
      className="flex items-center"
      style={{
        background: T.page,
        padding: "8px 14px 6px 14px",
        gap: 4,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      {pills.map((p) => {
        const on = p.id === active;
        return (
          <div
            key={p.id}
            className="flex items-center gap-1"
            style={{
              padding: "3px 10px",
              borderBottom: `1px solid ${on ? T.amber : "transparent"}`,
            }}
          >
            <span
              className="font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: on ? T.ink : T.inkFaint }}
            >
              {p.label}
            </span>
            <span
              className="font-mono tabular-nums"
              style={{ fontSize: 9, color: on ? T.amber : T.inkFainter }}
            >
              {p.count}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function LibraryRow({
  kind,
  letter,
  title,
  meta,
  fresh,
  annotated,
}: {
  kind: keyof typeof KIND_COLOR;
  letter: string;
  title: string;
  meta: string;
  fresh?: boolean;
  annotated?: boolean;
}) {
  return (
    <div
      className="flex items-center"
      style={{
        gap: 10,
        padding: "9px 16px",
        borderBottom: `0.5px solid ${T.inkRuleS}`,
        background: fresh ? "rgba(196,125,28,0.05)" : "transparent",
      }}
    >
      <span
        className="flex items-center justify-center font-mono font-semibold"
        style={{
          width: 18,
          height: 18,
          fontSize: 9,
          color: KIND_COLOR[kind],
          border: `0.5px solid ${KIND_COLOR[kind]}`,
          borderRadius: 2,
        }}
      >
        {letter}
      </span>
      <div className="flex flex-col" style={{ minWidth: 0, flex: 1 }}>
        <span
          className="truncate"
          style={{ fontSize: 12, color: T.ink, fontWeight: fresh ? 500 : 400 }}
        >
          {title}
        </span>
        <span
          className="font-mono uppercase tracking-[0.14em]"
          style={{ fontSize: 8.5, color: T.inkFainter }}
        >
          {meta}
        </span>
      </div>
      {annotated && (
        <span
          className="font-mono font-semibold uppercase tracking-[0.20em]"
          style={{
            fontSize: 8.5,
            color: T.amberDeep,
            padding: "2px 6px",
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            borderRadius: 2,
          }}
        >
          ↳ markup
        </span>
      )}
      {fresh && !annotated && (
        <span
          className="font-mono uppercase tracking-[0.20em]"
          style={{ fontSize: 8.5, color: T.amber }}
        >
          NEW
        </span>
      )}
    </div>
  );
}

// Act III · Screenshots gallery
function ScreenshotsSurface() {
  return (
    <>
      <WindowChrome title="Screenshots · 18 captures" subtitle="grid · 4-up · sorted recent" />
      <div
        style={{
          padding: 14,
          display: "grid",
          gridTemplateColumns: "repeat(4, 1fr)",
          gap: 10,
          background: T.rail,
        }}
      >
        {Array.from({ length: 8 }).map((_, i) => (
          <ScreenshotCard
            key={i}
            selected={i === 0}
            label={`C-${String(17 - i).padStart(4, "0")}`}
            tone={i % 3 === 0 ? "log" : i % 3 === 1 ? "table" : "doc"}
          />
        ))}
      </div>
      <div
        className="flex items-center"
        style={{
          padding: "6px 14px",
          gap: 10,
          background: T.chrome,
          borderTop: `0.5px solid ${T.inkRuleS}`,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.20em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          1 selected · C-0017
        </span>
        <span style={{ width: 1, height: 12, background: T.inkRuleS }} />
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFaint }}
        >
          dbl-click to mark up · ⌫ to delete
        </span>
        <span className="ml-auto font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: T.inkFainter }}>
          ⌘-click for multi · shift for range
        </span>
      </div>
    </>
  );
}

function ScreenshotCard({
  selected,
  multi,
  label,
  tone,
}: {
  selected?: boolean;
  multi?: boolean;
  label: string;
  tone?: "log" | "table" | "doc";
}) {
  const ring =
    selected ? T.amber : multi ? T.amberSoft : T.inkRuleS;
  const ringWidth = selected ? 1.5 : multi ? 1 : 0.5;
  return (
    <div
      style={{
        position: "relative",
        background: T.page,
        border: `${ringWidth}px solid ${ring}`,
        borderRadius: 4,
        aspectRatio: "4 / 3",
        boxShadow: selected
          ? `0 0 0 3px ${T.amberFaint}`
          : "0 1px 2px rgba(0,0,0,0.04)",
        overflow: "hidden",
      }}
    >
      <CardArtwork tone={tone || "log"} />
      {multi && (
        <span
          style={{
            position: "absolute",
            top: 5,
            right: 5,
            width: 8,
            height: 8,
            borderRadius: 999,
            background: T.amberDeep,
            boxShadow: `0 0 0 1.5px ${T.amberFaint}`,
          }}
        />
      )}
      <span
        className="font-mono uppercase tracking-[0.16em]"
        style={{
          position: "absolute",
          left: 7,
          bottom: 4,
          fontSize: 8,
          color: T.inkFainter,
        }}
      >
        {label}
      </span>
    </div>
  );
}

function CardArtwork({ tone }: { tone: "log" | "table" | "doc" }) {
  // Quietly suggest the kind of content captured. Three tones cycle
  // through the grid so the wall doesn't read as one image repeated.
  if (tone === "log") {
    return (
      <div style={{ padding: 7 }}>
        {Array.from({ length: 6 }).map((_, i) => (
          <div
            key={i}
            style={{
              height: 3,
              background: i === 3 ? T.alert : T.inkFainter,
              opacity: i === 3 ? 0.6 : 0.3,
              borderRadius: 1,
              width: `${50 + ((i * 13) % 40)}%`,
              marginTop: 4,
            }}
          />
        ))}
      </div>
    );
  }
  if (tone === "table") {
    return (
      <div style={{ padding: 7 }}>
        {Array.from({ length: 4 }).map((_, r) => (
          <div key={r} className="flex" style={{ gap: 3, marginTop: 3 }}>
            {Array.from({ length: 3 }).map((_, c) => (
              <div
                key={c}
                style={{
                  flex: 1,
                  height: 6,
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
  return (
    <div style={{ padding: 7 }}>
      <div
        style={{
          height: 6,
          width: "55%",
          background: T.inkFainter,
          opacity: 0.4,
          borderRadius: 1,
          marginBottom: 5,
        }}
      />
      {Array.from({ length: 5 }).map((_, i) => (
        <div
          key={i}
          style={{
            height: 3,
            background: T.inkFainter,
            opacity: 0.3,
            borderRadius: 1,
            width: `${70 + ((i * 7) % 25)}%`,
            marginTop: 3,
          }}
        />
      ))}
    </div>
  );
}

// Act IV · Markup window
function MarkupSurface() {
  return (
    <>
      <WindowChrome title="Markup · C-0017" subtitle="4 layers · agent ran 1.4s ago" />
      <MarkupMiniToolbar />
      <div
        style={{
          padding: 14,
          background: T.rail,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          position: "relative",
          minHeight: 200,
          overflow: "hidden",
        }}
      >
        <MarkupCanvas />
        <ZoomCluster />
      </div>
      <SpeakStrip />
    </>
  );
}

function MarkupMiniToolbar() {
  const tools: { id: string; glyph: string; on?: boolean }[] = [
    { id: "rect",  glyph: "▢", on: true },
    { id: "arrow", glyph: "↗" },
    { id: "line",  glyph: "—" },
    { id: "text",  glyph: "T" },
    { id: "blur",  glyph: "▒" },
  ];
  return (
    <div
      className="flex items-center"
      style={{
        height: 32,
        padding: "0 10px",
        gap: 4,
        background: T.chrome,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      {tools.map((t) => (
        <span
          key={t.id}
          className="flex items-center justify-center"
          style={{
            width: 22,
            height: 22,
            borderRadius: 3,
            background: t.on ? T.amberFaint : "transparent",
            border: t.on ? `0.5px solid ${T.amberSoft}` : "0.5px solid transparent",
            color: t.on ? T.amberDeep : T.inkFaint,
            fontSize: 12,
            fontFamily: "ui-monospace, monospace",
          }}
        >
          {t.glyph}
        </span>
      ))}
      <span style={{ width: 1, height: 18, background: T.inkRuleS, margin: "0 8px" }} />
      <span className="flex items-center" style={{ gap: 3 }}>
        {[1, 2, 3].map((w) => (
          <span
            key={`s${w}`}
            style={{
              width: 16,
              height: 16,
              borderRadius: 2,
              border: `0.5px solid ${w === 2 ? T.amberSoft : T.inkRuleS}`,
              background: w === 2 ? T.amberFaint : "transparent",
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <span
              style={{
                display: "block",
                width: 9,
                height: w,
                background: w === 2 ? T.amberDeep : T.inkFainter,
                borderRadius: 1,
              }}
            />
          </span>
        ))}
      </span>
      <span style={{ width: 6 }} />
      <span className="flex items-center" style={{ gap: 3 }}>
        {[T.ink, T.alert, T.amber, T.brass].map((c, i) => (
          <span
            key={i}
            style={{
              display: "inline-block",
              width: 12,
              height: 12,
              borderRadius: 999,
              background: c,
              outline: i === 2 ? `1.5px solid ${T.amberDeep}` : "none",
              outlineOffset: 1,
            }}
          />
        ))}
      </span>
    </div>
  );
}

function MarkupCanvas() {
  return (
    <div
      style={{
        position: "relative",
        width: "85%",
        aspectRatio: "16 / 10",
        background: T.page,
        borderRadius: 3,
        border: `0.5px solid ${T.inkRule}`,
        boxShadow: "0 4px 14px rgba(0,0,0,0.10)",
        overflow: "hidden",
      }}
    >
      <div style={{ padding: 12 }}>
        <div
          style={{
            height: 5,
            background: T.inkFainter,
            opacity: 0.45,
            borderRadius: 1,
            width: "55%",
          }}
        />
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            style={{
              height: 3.5,
              background: i === 3 ? T.alert : T.inkFainter,
              opacity: i === 3 ? 0.7 : 0.32,
              borderRadius: 1,
              width: `${68 + (i % 3) * 9}%`,
              marginTop: 6,
            }}
          />
        ))}
      </div>
      <div
        style={{
          position: "absolute",
          left: "8%",
          top: "47%",
          width: "78%",
          height: 14,
          border: `1.6px solid ${T.amber}`,
          borderRadius: 2,
          background: "rgba(196, 125, 28, 0.08)",
        }}
      />
      <span
        className="font-mono uppercase tracking-[0.18em]"
        style={{
          position: "absolute",
          left: "8%",
          top: "35%",
          fontSize: 8,
          padding: "2px 5px",
          background: "rgba(20,24,30,0.84)",
          color: "#fff",
          borderRadius: 1,
        }}
      >
        BUILD FAILED · L2
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
        bottom: 10,
        right: 10,
        gap: 1,
        padding: 2,
        background: "#fff",
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 4,
        boxShadow: "0 2px 6px rgba(0,0,0,0.10)",
      }}
    >
      <span
        className="flex items-center justify-center font-mono"
        style={{ width: 16, height: 16, fontSize: 11, color: T.inkFaint }}
      >
        −
      </span>
      <span
        className="font-mono tabular-nums"
        style={{ fontSize: 9, color: T.inkMid, padding: "0 4px" }}
      >
        100%
      </span>
      <span
        className="flex items-center justify-center font-mono"
        style={{ width: 16, height: 16, fontSize: 11, color: T.inkFaint }}
      >
        +
      </span>
      <span style={{ width: 1, height: 12, background: T.inkRuleS, margin: "0 2px" }} />
      <span
        className="font-mono font-semibold uppercase tracking-[0.16em]"
        style={{ padding: "0 5px", fontSize: 8, color: T.inkFaint }}
      >
        FIT
      </span>
    </div>
  );
}

function SpeakStrip() {
  return (
    <div
      style={{
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        padding: "8px 12px",
      }}
    >
      {/* Selection bar (scope strip) */}
      <div
        className="flex items-stretch"
        style={{
          marginBottom: 6,
          background: T.pane,
          border: `0.5px solid ${T.inkRule}`,
          borderRadius: 3,
          overflow: "hidden",
        }}
      >
        <span style={{ width: 3, background: T.amber }} />
        <div className="flex items-center" style={{ flex: 1, padding: "4px 8px", gap: 6 }}>
          <span
            className="font-mono uppercase tracking-[0.20em]"
            style={{ fontSize: 8, color: T.inkFainter }}
          >
            · scope
          </span>
          <span
            className="font-mono font-semibold uppercase tracking-[0.16em]"
            style={{
              fontSize: 8.5,
              color: T.amberDeep,
              padding: "1px 4px",
              background: T.amberFaint,
              border: `0.5px solid ${T.amberSoft}`,
              borderRadius: 2,
            }}
          >
            L2
          </span>
          <span
            className="font-display"
            style={{ fontSize: 10.5, color: T.ink, fontWeight: 500 }}
          >
            build failed line
          </span>
        </div>
      </div>

      {/* Mic + prompt + run */}
      <div className="flex items-center" style={{ gap: 8 }}>
        <span
          className="flex items-center justify-center"
          style={{
            width: 26,
            height: 26,
            borderRadius: 999,
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            color: T.amberDeep,
          }}
        >
          <svg width={12} height={12} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
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
            borderRadius: 3,
            height: 26,
            padding: "0 10px",
          }}
        >
          <span
            className="font-display italic"
            style={{ fontSize: 11, color: T.inkFainter }}
          >
            label it &lsquo;build failed&rsquo;
          </span>
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 12,
              background: T.amber,
              marginLeft: 4,
              animation: "promptcaret 1s steps(2) infinite",
            }}
          />
        </div>
        <span
          className="font-mono font-semibold uppercase tracking-[0.18em]"
          style={{
            background: T.amber,
            color: "#fff",
            padding: "5px 10px",
            borderRadius: 3,
            fontSize: 9,
          }}
        >
          run ⌘↵
        </span>
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

// ─── Alternate path — bulk select ────────────────────────────────────

function AlternatePath() {
  return (
    <div style={{ padding: "32px 40px 4px 40px" }}>
      <SubHeader
        label="alternate path · bulk review"
        hint="diverges at Act III when the user picks several at once"
      />
      <div style={{ marginTop: 14 }}>
        <Act
          number="III'"
          verb="multi-select"
          scene="The user is reviewing the day's captures end-of-day. ⌘-click picks three; the status bar lights up with bulk actions. Markup opens a queue: walk each in turn, same window, layers saved per item."
          persists="Three anchor IDs in the selection set. Bulk action bar enabled."
          next="MARKUP → queue mode · SHARE → multi-target picker · DELETE → confirm + soft-delete."
        >
          <ScreenshotsSurfaceBulk />
        </Act>
      </div>
    </div>
  );
}

function ScreenshotsSurfaceBulk() {
  return (
    <>
      <WindowChrome title="Screenshots · 18 captures" subtitle="grid · 4-up · multi-select" />
      <div
        style={{
          padding: 14,
          display: "grid",
          gridTemplateColumns: "repeat(4, 1fr)",
          gap: 10,
          background: T.rail,
        }}
      >
        {Array.from({ length: 8 }).map((_, i) => (
          <ScreenshotCard
            key={i}
            selected={i === 4}
            multi={i === 1 || i === 6}
            label={`C-${String(17 - i).padStart(4, "0")}`}
            tone={i % 3 === 0 ? "log" : i % 3 === 1 ? "table" : "doc"}
          />
        ))}
      </div>
      <div
        className="flex items-center"
        style={{
          padding: "6px 14px",
          gap: 10,
          background: T.chrome,
          borderTop: `0.5px solid ${T.inkRuleS}`,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.20em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          3 selected
        </span>
        <span style={{ width: 1, height: 12, background: T.inkRuleS }} />
        <BulkVerb label="markup" tone="primary" />
        <BulkVerb label="share" />
        <BulkVerb label="delete" tone="alert" />
      </div>
    </>
  );
}

function BulkVerb({
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
      }}
    >
      {label}
    </span>
  );
}

// ─── Vocabulary ──────────────────────────────────────────────────────

function NamesMarginalia() {
  const groups: { title: string; entries: [string, string][] }[] = [
    {
      title: "surfaces",
      entries: [
        ["Capture HUD",        "the moment-of-capture overlay. Marquee + bottom chip."],
        ["Library",            "Scope's cross-content list. Captures live here alongside memos."],
        ["Screenshots",        "captures-only gallery. Grid + multi-select + bulk verbs."],
        ["Markup Window",      "single-capture annotation surface. Synonyms: Annotation View."],
      ],
    },
    {
      title: "objects",
      entries: [
        ["Capture",            "the screenshot PNG itself. Identified by C-NNNN."],
        ["Sidecar",            "JSON next to the PNG. Holds layers; written non-destructively."],
        ["Layer",              "one annotation in the sidecar. Kinds: rect, arrow, line, label, blur."],
        ["Pass",               "one agent run that mutates the sidecar. Tracked for undo."],
      ],
    },
    {
      title: "states",
      entries: [
        ["Anchor Selection",   "the one card the user just plain-clicked. Drives the inspector."],
        ["Multi-select",       "anchor + ⌘-toggled siblings. Drives bulk actions."],
        ["Annotated",          "capture whose sidecar carries layers. Library row shows the badge."],
      ],
    },
  ];
  return (
    <div style={{ padding: "32px 40px 4px 40px" }}>
      <SubHeader label="names" hint="shared vocabulary across studio / Swift / chat" />
      <div
        style={{
          marginTop: 14,
          display: "grid",
          gridTemplateColumns: "1fr 1fr 1fr",
          gap: 14,
        }}
      >
        {groups.map((g) => (
          <div
            key={g.title}
            style={{
              padding: "14px 16px 16px 16px",
              background: T.pane,
              border: `0.5px solid ${T.inkRuleS}`,
              borderRadius: 6,
            }}
          >
            <div
              className="font-mono font-semibold uppercase tracking-[0.22em]"
              style={{ fontSize: 9, color: T.amberDeep, marginBottom: 10 }}
            >
              · {g.title}
            </div>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr",
                rowGap: 6,
              }}
            >
              {g.entries.map(([name, def]) => (
                <div key={name}>
                  <span
                    className="font-mono font-semibold uppercase tracking-[0.16em]"
                    style={{ fontSize: 10, color: T.ink }}
                  >
                    {name}
                  </span>
                  <p
                    className="font-display italic"
                    style={{
                      fontSize: 11.5,
                      color: T.inkMid,
                      lineHeight: 1.45,
                      marginTop: 2,
                    }}
                  >
                    {def}
                  </p>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Footer ──────────────────────────────────────────────────────────

function StudyFooter() {
  const links: [string, string, string][] = [
    ["mac-capture-hud",     "Capture HUD",     "Act I"],
    ["mac-library",         "Library",         "Acts II + V"],
    ["mac-screenshots",     "Screenshots",     "Act III"],
    ["mac-capture-markup",  "Capture Markup",  "Act IV"],
  ];
  return (
    <div style={{ padding: "36px 40px 32px 40px" }}>
      <div style={{ height: 1, background: T.inkRuleS, marginBottom: 16 }} />
      <div className="flex items-baseline gap-3" style={{ marginBottom: 10 }}>
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 9, color: T.inkFaint }}
        >
          · the full versions
        </span>
        <span
          className="font-display italic"
          style={{ fontSize: 12, color: T.inkFaint }}
        >
          each act has its own study — open the linked surface for the full mock
        </span>
      </div>
      <div className="flex" style={{ gap: 14, flexWrap: "wrap" }}>
        {links.map(([slug, label, where]) => (
          <a
            key={slug}
            href={`/${slug}`}
            style={{
              padding: "8px 12px",
              border: `0.5px solid ${T.inkRule}`,
              borderRadius: 4,
              background: T.pane,
              textDecoration: "none",
              display: "flex",
              flexDirection: "column",
              gap: 2,
              minWidth: 180,
            }}
          >
            <span
              className="font-mono font-semibold uppercase tracking-[0.18em]"
              style={{ fontSize: 9.5, color: T.ink }}
            >
              {label}
            </span>
            <span
              className="font-mono uppercase tracking-[0.16em]"
              style={{ fontSize: 8.5, color: T.amberDeep }}
            >
              /{slug}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 10.5, color: T.inkFaint, marginTop: 2 }}
            >
              {where}
            </span>
          </a>
        ))}
      </div>
    </div>
  );
}

// ─── Shared bits ─────────────────────────────────────────────────────

function WindowChrome({
  title,
  subtitle,
}: {
  title: string;
  subtitle?: string;
}) {
  return (
    <div
      className="flex items-center"
      style={{
        height: 26,
        padding: "0 10px",
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
          className="ml-auto font-mono uppercase tracking-[0.16em]"
          style={{ fontSize: 8.5, color: T.inkFaint }}
        >
          {subtitle}
        </span>
      )}
    </div>
  );
}

function SubHeader({ label, hint }: { label: string; hint?: string }) {
  return (
    <div className="flex items-baseline gap-3">
      <span
        className="font-mono font-semibold uppercase tracking-[0.30em]"
        style={{ color: T.amber, fontSize: 9.5 }}
      >
        · {label}
      </span>
      {hint && (
        <span
          className="font-display italic"
          style={{ color: T.inkFaint, fontSize: 12 }}
        >
          {hint}
        </span>
      )}
      <div className="ml-3 flex-1" style={{ height: 1, background: T.inkRuleS }} />
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
