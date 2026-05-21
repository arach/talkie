"use client";

import { useEffect, useMemo, useState } from "react";
import streamsData from "@/data/parity/streams.json";

/**
 * Parity audit — donor (legacy iOS) vs Next shell rebuild.
 *
 * Findings produced by a 6-agent swarm review on 2026-05-21,
 * each cluster comparing `git show master:<donor>` vs HEAD's Next/
 * counterparts. Tag legend:
 *
 *   MISSING — donor feature absent from Next
 *   STUB    — Next surface paints but logic not wired
 *   CHANGED — different behavior on each side (intentional or drift)
 *   NEW     — Next-only addition without a donor counterpart
 */

type Tag = "MISSING" | "STUB" | "CHANGED" | "NEW";
type Decision = "PORT" | "DROP" | "DEFER";
type StreamStatus = "queued" | "in-flight" | "blocked" | "done";
type NoteLevel =
  | "info"
  | "progress"
  | "landed"
  | "blocked"
  | "proposal"
  | "question";

interface StreamNote {
  ts: string;
  agent: string;
  level: NoteLevel;
  findingKey?: string;
  message: string;
  ref?: string;
}

interface Stream {
  key: string;
  title: string;
  scope: string;
  owner: string | null;
  status: StreamStatus;
  lockedAt: string | null;
  notes: StreamNote[];
}

const STREAMS_BY_KEY: Record<string, Stream> = Object.fromEntries(
  (streamsData.streams as Stream[]).map((s) => [s.key, s]),
);

interface Finding {
  tag: Tag;
  title: string;
  detail: string;
}

interface DecisionEntry {
  decision: Decision | null;
  note: string;
}

type DecisionMap = Record<string, DecisionEntry>;

const STORAGE_KEY = "parity-decisions-v1";

function findingKey(clusterKey: string, donor: string, title: string): string {
  return `${clusterKey}::${donor}::${title}`;
}

interface Subsurface {
  donor: string;
  next: string;
  findings: Finding[];
}

interface Cluster {
  key: string;
  label: string;
  blurb: string;
  subsurfaces: Subsurface[];
}

const CLUSTERS: Cluster[] = [
  {
    key: "C1",
    label: "C1 · HOME · LIBRARY · HISTORY",
    blurb:
      "Home dashboard, library list, dictation history feed. The shell's read-side surfaces — what gets surfaced from Core Data into rows.",
    subsurfaces: [
      {
        donor: "HomeView",
        next: "HomeNextView + HomeFeed",
        findings: [
          { tag: "MISSING", title: "Full-screen search", detail: "Donor `isSearching` toggle drives live filter on title + transcription with NO MATCHES empty. Next has no home search." },
          { tag: "MISSING", title: "Content filter toggle", detail: "Donor `ContentFilterToggle` (Memos / Dictations / Captures) with per-type fetch requests + scoped search. Next mixes types into one recent feed." },
          { tag: "MISSING", title: "Sort options", detail: "Donor `SortOption` enum (dateNewest / oldest / title / duration) applied to fetch descriptors. HomeFeed hardcodes lastModified DESC." },
          { tag: "MISSING", title: "Load-more pagination", detail: "Donor increments `displayLimit += 10`. HomeFeed caps recent list at 5 with no expansion." },
          { tag: "MISSING", title: "Tally window rollover", detail: "Donor auto-selects 24h → 7d → 30d window when earlier has no signal. HomeFeed picks the first non-empty window but always anchored at 24h." },
          { tag: "MISSING", title: "Workflow run badge on rows", detail: "Donor VoiceMemoRow shows sparkles + count of completed WorkflowRuns. RecentItem has no workflow integration." },
          { tag: "MISSING", title: "File size + audio format meta", detail: "Donor row estimates file size (~16KB/sec) + extracts format from extension. RecentItem omits both." },
          { tag: "MISSING", title: "Deep-link search action", detail: "Donor handles `.search(query)` deep link → search mode + focused field. Next has no deep-link integration." },
          { tag: "MISSING", title: "Promote-to-memo swipe on home dictations", detail: "Donor home shows recent dictations with swipe-leading `promoteHomeDictationToMemo`. Next has no path." },
          { tag: "CHANGED", title: "Mac connection signal", detail: "Donor's 4-pixel ambient row (iCloud · Mac · Account · Deck) consolidated to a single 40pt chip in Next." },
          { tag: "NEW", title: "QuickEntriesBar", detail: "PICK UP card footer with Compose / Ask AI / Scan cells. No donor equivalent." },
          { tag: "NEW", title: "PICK UP continue card", detail: "Surfaces last-modified document with continue CTA. Donor home had no continue-last-session card." },
        ],
      },
      {
        donor: "LibraryView",
        next: "LibraryNextView + LibraryFeed",
        findings: [
          { tag: "STUB", title: "SearchBar not wired", detail: "TextField binds to local @State query but no filter logic — placeholder updates per tab but nothing filters." },
          { tag: "MISSING", title: "Live filtering across tabs", detail: "Donor applies search text dynamically to filteredMemos / filteredDictations / filteredCaptures predicates. LibraryFeed has no filter state." },
          { tag: "MISSING", title: "Promote-to-memo swipe on Library dictations", detail: "Donor DictationListSection has swipe-leading with promoteToMemo. LibraryListCard only exposes trailing delete." },
          { tag: "MISSING", title: "Source-type filtering on Items tab", detail: "LibraryFeed merges typed / dictation / items — `itemSource()` returns nil for typed/dictation sources." },
          { tag: "MISSING", title: "Capture sync status", detail: "Donor CaptureCard shows `syncedToMac` checkmark vs dotted circle. LibraryFeed.Item has no sync state." },
          { tag: "CHANGED", title: "Dictation tap target", detail: "Donor opens DictationDetailView sheet; Next routes to Compose document — different user journey." },
          { tag: "CHANGED", title: "EARLIER · THIS WEEK bucket copy", detail: "Label reads `EARLIER · THIS WEEK` but earlier count is for items *older* than visible, not the other way." },
        ],
      },
      {
        donor: "DictationHistoryView",
        next: "DictationHistoryNext",
        findings: [
          { tag: "STUB", title: "Swipe-leading Save-as-Memo + trailing Delete", detail: "File header acknowledges both as paint-side TODOs." },
          { tag: "MISSING", title: "Detail view with Save as Memo button", detail: "Donor DictationDetailView has full-screen detail with promote button + toolbar read-aloud. Next opens Compose seeded with ID instead." },
          { tag: "MISSING", title: "Word count in detail", detail: "Donor DictationDetailView shows wordCount metadata; Next feed entry has no wordCount field." },
          { tag: "MISSING", title: "App context (Source) row", detail: "Donor shows metadata row for `Source` (Messages / Notes / etc). Next omits." },
          { tag: "MISSING", title: "Read-aloud toolbar button", detail: "Donor toolbar speaker toggles SpeechSynthesisService.toggleReadout(). Next has no in-row affordance." },
        ],
      },
      {
        donor: "Cross-cutting data flow",
        next: "HomeFeed / LibraryFeed / DictationHistoryFeed",
        findings: [
          { tag: "MISSING", title: "Live @FetchRequest binding", detail: "Donor uses @FetchRequest + animation for reactive updates. Next uses manual `.reload()` on NotificationCenter observers." },
          { tag: "MISSING", title: "Predicate filtering at fetch time", detail: "Donor applies Core Data predicates (unsynced captures etc); Next fetches all and filters in-memory." },
          { tag: "MISSING", title: "Error / loading states", detail: "Neither side surfaces fetch errors. Next has no loading skeleton." },
          { tag: "MISSING", title: "iCloud sync CTA in empty state", detail: "Donor EmptyStateView shows sync CTA when `iCloudStatus.status == .noAccount`. Next empty state is icon + text only." },
        ],
      },
    ],
  },
  {
    key: "C2",
    label: "C2 · CAPTURE",
    blurb:
      "Camera + Vision OCR, web link grab, AI-command sheet, capture list/detail. The capture-side ingestion stack.",
    subsurfaces: [
      {
        donor: "CaptureListSection",
        next: "(none)",
        findings: [
          { tag: "MISSING", title: "Entire surface absent", detail: "Donor cards + rows (CaptureCard + CaptureRow) with sync-all button, unsynced count badge, type icons, sync indicator — no Next port." },
        ],
      },
      {
        donor: "CaptureDetailView",
        next: "CaptureDetailNext",
        findings: [
          { tag: "MISSING", title: "Image viewer fullscreen", detail: "Donor `CaptureDetailImageViewer` opens image at full bleed; Next renders placeholder only." },
          { tag: "MISSING", title: "Image loading from MemoAttachmentStore", detail: "Donor wires `CaptureStore.loadImageData`; Next hardcodes placeholder." },
          { tag: "MISSING", title: "Audio playback state machine", detail: "Donor uses `@StateObject AudioPlayerManager` for capture audio + preloaded TTS. Next has no audio integration." },
          { tag: "MISSING", title: "capturesDidChange refresh", detail: "Donor observes `.capturesDidChange` to refresh loaded assets. Next ignores notification." },
          { tag: "STUB", title: "AI Commands sheet bidirectional sync", detail: "Sheet stores `sourceCapture` locally; no propagation of AI result persistence back to detail." },
          { tag: "STUB", title: "Edit + delete flows", detail: "No affordances surface on CaptureDetailNext." },
        ],
      },
      {
        donor: "CaptureComposeView",
        next: "(none)",
        findings: [
          { tag: "MISSING", title: "Import + edit surface", detail: "Donor combines text editor + dictation + camera + photo library + URL browser + OCR into one capture-creation flow. No Next equivalent." },
          { tag: "MISSING", title: "Multi-page scan batching", detail: "Donor persists `imageFilename` + `deferredPageFilenames` + `totalPageCount` (deferred-page queue). Next CameraCaptureNext saves single scans." },
          { tag: "MISSING", title: "ScreenshotOCRService deferred pages", detail: "Donor queues subsequent pages via `extractText()` with batch OCR status. Not in Next." },
          { tag: "MISSING", title: "initialURL fast-path → WebCaptureBrowser", detail: "Donor accepts URL param and opens browser directly. Next has no such handoff." },
          { tag: "MISSING", title: "onCaptureSaved → compose handoff", detail: "Donor passes saved capture into a compose-from-capture surface. Next has no integration." },
        ],
      },
      {
        donor: "CameraImagePicker + OCRPreviewSheet",
        next: "CameraCaptureNext + ScanPreviewOverlay",
        findings: [
          { tag: "MISSING", title: "VNDocumentCameraViewController", detail: "Donor uses Vision multi-page scanner with perspective correction. Next builds AVFoundation session direct." },
          { tag: "MISSING", title: "UIImagePickerController fallback", detail: "Donor falls back on older devices. Next has no fallback path." },
          { tag: "MISSING", title: "Deferred page status row", detail: "Donor OCR sheet shows `Page X of Y scanned · N pages waiting`. Next overlay does not surface batch state." },
          { tag: "CHANGED", title: "Sheet → full-bleed overlay", detail: "Donor OCRPreviewSheet was a modal; Next ScanPreviewOverlay is full-bleed." },
          { tag: "NEW", title: "Inline edit mode in scan preview", detail: "Next ScanPreviewOverlay flips chunks into a TextEditor seeded with combinedText so users correct wobbly OCR before save." },
          { tag: "NEW", title: "Low-confidence coaching banner", detail: "Next shows banner when chunk scores are low — donor had none." },
        ],
      },
      {
        donor: "WebCaptureBrowser",
        next: "WebCaptureBrowserNext",
        findings: [
          { tag: "CHANGED", title: "State machine refactor", detail: "Donor used @StateObject + @ObservedObject; Next wraps both in `WebCaptureBrowserStore` @MainActor. Equivalent behavior, different binding shape." },
        ],
      },
      {
        donor: "CaptureAICommandsSheet",
        next: "(stub in CaptureDetailNext)",
        findings: [
          { tag: "MISSING", title: "Path selection (direct vs Mac)", detail: "Donor `CaptureAICommandPath` enum with provider + model picker. Not wired in Next." },
          { tag: "MISSING", title: "Quick prompts carousel", detail: "Donor's 5 hardcoded buttons (Two Key Points / Summarize / Explain / Relate / Research). Absent." },
          { tag: "MISSING", title: "Dictation mic in command field", detail: "Donor wraps DictationWrapper inline. Next has no in-sheet voice input." },
          { tag: "MISSING", title: "TTS speak-back of response", detail: "Donor plays response via AudioPlayerManager. Next has no playback." },
          { tag: "MISSING", title: "Execution history / persistence", detail: "Donor logs via `CaptureAICommandStore.shared`. Next has no record." },
          { tag: "MISSING", title: "Bridge reconnect on failure", detail: "Donor surfaces reconnect on bridge-down errors. Next error state not wired." },
        ],
      },
    ],
  },
  {
    key: "C3",
    label: "C3 · COMPOSE · MEMO DETAIL",
    blurb:
      "Compose document editor, voice-memo detail, attachments, agent + CLI sheets, read-aloud. The write-side editing surfaces.",
    subsurfaces: [
      {
        donor: "ComposeView",
        next: "ComposeNextView + ComposeStore",
        findings: [
          { tag: "STUB", title: "ComposeLocalRevisionService persistence", detail: "Next has mock `appliedRevisions: [ComposeAppliedRevision]` shape but no persistent service implementation." },
          { tag: "STUB", title: "Autosave on scenePhase", detail: "Donor saves on phase change + explicit; Next saves only on `acceptDiff()` and `appendDictation()`." },
          { tag: "MISSING", title: "Notes list view", detail: "Donor lists saved notes via FetchRequest with create-new CTA. Next collapses to single-document open." },
          { tag: "MISSING", title: "InlineDictationController pipeline", detail: "Donor integrates full keyboard-dictation controller with error states + transcript consumption. Next has raw AudioRecorderManager + TranscriptionService." },
          { tag: "MISSING", title: "Bridge revision path (.mac / .direct)", detail: "Donor `ComposeRevisionPath` enum with provider loading + connection status. Next removes entirely." },
          { tag: "CHANGED", title: "Revision UI", detail: "Donor shows inline ComposeRevisionCard with history rollup; Next has accept/discard/refine but no history accumulation." },
          { tag: "NEW", title: "Quick transforms", detail: "Next adds shorter / polish / connect / grammar shortcut buttons. No donor equivalent." },
        ],
      },
      {
        donor: "VoiceMemoDetailView",
        next: "VoiceMemoDetailNext",
        findings: [
          { tag: "STUB", title: "Title edit mode", detail: "Donor has `isEditingTitle` + `editedTitle` + `saveTitle()`. Next has no inline title editing." },
          { tag: "STUB", title: "Transcript edit mode", detail: "Donor has `isEditingTranscript` + `editedTranscript`. Next has no edit affordance." },
          { tag: "MISSING", title: "AI title generation", detail: "Donor `isGeneratingTitle` + `generateTitle()` via OnDeviceAIService. Next has no entry point." },
          { tag: "MISSING", title: "TranscriptVersionHistorySheet", detail: "Stub note in Next: `Not brought across yet`." },
          { tag: "MISSING", title: "Share sheet", detail: "Donor `showingShare` + ShareSheet. Next has TODO comment." },
          { tag: "MISSING", title: "EventKit reminders", detail: "Donor full reminder flow (ReminderStatus, date picker, createReminder). Next omits entirely." },
          { tag: "MISSING", title: "Mac workflow polling + toast", detail: "Donor tracks `liveWorkflowStatuses`, polls, toasts. Next removes pinnedMacWorkflows + workflow surfaces from memo detail." },
          { tag: "MISSING", title: "OCR → append to notes", detail: "Donor `showingOCRPhotoPicker` + `performOCR()` + append flow. Next omits." },
          { tag: "MISSING", title: "Delete confirmation + audio file cleanup", detail: "Donor `showingDeleteConfirmation` alert + audio-file delete. Next has TODO in more menu." },
          { tag: "CHANGED", title: "Attachment picker", detail: "Donor MemoAttachmentPickerSheet has OCR + onScanText callback + permission state; Next uses plain PhotosPicker." },
        ],
      },
      {
        donor: "MemoAgentSheet",
        next: "(none)",
        findings: [
          { tag: "MISSING", title: "Multi-turn Claude conversation", detail: "Donor implements turns array + `claudeSessionId` for follow-ups + streaming response + Scout handoff card. No Next surface." },
          { tag: "MISSING", title: "In-sheet dictation", detail: "Donor wraps DictationWrapper for voice input. Absent." },
          { tag: "MISSING", title: "Context pinning", detail: "Donor pins memo transcript + title at top of conversation. Absent." },
        ],
      },
      {
        donor: "MemoCLISheet",
        next: "(none)",
        findings: [
          { tag: "MISSING", title: "Preset commands", detail: "Donor's 6 presets (Show Memo / Sync Latest / Recent Memos / Workflow Runs / Data Stats / Service Status) with memo ID interpolation. Absent." },
          { tag: "MISSING", title: "Custom command input", detail: "Monospace field + submit-on-return + output card + copy. No Next CLI surface." },
          { tag: "MISSING", title: "Bridge headless transport", detail: "Donor routes through BridgeManager headless endpoint. No integration." },
        ],
      },
      {
        donor: "Attachments + context menus",
        next: "VoiceMemoDetailNext attachments",
        findings: [
          { tag: "MISSING", title: "Send attachments to Mac", detail: "Donor `isSendingAttachmentsToMac` + `lastSentAttachmentFingerprint` + alert. Absent." },
          { tag: "MISSING", title: "OCR scanner in picker", detail: "Donor MemoAttachmentPickerSheet has `onScanText` button. Next uses vanilla PhotosPicker." },
          { tag: "MISSING", title: "Recent assets carousel", detail: "Donor loads recentAttachmentAssets via PHCachingImageManager. Not implemented." },
          { tag: "MISSING", title: "Transcript context menu", detail: "Donor `.contextMenu` with Version History + Copy. Absent." },
          { tag: "MISSING", title: "Attachment tile context menu", detail: "Donor `.contextMenu` with Remove on each tile. Absent." },
          { tag: "NEW", title: "Shell long-press → voice command", detail: "Next VoicePivotButton 0.35s LongPressGesture → `chrome.longPressBegan()` → compose voice command. No donor equivalent." },
        ],
      },
      {
        donor: "TTS hooks in memo detail",
        next: "ReadAloudNext",
        findings: [
          { tag: "CHANGED", title: "Surface model", detail: "Donor integrates TTS into memo detail via `SpeechSynthesisService.toggleReadout(text)`. Next separates into dedicated ReadAloudNext with 4 source buttons (memo / capture / PDF / response)." },
          { tag: "MISSING", title: "Range-of-speech highlighting", detail: "Neither side implements word-by-word highlighting during playback." },
          { tag: "NEW", title: "Transport with skip + seek", detail: "Next has ±15s skip + waveform seek. Donor had simple toggle." },
        ],
      },
    ],
  },
  {
    key: "C4",
    label: "C4 · SETTINGS · ONBOARDING · SIGN-IN",
    blurb:
      "Settings inspector, onboarding tour, sign-in, AI credentials, workspace switcher. Configuration surfaces.",
    subsurfaces: [
      {
        donor: "SettingsView (10 sections)",
        next: "SettingsNext (6 panels)",
        findings: [
          { tag: "MISSING", title: "COMPANION section", detail: "Donor `followComputerShortcutMode` Command Deck toggle. Absent." },
          { tag: "MISSING", title: "RECORDING section", detail: "Donor mic input selection, sample rate, echo cancellation controls (SettingsView:650–750). Absent." },
          { tag: "MISSING", title: "TEXT-TO-SPEECH section", detail: "Donor TTS provider picker (Local / OpenAI / ElevenLabs) + API key + voice selection (SettingsView:753–890). Absent." },
          { tag: "MISSING", title: "REMOTE ACCESS section", detail: "Donor SSH Terminal + Connection Center (platform-gated). Absent in Next surface." },
          { tag: "CHANGED", title: "Inspector layout", detail: "Vertical list → horizontal rail + active panel. Six panels: VOICE / LOOK / CONNECT / KEYS / LAB / ABOUT." },
          { tag: "STUB", title: "Appearance bindings", detail: "Theme swatches present; density / accent intensity / wordmark style still TODO." },
          { tag: "STUB", title: "iCloud last-sync timestamp", detail: "Status binding exists (`checking / couldNotDetermine`) but no last-sync timestamp rendered." },
        ],
      },
      {
        donor: "KeyboardSettingsView",
        next: "KEYS panel",
        findings: [
          { tag: "MISSING", title: "SETUP INSTRUCTIONS disclosure", detail: "Donor walks user through enabling the extension. Absent." },
          { tag: "MISSING", title: "KeyboardConfiguratorView push", detail: "Donor navigates to custom slot configurator. Absent." },
          { tag: "MISSING", title: "Testing playground", detail: "Donor KeyboardPlayground for in-app try-it. Absent." },
        ],
      },
      {
        donor: "OnboardingView",
        next: "OnboardingNext",
        findings: [
          { tag: "STUB", title: "Welcome hero", detail: "Placeholder waveform.mic icon + TODO for TalkieLogo + LogoRibbon." },
          { tag: "STUB", title: "Capture + Sync hero animations", detail: "Donor has interactive architecture diagram; Next has TODO comments deferring decoration." },
          { tag: "MISSING", title: "Explicit permission prompts", detail: "Mic / speech recognition / dictation extension enable — not surfaced explicitly on either side, but donor likely sequences them." },
          { tag: "CHANGED", title: "iCloud account check", detail: "Donor uses `CKContainer(identifier:)`; Next uses `CKContainer.default()` + simulator guard." },
        ],
      },
      {
        donor: "SignInView",
        next: "SignInNext",
        findings: [
          { tag: "NEW", title: "SignInStore 3-step state machine", detail: "Extracted @MainActor class managing Request credentials → Validate → Provision iCloud." },
          { tag: "NEW", title: "NativeAppleCredential Keychain struct", detail: "userID / email / givenName / familyName / tokens. Donor didn't surface this detail." },
          { tag: "STUB", title: "CloudKit provisioning result", detail: "`CKContainer.accountStatus` called post-sign-in but result not reflected in UI." },
        ],
      },
      {
        donor: "(none)",
        next: "AICredentialsNext",
        findings: [
          { tag: "NEW", title: "Standalone AI credentials surface", detail: "Catalog of OpenAI / Anthropic / Groq / OpenRouter with per-provider edit modal. No donor equivalent in SettingsView." },
          { tag: "STUB", title: "Provider resolver wiring", detail: "TalkieAIProviderResolver + AICredentialStore not yet bound; paint is in-memory only." },
        ],
      },
      {
        donor: "(none)",
        next: "WorkspaceSwitcherNext",
        findings: [
          { tag: "NEW", title: "Standalone workspace switcher", detail: "Lists identities (personal / work / other) with active indicator + role label + last-used + capture count. No donor equivalent." },
          { tag: "STUB", title: "WorkspaceStore wiring", detail: "Mock data; no live identities or `activate(_:)` swap of iCloud zone + Core Data store + bridge pairing." },
        ],
      },
    ],
  },
  {
    key: "C5",
    label: "C5 · BRIDGE · MAC · DECK",
    blurb:
      "Mac bridge, connection center, deck mirror, ambient connection chip. The cross-device transport surfaces.",
    subsurfaces: [
      {
        donor: "ConnectionCenterView",
        next: "ConnectionCenterNext",
        findings: [
          { tag: "CHANGED", title: "Reactive store pattern", detail: "Donor used @ObservedObject direct properties; Next refactors to `ConnectionCenterStore` with @Observable trackObservationTracking()." },
          { tag: "NEW", title: "Header chrome bar", detail: "Nav back + Done + Settings gear above the scroll view. Donor relied on NavigationView title + environment dismiss." },
        ],
      },
      {
        donor: "BridgeSettingsView + SessionListView + SessionDetailView",
        next: "BridgeDetailNext (unified)",
        findings: [
          { tag: "MISSING", title: "SessionDetailView", detail: "Donor's message-history view with audio + image inputs is entirely absent. TerminalNext (11L stub) has no session-history surface." },
          { tag: "MISSING", title: "MacStatusObserver cloud fallback", detail: "Donor uses cloudObserver for `freshCloudStatuses` filter. BridgeDetailNext does not reference MacStatusObserver; only direct pairing tracked." },
          { tag: "CHANGED", title: "Three surfaces → one", detail: "Donor split Bridge / Sessions / Detail across three views. Next unifies into BridgeDetailNext (status + pairing + sessions + actions)." },
          { tag: "CHANGED", title: "Session list shape", detail: "Donor SessionListView was a grid with pull-to-refresh. Next embeds simple rows in SESSIONS section." },
          { tag: "STUB", title: "File header claims Phase-1 placeholder", detail: "Misleading — implementation is functionally complete (live BridgeManager + nearby Mac discovery + QR pairing + sessions)." },
        ],
      },
      {
        donor: "CompanionShortcutModeView (runtime)",
        next: "DeckMirrorNext (view-only)",
        findings: [
          { tag: "MISSING", title: "Execution feedback loop", detail: "Donor tracks `lastTriggeredShortcutID` + `latestTriggerFeedback` + optimistic state + idle reset timer. Next shows only `lastErrorMessage`." },
          { tag: "MISSING", title: "App switcher modal", detail: "Donor three-tap → app grid + `app runtime active` badge. Absent." },
          { tag: "MISSING", title: "Trackpad interaction", detail: "Donor `isTrackpadInteracting` state with mouse-down → highlight, release → fire. Next is single-tap only." },
          { tag: "CHANGED", title: "Runtime → snapshot", detail: "700+L runtime collapsed to 208L view-only paint driven by DeckMirrorStore events." },
        ],
      },
      {
        donor: "CompanionScreenPreviewView",
        next: "(none)",
        findings: [
          { tag: "MISSING", title: "Live Mac display peek", detail: "Donor 2fps low-res desktop stream (4:3, LIVE DESKTOP label, isStreaming indicator). No Next equivalent." },
        ],
      },
      {
        donor: "MacAvailabilityCoachView",
        next: "MacCoachCard (embedded in BridgeDetailNext)",
        findings: [
          { tag: "CHANGED", title: "Standalone tab → embedded card", detail: "Donor was a full Macs tab; Next embeds the empty-state card inside BridgeDetailNext when !hasPairedMacs. Auto-dismisses on pair." },
          { tag: "MISSING", title: "Cloud signals", detail: "Donor MacStatusObserver `freshCloudStatuses` filter removed. Cloud-aware reconnect fallback not surfaced." },
        ],
      },
      {
        donor: "AmbientStatusRow (4-pixel)",
        next: "MacConnectionChip (single 40pt)",
        findings: [
          { tag: "CHANGED", title: "Density + interaction", detail: "4×6pt pixel row → single 40pt chip (icon-only) — fingers can't reliably hit 6pt dots." },
          { tag: "NEW", title: "Context-aware tap target", detail: "Connected + deck snapshot → opens Deck; connected (no deck) or paired-offline → ConnectionCenter; not paired → hidden." },
        ],
      },
      {
        donor: "QRScannerView",
        next: "SSHPrivateKeyQRCodeImportView",
        findings: [
          { tag: "CHANGED", title: "Consolidated scanner", detail: "Donor had parallel QR paths (Mac pairing + SSH key). Next consolidates to a unified SSH key scanner." },
        ],
      },
      {
        donor: "(none — per-surface error handling)",
        next: "NetworkStatusBanner",
        findings: [
          { tag: "NEW", title: "Shared banner component", detail: "ok / offline / requestFailed enum + View. Used by AskAINext + ReadAloudNext." },
          { tag: "MISSING", title: "Banner in Bridge cluster", detail: "Not wired into ConnectionCenterNext / BridgeDetailNext / DeckMirrorNext yet — those only show local bridge errors." },
        ],
      },
    ],
  },
  {
    key: "C6",
    label: "C6 · RECORDING · WORKFLOWS · FEEDBACK · ASK AI",
    blurb:
      "Recording sheet, dictation overlay, keyboard activation, workflows hub, feedback, Ask AI. Action surfaces.",
    subsurfaces: [
      {
        donor: "RecordingView",
        next: "RecordingSheetNext",
        findings: [
          { tag: "MISSING", title: "Attachment pipeline", detail: "Donor `showingAttachmentPhotoPicker` + `pendingAttachments` + MemoAttachmentStore + sidecar requests. Zero attachment support in Next." },
          { tag: "CHANGED", title: "Detents 280/600 → 280/560", detail: "Expanded height trimmed 40pt; title input gated to stopped state only." },
          { tag: "CHANGED", title: "Three explicit transport buttons", detail: "Cancel / Stop / Save with primary/secondary styling — clearer affordances vs donor's center-only button." },
        ],
      },
      {
        donor: "MinimalDictationOverlay",
        next: "MinimalDictationOverlayNext",
        findings: [
          { tag: "CHANGED", title: "Controller singleton abstraction", detail: "Donor observes HeadlessDictationService directly with 0.2s timer. Next paints from `MinimalDictationOverlayController.isVisible` + `partialText` — real state binding deferred to Codex." },
          { tag: "NEW", title: "Demo surface for screenshots", detail: "MinimalDictationOverlayDemoSurface wrapper for screenshot/preview mode. Donor has none." },
        ],
      },
      {
        donor: "KeyboardActivationView (829L)",
        next: "KeyboardActivationNext (450L)",
        findings: [
          { tag: "CHANGED", title: "Decoupled via store", detail: "KeyboardActivationStore enables screenshot mode + preview unit tests without full service stack. Live bindings deferred." },
          { tag: "CHANGED", title: "Keyboard mode toggle", detail: "Donor's KeyboardModeToggle binds to HeadlessDictationService.isActive. Next is visual pill only — no real toggle in paint layer." },
          { tag: "STUB", title: "returnInfoDismissed persistence", detail: "Both track it; Next store doesn't save to UserDefaults — resets per session." },
        ],
      },
      {
        donor: "ActionDock (565L)",
        next: "VoicePivotButton + QuickEntriesBar",
        findings: [
          { tag: "MISSING", title: "Terminal button", detail: "Donor leftmost ActionDock button (terminalState enum pair/open/resume). No equivalent in Next shell — terminal discovered via Settings." },
          { tag: "MISSING", title: "Center button → showingRecordingView", detail: "Donor centerButton toggles modal binding. Next routes via VoicePivotButton.tap → `chrome.tapVoiceButton()`." },
          { tag: "CHANGED", title: "Three-button dock → corner + bar", detail: "VoicePivotButton (48pt corner, three states) + QuickEntriesBar (full-width strip)." },
          { tag: "NEW", title: "ListeningBubble floats above mic", detail: "`Hold · Listening` + waveform. No donor equivalent." },
        ],
      },
      {
        donor: "WorkflowActionSheet",
        next: "WorkflowsNext (hub)",
        findings: [
          { tag: "CHANGED", title: "Per-memo sheet → standalone hub", detail: "Donor was Summarize / Taskify / Reminders on a single memo. Next hub: templates + schedules + history. Distinct from CaptureAICommandsSheet." },
          { tag: "MISSING", title: "Per-memo workflow triggers", detail: "No inline 'Summarize this memo' button on memo detail in Next — user must enter the hub." },
        ],
      },
      {
        donor: "FeedbackSheet",
        next: "FeedbackNext",
        findings: [
          { tag: "MISSING", title: "Log attachment + redaction UI", detail: "Both sides reference auto-included logs but neither paints log inspection / redaction. Redaction deferred to FeedbackReporter service." },
        ],
      },
      {
        donor: "(none)",
        next: "AskAINext",
        findings: [
          { tag: "NEW", title: "Net-new agentic loop surface", detail: "Multi-turn USER/TALKIE turns with T01/T02 codes + latency + token estimates. Presets carousel (Summarize / Action items / Rewrite / Explain). Post-response actions (Save / Listen / Refine)." },
          { tag: "STUB", title: "Provider resolution", detail: "Mocks `No configuration` error; Codex wires real TalkieAIProviderResolver + borrowed Mac credentials." },
        ],
      },
    ],
  },
];

const TAG_TONE: Record<Tag, { color: string; bg: string }> = {
  MISSING: { color: "#d97757", bg: "rgba(217, 119, 87, 0.08)" },
  STUB: { color: "var(--theme-amber, #b5823a)", bg: "rgba(181, 130, 58, 0.08)" },
  CHANGED: { color: "var(--studio-ink, #222)", bg: "transparent" },
  NEW: { color: "#3fa57a", bg: "rgba(63, 165, 122, 0.08)" },
};

export function ParityAudit() {
  const all = CLUSTERS.flatMap((c) => c.subsurfaces.flatMap((s) => s.findings));
  const counts = {
    total: all.length,
    missing: all.filter((f) => f.tag === "MISSING").length,
    stub: all.filter((f) => f.tag === "STUB").length,
    changed: all.filter((f) => f.tag === "CHANGED").length,
    fresh: all.filter((f) => f.tag === "NEW").length,
  };

  const [decisions, setDecisions] = useState<DecisionMap>({});
  const [hydrated, setHydrated] = useState(false);
  const [copyState, setCopyState] = useState<"idle" | "copied">("idle");

  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) setDecisions(JSON.parse(raw));
    } catch {
      // ignore — start with empty map
    }
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(decisions));
    } catch {
      // storage full / disabled — silent
    }
  }, [decisions, hydrated]);

  function setEntry(key: string, patch: Partial<DecisionEntry>) {
    setDecisions((prev) => {
      const next = { ...prev };
      const current = next[key] ?? { decision: null, note: "" };
      const merged = { ...current, ...patch };
      // PORT is the default — only persist entries that diverge (DROP/DEFER) or have a note.
      const divergent = merged.decision === "DROP" || merged.decision === "DEFER";
      if (!divergent && !merged.note.trim()) {
        delete next[key];
      } else {
        next[key] = merged;
      }
      return next;
    });
  }

  const decisionCounts = useMemo(() => {
    let drop = 0;
    let defer = 0;
    for (const entry of Object.values(decisions)) {
      if (entry.decision === "DROP") drop += 1;
      else if (entry.decision === "DEFER") defer += 1;
    }
    return { port: counts.total - drop - defer, drop, defer };
  }, [decisions, counts.total]);

  async function copyDecisions() {
    const payload = CLUSTERS.flatMap((c) =>
      c.subsurfaces.flatMap((s) =>
        s.findings.map((f) => {
          const key = findingKey(c.key, s.donor, f.title);
          const entry = decisions[key];
          const decision: Decision = entry?.decision ?? "PORT";
          return {
            cluster: c.key,
            donor: s.donor,
            next: s.next,
            tag: f.tag,
            title: f.title,
            decision,
            note: entry?.note?.trim() || undefined,
          };
        }),
      ),
    );
    try {
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      setCopyState("copied");
      setTimeout(() => setCopyState("idle"), 1500);
    } catch {
      // clipboard blocked
    }
  }

  function clearDecisions() {
    if (!confirm("Reset all findings back to PORT and clear notes?")) return;
    setDecisions({});
  }

  return (
    <div className="flex flex-col gap-10">
      <div className="grid grid-cols-5 gap-4 rounded-md border border-studio-edge p-4">
        <Stat label="Findings" value={String(counts.total)} />
        <Stat label="Missing" value={String(counts.missing)} tone="coral" />
        <Stat label="Stubbed" value={String(counts.stub)} tone="amber" />
        <Stat label="Changed" value={String(counts.changed)} />
        <Stat label="New in Next" value={String(counts.fresh)} tone="ok" />
      </div>

      <div className="flex flex-col gap-3 rounded-md border border-studio-edge p-4">
        <div className="flex items-baseline justify-between gap-4 flex-wrap">
          <span className="text-[9px] font-semibold uppercase tracking-eyebrow font-mono text-studio-ink">
            · Triage
          </span>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={copyDecisions}
              className="rounded-md border border-studio-edge px-2.5 py-1 text-[10px] font-mono uppercase tracking-eyebrow text-studio-ink hover:bg-[rgba(0,0,0,0.04)] transition-colors"
            >
              {copyState === "copied" ? "Copied" : "Copy decisions"}
            </button>
            <button
              type="button"
              onClick={clearDecisions}
              className="rounded-md border border-studio-edge px-2.5 py-1 text-[10px] font-mono uppercase tracking-eyebrow text-studio-ink-faint hover:bg-[rgba(0,0,0,0.04)] transition-colors"
            >
              Clear
            </button>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-4">
          <Stat label="Port (default)" value={String(decisionCounts.port)} tone="ok" />
          <Stat label="Drop" value={String(decisionCounts.drop)} tone="coral" />
          <Stat label="Defer" value={String(decisionCounts.defer)} tone="amber" />
        </div>
      </div>

      <div className="text-[11px] leading-relaxed text-studio-ink-faint max-w-[760px]">
        Donor lives on <code className="font-mono text-[10px] text-studio-ink">master</code>;
        Next lives on <code className="font-mono text-[10px] text-studio-ink">feat/ios-shell-phase-0</code>.
        Findings produced by a 6-agent swarm comparing each cluster on
        2026-05-21. Tags carry intent: <Legend tag="MISSING" /> means a donor
        feature is gone; <Legend tag="STUB" /> means Next paints but the logic
        isn't wired; <Legend tag="CHANGED" /> is a deliberate behavior swap;{" "}
        <Legend tag="NEW" /> is Next-only scope without a donor counterpart.
        Styling differences are out of scope. Decisions persist locally — use{" "}
        <span className="font-mono">Copy decisions</span> to hand them to the
        swarm.
      </div>

      {CLUSTERS.map((c) => (
        <ClusterSection
          key={c.key}
          cluster={c}
          decisions={decisions}
          onSet={setEntry}
        />
      ))}
    </div>
  );
}

function Stat({
  label,
  value,
  tone = "neutral",
}: {
  label: string;
  value: string;
  tone?: "neutral" | "ok" | "amber" | "coral";
}) {
  const color =
    tone === "ok"
      ? "#3fa57a"
      : tone === "amber"
        ? "var(--theme-amber, #b5823a)"
        : tone === "coral"
          ? "#d97757"
          : undefined;
  return (
    <div className="flex flex-col gap-1">
      <span className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        {label}
      </span>
      <span
        className="text-[26px] tabular-nums leading-none font-mono"
        style={{ color }}
      >
        {value}
      </span>
    </div>
  );
}

function Legend({ tag }: { tag: Tag }) {
  return (
    <span
      className="rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono"
      style={{ color: TAG_TONE[tag].color, border: `1px solid ${TAG_TONE[tag].color}` }}
    >
      {tag}
    </span>
  );
}

function ClusterSection({
  cluster,
  decisions,
  onSet,
}: {
  cluster: Cluster;
  decisions: DecisionMap;
  onSet: (key: string, patch: Partial<DecisionEntry>) => void;
}) {
  const total = cluster.subsurfaces.reduce(
    (acc, s) => acc + s.findings.length,
    0,
  );
  const missing = cluster.subsurfaces.reduce(
    (acc, s) => acc + s.findings.filter((f) => f.tag === "MISSING").length,
    0,
  );
  const stream = STREAMS_BY_KEY[cluster.key];
  const streamNotes = stream?.notes ?? [];
  const generalNotes = streamNotes.filter((n) => !n.findingKey);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-baseline gap-4 pb-1.5 border-b border-studio-edge flex-wrap">
        <span
          className="text-[9px] font-semibold uppercase tracking-eyebrow font-mono"
          style={{ color: "var(--studio-ink, #222)" }}
        >
          · {cluster.label}
        </span>
        <span className="text-[10px] tabular-nums font-mono text-studio-ink-faint">
          {total} findings · {missing} missing
        </span>
        {stream && <StreamBadge stream={stream} />}
        <span className="text-[11px] text-studio-ink-faint">{cluster.blurb}</span>
      </div>
      {generalNotes.length > 0 && (
        <NotesLog
          notes={generalNotes}
          heading={`STREAM · ${cluster.key}`}
        />
      )}
      <div className="flex flex-col gap-4">
        {cluster.subsurfaces.map((s, i) => (
          <SubsurfaceBlock
            key={`${cluster.key}-${i}`}
            subsurface={s}
            clusterKey={cluster.key}
            decisions={decisions}
            onSet={onSet}
            streamNotes={streamNotes}
          />
        ))}
      </div>
    </div>
  );
}

const STREAM_STATUS_TONE: Record<StreamStatus, { color: string; label: string }> = {
  queued: { color: "var(--studio-ink-faint, #888)", label: "QUEUED" },
  "in-flight": { color: "var(--theme-amber, #b5823a)", label: "IN FLIGHT" },
  blocked: { color: "#d97757", label: "BLOCKED" },
  done: { color: "#3fa57a", label: "DONE" },
};

function StreamBadge({ stream }: { stream: Stream }) {
  const meta = STREAM_STATUS_TONE[stream.status];
  return (
    <span className="inline-flex items-center gap-1.5 text-[9px] font-mono uppercase tracking-eyebrow">
      <span
        className="rounded-full px-1.5 py-0.5 font-semibold"
        style={{ color: meta.color, border: `1px solid ${meta.color}` }}
      >
        {meta.label}
      </span>
      {stream.owner ? (
        <span className="text-studio-ink-faint">
          · owner <span className="text-studio-ink">{stream.owner}</span>
        </span>
      ) : (
        <span className="text-studio-ink-faint">· unclaimed</span>
      )}
    </span>
  );
}

const NOTE_LEVEL_TONE: Record<NoteLevel, string> = {
  info: "var(--studio-ink-faint, #888)",
  progress: "var(--theme-amber, #b5823a)",
  landed: "#3fa57a",
  blocked: "#d97757",
  proposal: "var(--theme-amber, #b5823a)",
  question: "#d97757",
};

function NotesLog({
  notes,
  heading,
}: {
  notes: StreamNote[];
  heading: string;
}) {
  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-studio-edge p-3 bg-[rgba(0,0,0,0.02)]">
      <div className="text-[9px] font-semibold uppercase tracking-eyebrow font-mono text-studio-ink-faint">
        {heading}
      </div>
      {notes.map((n, i) => (
        <NoteRow key={i} note={n} />
      ))}
    </div>
  );
}

function NoteRow({ note }: { note: StreamNote }) {
  const color = NOTE_LEVEL_TONE[note.level];
  return (
    <div className="flex items-baseline gap-2 text-[11px] leading-snug flex-wrap">
      <span
        className="rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono"
        style={{ color, border: `1px solid ${color}` }}
      >
        {note.level}
      </span>
      <span className="font-mono text-[9px] text-studio-ink-faint shrink-0">
        {note.ts.slice(0, 16).replace("T", " ")} · {note.agent}
      </span>
      <span className="text-studio-ink">{note.message}</span>
      {note.ref && (
        <span className="font-mono text-[10px] text-studio-ink-faint">
          {note.ref}
        </span>
      )}
    </div>
  );
}

function SubsurfaceBlock({
  subsurface,
  clusterKey,
  decisions,
  onSet,
  streamNotes,
}: {
  subsurface: Subsurface;
  clusterKey: string;
  decisions: DecisionMap;
  onSet: (key: string, patch: Partial<DecisionEntry>) => void;
  streamNotes: StreamNote[];
}) {
  const findingKeys = new Set(
    subsurface.findings.map((f) =>
      findingKey(clusterKey, subsurface.donor, f.title),
    ),
  );
  const sectionNotes = streamNotes.filter(
    (n) => n.findingKey && findingKeys.has(n.findingKey),
  );
  return (
    <div className="flex flex-col gap-2 rounded-md border border-studio-edge p-4">
      <div className="flex items-baseline gap-3 flex-wrap">
        <span className="font-display text-[14px] font-medium text-studio-ink">
          {subsurface.donor}
        </span>
        <span className="text-[10px] font-mono text-studio-ink-faint">→</span>
        <span className="font-mono text-[11px] text-studio-ink">
          {subsurface.next}
        </span>
        {sectionNotes.length > 0 && (
          <span className="ml-auto text-[9px] font-mono uppercase tracking-eyebrow text-studio-ink-faint">
            {sectionNotes.length} agent note{sectionNotes.length === 1 ? "" : "s"}
          </span>
        )}
      </div>
      <div className="grid grid-cols-2 gap-2 mt-1">
        {subsurface.findings.map((f, i) => {
          const key = findingKey(clusterKey, subsurface.donor, f.title);
          const cardNotes = streamNotes.filter((n) => n.findingKey === key);
          return (
            <FindingCard
              key={i}
              finding={f}
              entry={decisions[key] ?? { decision: null, note: "" }}
              onSet={(patch) => onSet(key, patch)}
              agentNotes={cardNotes}
            />
          );
        })}
      </div>
    </div>
  );
}

const DECISION_TONE: Record<Decision, string> = {
  PORT: "#3fa57a",
  DROP: "#d97757",
  DEFER: "var(--theme-amber, #b5823a)",
};

function FindingCard({
  finding,
  entry,
  onSet,
  agentNotes,
}: {
  finding: Finding;
  entry: DecisionEntry;
  onSet: (patch: Partial<DecisionEntry>) => void;
  agentNotes: StreamNote[];
}) {
  const tone = TAG_TONE[finding.tag];
  return (
    <div
      className="flex flex-col gap-1.5 rounded-md border border-studio-edge p-3"
      style={{ backgroundColor: tone.bg }}
    >
      <div className="flex items-baseline gap-2">
        <span
          className="rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono"
          style={{ color: tone.color, border: `1px solid ${tone.color}` }}
        >
          {finding.tag}
        </span>
        <span className="text-[12px] font-medium leading-tight text-studio-ink">
          {finding.title}
        </span>
      </div>
      <div className="text-[11px] leading-snug text-studio-ink-faint">
        {finding.detail}
      </div>
      <div className="flex items-center gap-1 mt-1">
        {(["PORT", "DROP", "DEFER"] as Decision[]).map((d) => {
          // PORT is the implicit default — show it active when no choice has been made.
          const effective = entry.decision ?? "PORT";
          const active = effective === d;
          const color = DECISION_TONE[d];
          const onClick =
            d === "PORT"
              ? () => onSet({ decision: null })
              : () => onSet({ decision: active ? null : d });
          return (
            <button
              key={d}
              type="button"
              onClick={onClick}
              className="rounded-full px-2 py-0.5 text-[9px] font-semibold uppercase tracking-eyebrow font-mono transition-colors"
              style={{
                color: active ? "#fff" : color,
                backgroundColor: active ? color : "transparent",
                border: `1px solid ${color}`,
              }}
            >
              {d}
            </button>
          );
        })}
      </div>
      <textarea
        value={entry.note}
        onChange={(e) => onSet({ note: e.target.value })}
        placeholder="note for the swarm…"
        rows={1}
        className="mt-0.5 w-full resize-y rounded-md border border-studio-edge bg-transparent px-2 py-1 text-[11px] leading-snug text-studio-ink placeholder:text-studio-ink-faint focus:outline-none focus:border-studio-ink"
      />
      {agentNotes.length > 0 && (
        <div className="mt-1 flex flex-col gap-1 border-t border-studio-edge pt-1.5">
          {agentNotes.map((n, i) => (
            <NoteRow key={i} note={n} />
          ))}
        </div>
      )}
    </div>
  );
}
