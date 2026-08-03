/**
 * Content truth for The Aperture at-bat.
 *
 * Values are either (a) something the Codex bridge can observe today, or
 * (b) plain-language copy a user would actually read. Nothing invents
 * progress percentages, token counts, queue depth, continuous telemetry,
 * reasoning traces, or capabilities the bridge does not provide.
 */

export const MAC = {
  name: "Arachs-Mac-Mini.Local",
  since: "connected since 09:14",
  lastHeard: "11 minutes ago",
} as const;

/** States Talkie can truthfully derive from bridge events. */
export type TaskState = "working" | "idle" | "needs-you" | "unknown";

export type ResultBlock =
  | { kind: "prose"; text: string }
  | { kind: "quoted"; lines: string[]; caption: string };

export interface Task {
  id: string;
  /** Short hanging-tag label. */
  name: string;
  project: string;
  branch: string;
  state: TaskState;
  /** Plain-language state word on the plate. null when unobservable. */
  stateWord: string | null;
  /** Last thing the user said to this task. */
  instruction: { text: string; at: string } | null;
  /** Present only while a turn is running. */
  activity: { text: string; started: string } | null;
  /** Blocking question from Codex — answer lives in Codex Desktop. */
  question: string | null;
  result: {
    at: string;
    turn: string;
    blocks: ResultBlock[];
  } | null;
  emptyNote: string | null;
  /** Provenance behind "Turn detail" — never primary chrome. */
  detail: string[];
}

export const TASKS: Task[] = [
  {
    id: "bridge-reconnect",
    name: "Bridge reconnect",
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
    name: "Companion shortcuts",
    project: "talkie",
    branch: "feat/agent-companion-direct",
    state: "idle",
    stateWord: "Ready",
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
          text: "Trigger handling lives in the agent’s own bridge server, so a shortcut works while the app window is closed. The fallback path is unchanged for verbs that need a window.",
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
          text: "Two shortcuts still depend on the app: opening a memo and revealing a file. Both need a window, so they keep the old route.",
        },
      ],
    },
    emptyNote: null,
    detail: [
      "turn 6 · completed on Studio Mac",
      "feat/agent-companion-direct · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
  {
    id: "protocol-tests",
    name: "Protocol tests",
    project: "talkie",
    branch: "test/bridge-retry",
    state: "needs-you",
    stateWord: "Needs you",
    instruction: {
      text: "The bridge protocol tests are flaky on the retry suite. Tell me which ones are worth keeping before you rewrite anything.",
      at: "13:40",
    },
    activity: null,
    question:
      "Keep reconnect, out-of-order delivery, and token expiry — retire the nine that only asserted mock timing?",
    result: {
      at: "14:12",
      turn: "turn 2",
      blocks: [
        {
          kind: "prose",
          text: "Three retry tests exercise the real bridge path. The other nine assert mock timing and hide real failures when the mock is too polite.",
        },
        {
          kind: "quoted",
          caption: "keep",
          lines: [
            "reconnect after drop",
            "out-of-order delivery",
            "token expiry mid-stream",
          ],
        },
      ],
    },
    emptyNote: null,
    detail: [
      "turn 2 · waiting in Codex Desktop",
      "test/bridge-retry · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
  {
    id: "sync-audit",
    name: "Sync audit",
    project: "talkie",
    branch: "audit/transcript-sync",
    state: "idle",
    stateWord: "Quiet",
    instruction: {
      text: "Check whether transcript edits on iPhone reach the Mac before the readout runs. Quiet audit, no changes.",
      at: "Thu",
    },
    activity: null,
    question: null,
    result: {
      at: "11:20",
      turn: "turn 1",
      blocks: [
        {
          kind: "prose",
          text: "Every edit landed before readout across the captured week. The only lag is first library load after reinstall, and it clears within a minute.",
        },
      ],
    },
    emptyNote: null,
    detail: [
      "turn 1 · read-only audit",
      "audit/transcript-sync · talkie",
      "Arachs-Mac-Mini.Local",
    ],
  },
];

export type ScenarioKey = "active" | "result" | "unavailable";

export interface Scenario {
  key: ScenarioKey;
  label: string;
  /** Which task the scenario aims at when first selected. */
  taskId: string;
  online: boolean;
}

export const SCENARIOS: Scenario[] = [
  {
    key: "active",
    label: "Active work",
    taskId: "bridge-reconnect",
    online: true,
  },
  {
    key: "result",
    label: "Useful result",
    taskId: "companion-shortcuts",
    online: true,
  },
  {
    key: "unavailable",
    label: "Mac unavailable",
    taskId: "companion-shortcuts",
    online: false,
  },
];
