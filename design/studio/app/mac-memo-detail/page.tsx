"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacMemoDetail } from "@/components/studies/MacMemoDetail";

/**
 * Mac Memo Detail — right-hand pane of the Library split view.
 *
 * Three sections stacked:
 *   0. Swift gap audit — concrete UX issues in the shipping macOS detail
 *      view, with file:line refs and fix directions. The studio prototype
 *      below is the target.
 *   1. With icon-rail — the shipping vision after the Talkie button
 *      consolidation. Three-pane shape: nav rail + list + detail.
 *   2. No rail (existing reference) — original two-pane composition, kept
 *      for comparison so the design language work is still legible.
 */
export default function MacMemoDetailStudy() {
  return (
    <StudioPage
      eyebrow="Memo · macOS · Composition study + Swift audit"
      title="Mac Memo Detail"
      help="edit components/studies/MacMemoDetail.tsx · audit findings vs. shipping Swift"
    >
      <div className="flex flex-col gap-10 py-4">
        <SwiftGapAudit />

        <section>
          <SubHeader
            eyebrow="· Target · With icon-rail"
            title="Three panes — nav rail + library list + detail"
            hint="52pt rail · Library is the selected nav · same canonical 1180px width"
          />
          <MacMemoDetail withRail />
        </section>

        <section>
          <SubHeader
            eyebrow="· Reference · No rail"
            title="Two panes — library list + detail"
            hint="for comparison · pre-consolidation read"
          />
          <MacMemoDetail />
        </section>
      </div>
    </StudioPage>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Swift gap audit — punch list of UX issues found in the shipping macOS
// `TalkieView` + section views, with file:line refs and proposed fixes.
// Source: subagent audit on 2026-05-19.

type Severity = "HIGH" | "MEDIUM" | "LOW";

type AuditItem = {
  id: number;
  severity: Severity;
  summary: string;
  refs: string[];
  fix: string;
};

const AUDIT: AuditItem[] = [
  {
    id: 1,
    severity: "HIGH",
    summary: "Action duplication — Copy/Share live in 3 places",
    refs: ["TalkieView.swift:107-116", "TOSharedComponents.swift:795-858"],
    fix: "Keep masthead toolbar canonical. Drop inline COPY tab + action pill scrollview.",
  },
  {
    id: 2,
    severity: "HIGH",
    summary: "Star / Pin are dead TODO stubs",
    refs: ["TOHeaderSection.swift:298-303"],
    fix: "Wire them or remove them — most prominent toolbar items do nothing.",
  },
  {
    id: 3,
    severity: "HIGH",
    summary: "No single answer to “what can I do with this memo?”",
    refs: ["TOWorkflowRunsSection.swift", "TalkieView.swift overflow menu"],
    fix: "One Actions/Workflows rail: pinned workflows + Run… + collapsible recent runs.",
  },
  {
    id: 4,
    severity: "HIGH",
    summary: "Continue-recording floating red pill overlays transcript",
    refs: ["TOTranscriptSection.swift:54-78"],
    fix: "Move Continue into the player rail next to play, or into the toolbar.",
  },
  {
    id: 5,
    severity: "HIGH",
    summary: "Transcription CTA hidden as quiet card",
    refs: ["TOTranscriptSection.swift:89-175"],
    fix: "When transcript is missing, promote to full-width brass hero band with one primary button.",
  },
  {
    id: 6,
    severity: "HIGH",
    summary: "Lead paragraph rendered twice (masthead standfirst + body first paragraph)",
    refs: ["TOHeaderSection.swift:147-181", "TOSharedComponents.swift:1259"],
    fix: "Render lead only in masthead OR only in body — pick one, drop the other consistently.",
  },
  {
    id: 7,
    severity: "MEDIUM",
    summary: "Section headers read as dev chrome (caps mono + count chips)",
    refs: [
      "TOMediaGallerySection.swift:26-39",
      "TOAttachmentsSection.swift:27-39",
      "TONotesSection.swift:24-44",
      "TOWorkflowRunsSection.swift:21-35",
    ],
    fix: "Standardize as `· LABEL · N` eyebrow with brass dot. Kill count badge capsules.",
  },
  {
    id: 8,
    severity: "MEDIUM",
    summary: "“SCRATCHPAD” label is jargon",
    refs: ["TONotesSection.swift:25"],
    fix: "Rename to “Notes” or drop the label entirely.",
  },
  {
    id: 9,
    severity: "MEDIUM",
    summary: "Bottom Delete button is a third escape hatch",
    refs: ["TalkieView.swift:232-246"],
    fix: "Delete the bottom button — overflow ⋯ + ⌘⌫ is enough.",
  },
  {
    id: 10,
    severity: "MEDIUM",
    summary: "Tool Tray (Quick Open icons) below transcript has no label",
    refs: ["TOSharedComponents.swift:959-980"],
    fix: "Add `· OPEN IN` eyebrow or fold into masthead toolbar as inline cluster.",
  },
  {
    id: 11,
    severity: "MEDIUM",
    summary: "Player rail missing −15 / +15 / speed pill / volume",
    refs: ["TOPlaybackSection.swift:60-95", "TOSharedComponents.swift:1479+"],
    fix: "Port the transport + 1.0× speed pill from the studio PlayerRail below.",
  },
  {
    id: 12,
    severity: "MEDIUM",
    summary: "Card-vs-document treatment inconsistent",
    refs: [
      "TalkieDetailLayout.swift:96-103",
      "TOSharedComponents.swift:742 (documentMode opts out)",
    ],
    fix: "Thread document-mode (.inline chrome + eyebrow) through Workflow Runs / Media / Attachments. Drop .ultraThinMaterial cards.",
  },
  {
    id: 13,
    severity: "LOW",
    summary: "iCloud-fetch empty state still wears card chrome",
    refs: ["TOPlaybackSection.swift:99-141"],
    fix: "Flatten to inline document treatment matching the rest of the scroll.",
  },
  {
    id: 14,
    severity: "LOW",
    summary: "Workflow Run rows wear gradient/material chrome (Big Sur leftover)",
    refs: ["TOSharedComponents.swift:579-610"],
    fix: "Flatten to hairline row, kill gradient stroke + ultraThinMaterial.",
  },
  {
    id: 15,
    severity: "LOW",
    summary: "M-XXXX sequence label duplicated (toolbar slug + eyebrow)",
    refs: ["TOHeaderSection.swift:80-89", "TOHeaderSection.swift:198-211"],
    fix: "Drop eyebrow row — toolbar slug already names the channel.",
  },
];

const FIRST_MOVES = [
  {
    n: 1,
    title: "Unify actions in the masthead toolbar",
    body: "Pick the masthead toolbar as canonical. Wire Star/Pin (or kill them). Add Run Workflow split-button. Drop the action-pill scrollview, the bottom Delete, and the standalone tool tray. Single answer to “what can I do with this memo?”",
  },
  {
    n: 2,
    title: "Promote the transcription CTA",
    body: "When a memo has audio but no transcript, the page is broken until transcribed. Currently it's a quiet card with two truncated lines of red error text. Lift to a full-width brass hero band, one primary button — “fix this first, then read.”",
  },
  {
    n: 3,
    title: "Port the studio prototype end-to-end",
    body: "Player rail (−15 / play / +15 / speed pill / volume), re-skin Workflow Runs + Media + Attachments to inline-document chrome (eyebrow labels, hairline separators, no cards), drop the redundant eyebrow row. After this, the whole scroll reads as one sheet of paper.",
  },
];

function SwiftGapAudit() {
  return (
    <section>
      <SubHeader
        eyebrow="· Audit · Swift gaps"
        title="What's broken in the shipping macOS view"
        hint="15 issues · graded HIGH / MEDIUM / LOW · 3 first-move fixes"
      />

      <div className="flex flex-col gap-6">
        {(["HIGH", "MEDIUM", "LOW"] as Severity[]).map((sev) => (
          <SeverityBlock key={sev} severity={sev} items={AUDIT.filter((a) => a.severity === sev)} />
        ))}

        <FirstMovesBlock />
      </div>
    </section>
  );
}

function SeverityBlock({ severity, items }: { severity: Severity; items: AuditItem[] }) {
  const tone = SEVERITY_TONE[severity];
  return (
    <div>
      <div className="mb-2 flex items-baseline gap-2">
        <span
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em]"
          style={{ color: tone.label }}
        >
          · {severity}
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {tone.copy} · {items.length} issues
        </span>
      </div>

      <div className="grid grid-cols-1 gap-2 md:grid-cols-2 lg:grid-cols-3">
        {items.map((item) => (
          <AuditCard key={item.id} item={item} tone={tone} />
        ))}
      </div>
    </div>
  );
}

function AuditCard({ item, tone }: { item: AuditItem; tone: SeverityTone }) {
  return (
    <div
      className="flex flex-col gap-2 rounded-sm border border-studio-edge bg-white p-3"
      style={{ borderLeft: `2px solid ${tone.label}` }}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span
          className="font-mono text-[9px] font-semibold tracking-[0.18em]"
          style={{ color: tone.label }}
        >
          #{String(item.id).padStart(2, "0")}
        </span>
      </div>

      <p className="m-0 text-[13px] font-medium leading-tight text-studio-ink">
        {item.summary}
      </p>

      <div className="flex flex-col gap-0.5">
        {item.refs.map((ref) => (
          <code
            key={ref}
            className="font-mono text-[10px] leading-tight text-studio-ink-faint"
          >
            {ref}
          </code>
        ))}
      </div>

      <p className="m-0 border-t border-studio-edge pt-2 text-[11.5px] leading-snug text-studio-ink">
        <span
          className="mr-1 font-mono text-[9px] font-semibold uppercase tracking-[0.18em]"
          style={{ color: tone.label }}
        >
          Fix
        </span>
        {item.fix}
      </p>
    </div>
  );
}

function FirstMovesBlock() {
  return (
    <div className="mt-2 rounded-sm border border-studio-edge bg-[#F1F1F0] p-5">
      <div className="mb-3 flex items-baseline gap-2">
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-[#C47D1C]">
          · Three first moves
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          highest leverage · do these first
        </span>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
        {FIRST_MOVES.map((m) => (
          <div key={m.n} className="flex flex-col gap-1.5">
            <div className="flex items-baseline gap-2">
              <span className="font-display text-[24px] font-light leading-none text-[#C47D1C]">
                {m.n}
              </span>
              <h4 className="m-0 text-[13px] font-semibold leading-tight text-studio-ink">
                {m.title}
              </h4>
            </div>
            <p className="m-0 text-[12px] leading-snug text-studio-ink">{m.body}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

type SeverityTone = { label: string; copy: string };

const SEVERITY_TONE: Record<Severity, SeverityTone> = {
  HIGH:   { label: "#B83A2A", copy: "broken or confusing" },
  MEDIUM: { label: "#C47D1C", copy: "friction or visual noise" },
  LOW:    { label: "#7A6D5A", copy: "polish" },
};

function SubHeader({
  eyebrow,
  title,
  hint,
}: {
  eyebrow: string;
  title: string;
  hint?: string;
}) {
  return (
    <div className="mb-5 flex items-baseline gap-4 border-b border-studio-edge pb-3">
      <div>
        <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          {eyebrow}
        </div>
        <h2 className="m-0 font-display text-[20px] font-medium leading-none tracking-tight text-studio-ink">
          {title}
        </h2>
      </div>
      {hint && (
        <div className="ml-auto font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {hint}
        </div>
      )}
    </div>
  );
}
