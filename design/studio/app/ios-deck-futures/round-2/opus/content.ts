/**
 * Content truth for the Standing Page at-bat.
 *
 * Every value here is either (a) something the Codex bridge can actually
 * observe today, or (b) quoted text that Codex itself produced. Nothing in
 * this file invents progress percentages, token counts, queue depth,
 * continuous telemetry, or reasoning traces.
 *
 * Two deliberate honesty rules carried over from the model flight:
 *   1. A task whose state Talkie cannot observe renders with NO state mark.
 *      It never renders a false `Idle`.
 *   2. `Needs you` is observable but not resolvable in Talkie. The sill
 *      states where the answer has to happen instead of offering a control
 *      the bridge cannot complete.
 */

export const MAC = {
  name: "Arachs-Mac-Mini.Local",
  since: "connected since 09:14",
  lastHeard: "11 minutes ago",
} as const;

/** State Talkie can truthfully derive from bridge events. */
export type TaskState = "working" | "idle" | "needs-you" | "unknown";

export type ResultBlock =
  | { kind: "prose"; text: string }
  | { kind: "quoted"; lines: string[]; caption: string };

export interface Task {
  id: string;
  /** Spine label. Kept short enough to read vertically at a glance. */
  name: string;
  project: string;
  branch: string;
  state: TaskState;
  /** Plain-language state word shown on the page. `null` when unobservable. */
  stateWord: string | null;
  /** The last thing the user said to this task, verbatim. */
  instruction: { text: string; at: string } | null;
  /** Truthful activity prose — only present while a turn is running. */
  activity: { text: string; started: string } | null;
  /** The blocking question, quoted from Codex. */
  question: string | null;
  /** The latest returned result. */
  result: {
    at: string;
    turn: string;
    blocks: ResultBlock[];
  } | null;
  /** Shown when there is genuinely nothing to read yet. */
  emptyNote: string | null;
  /** Provenance revealed on request, never up front. */
  detail: string[];
}

export const TASKS: Task[] = [
  {
    id: "bridge-reconnect",
    name: "Bridge reconnect flow",
    project: "talkie",
    branch: "codex/bridge-reconnect",
    state: "working",
    stateWord: "Working",
    instruction: {
      text: "Make the reconnect path recover without restarting the app when the Mac comes back on a new address.",
      at: "14:58",
    },
    activity: {
      text: "Codex is editing NearbyMacBrowser.swift.",
      started: "started 4 minutes ago",
    },
    question: null,
    result: null,
    emptyNote: "This turn has not returned a result yet.",
    detail: [
      "turn 3 · dispatched from this iPad",
      "codex/bridge-reconnect · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
  {
    id: "companion-shortcuts",
    name: "Companion shortcut actions",
    project: "talkie",
    branch: "feat/agent-companion-direct",
    state: "idle",
    stateWord: "Idle",
    instruction: {
      text: "Make the companion shortcuts route straight to the agent instead of going through the app, and fall back if the agent isn’t up.",
      at: "14:19",
    },
    activity: null,
    question: null,
    result: {
      at: "14:32",
      turn: "turn 6",
      blocks: [
        {
          kind: "prose",
          text: "Companion shortcuts now reach TalkieAgent directly. The bridge tries the agent’s local endpoint first and only falls back to the app when the agent does not answer.",
        },
        {
          kind: "prose",
          text: "I moved trigger handling into the agent’s own bridge server, so a shortcut works while the app window is closed. The fallback path is unchanged, which means the verbs that need a window still land in the app.",
        },
        {
          kind: "quoted",
          caption: "files changed",
          lines: [
            "src/bridge/codex-desktop-bridge.cjs",
            "src/bridge/codex-desktop-bridge.test.ts",
          ],
        },
        {
          kind: "prose",
          text: "Two shortcuts still depend on the app: opening a memo and revealing a file. Both verbs need a window, so they keep the old route and I left a comment saying why.",
        },
        {
          kind: "prose",
          text: "I ran the bridge test file and twelve tests pass. I did not touch the pairing flow.",
        },
      ],
    },
    emptyNote: null,
    detail: [
      "turn 6 of 6 · dispatched from this iPad",
      "feat/agent-companion-direct · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
  {
    id: "ipad-deck",
    name: "iPad deck composition",
    project: "talkie",
    branch: "codex/ipad-deck",
    state: "needs-you",
    stateWord: "Needs you",
    instruction: {
      text: "Bring the deck layout up to the full-size iPad without turning it into the phone keybed.",
      at: "13:47",
    },
    activity: null,
    question:
      "Two of the deck layouts define a different Talk shelf height. Should I keep 96 pt from the desk layout or 118 pt from the folio layout?",
    result: null,
    emptyNote: null,
    detail: [
      "turn 2 · dispatched from this iPad",
      "codex/ipad-deck · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
  {
    id: "screen-preview",
    name: "Screen preview autostart",
    project: "talkie",
    branch: "codex/automatic-screen-preview",
    state: "idle",
    stateWord: "Idle",
    instruction: {
      text: "Open the Mac screen preview automatically once a bridge is picked.",
      at: "11:02",
    },
    activity: null,
    question: null,
    result: {
      at: "11:26",
      turn: "turn 4",
      blocks: [
        {
          kind: "prose",
          text: "The preview now opens on its own the first time a bridge is selected in a session, and stays closed after you dismiss it manually.",
        },
        {
          kind: "prose",
          text: "The dismissal is remembered per bridge rather than globally, so picking a different Mac starts the preview again.",
        },
      ],
    },
    emptyNote: null,
    detail: [
      "turn 4 of 4 · dispatched from this iPad",
      "codex/automatic-screen-preview · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
  {
    id: "memo-duration",
    name: "Memo duration audit",
    project: "talkie",
    branch: "main",
    // Talkie has seen this task exist, but has observed no turn for it on
    // this device. It gets no state mark rather than a false `Idle`.
    state: "unknown",
    stateWord: null,
    instruction: null,
    activity: null,
    question: null,
    result: null,
    emptyNote:
      "Nothing has run for this task on this device, so there is no state to report and nothing to read yet.",
    detail: ["no observed turn", "main · talkie", "Arachs-Mac-Mini.Local"],
  },
];

export interface Scenario {
  key: string;
  label: string;
  taskId: string;
  online: boolean;
}

/**
 * The three required states plus the honest `Needs you` correction the
 * model flight asked for. Each scenario names the selected task, so the
 * voice destination is never ambiguous.
 */
export const SCENARIOS: Scenario[] = [
  { key: "working", label: "Active work", taskId: "bridge-reconnect", online: true },
  { key: "result", label: "Useful result", taskId: "companion-shortcuts", online: true },
  { key: "needs", label: "Needs you", taskId: "ipad-deck", online: true },
  { key: "offline", label: "Mac unavailable", taskId: "companion-shortcuts", online: false },
];

/** Deterministic waveform silhouette — no random values, no hydration drift. */
export const WAVE = [
  4, 7, 5, 11, 16, 9, 6, 13, 22, 17, 10, 8, 14, 26, 31, 21, 12, 9, 15, 24, 34,
  28, 18, 11, 8, 13, 20, 30, 25, 16, 10, 7, 12, 19, 27, 23, 14, 9, 6, 11, 17,
  12, 8, 5,
] as const;
