export type HomeVariant =
  | "baseline"
  | "ticker-line"
  | "grouped-rhythm"
  | "simple-recent"
  | "deduped-quick"
  | "material-calibration";

export type HomeContentIdea =
  | "utility-console"
  | "life-pulse"
  | "communication-cockpit"
  | "cockpit-notifications"
  | "cockpit-wide"
  | "activity"
  | "pickup"
  | "growth-loop"
  | "inbox-review"
  | "bridge-ready";

export const HOME_VARIANTS: Array<{
  key: HomeVariant;
  label: string;
  intent: string;
}> = [
  {
    key: "baseline",
    label: "Current Swift",
    intent: "Parity target: today's ticker, raised Quick deck, recessed Recent, Explore rail.",
  },
  {
    key: "ticker-line",
    label: "Ticker Demoted",
    intent: "Collapses Today into one quiet line so Recent gets more vertical authority.",
  },
  {
    key: "grouped-rhythm",
    label: "Grouped Rhythm",
    intent: "Tighter header stats, larger pauses before Quick and Recent, stronger section grouping.",
  },
  {
    key: "simple-recent",
    label: "Simple Recent",
    intent: "Keeps the Home list focused: Recent count left, one All action right.",
  },
  {
    key: "deduped-quick",
    label: "De-duped Quick",
    intent: "Lets the FAB own recording and removes Deck from Explore.",
  },
  {
    key: "material-calibration",
    label: "Material Calibration",
    intent: "Extends action ink to the Explore rail and darkens the recessed fill to test theme token clarity.",
  },
];

export const HOME_CONTENT_IDEAS: Array<{
  key: HomeContentIdea;
  label: string;
  intent: string;
}> = [
  {
    key: "utility-console",
    label: "Utility Console",
    intent: "No Today stats: shortcuts first, omni command/search second, then a deeper Recent list.",
  },
  {
    key: "life-pulse",
    label: "Life Pulse",
    intent: "A pulse only earns space if it shows contribution and momentum, not bookkeeping.",
  },
  {
    key: "communication-cockpit",
    label: "Cockpit Dots",
    intent: "Communication cockpit with Life-in-Dots style contribution/status readout.",
  },
  {
    key: "cockpit-notifications",
    label: "Cockpit Inbox",
    intent: "Communication cockpit with a notification-center module instead of a chart.",
  },
  {
    key: "cockpit-wide",
    label: "Cockpit Full-Width",
    intent: "One uninterrupted comms rectangle: no right column, just routing lanes.",
  },
  {
    key: "activity",
    label: "Activity Pulse",
    intent: "Current neutral Home content: counts, recent captures, and quick entry points.",
  },
  {
    key: "pickup",
    label: "Pick Up Memo",
    intent: "Lead with the next useful edit on the current memo instead of today's totals.",
  },
  {
    key: "growth-loop",
    label: "Growth Loop",
    intent: "Turn the morning memo into a lightweight daily plan and creative prompt.",
  },
  {
    key: "inbox-review",
    label: "Review Inbox",
    intent: "Make Home feel like a triage surface for screenshots, shares, and pending AI output.",
  },
  {
    key: "bridge-ready",
    label: "Bridge Ready",
    intent: "Use Home to clarify Mac pairing state and the next cross-device action.",
  },
];
