"use client";

/**
 * Home - current iOS composition parity board.
 *
 * Mirrors the shipped Swift HomeNextView shape after the July 1 pass:
 * header complication / Today ticker / Quick deck / Recent screen /
 * Explore rail / bottom voice + record chrome.
 *
 * The component accepts variants so /home can compare layout proposals
 * before Swift changes:
 * - baseline: current Swift structure
 * - ticker-line: demote Today to one compact line
 * - grouped-rhythm: give Recent stronger hierarchy through spacing
 * - simple-recent: simplify the Recent header controls
 * - deduped-quick: remove duplicate Record/Deck entry points
 * - material-calibration: stress tonal recess/action/theme tokens
 */

import { StatusBar } from "./primitives/StatusBar";
import type { ListRowSource } from "./primitives/ListRow";
import type { HomeContentIdea, HomeVariant } from "./homeVariants";
import type { ReactNode } from "react";

type RecentMode = "full" | "simple";

interface HomeProps {
  variant?: HomeVariant;
  contentIdea?: HomeContentIdea;
}

type RecentItem = {
  source: ListRowSource;
  title: string;
  time: string;
};

type TodayCellModel = {
  count: string;
  label: string;
  dim?: boolean;
};

type QuickAction = {
  key: string;
  label: string;
  icon: IconName;
};

type HomeContentModel = {
  lead:
    | {
        kind: "none";
      }
    | {
        kind: "stats";
        eyebrow: string;
        cells: TodayCellModel[];
      }
    | {
        kind: "spotlight";
        eyebrow: string;
        title: string;
        detail: string;
        meta: string;
        status?: string;
      }
    | {
        kind: "contribution";
        eyebrow: string;
        title: string;
        subtitle: string;
        total: string;
        totalLabel: string;
        dotRows: Array<{
          label: string;
          percent: string;
          total: number;
          filled: number;
          marker: number;
        }>;
      }
    | {
        kind: "cockpit";
        eyebrow: string;
        module: "dots" | "notifications" | "wide";
        title: string;
        detail: string;
        status: string;
        lanes: Array<{
          label: string;
          value: string;
          meta: string;
          level: number;
        }>;
        notifications?: Array<{
          label: string;
          value: string;
          tone: "live" | "waiting" | "done";
        }>;
        dotRows?: Array<{
          label: string;
          percent: string;
          total: number;
          filled: number;
          marker: number;
        }>;
      };
  line: string;
  omni?: {
    placeholder: string;
    hint: string;
  };
  quickActions: QuickAction[];
  recentCount: string;
  recentItems: RecentItem[];
  loadLabel: string;
  exploreItems?: QuickAction[];
};

const RECENT_ITEMS: RecentItem[] = [
  { source: "typed", title: "Memo Jul 1 - 9:04 AM...", time: "2:49 PM" },
  { source: "dictation", title: "Memo Jul 1 - 9:04 AM", time: "9:08 AM" },
  { source: "link", title: "Chitransh (@_chitransh09) on X", time: "Jun 22" },
  { source: "dictation", title: "Recording 6/22/26, 2:59 PM", time: "Jun 22" },
];

const QUICK_ACTIONS: QuickAction[] = [
  { key: "record", label: "Record", icon: "waveform" },
  { key: "compose", label: "Compose", icon: "compose" },
  { key: "scan", label: "Scan", icon: "camera" },
  { key: "ask", label: "Ask AI", icon: "sparkles" },
];

const EXPLORE_ITEMS = [
  { key: "deck", label: "Deck", icon: "deck" },
  { key: "library", label: "Library", icon: "library" },
  { key: "workflows", label: "Workflows", icon: "workflow" },
  { key: "terminal", label: "Terminal", icon: "terminal" },
  { key: "keyboard", label: "Keyboard", icon: "keyboard" },
];

const HOME_CONTENT: Record<HomeContentIdea, HomeContentModel> = {
  "utility-console": {
    lead: { kind: "none" },
    line: "",
    omni: {
      placeholder: "Search or run a command...",
      hint: "Memos, screenshots, workflows, Mac bridge",
    },
    quickActions: [
      { key: "compose", label: "Memo", icon: "compose" },
      { key: "scan", label: "Scan", icon: "camera" },
      { key: "ask", label: "Ask AI", icon: "sparkles" },
      { key: "command", label: "Command", icon: "terminal" },
    ],
    recentCount: "40 items",
    recentItems: [
      { source: "typed", title: "Memo Jul 1 - 9:04 AM...", time: "2:49 PM" },
      { source: "dictation", title: "Memo Jul 1 - 9:04 AM", time: "9:08 AM" },
      { source: "scan", title: "Deck top area visual note", time: "6:02 PM" },
      { source: "typed", title: "Direct Pair failure language", time: "10:43 AM" },
      { source: "dictation", title: "Button row treatment feedback", time: "3:57 PM" },
      { source: "scan", title: "Paired Macs selector clarity pass", time: "6:38 PM" },
      { source: "typed", title: "Trackpad y-axis and enter key report", time: "3:25 PM" },
      { source: "link", title: "Chitransh (@_chitransh09) on X", time: "Jun 22" },
    ],
    loadLabel: "All",
    exploreItems: [
      { key: "workflows", label: "Workflows", icon: "workflow" },
      { key: "terminal", label: "Terminal", icon: "terminal" },
      { key: "keyboard", label: "Keyboard", icon: "keyboard" },
      { key: "bridge", label: "Bridge", icon: "link" },
    ],
  },
  "life-pulse": {
    lead: {
      kind: "contribution",
      eyebrow: "Life pulse",
      title: "Life in Dots",
      subtitle: "A personal instrument readout for momentum, contribution, and the current day.",
      total: "18",
      totalLabel: "meaningful captures",
      dotRows: [
        { label: "2026", percent: "22%", total: 12, filled: 3, marker: 2 },
        { label: "JULY", percent: "74%", total: 24, filled: 21, marker: 20 },
        { label: "DAY 01", percent: "24%", total: 24, filled: 7, marker: 6 },
        { label: "9:04 AM", percent: "78%", total: 12, filled: 10, marker: 9 },
      ],
    },
    line: "18 Captures / 7 Ideas / 4 Followups",
    omni: {
      placeholder: "Search your week...",
      hint: "Ideas, decisions, shares, followups",
    },
    quickActions: [
      { key: "memo", label: "Memo", icon: "compose" },
      { key: "idea", label: "Idea", icon: "sparkles" },
      { key: "review", label: "Review", icon: "tray" },
    ],
    recentCount: "18 signals",
    recentItems: [
      { source: "dictation", title: "Growth hour and faceless account idea", time: "Wed" },
      { source: "typed", title: "Homepage utility console direction", time: "Today" },
      { source: "scan", title: "Deck top area visual note", time: "Today" },
      { source: "dictation", title: "Diff treatment and version cards", time: "Wed" },
      { source: "link", title: "Chitransh thread reference", time: "Jun 22" },
    ],
    loadLabel: "Open pulse",
    exploreItems: [
      { key: "workflows", label: "Workflows", icon: "workflow" },
      { key: "terminal", label: "Terminal", icon: "terminal" },
      { key: "keyboard", label: "Keyboard", icon: "keyboard" },
    ],
  },
  "communication-cockpit": {
    lead: {
      kind: "cockpit",
      eyebrow: "Cockpit",
      module: "dots",
      title: "Communication state",
      detail: "A few things are live: one Mac bridge, one share flow, and two design decisions waiting on review.",
      status: "Live",
      lanes: [
        { label: "Bridge", value: "Art's Mac mini", meta: "ready", level: 0.92 },
        { label: "Shares", value: "2 drafts", meta: "queued", level: 0.54 },
        { label: "Replies", value: "1 prompt", meta: "waiting", level: 0.36 },
      ],
      dotRows: [
        { label: "BRDG", percent: "92%", total: 12, filled: 11, marker: 10 },
        { label: "SEND", percent: "54%", total: 12, filled: 7, marker: 6 },
        { label: "WAIT", percent: "36%", total: 12, filled: 4, marker: 3 },
      ],
    },
    line: "Bridge Live / 2 Shares / 1 Reply",
    omni: {
      placeholder: "Ask, send, share, or route...",
      hint: "Claude, Mac bridge, screenshots, memos",
    },
    quickActions: [
      { key: "share", label: "Share", icon: "link" },
      { key: "claude", label: "Claude", icon: "sparkles" },
      { key: "deck", label: "Deck", icon: "deck" },
    ],
    recentCount: "live cockpit",
    recentItems: [
      { source: "scan", title: "Latest homepage screenshot", time: "Ready" },
      { source: "typed", title: "Claude Studio review", time: "Done" },
      { source: "dictation", title: "Homepage utility direction", time: "Now" },
      { source: "link", title: "Arts-Mac-mini.local bridge", time: "Live" },
      { source: "scan", title: "Paired Macs selector", time: "Open" },
    ],
    loadLabel: "Open cockpit",
    exploreItems: [
      { key: "workflows", label: "Workflows", icon: "workflow" },
      { key: "terminal", label: "Terminal", icon: "terminal" },
      { key: "bridge", label: "Bridge", icon: "link" },
    ],
  },
  "cockpit-notifications": {
    lead: {
      kind: "cockpit",
      eyebrow: "Cockpit",
      module: "notifications",
      title: "Communication state",
      detail: "Incoming, queued, and waiting items in one compact comms center.",
      status: "Live",
      lanes: [
        { label: "Bridge", value: "Art's Mac mini", meta: "ready", level: 0.92 },
        { label: "Shares", value: "2 drafts", meta: "queued", level: 0.54 },
        { label: "Replies", value: "1 prompt", meta: "waiting", level: 0.36 },
      ],
      notifications: [
        { label: "Claude", value: "review done", tone: "done" },
        { label: "Share", value: "2 drafts", tone: "waiting" },
        { label: "Bridge", value: "live", tone: "live" },
      ],
    },
    line: "Cockpit Live / Notifications / Bridge",
    omni: {
      placeholder: "Ask, send, share, or route...",
      hint: "Mac bridge, Claude, screenshots, memos",
    },
    quickActions: [
      { key: "share", label: "Share", icon: "link" },
      { key: "claude", label: "Claude", icon: "sparkles" },
      { key: "deck", label: "Deck", icon: "deck" },
    ],
    recentCount: "live cockpit",
    recentItems: [
      { source: "scan", title: "Latest homepage screenshot", time: "Ready" },
      { source: "typed", title: "Claude Studio review", time: "Done" },
      { source: "dictation", title: "Homepage utility direction", time: "Now" },
      { source: "link", title: "Arts-Mac-mini.local bridge", time: "Live" },
      { source: "scan", title: "Paired Macs selector", time: "Open" },
    ],
    loadLabel: "Open cockpit",
    exploreItems: [
      { key: "workflows", label: "Workflows", icon: "workflow" },
      { key: "terminal", label: "Terminal", icon: "terminal" },
      { key: "bridge", label: "Bridge", icon: "link" },
    ],
  },
  "cockpit-wide": {
    lead: {
      kind: "cockpit",
      eyebrow: "Cockpit",
      module: "wide",
      title: "Communication state",
      detail: "One uninterrupted comms rectangle with no auxiliary column.",
      status: "Live",
      lanes: [
        { label: "Bridge", value: "Art's Mac mini", meta: "ready", level: 0.92 },
        { label: "Shares", value: "2 drafts", meta: "queued", level: 0.54 },
        { label: "Replies", value: "1 prompt", meta: "waiting", level: 0.36 },
      ],
    },
    line: "Cockpit Live / Full-width",
    omni: {
      placeholder: "Ask, send, share, or route...",
      hint: "Claude, Mac bridge, screenshots, memos",
    },
    quickActions: [
      { key: "share", label: "Share", icon: "link" },
      { key: "claude", label: "Claude", icon: "sparkles" },
      { key: "deck", label: "Deck", icon: "deck" },
    ],
    recentCount: "live cockpit",
    recentItems: [
      { source: "scan", title: "Latest homepage screenshot", time: "Ready" },
      { source: "typed", title: "Claude Studio review", time: "Done" },
      { source: "dictation", title: "Homepage utility direction", time: "Now" },
      { source: "link", title: "Arts-Mac-mini.local bridge", time: "Live" },
      { source: "scan", title: "Paired Macs selector", time: "Open" },
    ],
    loadLabel: "Open cockpit",
    exploreItems: [
      { key: "workflows", label: "Workflows", icon: "workflow" },
      { key: "terminal", label: "Terminal", icon: "terminal" },
      { key: "bridge", label: "Bridge", icon: "link" },
    ],
  },
  activity: {
    lead: {
      kind: "stats",
      eyebrow: "Today",
      cells: [
        { count: "1", label: "Memos" },
        { count: "1", label: "Dictations" },
        { count: "0", label: "Items", dim: true },
      ],
    },
    line: "1 Memo / 1 Dictation / 0 Items",
    quickActions: QUICK_ACTIONS,
    recentCount: "40 items",
    recentItems: RECENT_ITEMS,
    loadLabel: "Load 10 more",
  },
  pickup: {
    lead: {
      kind: "spotlight",
      eyebrow: "Pick up",
      title: "Memo Jul 1 - shape the draft",
      detail: "V2 is clean. Next best move: format it into a memo, then share the before/after.",
      meta: "Current v2 / 532 words / ready",
      status: "V2",
    },
    line: "Memo Jul 1 / V2 ready / 532 words",
    quickActions: [
      { key: "format", label: "Format", icon: "sparkles" },
      { key: "polish", label: "Polish", icon: "compose" },
      { key: "share", label: "Share", icon: "link" },
    ],
    recentCount: "3 edits",
    recentItems: [
      { source: "typed", title: "V2 - filler words removed", time: "11:35 AM" },
      { source: "dictation", title: "Original morning memo", time: "9:04 AM" },
      { source: "scan", title: "Before / after diff image", time: "Today" },
      { source: "link", title: "Share through Talkie Deck", time: "Ready" },
    ],
    loadLabel: "Open memo",
  },
  "growth-loop": {
    lead: {
      kind: "spotlight",
      eyebrow: "Today",
      title: "3 PM growth hour",
      detail: "Turn one captured thought into a small public artifact before the day loses steam.",
      meta: "1 focus block / 5 seeds / no meeting prep",
      status: "Plan",
    },
    line: "3 PM Growth / 5 seeds / 1 ship",
    quickActions: [
      { key: "memo", label: "Memo", icon: "compose" },
      { key: "prompt", label: "Prompt", icon: "sparkles" },
      { key: "capture", label: "Scan", icon: "camera" },
    ],
    recentCount: "5 seeds",
    recentItems: [
      { source: "dictation", title: "Faceless X account idea", time: "9:12 AM" },
      { source: "typed", title: "Growth-oriented activity slot", time: "9:10 AM" },
      { source: "link", title: "Chitransh thread reference", time: "Jun 22" },
      { source: "dictation", title: "Epic run / internal beat note", time: "9:05 AM" },
    ],
    loadLabel: "Open seeds",
  },
  "inbox-review": {
    lead: {
      kind: "spotlight",
      eyebrow: "Review",
      title: "2 items need a decision",
      detail: "A deck screenshot and one bridge failure note are waiting to become either tasks or memos.",
      meta: "2 pending / 1 screenshot / 1 system note",
      status: "Inbox",
    },
    line: "2 Pending / 1 Screenshot / 1 Note",
    quickActions: [
      { key: "review", label: "Review", icon: "tray" },
      { key: "memo", label: "Memo", icon: "compose" },
      { key: "ask", label: "Ask AI", icon: "sparkles" },
    ],
    recentCount: "2 pending",
    recentItems: [
      { source: "scan", title: "Deck top area visual note", time: "6:02 PM" },
      { source: "typed", title: "Direct Pair failure language", time: "10:43 AM" },
      { source: "dictation", title: "Button row treatment feedback", time: "3:57 PM" },
      { source: "link", title: "Claude design review session", time: "Live" },
    ],
    loadLabel: "Review inbox",
  },
  "bridge-ready": {
    lead: {
      kind: "spotlight",
      eyebrow: "Mac bridge",
      title: "Art's Mac mini is live",
      detail: "Trackpad, paste, enter, and image sharing should route through the bridge without Talkie.app.",
      meta: "Local / TalkieAgent / 0 queued",
      status: "Live",
    },
    line: "Art's Mac mini / Live / 0 queued",
    quickActions: [
      { key: "deck", label: "Deck", icon: "deck" },
      { key: "paste", label: "Paste", icon: "keyboard" },
      { key: "share", label: "Share", icon: "link" },
    ],
    recentCount: "live link",
    recentItems: [
      { source: "typed", title: "Arts-Mac-mini.local", time: "Live" },
      { source: "scan", title: "Latest deck screenshot", time: "Ready" },
      { source: "dictation", title: "Trackpad y-axis report", time: "3:25 PM" },
      { source: "link", title: "Pairing settings clarity pass", time: "Open" },
    ],
    loadLabel: "Open bridge",
  },
};

export function Home({ variant = "baseline", contentIdea = "activity" }: HomeProps) {
  const compactTicker = variant === "ticker-line";
  const grouped = variant === "grouped-rhythm";
  const simpleRecent = variant === "simple-recent";
  const deduped = variant === "deduped-quick";
  const calibrated = variant === "material-calibration";
  const content = HOME_CONTENT[contentIdea];
  const hasLead = content.lead.kind !== "none";

  return (
    <div
      className="relative flex h-full flex-col overflow-hidden"
      style={{ background: "var(--theme-canvas)" }}
    >
      {/* `var(--theme-eyebrow-leader)` is a CSS string var; emit via ::before
          (same pattern as MacLearnKB) so ·/—/› follow the theme. */}
      <style>{`.home-eyebrow-leader::before { content: var(--theme-eyebrow-leader, "\\B7"); }`}</style>
      <CanvasLight calibrated={calibrated} />
      <StatusBar time="6:02" />
      <HomeHeader />

      <main
        className="relative z-[1] flex min-h-0 flex-1 flex-col px-3"
        style={{
          paddingTop: hasLead ? (grouped ? 2 : 6) : 2,
          paddingBottom: 96,
          gap: hasLead && grouped ? 0 : 10,
        }}
      >
        {hasLead ? (
          compactTicker ? <TodayLine line={content.line} /> : <HomeLead lead={content.lead} />
        ) : null}

        {hasLead ? <div style={{ height: grouped ? 18 : 0 }} /> : null}
        <QuickDeck actions={content.quickActions} deduped={deduped} calibrated={calibrated} />

        {content.omni ? <OmniSearch {...content.omni} /> : null}

        {hasLead ? <div style={{ height: grouped ? 18 : 0 }} /> : null}
        <RecentScreen
          mode={simpleRecent ? "simple" : "full"}
          calibrated={calibrated}
          count={content.recentCount}
          items={content.recentItems}
          loadLabel={content.loadLabel}
        />

        <div style={{ height: grouped ? 12 : 0 }} />
        <ExploreRail items={content.exploreItems} deduped={deduped} calibrated={calibrated} />
      </main>

      <VoicePivot />
      <MicFab />
    </div>
  );
}

function CanvasLight({ calibrated }: { calibrated: boolean }) {
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0 z-0"
      style={{
        background: calibrated
          ? "radial-gradient(circle at 50% 13%, var(--theme-ambient) 0%, transparent 44%), linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.035) 100%)"
          : "radial-gradient(circle at 50% 13%, var(--theme-ambient) 0%, transparent 46%)",
        mixBlendMode: "normal",
      }}
    />
  );
}

function HomeHeader() {
  // Swift keeps the Deck complication in every variant — the de-duped
  // premise is that Explore can drop Deck BECAUSE the header owns it.
  // No status bead: HomeNextView exposes bridge state via the Deck
  // surface + accessibility, not a dot.
  return (
    <header className="relative z-[1] flex items-center justify-between px-5 pb-2 pt-1.5">
      <CircleButton label="Deck" icon="deck" />
      <div
        className="text-[12px] font-bold uppercase leading-none"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        Talkie
      </div>
      <CircleButton label="Settings" icon="gear" />
    </header>
  );
}

function CircleButton({ label, icon }: { label: string; icon: IconName }) {
  return (
    <button
      aria-label={label}
      className="relative flex h-10 w-10 items-center justify-center rounded-full"
      style={{
        color: "var(--theme-ink-dim)",
        background: "linear-gradient(180deg, var(--theme-metal-top), transparent 52%, var(--theme-metal-bottom)), var(--theme-paper)",
        border: "var(--theme-hairline-w) solid var(--theme-edge-dim)",
        boxShadow: "var(--theme-card-shadow-strong)",
      }}
    >
      <Icon name={icon} size={16} />
    </button>
  );
}

function HomeLead({ lead }: { lead: HomeContentModel["lead"] }) {
  if (lead.kind === "none") {
    return null;
  }

  if (lead.kind === "spotlight") {
    return <SpotlightLead lead={lead} />;
  }

  if (lead.kind === "contribution") {
    return <ContributionLead lead={lead} />;
  }

  if (lead.kind === "cockpit") {
    return <CockpitLead lead={lead} />;
  }

  return (
    <section className="space-y-2">
      <Eyebrow>{lead.eyebrow}</Eyebrow>
      <div className="grid grid-cols-3">
        {lead.cells.map((cell) => (
          <TodayCell key={cell.label} {...cell} />
        ))}
      </div>
    </section>
  );
}

function SpotlightLead({
  lead,
}: {
  lead: Extract<HomeContentModel["lead"], { kind: "spotlight" }>;
}) {
  return (
    <section className="space-y-2">
      <Eyebrow>{lead.eyebrow}</Eyebrow>
      <button
        className="w-full overflow-hidden text-left"
        style={{
          borderRadius: 12,
          background: "linear-gradient(180deg, var(--theme-metal-top), transparent 60%, var(--theme-metal-bottom)), var(--theme-paper)",
          border: "var(--theme-hairline-w) solid var(--theme-edge-dim)",
          boxShadow: "var(--theme-card-shadow-strong)",
        }}
      >
        <div className="flex items-start gap-3 px-3.5 py-3">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <h2
                className="min-w-0 flex-1 truncate text-[17px] leading-tight"
                style={{
                  color: "var(--theme-ink)",
                  fontFamily: "var(--theme-font-body)",
                  fontWeight: 500,
                }}
              >
                {lead.title}
              </h2>
              {lead.status ? (
                <span
                  className="flex-none rounded-full px-2 py-0.5 text-[8px] font-semibold uppercase"
                  style={{
                    color: "var(--theme-accent)",
                    border: "var(--theme-hairline-w) solid var(--theme-amber-soft)",
                    fontFamily: "var(--theme-font-mono)",
                    letterSpacing: "0.18em",
                  }}
                >
                  {lead.status}
                </span>
              ) : null}
            </div>
            <p
              className="mt-2 line-clamp-2 text-[12px] leading-[1.45]"
              style={{
                color: "var(--theme-ink-muted)",
                fontFamily: "var(--theme-font-body)",
              }}
            >
              {lead.detail}
            </p>
            <p
              className="mt-2 truncate text-[9px] font-semibold uppercase"
              style={{
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.16em",
              }}
            >
              {lead.meta}
            </p>
          </div>
        </div>
      </button>
    </section>
  );
}

function ContributionLead({
  lead,
}: {
  lead: Extract<HomeContentModel["lead"], { kind: "contribution" }>;
}) {
  return (
    <section className="space-y-2">
      <Eyebrow>{lead.eyebrow}</Eyebrow>
      <button
        className="w-full overflow-hidden text-center"
        style={{
          borderRadius: 12,
          background: "linear-gradient(180deg, var(--theme-metal-top), transparent 60%, var(--theme-metal-bottom)), var(--theme-paper)",
          border: "var(--theme-hairline-w) solid var(--theme-edge-dim)",
          boxShadow: "var(--theme-card-shadow-strong)",
        }}
      >
        <div className="px-4 py-3.5">
          <div
            className="mx-auto max-w-[286px] rounded-[14px] px-2.5 py-3"
            style={{
              background: "var(--theme-screen-bg)",
              border: "var(--theme-hairline-w) solid rgba(255,255,255,0.10)",
              boxShadow: "inset 0 0.5px 0 rgba(255,255,255,0.10), 0 10px 24px -18px rgba(0,0,0,0.65)",
            }}
          >
            <div className="space-y-2.5">
              {lead.dotRows.map((row) => (
                <DotMatrixRow key={row.label} row={row} />
              ))}
            </div>
          </div>

          <div className="mt-3">
            <h2
              className="text-[18px] leading-none"
              style={{
                color: "var(--theme-ink)",
                fontFamily: "var(--theme-font-display)",
                fontWeight: 500,
                letterSpacing: "0",
              }}
            >
              {lead.title}
            </h2>
            <p
              className="mx-auto mt-1 max-w-[250px] truncate text-[9px] font-semibold uppercase"
              style={{
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.12em",
              }}
            >
              [{lead.total}] {lead.totalLabel}
            </p>
          </div>
        </div>
      </button>
    </section>
  );
}

function DotMatrixRow({
  row,
}: {
  row: Extract<HomeContentModel["lead"], { kind: "contribution" }>["dotRows"][number];
}) {
  return (
    <div className="grid items-center gap-2" style={{ gridTemplateColumns: "54px 1fr 32px" }}>
      <div
        className="truncate text-left text-[9px] font-semibold uppercase"
        style={{
          color: "rgba(255,255,255,0.64)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.08em",
        }}
      >
        {row.label}
      </div>
      <div
        className="grid gap-[3px]"
        style={{ gridTemplateColumns: "repeat(12, 7px)" }}
      >
        {Array.from({ length: row.total }, (_, index) => {
          const isMarker = index === row.marker;
          const isFilled = index < row.filled;

          return (
            <span
              key={index}
              aria-hidden
              className="h-[7px] w-[7px] rounded-full"
              style={{
                background: isMarker
                  ? "var(--theme-rec)"
                  : isFilled
                    ? "rgba(255,255,255,0.94)"
                    : "transparent",
                border: isFilled ? "0" : "1px solid rgba(255,255,255,0.20)",
                boxShadow: isMarker ? "0 0 8px var(--theme-rec-glow)" : "none",
              }}
            />
          );
        })}
      </div>
      <div
        className="text-right text-[9px] font-semibold tabular-nums"
        style={{
          color: "rgba(255,255,255,0.72)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {row.percent}
      </div>
    </div>
  );
}

function CockpitLead({
  lead,
}: {
  lead: Extract<HomeContentModel["lead"], { kind: "cockpit" }>;
}) {
  return (
    <section className="space-y-2">
      <Eyebrow>{lead.eyebrow}</Eyebrow>
      <button
        className="w-full overflow-hidden text-left"
        style={{
          borderRadius: 12,
          background: "linear-gradient(180deg, var(--theme-metal-top), transparent 58%, var(--theme-metal-bottom)), var(--theme-paper)",
          border: "var(--theme-hairline-w) solid var(--theme-edge-dim)",
          boxShadow: "var(--theme-card-shadow-strong)",
        }}
      >
        <div className="px-3 py-3">
          <div
            className="overflow-hidden rounded-[18px] px-3 py-2.5"
            style={{
              background:
                "radial-gradient(circle at 50% 44%, var(--theme-amber-glow), transparent 32%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02) 45%, rgba(0,0,0,0.24)), var(--theme-screen-bg)",
              border: "var(--theme-hairline-w) solid rgba(255,255,255,0.14)",
              boxShadow: "inset 0 0.5px 0 rgba(255,255,255,0.16), inset 0 -18px 28px -28px rgba(0,0,0,0.85)",
            }}
          >
            <div
              className="mb-2 flex items-center justify-between text-[7px] font-semibold uppercase"
              style={{
                color: "rgba(255,255,255,0.64)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.12em",
              }}
            >
              <span>Talkie</span>
              <span style={{ color: "var(--theme-accent)" }}>{lead.status}</span>
              <span>20:04</span>
            </div>

            <div
              className="grid items-center gap-3"
              style={{ gridTemplateColumns: lead.module === "wide" ? "1fr" : "1fr 84px" }}
            >
              <div className="space-y-1.5">
                {lead.lanes.map((lane) => (
                  <CommsLane key={lane.label} lane={lane} />
                ))}
              </div>
              {lead.module === "dots" ? <CockpitDots rows={lead.dotRows ?? []} /> : null}
              {lead.module === "notifications" ? (
                <CockpitNotifications notifications={lead.notifications ?? []} />
              ) : null}
            </div>
          </div>
          <div className="mt-2 px-1">
            <p
              className="truncate text-center text-[9px] font-semibold uppercase"
              style={{
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.12em",
              }}
            >
              {lead.detail}
            </p>
          </div>
        </div>
      </button>
    </section>
  );
}

function CommsLane({
  lane,
}: {
  lane: Extract<HomeContentModel["lead"], { kind: "cockpit" }>["lanes"][number];
}) {
  return (
    <div
      className="rounded-md px-2 py-1.5"
      style={{
        background: "rgba(255,255,255,0.035)",
        border: "1px solid rgba(255,255,255,0.08)",
      }}
    >
      <div className="flex items-baseline gap-2">
        <span
          className="w-12 flex-none text-[7px] font-semibold uppercase"
          style={{
            color: "rgba(255,255,255,0.54)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.1em",
          }}
        >
          {lane.label}
        </span>
        <span
          className="min-w-0 flex-1 truncate text-[10px]"
          style={{
            color: "rgba(255,255,255,0.88)",
            fontFamily: "var(--theme-font-body)",
          }}
        >
          {lane.value}
        </span>
        <span
          className="text-[7px] font-semibold uppercase"
          style={{
            color: "var(--theme-accent)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.08em",
          }}
        >
          {lane.meta}
        </span>
      </div>
      <div className="mt-1 flex gap-[3px]">
        {Array.from({ length: 12 }, (_, index) => (
          <span
            key={index}
            aria-hidden
            className="h-[3px] flex-1 rounded-full"
            style={{
              background:
                index < Math.round(lane.level * 12)
                  ? "var(--theme-accent)"
                  : "rgba(255,255,255,0.10)",
              boxShadow: index === Math.round(lane.level * 12) - 1 ? "0 0 6px var(--theme-amber-glow)" : "none",
            }}
          />
        ))}
      </div>
    </div>
  );
}

function CockpitDots({
  rows,
}: {
  rows: NonNullable<Extract<HomeContentModel["lead"], { kind: "cockpit" }>["dotRows"]>;
}) {
  return (
    <div
      className="flex h-[92px] flex-col justify-center gap-2 overflow-hidden rounded-lg px-2"
      style={{
        background: "rgba(255,255,255,0.035)",
        border: "1px solid rgba(255,255,255,0.08)",
      }}
    >
      {rows.map((row) => (
        <div key={row.label} className="space-y-1">
          <div
            className="flex justify-between text-[6px] font-semibold uppercase"
            style={{
              color: "rgba(255,255,255,0.56)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.06em",
            }}
          >
            <span>{row.label}</span>
            <span>{row.percent}</span>
          </div>
          <div className="grid gap-[3px]" style={{ gridTemplateColumns: "repeat(6, 1fr)" }}>
            {Array.from({ length: row.total }, (_, index) => {
              const isMarker = index === row.marker;
              const isFilled = index < row.filled;

              return (
                <span
                  key={index}
                  aria-hidden
                  className="h-[5px] w-[5px] rounded-full"
                  style={{
                    background: isMarker
                      ? "var(--theme-rec)"
                      : isFilled
                        ? "rgba(255,255,255,0.92)"
                        : "transparent",
                    border: isFilled ? "0" : "1px solid rgba(255,255,255,0.18)",
                    boxShadow: isMarker ? "0 0 7px var(--theme-rec-glow)" : "none",
                  }}
                />
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

function CockpitNotifications({
  notifications,
}: {
  notifications: NonNullable<Extract<HomeContentModel["lead"], { kind: "cockpit" }>["notifications"]>;
}) {
  return (
    <div
      className="flex h-[92px] flex-col justify-center gap-1.5 overflow-hidden rounded-lg px-2"
      style={{
        background: "rgba(255,255,255,0.035)",
        border: "1px solid rgba(255,255,255,0.08)",
      }}
    >
      {notifications.map((notification) => (
        <div
          key={notification.label}
          className="rounded-md px-1.5 py-1"
          style={{
            background: "rgba(255,255,255,0.035)",
            border: "1px solid rgba(255,255,255,0.07)",
          }}
        >
          <div
            className="flex items-center gap-1 text-[6px] font-semibold uppercase"
            style={{
              color: "rgba(255,255,255,0.54)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.07em",
            }}
          >
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{
                background:
                  notification.tone === "live"
                    ? "var(--theme-accent)"
                    : notification.tone === "waiting"
                      ? "var(--theme-rec)"
                      : "rgba(255,255,255,0.72)",
                boxShadow: notification.tone === "live" ? "0 0 7px var(--theme-amber-glow)" : "none",
              }}
            />
            <span className="truncate">{notification.label}</span>
          </div>
          <div
            className="mt-0.5 truncate text-[9px]"
            style={{ color: "rgba(255,255,255,0.88)", fontFamily: "var(--theme-font-body)" }}
          >
            {notification.value}
          </div>
        </div>
      ))}
    </div>
  );
}

function TodayLine({ line }: { line: string }) {
  return (
    <section
      className="flex h-8 items-center justify-center rounded-[var(--theme-chrome-corner)] px-3 text-[11px] font-semibold uppercase"
      style={{
        color: "var(--theme-ink-faint)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.16em",
        border: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
        background: "var(--theme-action-faint)",
      }}
    >
      <span className="truncate">{line}</span>
    </section>
  );
}

function TodayCell({ count, label, dim = false }: { count: string; label: string; dim?: boolean }) {
  return (
    <button
      className="flex flex-col items-center justify-center gap-1 border-r py-1.5 last:border-r-0"
      style={{
        borderColor: "var(--theme-edge-faint)",
        color: dim ? "var(--theme-ink-faint)" : "var(--theme-ink)",
      }}
    >
      <span
        className="text-[15px] leading-none tabular-nums"
        style={{ fontFamily: "var(--theme-font-mono)" }}
      >
        {count}
      </span>
      <span
        className="text-[8px] font-semibold uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        {label}
      </span>
    </button>
  );
}

function QuickDeck({
  actions,
  deduped,
  calibrated,
}: {
  actions: QuickAction[];
  deduped: boolean;
  calibrated: boolean;
}) {
  const visibleActions = deduped ? actions.filter((action) => action.key !== "record") : actions;

  return (
    <section className="space-y-2">
      {!deduped ? <Eyebrow>Quick</Eyebrow> : null}
      <div
        className="grid overflow-hidden"
        style={{
          gridTemplateColumns: `repeat(${visibleActions.length}, minmax(0, 1fr))`,
          borderRadius: calibrated ? "var(--theme-chrome-corner)" : 12,
          background: "linear-gradient(180deg, var(--theme-metal-top), transparent 52%, var(--theme-metal-bottom)), var(--theme-paper)",
          border: "var(--theme-hairline-w) solid var(--theme-edge-dim)",
          boxShadow: "var(--theme-card-shadow-strong)",
        }}
      >
        {visibleActions.map((action) => (
          <button
            key={action.key}
            className="flex h-[56px] flex-col items-center justify-center gap-2 border-r last:border-r-0"
            style={{
              borderColor: "var(--theme-edge-faint)",
              // chrome.action in Swift (HomeNextView actionCell) — neutral
              // affordance ink, not accent; the FAB is the one lit anchor.
              color: "var(--theme-action)",
            }}
          >
            <Icon name={action.icon as IconName} size={15} />
            <span
              className="text-[10px] font-semibold uppercase"
              style={{
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.24em",
                color: "var(--theme-ink-dim)",
              }}
            >
              {action.label}
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}

function OmniSearch({ placeholder, hint }: { placeholder: string; hint: string }) {
  return (
    <section className="space-y-1.5">
      <button
        className="flex h-11 w-full items-center gap-2.5 rounded-full px-3.5 text-left"
        style={{
          color: "var(--theme-ink-muted)",
          background: "var(--theme-paper)",
          border: "var(--theme-hairline-w) solid var(--theme-edge-dim)",
          boxShadow: "inset 0 0.5px 0 var(--theme-metal-top)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        <span style={{ color: "var(--theme-accent)" }}>
          <Icon name="sparkles" size={15} />
        </span>
        <span className="min-w-0 flex-1 truncate text-[14px]">{placeholder}</span>
        <span
          className="flex h-7 w-7 flex-none items-center justify-center rounded-full"
          style={{
            color: "var(--theme-action)",
            border: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
            background: "var(--theme-action-faint)",
          }}
        >
          <Icon name="mic" size={14} />
        </span>
      </button>
      <p
        className="truncate px-3 text-[9px] font-semibold uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.14em",
        }}
      >
        {hint}
      </p>
    </section>
  );
}

function RecentScreen({
  mode,
  calibrated,
  count,
  items,
  loadLabel,
}: {
  mode: RecentMode;
  calibrated: boolean;
  count: string;
  items: RecentItem[];
  loadLabel: string;
}) {
  return (
    <section className="min-h-0 space-y-2">
      <RecentHeader mode={mode} count={count} />
      <div
        className="overflow-hidden"
        style={{
          borderRadius: calibrated ? "var(--theme-chrome-corner)" : 10,
          background: calibrated ? "var(--theme-panel)" : "var(--theme-paper)",
          border: "var(--theme-hairline-w) solid var(--theme-edge)",
          boxShadow: "inset 0 10px 12px -12px var(--theme-recess-lip)",
        }}
      >
        {items.map((item, index) => (
          <RecentRow key={item.title} {...item} divider={index > 0} />
        ))}
        <button
          className="flex h-[38px] w-full items-center justify-center gap-2 border-t text-[14px]"
          style={{
            borderColor: "var(--theme-edge-subtle)",
            color: "var(--theme-ink-dim)",
            fontFamily: "var(--theme-font-body)",
          }}
        >
          <Icon name="arrowDown" size={12} />
          <span>{loadLabel}</span>
        </button>
      </div>
    </section>
  );
}

function RecentHeader({ mode, count }: { mode: RecentMode; count: string }) {
  return (
    <div className="flex h-7 items-center gap-2">
      <Eyebrow strong>Recent</Eyebrow>
      <span
        className="text-[11px] font-medium tabular-nums"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {count}
      </span>
      <span className="ml-auto" />
      {mode === "full" ? (
        <>
          <SmallIconButton icon="tray" label="Filter" />
          <SmallIconButton icon="arrowDown" label="Sort" />
        </>
      ) : null}
      <button
        className="flex items-center gap-1 text-[11px] font-semibold uppercase"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.20em",
        }}
      >
        All <span aria-hidden>›</span>
      </button>
    </div>
  );
}

function RecentRow({
  source,
  title,
  time,
  divider,
}: {
  source: ListRowSource;
  title: string;
  time: string;
  divider: boolean;
}) {
  return (
    // 38px rows + full-width hairlines mirror HomeRecentMetrics.rowHeight
    // and the edge-to-edge divider in RecentRow.
    <div className="relative flex h-[38px] items-center gap-2 px-3">
      {divider ? (
        <span
          aria-hidden
          className="absolute inset-x-0 top-0 h-px"
          style={{ background: "var(--theme-edge-subtle)" }}
        />
      ) : null}
      <span
        className="flex h-4 w-4 items-center justify-center"
        style={{ color: "var(--theme-ink-faint)" }}
      >
        <Icon
          name={
            source === "typed"
              ? "keyboard"
              : source === "link"
                ? "link"
                : source === "scan"
                  ? "camera"
                  : "waveform"
          }
          size={13}
        />
      </span>
      <span
        className="min-w-0 flex-1 truncate text-[16px]"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-body)",
          fontWeight: 400,
        }}
      >
        {title}
      </span>
      <span
        className="text-[10px] tabular-nums"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          fontWeight: 500,
        }}
      >
        {time}
      </span>
    </div>
  );
}

function ExploreRail({
  items: providedItems,
  deduped,
  calibrated,
}: {
  items?: QuickAction[];
  deduped: boolean;
  calibrated: boolean;
}) {
  const baseItems = providedItems ?? EXPLORE_ITEMS;
  const items = deduped
    ? baseItems.filter((item) => item.key !== "deck" && item.key !== "library")
    : baseItems;

  return (
    <section className="min-h-0 space-y-2">
      <Eyebrow>Explore</Eyebrow>
      <div className="flex gap-2 overflow-hidden">
        {items.map((item) => (
          <button
            key={item.key}
            className="flex h-9 flex-none items-center gap-1.5 rounded-full px-3"
            style={{
              color: "var(--theme-ink-dim)",
              background: "var(--theme-paper)",
              border: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
              fontFamily: "var(--theme-font-body)",
            }}
          >
            {/* Swift paints the chip glyph in chrome.accent (the rail's one
                chromatic anchor); calibration swaps it to action ink. */}
            <span
              className="flex"
              style={{ color: calibrated ? "var(--theme-action)" : "var(--theme-accent)" }}
            >
              <Icon name={item.icon as IconName} size={13} />
            </span>
            <span className="text-[12px]">{item.label}</span>
          </button>
        ))}
      </div>
    </section>
  );
}

function MicFab() {
  // ChromeOverlay MicFAB: 56pt accent-filled circle, paper glyph,
  // accent-glow shadow — the one lit anchor on the surface.
  return (
    <button
      aria-label="Record"
      className="absolute bottom-3 left-1/2 z-[2] flex h-14 w-14 -translate-x-1/2 items-center justify-center rounded-full"
      style={{
        background: "var(--theme-accent)",
        color: "var(--theme-paper)",
        boxShadow: "0 2px 6px var(--theme-amber-glow), 0 8px 20px -10px rgba(0,0,0,0.30)",
      }}
    >
      <Icon name="mic" size={24} />
    </button>
  );
}

function VoicePivot() {
  return (
    <button
      aria-label="Summon voice chrome"
      className="absolute bottom-4 left-5 z-[2] flex h-12 w-12 items-center justify-center rounded-full"
      style={{
        color: "var(--theme-ink-dim)",
        background: "var(--theme-paper)",
        border: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
        boxShadow: "var(--theme-card-shadow-strong)",
      }}
    >
      <Icon name="broadcast" size={20} />
    </button>
  );
}

function Eyebrow({ children, strong = false }: { children: ReactNode; strong?: boolean }) {
  // All Home eyebrows sit at textSecondary in Swift, leader included —
  // RECENT differentiates through wider tracking (channelLabel 2.4 vs
  // channelLabelTiny 1.8), not through ink or accent.
  return (
    <div
      className="flex items-center gap-2 text-[10px] font-semibold uppercase"
      style={{
        color: "var(--theme-ink-dim)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: strong ? "0.24em" : "0.18em",
      }}
    >
      <span aria-hidden className="home-eyebrow-leader" />
      {children}
    </div>
  );
}

function SmallIconButton({ icon, label }: { icon: IconName; label: string }) {
  return (
    <button
      aria-label={label}
      className="flex h-7 w-7 items-center justify-center rounded-full"
      style={{
        color: "var(--theme-ink-faint)",
        border: "var(--theme-hairline-w) solid var(--theme-edge-faint)",
      }}
    >
      <Icon name={icon} size={16} />
    </button>
  );
}

type IconName =
  | "arrowDown"
  | "broadcast"
  | "camera"
  | "compose"
  | "deck"
  | "gear"
  | "home"
  | "keyboard"
  | "library"
  | "link"
  | "mic"
  | "sparkles"
  | "terminal"
  | "tray"
  | "waveform"
  | "workflow";

function Icon({ name, size = 16 }: { name: IconName; size?: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };

  if (name === "deck") {
    return (
      <svg {...common}>
        {[5, 10, 15].map((x) => [5, 10, 15].map((y) => (
          <rect key={`${x}-${y}`} x={x - 1.7} y={y - 1.7} width={3.4} height={3.4} rx={0.6} />
        )))}
      </svg>
    );
  }
  if (name === "gear") {
    return (
      <svg {...common}>
        <circle cx={12} cy={12} r={3.2} />
        <path d="M12 2.8v2.3M12 18.9v2.3M4.2 4.2l1.6 1.6M18.2 18.2l1.6 1.6M2.8 12h2.3M18.9 12h2.3M4.2 19.8l1.6-1.6M18.2 5.8l1.6-1.6" />
      </svg>
    );
  }
  if (name === "home") {
    return (
      <svg {...common}>
        <path d="M4 11.5 12 4l8 7.5" />
        <path d="M6.5 10.5V20h11v-9.5" />
      </svg>
    );
  }
  if (name === "waveform") {
    return (
      <svg {...common}>
        <path d="M3 12h.1M6 8v8M9 5v14M12 8v8M15 6v12M18 9v6M21 12h.1" />
      </svg>
    );
  }
  if (name === "compose") {
    return (
      <svg {...common}>
        <path d="M4 20h16" />
        <path d="M6 18l10.5-10.5 2 2L8 20H6z" />
        <path d="M14.8 5.2l2 2" />
      </svg>
    );
  }
  if (name === "camera") {
    return (
      <svg {...common}>
        <rect x={4} y={7} width={16} height={12} rx={2} />
        <path d="M9 7l1.4-2h3.2L15 7" />
        <circle cx={12} cy={13} r={3} />
      </svg>
    );
  }
  if (name === "sparkles") {
    return (
      <svg {...common}>
        <path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5L12 3z" />
        <path d="M5 14l.8 2.2L8 17l-2.2.8L5 20l-.8-2.2L2 17l2.2-.8L5 14z" />
        <path d="M19 4l.6 1.4L21 6l-1.4.6L19 8l-.6-1.4L17 6l1.4-.6L19 4z" />
      </svg>
    );
  }
  if (name === "keyboard") {
    return (
      <svg {...common}>
        <rect x={3} y={6} width={18} height={12} rx={2} />
        <path d="M7 10h.1M11 10h.1M15 10h.1M7 14h10" />
      </svg>
    );
  }
  if (name === "link") {
    return (
      <svg {...common}>
        <path d="M10 13a5 5 0 0 0 7.1 0l1.4-1.4a5 5 0 0 0-7.1-7.1L10.5 5.4" />
        <path d="M14 11a5 5 0 0 0-7.1 0l-1.4 1.4a5 5 0 0 0 7.1 7.1l.9-.9" />
      </svg>
    );
  }
  if (name === "library") {
    return (
      <svg {...common}>
        <path d="M4 19V5M9 19V5M14 19V5M19 19V5" />
        <path d="M4 19h15" />
      </svg>
    );
  }
  if (name === "workflow") {
    return (
      <svg {...common}>
        <circle cx={5} cy={7} r={2} />
        <circle cx={19} cy={7} r={2} />
        <circle cx={12} cy={18} r={2} />
        <path d="M7 8l3.5 7M17 8l-3.5 7M7 7h10" />
      </svg>
    );
  }
  if (name === "terminal") {
    return (
      <svg {...common}>
        <rect x={3} y={5} width={18} height={14} rx={2} />
        <path d="M7 10l3 2-3 2M12 15h5" />
      </svg>
    );
  }
  if (name === "mic") {
    return (
      <svg {...common}>
        <rect x={9} y={3} width={6} height={11} rx={3} />
        <path d="M5 11a7 7 0 0 0 14 0M12 18v3M8 21h8" />
      </svg>
    );
  }
  if (name === "broadcast") {
    return (
      <svg {...common}>
        <path d="M7 7a7 7 0 0 0 0 10M17 7a7 7 0 0 1 0 10M9.5 9.5a3.5 3.5 0 0 0 0 5M14.5 9.5a3.5 3.5 0 0 1 0 5" />
        <circle cx={12} cy={12} r={1.2} fill="currentColor" stroke="none" />
      </svg>
    );
  }
  if (name === "tray") {
    return (
      <svg {...common}>
        <path d="M4 14h4l2 3h4l2-3h4" />
        <path d="M6 10h12M7 6h10" />
        <path d="M4 14v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4" />
      </svg>
    );
  }
  if (name === "arrowDown") {
    return (
      <svg {...common}>
        <path d="M12 5v14M6 13l6 6 6-6" />
      </svg>
    );
  }
  return null;
}
