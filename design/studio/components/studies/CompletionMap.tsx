"use client";

/**
 * Completion map — feature-completion roadmap for the Talkie iOS
 * rebuild. Organized as a release train (M1 → Mx), each milestone
 * is a section of feature cards with status / size / risk pills.
 *
 * Surface vocabulary matches ArchitectureMap (channel codes,
 * mono eyebrows, ORPHAN-tone for risk, accent for "next up"
 * indicators).
 */

type Status = "shipped" | "in-flight" | "next" | "queued" | "future" | "deferred";
type Size = "xs" | "s" | "m" | "l" | "xl";
type Risk = "low" | "med" | "high";

interface Item {
  code: string;
  title: string;
  detail: string;
  status: Status;
  size: Size;
  risk?: Risk;
  /** Which agent / owner — usually a codex stream name or "self". */
  owner?: string;
}

interface Milestone {
  key: string;
  label: string;
  blurb: string;
  items: Item[];
}

const MILESTONES: Milestone[] = [
  {
    key: "M1",
    label: "M1 · NEXT SHELL",
    blurb:
      "The Next design system landed — shell, router, all canonical surfaces painted + wired, Clerk teardown, type token system.",
    items: [
      { code: "F01", title: "AppShellNext + AppShellRouter", detail: "Surface enum, direction-aware push/pop transitions, voice button + chrome overlay.", status: "shipped", size: "l" },
      { code: "F02", title: "Canonical surfaces", detail: "Home, Library, Compose, CaptureDetail, VoiceMemoDetail, DictationHistory, RecordingSheet.", status: "shipped", size: "xl" },
      { code: "F03", title: "Clerk teardown", detail: "AuthManager + ClerkKit SPM + 23k lines of legacy donor cluster removed.", status: "shipped", size: "l" },
      { code: "F04", title: "Native ASAuthorization", detail: "SignInNext on AppleID + Keychain. Drives auth-steps S01–S03 channel display.", status: "shipped", size: "m" },
      { code: "F05", title: "Type token system", detail: "TalkieTypeStyle bundles font + tracking + textCase + monospacedDigit. Newsreader as editorial punctuation.", status: "shipped", size: "m" },
      { code: "F06", title: "Token migration sweep", detail: "12 Next surfaces migrated from inline .font() to .talkieType() tokens.", status: "shipped", size: "m" },
      { code: "F07", title: "SettingsNext Inspector", detail: "Vertical rail of rotated-type chips, 6 panels, uniform 28×88 chip cells, 44pt field rows.", status: "shipped", size: "l" },
      { code: "F08", title: "SettingsNext data wiring", detail: "TalkieAppSettings, ThemeManager, BridgeManager, iCloudStatusManager all bound.", status: "shipped", size: "m" },
      { code: "F09", title: "TerminalNext", detail: "Saved SSH host list backed by SSHTerminalSavedHostStore. Tap → SSHTerminalView sheet.", status: "shipped", size: "m" },
      { code: "F10", title: "CameraCaptureNext", detail: "AVFoundation camera + Vision OCR + CaptureStore write-through.", status: "shipped", size: "l" },
      { code: "F11", title: "BridgeDetailNext", detail: "Replaces legacy BridgeSettingsView sheet. Live BridgeManager status, sessions, pairing.", status: "shipped", size: "l" },
      { code: "F12", title: "AskAINext", detail: "Multi-turn agentic loop, T-channel turns, presets, AI service + voice shim.", status: "shipped", size: "l" },
      { code: "F13", title: "ReadAloudNext", detail: "TTS playback surface, source viewer with text/image/url/pdf modes.", status: "shipped", size: "l" },
    ],
  },
  {
    key: "M2",
    label: "M2 · ENTRY POINTS",
    blurb:
      "Wire the orphan surfaces and round out the connections — small surgical edits, no new features.",
    items: [
      { code: "W01", title: "Listen-anywhere", detail: "Action chip on CaptureDetail · VoiceMemoDetail · AskAI (post-response) → openReadAloud(source:). Declares ReadAloudSource payload on AppShellRouter; Codex wires player.bind consumption.", status: "shipped", size: "s" },
      { code: "W02", title: "Sign in from Settings", detail: "SettingsNext CONNECT panel → conditional 'Sign in with Apple' row when account empty (replaces 'Sign out' when signed out).", status: "shipped", size: "s" },
      { code: "W03", title: "Browse tray slot", detail: "ChromeOverlay tray grew from 3 to 5 slots: Camera · Browse · Mic FAB · Ask AI · Terminal. FAB stays centered — additions paired across the FAB to preserve symmetry.", status: "shipped", size: "s" },
      { code: "W04", title: "Connection detail link", detail: "SettingsNext CONNECT panel → 'View connections detail ›' nav row → openConnectionCenter(). New navRow primitive for chevron-style navigation.", status: "shipped", size: "xs" },
      { code: "W05", title: "Dictation History in Library", detail: "LibraryNextView Dictations tab → 'View full dictation history ›' link card → openDictationHistory().", status: "shipped", size: "s" },
      { code: "W06", title: "Retire Appearance", detail: "Deleted AppearancePickerNext.swift + Surface.appearance + openAppearance() + --appearance launch arg. Home gear now routes only to Settings.", status: "shipped", size: "xs" },
      { code: "W07", title: "Architecture canvas v2", detail: "Studio /architecture upgrade to canvas-based UX journey map with embedded mini-views.", status: "in-flight", size: "m", owner: "codex-talkie-canvas" },
    ],
  },
  {
    key: "M3",
    label: "M3 · INTEGRATION POLISH",
    blurb:
      "Incremental polish on the just-shipped surfaces — replace shims, tighten flows, add the missing affordances.",
    items: [
      { code: "P01", title: "ReadAloud real range callback", detail: "Replace local timer shim with AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString for chunk highlight.", status: "queued", size: "s", risk: "med", owner: "codex (pending)" },
      { code: "P02", title: "AskAI multi-turn persistence", detail: "Session state survives surface close + reopen. Save turns to local store.", status: "queued", size: "m", risk: "low", owner: "codex (pending)" },
      { code: "P03", title: "Camera OCR confidence", detail: "ScanPreviewOverlay with per-chunk confidence pills (HIGH/MED/LOW bands), low-confidence row tint, and a Reshoot affordance. Inserts a confirm step between OCR and save. Codex still needs to wire real Vision per-observation confidence into OCRChunk.", status: "shipped", size: "m" },
      { code: "P04", title: "Bridge pairing flow", detail: "PairingPhaseBanner across the top of BridgeDetailNext shows Discover → Pair → Handshake → Linked progression, derived live from BridgeManager state. ErrorBanner with inline RETRY for failure states.", status: "shipped", size: "m" },
      { code: "P05", title: "Home ambient status pixels", detail: "AmbientStatusRow at top-left of HomeNextView: three pixels (Mac · iCloud · Account) reactive to BridgeManager + iCloudStatusManager + SignInStore. Tap routes to ConnectionCenter (sign-in pixel → SignIn when signed out).", status: "shipped", size: "s" },
      { code: "P06", title: "AskAI next-action chips", detail: "Save as memo · Listen · Refine row beneath every completed TALKIE turn. Declares router contracts openComposeSeeded(text:) + saveAsMemo(text:) with pendingComposeSeed / pendingNewMemoText payloads for Codex to wire downstream.", status: "shipped", size: "s" },
    ],
  },
  {
    key: "M4",
    label: "M4 · MISSING SURFACES",
    blurb:
      "Features deleted with the donor cleanup that need Next equivalents if the user-facing scope still includes them.",
    items: [
      { code: "M01", title: "Memo attachments", detail: "VoiceMemoDetailNext grew an ATTACHMENTS section between transcript + action bar. Adaptive grid of thumbnail tiles with inline remove; PhotosPicker for adding. Bound to existing MemoAttachmentStore.shared.", status: "shipped", size: "m" },
      { code: "M02", title: "OCR preview before save", detail: "ScanPreviewOverlay grew an Edit toggle — chunk list flips into a TextEditor seeded with combinedText so the user can correct wobbly OCR before save. confirmAndSave(editedText:) accepts the override; nil falls back to OCR-derived text.", status: "shipped", size: "s" },
      { code: "M03", title: "AI provider credentials", detail: "AICredentialsNext lists providers (OpenAI · Anthropic · Groq · OpenRouter) with SET/NOT SET pills + tap-to-edit modal (masked field, paste, clear). Paint-side keys are in-memory; Codex wires AICredentialStore against Keychain.", status: "shipped", size: "m" },
      { code: "M04", title: "Feedback submission", detail: "FeedbackNext surface with description + optional contact + auto-included info panel. SettingsNext ABOUT panel grew a 'Send feedback' navRow. Submit is a 0.8s mock returning a FB-xxxxxxxx report id; Codex wires the real api.usetalkie.com endpoint.", status: "shipped", size: "xs" },
      { code: "M05", title: "Workflow actions surface", detail: "WorkflowsNext hub: TEMPLATES list (Summarize, Re-title, Outline, Translate) with per-row RUN chip, SCHEDULED section (empty for now), HISTORY with outcome markers + reason. Codex wires WorkflowsStore (templates/schedules/runs) + run(template:on:).", status: "shipped", size: "l" },
      { code: "M06", title: "Mac availability coach", detail: "MacCoachCard empty-state at the top of BridgeDetailNext when !hasPairedMacs. Numbered 3-step walkthrough (open Mac app · same network · tap nearby or scan) + QR CTA. Auto-dismisses once a pair lands.", status: "shipped", size: "s" },
      { code: "M07", title: "Companion shortcut config", detail: "Configure iOS Shortcuts integration. Donor: CompanionShortcutModeView.", status: "deferred", size: "m", risk: "low" },
      { code: "M08", title: "HyperScan capture flow", detail: "Niche bulk-scan flow. Donor: HyperScanCaptureView.", status: "deferred", size: "m", risk: "low" },
    ],
  },
  {
    key: "M5",
    label: "M5 · NEW SCOPE",
    blurb:
      "Surfaces that didn't exist in the donor — system-level integrations that extend Talkie's reach.",
    items: [
      { code: "N01", title: "Share extension", detail: "TalkieShare target — ShareViewController accepts URLs / text / images from the iOS share sheet, writes to the App Group container (group.to.talkie.app), and opens the main app to process. No legacy Clerk dependency.", status: "shipped", size: "l" },
      { code: "N02", title: "Widget complications", detail: "TalkieWidget + TalkieWatchWidget targets. iOS widget shows memo count + recent memos with adaptive theme; watch widget surfaces recording entry. Both wired via App Group.", status: "shipped", size: "m" },
      { code: "N03", title: "Watch app", detail: "TalkieWatch Watch App — RecordingView, RecentMemosView, PresetPickerView, AboutView, with WatchSessionManager bridging to the iPhone. AudioRecorder for watch-side capture.", status: "shipped", size: "xl" },
      { code: "N04", title: "Background dictation", detail: "Info.plist UIBackgroundModes includes 'audio' + 'remote-notification'. AudioRecorderManager wraps recordings in beginBackgroundTask/endBackgroundTask so iOS keeps the mic alive when the app suspends. BackgroundTasks framework registered for scheduled refreshes.", status: "shipped", size: "l" },
      { code: "N05", title: "Multi-account", detail: "Support multiple sign-ins (work + personal). Workspace switcher.", status: "future", size: "xl", risk: "high" },
      { code: "N06", title: "iCloud sync conflict resolution", detail: "SyncConflictNext surface — pending list of LOCAL vs iCLOUD versions with Keep local / Keep iCloud / Keep both chips per conflict. Resolved state when empty. Codex wires SyncConflictStore.pending from CKModifyRecordsOperation errors. Entry: Settings CONNECT → 'Resolve sync conflicts'.", status: "shipped", size: "m" },
    ],
  },
  {
    key: "M6",
    label: "M6 · SYSTEM POLISH",
    blurb:
      "Cross-cutting work — accessibility, performance, localization. Not optional for shipping, but parallel to feature work.",
    items: [
      { code: "S01", title: "Accessibility audit", detail: "Phase A · VoiceOver label sweep: every glyph button announces; AmbientStatusRow pixels labelled. Phase B · Dynamic Type: editorial tokens (headline · listTitle · preview · headlineSecondary) now anchor to TextStyle so they scale; channel labels + chip labels stay fixed for chrome density; shell clamps to .accessibility3. Phase C · theme contrast pass remains.", status: "in-flight", size: "l", risk: "med" },
      { code: "S02", title: "Localization", detail: "Scaffold landed — Localizable.xcstrings (modern String Catalog) replaces the old Localizable.strings. Xcode auto-extracts Text(...) literals via LocalizedStringKey on each build. Next: review the auto-extracted entries + add the first non-English locale.", status: "in-flight", size: "l", risk: "low" },
      { code: "S03", title: "Launch performance", detail: "Cold-launch budget under 1s. Profile + trim app boot path.", status: "future", size: "m", risk: "med" },
      { code: "S04", title: "Offline error states", detail: "Shared NetworkStatusBanner component (offline · requestFailed · ok) wired into AskAINext above the conversation area. RETRY chip resets session.errorMessage and re-sends. Codex layers NetworkReachability into networkStatus to drive the .offline branch.", status: "shipped", size: "m" },
      { code: "S05", title: "Empty states", detail: "LibraryNextView EmptyTabState upgraded — icon tile + headline + hint + per-tab CTA chip (RECORD · ENABLE KEYBOARD · OPEN CAMERA). DictationHistory, Terminal, Workflows schedules/history, memo attachments all already shipped with designed empties.", status: "shipped", size: "s" },
    ],
  },
];

const STATUS_TONE: Record<Status, { color: string; label: string }> = {
  shipped: { color: "#3fa57a", label: "SHIPPED" },
  "in-flight": { color: "var(--theme-amber, #b5823a)", label: "IN FLIGHT" },
  next: { color: "var(--theme-amber, #b5823a)", label: "NEXT" },
  queued: { color: "var(--studio-ink-faint, #888)", label: "QUEUED" },
  future: { color: "var(--studio-ink-faint, #888)", label: "FUTURE" },
  deferred: { color: "var(--studio-ink-faint, #888)", label: "DEFERRED" },
};

const RISK_TONE: Record<Risk, string> = {
  low: "var(--studio-ink-faint, #888)",
  med: "#b5823a",
  high: "#d97757",
};

export function CompletionMap() {
  const all = MILESTONES.flatMap((m) => m.items);
  const counts = {
    total: all.length,
    shipped: all.filter((i) => i.status === "shipped").length,
    inFlight: all.filter((i) => i.status === "in-flight").length,
    next: all.filter((i) => i.status === "next").length,
    ahead: all.filter((i) =>
      ["queued", "future", "deferred"].includes(i.status)
    ).length,
  };

  return (
    <div className="flex flex-col gap-10">
      <div className="grid grid-cols-5 gap-4 rounded-md border border-studio-edge p-4">
        <Stat label="Total" value={String(counts.total)} />
        <Stat label="Shipped" value={String(counts.shipped)} tone="ok" />
        <Stat label="In flight" value={String(counts.inFlight)} tone="amber" />
        <Stat label="Next up" value={String(counts.next)} tone="amber" />
        <Stat label="Ahead" value={String(counts.ahead)} />
      </div>

      {MILESTONES.map((m) => (
        <MilestoneSection key={m.key} milestone={m} />
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
  tone?: "neutral" | "ok" | "amber";
}) {
  const color =
    tone === "ok"
      ? "#3fa57a"
      : tone === "amber"
        ? "var(--theme-amber, #b5823a)"
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

function MilestoneSection({ milestone }: { milestone: Milestone }) {
  const shippedCount = milestone.items.filter((i) => i.status === "shipped")
    .length;
  const totalCount = milestone.items.length;
  const allShipped = shippedCount === totalCount;
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-baseline gap-4 pb-1.5 border-b border-studio-edge">
        <span
          className="text-[9px] font-semibold uppercase tracking-eyebrow font-mono"
          style={{ color: allShipped ? "#3fa57a" : "var(--theme-amber, #b5823a)" }}
        >
          · {milestone.label}
        </span>
        <span className="text-[10px] tabular-nums font-mono text-studio-ink-faint">
          {shippedCount} / {totalCount}
        </span>
        <span className="text-[11px] text-studio-ink-faint">{milestone.blurb}</span>
      </div>
      <div className="grid grid-cols-3 gap-3">
        {milestone.items.map((item) => (
          <ItemCard key={item.code} item={item} />
        ))}
      </div>
    </div>
  );
}

function ItemCard({ item }: { item: Item }) {
  const statusMeta = STATUS_TONE[item.status];
  const dim = item.status === "future" || item.status === "deferred";
  return (
    <div
      className="flex flex-col gap-2 rounded-md border border-studio-edge p-3"
      style={{ opacity: dim ? 0.7 : 1 }}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span
          className="text-[9px] font-semibold uppercase tracking-eyebrow font-mono"
          style={{ color: statusMeta.color }}
        >
          {item.code}
        </span>
        <div className="flex items-center gap-1.5">
          {item.risk && <RiskPill risk={item.risk} />}
          <SizePill size={item.size} />
          <StatusPill status={item.status} />
        </div>
      </div>

      <div className="text-[14px] font-medium leading-tight text-studio-ink">
        {item.title}
      </div>

      <div className="text-[11px] leading-snug text-studio-ink-faint">
        {item.detail}
      </div>

      {item.owner && (
        <div
          className="mt-1 text-[9px] uppercase tracking-eyebrow font-mono"
          style={{ color: STATUS_TONE["in-flight"].color }}
        >
          OWNER · {item.owner}
        </div>
      )}
    </div>
  );
}

function StatusPill({ status }: { status: Status }) {
  const meta = STATUS_TONE[status];
  return (
    <span
      className="rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono"
      style={{ color: meta.color, border: `1px solid ${meta.color}` }}
    >
      {meta.label}
    </span>
  );
}

function SizePill({ size }: { size: Size }) {
  return (
    <span
      className="text-[9px] tabular-nums font-mono"
      style={{ color: "var(--studio-ink-faint, #888)" }}
    >
      {size}
    </span>
  );
}

function RiskPill({ risk }: { risk: Risk }) {
  return (
    <span
      className="rounded-full px-1 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono"
      style={{
        color: RISK_TONE[risk],
        border: `1px solid ${RISK_TONE[risk]}`,
      }}
    >
      {risk === "low" ? "·" : risk === "med" ? "··" : "···"}
    </span>
  );
}
