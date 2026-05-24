/**
 * iOS Settings → flat extraction.
 *
 * Walks `apps/ios/Talkie iOS/Views/Next/SettingsNext.swift` panel by
 * panel and records every row: label, type, default/computed value,
 * underlying `TalkieAppSettings` key (when there is one), and a
 * status tag so we can see at a glance which rows are wired vs.
 * fake / TODO.
 *
 * Source-of-truth is the Swift file. This is a manual snapshot —
 * regenerate by re-walking SettingsNext.swift and updating the
 * `extractedAt` stamp + the rows below.
 */

export type SettingsPanel =
  | "voice"
  | "look"
  | "connect"
  | "keys"
  | "lab"
  | "about";

export type SettingsRowType =
  | "field" // read-only label
  | "cycle" // cycleRow — taps through a fixed choice list
  | "toggle" // toggleRow — Bool
  | "text" // textEntryRow
  | "metric" // a metric in a metricStrip
  | "install" // parakeetInstallRow
  | "action" // actionRow (button)
  | "nav" // navRow (push to subview)
  | "swatch"; // theme swatch (custom)

export type SettingsStatus =
  /** Bound to a real TalkieAppSettings key + writeable. */
  | "wired"
  /** Hardcoded placeholder; no binding yet. */
  | "todo"
  /** Computed from system / external state (battery, sync timestamps). */
  | "computed"
  /** Only shows in DEBUG builds. */
  | "debug"
  /** Conditionally rendered based on another row's value. */
  | "conditional";

export interface SettingsRow {
  panel: SettingsPanel;
  /** Section header above this row (TRANSCRIPTION / RECORDING / etc). */
  section?: string;
  type: SettingsRowType;
  label: string;
  /**
   * Display value when the row was extracted. For bound rows this is
   * the *current* value the user would see with default settings.
   * `null` when there's no inline value (action/nav/install).
   */
  value: string | null;
  hint?: string;
  /** Backing TalkieAppSettings key when this row is `wired`. */
  setting?: string;
  status: SettingsStatus;
  /** Source line in SettingsNext.swift. */
  line: number;
  /** Optional free-form note. */
  note?: string;
}

export const IOS_SETTINGS_EXTRACTED_AT = "2026-05-24T16:20:00Z";

export const IOS_SETTINGS_SOURCE =
  "apps/ios/Talkie iOS/Views/Next/SettingsNext.swift";

export const IOS_SETTINGS_ROWS: SettingsRow[] = [
  // ── voice ───────────────────────────────────────────────────────
  {
    panel: "voice",
    section: "TRANSCRIPTION",
    type: "cycle",
    label: "Dictation engine",
    value: "Auto",
    hint: "Used by Compose mic + Talkie keyboard",
    setting: "transcriptionKeyboardEngine",
    status: "wired",
    line: 408,
  },
  {
    panel: "voice",
    section: "TRANSCRIPTION",
    type: "cycle",
    label: "Memo engine",
    value: "Apple Speech",
    hint: "Used by background voice memo transcription",
    setting: "transcriptionMemoEngine",
    status: "wired",
    line: 422,
  },
  {
    panel: "voice",
    section: "TRANSCRIPTION",
    type: "metric",
    label: "LATENCY",
    value: "—",
    status: "todo",
    line: 436,
    note: "Metric strip header: ENGINE STATE. Not yet measured.",
  },
  {
    panel: "voice",
    section: "TRANSCRIPTION",
    type: "metric",
    label: "WER",
    value: "—",
    status: "todo",
    line: 436,
    note: "Word error rate — not yet measured.",
  },
  {
    panel: "voice",
    section: "TRANSCRIPTION",
    type: "metric",
    label: "LOADED",
    value: "{parakeetManager.statusDescription}",
    status: "computed",
    line: 436,
    note: "Live Parakeet ModelState (NOT LOADED / PREPARING / READY).",
  },
  {
    panel: "voice",
    section: "TRANSCRIPTION",
    type: "install",
    label: "Parakeet install / uninstall",
    value: null,
    status: "computed",
    line: 441,
    note: "Inline progress + delete affordance.",
  },
  {
    panel: "voice",
    section: "RECORDING",
    type: "toggle",
    label: "Tag Location",
    value: "Off",
    hint: "Attach coordinates to voice memos",
    setting: "tagLocationEnabled",
    status: "wired",
    line: 444,
  },
  {
    panel: "voice",
    section: "RECORDING",
    type: "cycle",
    label: "Input device",
    value: "System default",
    hint: "Preferred microphone",
    setting: "recordingInputDevice",
    status: "wired",
    line: 459,
    note: "Choices: System default / Built-in mic / Bluetooth.",
  },
  {
    panel: "voice",
    section: "RECORDING",
    type: "cycle",
    label: "Sample rate",
    value: "System",
    hint: "Recorder preference",
    setting: "recordingSampleRate",
    status: "wired",
    line: 468,
    note: "Choices: System / 44.1 kHz / 48 kHz.",
  },
  {
    panel: "voice",
    section: "RECORDING",
    type: "toggle",
    label: "Echo cancellation",
    value: "Off",
    hint: "Voice isolation",
    setting: "recordingEchoCancellationEnabled",
    status: "wired",
    line: 477,
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "cycle",
    label: "Provider",
    value: "OpenAI",
    hint: "{speechProviderHint}",
    setting: "ttsProvider",
    status: "wired",
    line: 488,
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "cycle",
    label: "Route",
    value: "Phone",
    hint: "{speechRouteHint}",
    setting: "ttsMode",
    status: "conditional",
    line: 501,
    note: 'Becomes read-only "Via Mac" field when provider == "local".',
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "text",
    label: "Voice",
    value: "echo",
    hint: "{speechVoiceSummary}",
    setting: "ttsVoice",
    status: "wired",
    line: 513,
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "text",
    label: "API Key",
    value: "(secret)",
    hint: "{speechCredentialSummary}",
    setting: "ttsApiKey",
    status: "conditional",
    line: 530,
    note: 'Hidden when reusable AI keys credential exists; becomes read-only "AI keys" field then.',
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "toggle",
    label: "Speak replies",
    value: "Silent",
    hint: "AI command responses",
    setting: "aiVoiceOutputRoute",
    status: "wired",
    line: 542,
    note: 'Toggle maps "silent" ↔ "phone".',
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "cycle",
    label: "Output",
    value: "{aiVoiceOutputRoute}",
    hint: "Where short replies speak",
    setting: "aiVoiceOutputRoute",
    status: "conditional",
    line: 553,
    note: 'Only shown when "Speak replies" is on.',
  },
  {
    panel: "voice",
    section: "TEXT-TO-SPEECH",
    type: "nav",
    label: "Manage AI keys",
    value: null,
    status: "wired",
    line: 563,
  },

  // ── look ────────────────────────────────────────────────────────
  {
    panel: "look",
    type: "field",
    label: "Theme",
    value: "{theme.currentTheme.displayName}",
    setting: "(theme — separate manager, not a TalkieAppSettings key)",
    status: "computed",
    line: 569,
  },
  {
    panel: "look",
    type: "cycle",
    label: "Density",
    value: "Standard",
    hint: "Inspector spacing",
    setting: "appearanceDensity",
    status: "wired",
    line: 570,
    note: "Choices: Standard / Compact / Comfort.",
  },
  {
    panel: "look",
    type: "cycle",
    label: "Accent intensity",
    value: "Theme",
    hint: "Chrome glow strength",
    setting: "appearanceAccentIntensity",
    status: "wired",
    line: 579,
  },
  {
    panel: "look",
    type: "cycle",
    label: "Wordmark style",
    value: "(see appearanceWordmarkChoices)",
    hint: "Header treatment",
    setting: "appearanceWordmarkStyle",
    status: "wired",
    line: 588,
  },
  {
    panel: "look",
    type: "toggle",
    label: "Reduce motion",
    value: "Standard",
    hint: "{theme.appearanceMode.displayName}",
    setting: "reduceMotionEnabled",
    status: "wired",
    line: 597,
  },
  {
    panel: "look",
    type: "swatch",
    label: "THEMES",
    value: null,
    status: "wired",
    line: 612,
    note: "ThemeManager.apply per swatch tap.",
  },

  // ── connect ─────────────────────────────────────────────────────
  {
    panel: "connect",
    type: "field",
    label: "iCloud sync",
    value: "{iCloudSyncEnabled ? On : Off}",
    hint: "{iCloudHint}",
    setting: "iCloudSyncEnabled",
    status: "wired",
    line: 664,
    note: "Inline action: CHECK (when status is errored).",
  },
  {
    panel: "connect",
    type: "field",
    label: "Last iCloud sync",
    value: "{relative date or Pending}",
    hint: "{iCloudLastSyncHint}",
    status: "computed",
    line: 670,
  },
  {
    panel: "connect",
    type: "field",
    label: "Mac Bridge",
    value: "{bridgeStatusValue}",
    hint: "{bridgeStatusHint}",
    status: "computed",
    line: 671,
    note: "Inline action: RECONNECT when paired but disconnected.",
  },
  {
    panel: "connect",
    type: "toggle",
    label: "Auto-open Command Deck",
    value: "Off",
    hint: "{companionShortcutHint}",
    setting: "followComputerShortcutMode",
    status: "wired",
    line: 677,
  },
  {
    panel: "connect",
    type: "field",
    label: "Account",
    value: "{nativeAccountValue}",
    hint: "Sign in with Apple",
    status: "computed",
    line: 687,
  },
  {
    panel: "connect",
    type: "metric",
    label: "RTT",
    value: "—",
    status: "todo",
    line: 688,
    note: "Metric strip header: LINK HEALTH.",
  },
  {
    panel: "connect",
    type: "metric",
    label: "SENT",
    value: "—",
    status: "todo",
    line: 688,
  },
  {
    panel: "connect",
    type: "metric",
    label: "QUEUED",
    value: "—",
    status: "todo",
    line: 688,
  },
  {
    panel: "connect",
    type: "nav",
    label: "SSH Terminal",
    value: null,
    status: "debug",
    line: 693,
    note: "DEBUG-only nav row.",
  },
  {
    panel: "connect",
    type: "nav",
    label: "View connections detail",
    value: null,
    status: "wired",
    line: 695,
  },
  {
    panel: "connect",
    type: "nav",
    label: "Workspaces",
    value: null,
    status: "wired",
    line: 696,
  },
  {
    panel: "connect",
    type: "nav",
    label: "Resolve sync conflicts",
    value: null,
    status: "wired",
    line: 697,
  },
  {
    panel: "connect",
    type: "action",
    label: "Sign out",
    value: null,
    status: "conditional",
    line: 699,
    note: 'Rendered when `isNativelySignedIn == true`. Tone: warn.',
  },
  {
    panel: "connect",
    type: "action",
    label: "Sign in with Apple",
    value: null,
    status: "conditional",
    line: 701,
    note: 'Rendered when `isNativelySignedIn == false`. Tone: accent.',
  },

  // ── keys (in-app Talkie keyboard preferences) ───────────────────
  {
    panel: "keys",
    type: "field",
    label: "Dictation engine",
    value: "{transcriptionKeyboardEngine.displayName}",
    setting: "transcriptionKeyboardEngine",
    status: "wired",
    line: 779,
    note: "READ-ONLY mirror of the Voice panel's cycle — duplicates, no picker here.",
  },
  {
    panel: "keys",
    type: "field",
    label: "Auto-format",
    value: "{keyboardModeEnabled ? Keyboard mode : Default}",
    hint: "{keyboardActiveLayout}",
    setting: "keyboardModeEnabled",
    status: "wired",
    line: 780,
    note: "Read-only field, not a toggle.",
  },
  {
    panel: "keys",
    type: "field",
    label: "Punctuation",
    value: "Inferred",
    status: "todo",
    line: 781,
    note: "Hardcoded — no TalkieAppSettings key yet.",
  },
  {
    panel: "keys",
    type: "field",
    label: "Auto-capitalize",
    value: "{keyboardAutoCapitalizeEnabled ? On : Off}",
    setting: "keyboardAutoCapitalizeEnabled",
    status: "wired",
    line: 782,
    note: "Read-only field, not a toggle.",
  },
  {
    panel: "keys",
    type: "field",
    label: "Trailing space",
    value: "Smart",
    status: "todo",
    line: 783,
    note: "Hardcoded — no TalkieAppSettings key yet.",
  },
  {
    panel: "keys",
    type: "field",
    label: "Voice activation",
    value: "{keyboardLEDIndicatorsEnabled ? Indicators on : Indicators off}",
    setting: "keyboardLEDIndicatorsEnabled",
    status: "wired",
    line: 784,
    note: "Read-only field, not a toggle.",
  },
  {
    panel: "keys",
    type: "field",
    label: "Haptic feedback",
    value: "{keyboardHapticFeedbackEnabled ? On : Off}",
    setting: "keyboardHapticFeedbackEnabled",
    status: "wired",
    line: 785,
    note: "Read-only field, not a toggle.",
  },

  // ── lab (DEBUG-only) ────────────────────────────────────────────
  {
    panel: "lab",
    type: "action",
    label: "Reset onboarding",
    value: null,
    setting: "hasSeenOnboarding",
    status: "debug",
    line: 796,
  },
  {
    panel: "lab",
    type: "action",
    label: "Reset auth state",
    value: null,
    status: "debug",
    line: 797,
  },
  {
    panel: "lab",
    type: "action",
    label: "Reset resume tooltip",
    value: null,
    setting: "hasSeenResumeTooltip",
    status: "debug",
    line: 798,
  },
  {
    panel: "lab",
    type: "action",
    label: "Open log viewer",
    value: null,
    status: "debug",
    line: 799,
    note: "Currently logs a stub message; LogViewerSheet not wired in Next target.",
  },
  {
    panel: "lab",
    type: "action",
    label: "Dump shared store",
    value: null,
    status: "debug",
    line: 800,
  },
  {
    panel: "lab",
    type: "action",
    label: "Force iCloud refresh",
    value: null,
    status: "debug",
    line: 801,
  },
  {
    panel: "lab",
    type: "nav",
    label: "Inspect theme contrast",
    value: null,
    status: "debug",
    line: 802,
  },

  // ── about ───────────────────────────────────────────────────────
  {
    panel: "about",
    type: "field",
    label: "Version",
    value: "{Bundle.main.shortVersion}",
    status: "computed",
    line: 808,
  },
  {
    panel: "about",
    type: "field",
    label: "Build",
    value: "{Bundle.main.buildNumber}",
    status: "computed",
    line: 809,
  },
  {
    panel: "about",
    type: "field",
    label: "Channel",
    value: "{iosChannel}",
    status: "computed",
    line: 810,
  },
  {
    panel: "about",
    type: "field",
    label: "Engine bundle",
    value: "{preferredParakeetModel.huggingFaceRepo}",
    setting: "preferredParakeetModel",
    status: "wired",
    line: 811,
  },
  {
    panel: "about",
    type: "field",
    label: "Mac bridge protocol",
    value: "talkie-bridge-v1",
    status: "computed",
    line: 812,
  },
  {
    panel: "about",
    type: "nav",
    label: "Manage AI keys",
    value: null,
    status: "wired",
    line: 813,
  },
  {
    panel: "about",
    type: "nav",
    label: "Workflows hub",
    value: null,
    status: "wired",
    line: 814,
  },
  {
    panel: "about",
    type: "nav",
    label: "Send feedback",
    value: null,
    status: "wired",
    line: 815,
  },
];

/** Counts by status — handy for the page header summary. */
export function statusSummary(rows: SettingsRow[] = IOS_SETTINGS_ROWS) {
  const out: Record<SettingsStatus, number> = {
    wired: 0,
    todo: 0,
    computed: 0,
    debug: 0,
    conditional: 0,
  };
  for (const r of rows) out[r.status]++;
  return out;
}
