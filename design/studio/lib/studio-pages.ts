/**
 * Studio page registry.
 *
 * Single source of truth for studio navigation. Sidebar + per-page
 * header strip + ⌘K palette all read from this list. Adding a page
 * means appending one entry — nav surfaces it automatically.
 *
 * Buckets: Foundations / Surfaces / Lab.
 *  - Foundations: shared design system (themes, tokens, type, complications).
 *  - Surfaces:    visual end-to-end composition. Sub-grouped by platform.
 *  - Lab:         interactive tools (audit, coverage, parity, future KB).
 */

export type StudioBucket = "foundations" | "surfaces" | "lab";
export type StudioPlatform = "mac" | "iphone" | "cross" | "system";
export type StudioStatus = "concept" | "wip" | "shipped" | "deprecated";

export interface StudioPage {
  /** Route. `/path` form, no trailing slash. */
  href: string;
  /** Short label for the sidebar. */
  label: string;
  /** Bucket — drives sidebar group. */
  bucket: StudioBucket;
  /**
   * Family — same logical surface, different variants. e.g. `home`,
   * `library`, `memo`. Variants get collapsed under one entry in the
   * sidebar.
   */
  family?: string;
  /** Platform — sub-grouping inside Surfaces; ignored for Foundations / Lab. */
  platform?: StudioPlatform;
  /** Shipping status — drives the dot color in the per-page strip. */
  status?: StudioStatus;
  /** Linked Swift file(s), relative to repo root. For the page strip. */
  swift?: string[];
  /**
   * Short description — shows in the per-page strip as a subtitle.
   */
  blurb?: string;
}

export const STUDIO_PAGES: StudioPage[] = [
  // ── Foundations ──────────────────────────────────────────────────
  {
    href: "/themes",
    label: "Themes",
    bucket: "foundations",
    status: "shipped",
    blurb: "Cross-platform theme bundles + scheme picker.",
  },
  {
    href: "/iphone-themes",
    label: "iPhone Themes",
    bucket: "foundations",
    status: "shipped",
    blurb: "Scope / Midnight / Tactical / Ghost token bundles.",
  },
  {
    href: "/complications",
    label: "Complications",
    bucket: "foundations",
    status: "shipped",
    blurb: "Status pills, lozenges, eyebrows — the chrome primitives.",
  },
  {
    href: "/typography",
    label: "Typography",
    bucket: "foundations",
    status: "concept",
    swift: [
      "apps/macos/Talkie/Views/CommandPalette/CommandPaletteView.swift",
      "apps/macos/Talkie/Services/Capture/CaptureBarPanel.swift",
      "apps/macos/Talkie/Services/Capture/CaptureHUDPanel.swift",
      "apps/macos/Talkie/Services/Tray/TrayViewer.swift",
    ],
    blurb: "macOS chrome type audit — every .font() config in the capture + tray + palette surfaces.",
  },
  {
    href: "/header-system",
    label: "Header System",
    bucket: "foundations",
    status: "concept",
    swift: [
      "apps/macos/Talkie/Services/DesignSystem.swift",
      "apps/macos/Talkie/Views/Library/ScopeLibraryView.swift",
      "apps/macos/Talkie/Views/ScreenshotsScreen.swift",
    ],
    blurb: "One header standard — mono eyebrow + serif title + mono tags — and the screens that drifted from it.",
  },
  {
    href: "/top-band",
    label: "Top Band",
    bucket: "foundations",
    status: "concept",
    swift: [
      "apps/macos/TalkieKit/Sources/TalkieKit/UI/ScopeComponents.swift",
      "apps/macos/Talkie/Components/TalkieChromeBar.swift",
    ],
    blurb: "One top-band component — wordmark · title · TALKIE · complications — with a variant per view.",
  },
  {
    href: "/tape-transport",
    label: "Tape Transport",
    bucket: "foundations",
    status: "concept",
    swift: ["apps/ios/Talkie iOS/Views/WaveformView.swift"],
    blurb: "Signature voice-waveform gesture — amber centerline + travelling tape-head needle across record / transcribe / playback, with crossing ticks. Tune before the iOS waveform port (replaces the particle cloud).",
  },

  // ── Surfaces · Mac ──────────────────────────────────────────────
  {
    href: "/mac-home",
    label: "Home",
    bucket: "surfaces",
    platform: "mac",
    family: "home",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/Home/ScopeHomeView.swift"],
    blurb: "Editorial home with bay panel + capture modes.",
  },
  {
    href: "/mac-home-wide",
    label: "Home (Wide)",
    bucket: "surfaces",
    platform: "mac",
    family: "home",
    status: "concept",
  },
  {
    href: "/mac-library",
    label: "Library",
    bucket: "surfaces",
    platform: "mac",
    family: "library",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/Library/ScopeLibraryView.swift"],
  },
  {
    href: "/mac-library-empty",
    label: "Library (Empty)",
    bucket: "surfaces",
    platform: "mac",
    family: "library",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/Library/ScopeLibraryEmptyState.swift"],
  },
  {
    href: "/mac-memo-detail",
    label: "Memo Detail",
    bucket: "surfaces",
    platform: "mac",
    family: "memo",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/TalkieObject/TalkieView.swift"],
    blurb: "Editorial masthead + transcript card + margin rail.",
  },
  {
    href: "/mac-memo-wide",
    label: "Memo (Wide)",
    bucket: "surfaces",
    platform: "mac",
    family: "memo",
    status: "concept",
  },
  {
    href: "/mac-dictation-detail",
    label: "Dictation Detail",
    bucket: "surfaces",
    platform: "mac",
    family: "dictation",
    status: "shipped",
  },
  {
    href: "/mac-dictation-wide",
    label: "Dictation (Wide)",
    bucket: "surfaces",
    platform: "mac",
    family: "dictation",
    status: "concept",
  },
  {
    href: "/mac-compose",
    label: "Compose",
    bucket: "surfaces",
    platform: "mac",
    family: "compose",
    status: "wip",
  },
  {
    href: "/mac-notes",
    label: "Notes",
    bucket: "surfaces",
    platform: "mac",
    family: "notes",
    status: "shipped",
  },
  {
    href: "/mac-note-detail",
    label: "Note Detail",
    bucket: "surfaces",
    platform: "mac",
    family: "notes",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/Notes/ScopeNoteDetailView.swift"],
  },
  {
    href: "/mac-capture-detail",
    label: "Capture Detail",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/Notes/ScopeCaptureDetailView.swift"],
  },
  {
    href: "/mac-capture-markup",
    label: "Capture Markup",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "concept",
    blurb: "Voice + image markup · ask then touch up · save the computed doc, share/export a flat PNG/JPEG · replaces CleanShot delegate.",
  },
  {
    href: "/mac-capture-markup-levelup",
    label: "Markup · Level Up",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "concept",
    blurb: "Leveled-up run feedback · Work Thread (right rail streams the agent's run log-style → pass summary + undo) + Speak Strip v2 (mag-tape waveform while recording). Ports to CaptureMarkupPanelChrome.swift.",
  },
  {
    href: "/mac-capture-markup-strip",
    label: "Markup · Speak Strip",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "concept",
    blurb: "Redesigned bottom band · coding-agent identity line (agent ▸ model · scope ▸ target · pass/saved) + mic·field·run as one composer cluster + single adaptive footer. Warm-amber canon. Ports to CaptureMarkupPanelChrome.swift.",
  },
  {
    href: "/mac-capture-flow",
    label: "Capture Flow",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "concept",
    blurb: "Library → Screenshots → Markup storyboard · transitions + vocabulary.",
  },
  {
    href: "/mac-screenshots",
    label: "Screenshots",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "concept",
    blurb: "Focused gallery · anchor/⌘-toggle/shift-range selection · bulk actions + inspector pane.",
    swift: ["apps/macos/Talkie/Views/ScreenshotsScreen.swift"],
  },
  {
    href: "/mac-screenshots-headers",
    label: "Screenshots Header",
    bucket: "surfaces",
    platform: "mac",
    family: "capture",
    status: "concept",
    blurb: "Header in place over the real grid — serif standard vs mono instrument.",
    swift: ["apps/macos/Talkie/Views/ScreenshotsScreen.swift"],
  },
  {
    href: "/mac-command-palette",
    label: "Command Palette",
    bucket: "surfaces",
    platform: "mac",
    family: "navigation",
    status: "concept",
    blurb: "Voice + text palette · one surface · collapses CommandPaletteView + VoiceCommandOverlay.",
  },
  {
    href: "/mac-onboarding",
    label: "Onboarding",
    bucket: "surfaces",
    platform: "mac",
    family: "onboarding",
    status: "shipped",
  },
  {
    href: "/mac-recording-state",
    label: "Recording State",
    bucket: "surfaces",
    platform: "mac",
    family: "recording",
    status: "shipped",
    swift: ["apps/macos/Talkie/Views/RecordingCompanionSurface.swift"],
  },
  {
    href: "/mac-record-to-memo",
    label: "Record → Memo",
    bucket: "surfaces",
    platform: "mac",
    family: "recording",
    status: "concept",
    blurb: "Transition study: wave settling into transcript.",
  },
  {
    href: "/mac-learn",
    label: "Learn",
    bucket: "surfaces",
    platform: "mac",
    family: "learn",
    status: "shipped",
  },
  {
    href: "/mac-skills",
    label: "Skills",
    bucket: "surfaces",
    platform: "mac",
    family: "skills",
    status: "shipped",
  },
  {
    href: "/mac-skill-forge",
    label: "Skill Forge",
    bucket: "surfaces",
    platform: "mac",
    family: "skills",
    status: "concept",
  },
  {
    href: "/mac-talkie-button",
    label: "Talkie Button",
    bucket: "surfaces",
    platform: "mac",
    family: "chrome",
    status: "shipped",
    blurb: "Centered TALKIE pill — chrome anchor for record + nav.",
  },
  {
    href: "/mac-actor-hud",
    label: "Actor HUD",
    bucket: "surfaces",
    platform: "mac",
    family: "actor-hud",
    status: "concept",
    blurb: "Flat 2D WebView dashboard for app-icon actors.",
  },
  {
    href: "/mac-notch-settings",
    label: "Notch Settings",
    bucket: "surfaces",
    platform: "mac",
    family: "chrome",
    status: "wip",
  },
  {
    href: "/mac-agent-home",
    label: "Agent Home",
    bucket: "surfaces",
    platform: "mac",
    family: "agent",
    status: "concept",
    swift: ["apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeView.swift"],
    blurb: "One conversation surface: topics, parent turns, branch threads, and agent work folding back in-line.",
  },
  {
    href: "/mac-agent-conversation",
    label: "Agent Conversation",
    bucket: "surfaces",
    platform: "mac",
    family: "agent",
    status: "concept",
    swift: ["apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeView.swift"],
    blurb: "Conversations tab revamp: no top status strip, quiet new-conversation + agent picker, per-conversation settings top-right, active agent beside the input, adapters demoted to a subtle footer entry.",
  },
  {
    href: "/mac-agent-tray",
    label: "Agent Tray",
    bucket: "surfaces",
    platform: "mac",
    family: "agent",
    status: "concept",
    swift: ["apps/macos/TalkieAgent/TalkieAgent/Views/Components/AgentMenuPopoverView.swift"],
    blurb: "Menu-bar pop-out reworked: NOW+INPUT collapse into one capture composer; recent + tools pick up scope language.",
  },
  {
    href: "/mac-agent-shell",
    label: "Agent Shell",
    bucket: "surfaces",
    platform: "mac",
    family: "agent",
    status: "concept",
    swift: [
      "apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeShellView.swift",
      "apps/macos/TalkieAgent/TalkieAgent/Views/Settings/SettingsView.swift",
    ],
    blurb: "Main rail simplified to a primary trio (Agents · History · Permissions) + “…” overflow + footer Settings; nicer section-picker header; Agents = status strip over assistant well.",
  },
  {
    href: "/mac-walkie",
    label: "Walkie",
    bucket: "surfaces",
    platform: "mac",
    family: "agent",
    status: "concept",
    blurb: "Hyper+T transmission loop — verbal ♪ / async ⟳ modes.",
  },

  // ── Surfaces · iPhone ───────────────────────────────────────────
  {
    href: "/home",
    label: "Home",
    bucket: "surfaces",
    platform: "iphone",
    family: "home",
    status: "shipped",
  },
  {
    href: "/library",
    label: "Library",
    bucket: "surfaces",
    platform: "iphone",
    family: "library",
    status: "shipped",
  },
  {
    href: "/ios-library-cta",
    label: "Library · CTA",
    bucket: "surfaces",
    platform: "iphone",
    family: "library",
    status: "concept",
    swift: ["apps/ios/Talkie iOS/Views/Next/LibraryNextView.swift"],
    blurb: "Contextual round CTA per tab (mic / keyboard / viewfinder) — Accent / Glass / Ring material variants.",
  },
  {
    href: "/compose",
    label: "Compose",
    bucket: "surfaces",
    platform: "iphone",
    family: "compose",
    status: "shipped",
  },
  {
    href: "/recording-sheet",
    label: "Recording",
    bucket: "surfaces",
    platform: "iphone",
    family: "recording",
    status: "shipped",
  },
  {
    href: "/ios-deck",
    label: "Deck",
    bucket: "surfaces",
    platform: "iphone",
    family: "deck",
    status: "shipped",
    swift: ["apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift"],
    blurb: "Command Deck mirror — cockpit chassis + 16-tile grid.",
  },
  {
    href: "/ios-deck-keypad",
    label: "Deck · Keypad",
    bucket: "surfaces",
    platform: "iphone",
    family: "deck",
    status: "concept",
    swift: ["apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift"],
    blurb: "Turn the floating 4×4 tiles into one physical keypad — 3 depth variants (faceplate / sunk pads / backlit).",
  },
  {
    href: "/ios-deck-keybed",
    label: "Deck · Key Bed",
    bucket: "surfaces",
    platform: "iphone",
    family: "deck",
    status: "concept",
    swift: ["apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift"],
    blurb: "Unify the floating control-strip keys into one recessed instrument — 3 depth variants (inset / routed / sunk).",
  },
  {
    href: "/ios-memo-connected",
    label: "Memo · Connected",
    bucket: "surfaces",
    platform: "iphone",
    family: "memo",
    status: "concept",
    swift: ["apps/ios/Talkie iOS/Views/Next/VoiceMemoDetailNext.swift"],
    blurb: "Memo detail IA rebuild — audio bound to the transcript, action wall collapsed to hero + rail.",
  },
  {
    href: "/agent-bay",
    label: "Agent Bay",
    bucket: "surfaces",
    platform: "iphone",
    family: "agent",
    status: "shipped",
  },
  {
    href: "/ask-ai",
    label: "Ask AI",
    bucket: "surfaces",
    platform: "iphone",
    family: "agent",
    status: "wip",
  },
  {
    href: "/read-aloud",
    label: "Read Aloud",
    bucket: "surfaces",
    platform: "iphone",
    family: "read",
    status: "wip",
  },
  {
    href: "/camera",
    label: "Camera",
    bucket: "surfaces",
    platform: "iphone",
    family: "capture",
    status: "wip",
  },
  {
    href: "/bridge-detail",
    label: "Bridge",
    bucket: "surfaces",
    platform: "iphone",
    family: "bridge",
    status: "wip",
  },
  {
    href: "/settings",
    label: "Settings",
    bucket: "surfaces",
    platform: "iphone",
    family: "settings",
    status: "wip",
  },
  {
    href: "/terminal",
    label: "Terminal",
    bucket: "surfaces",
    platform: "iphone",
    family: "terminal",
    status: "wip",
  },

  // ── Surfaces · Cross-platform ───────────────────────────────────
  {
    href: "/architecture",
    label: "Architecture",
    bucket: "surfaces",
    platform: "cross",
    family: "system",
    status: "shipped",
    blurb: "System map — services, surfaces, and their relations.",
  },
  {
    href: "/completion",
    label: "Completion",
    bucket: "surfaces",
    platform: "cross",
    family: "system",
    status: "concept",
    blurb: "Feature-completion roadmap.",
  },

  // ── Lab ─────────────────────────────────────────────────────────
  {
    href: "/eng",
    label: "Eng Docs",
    bucket: "lab",
    platform: "cross",
    status: "shipped",
    blurb: "TLK-NNN decision series — rendered from docs/specs/.",
  },
  {
    href: "/mac-audit",
    label: "Mac Audit",
    bucket: "lab",
    platform: "mac",
    status: "shipped",
    blurb: "Interactive worksheet — file-backed finding tracker.",
  },
  {
    href: "/mac-coverage",
    label: "Mac Coverage",
    bucket: "lab",
    platform: "mac",
    status: "shipped",
    blurb: "Per-surface ship status vs. studio canon.",
  },
  {
    href: "/parity",
    label: "Parity",
    bucket: "lab",
    platform: "cross",
    status: "shipped",
    blurb: "iOS Next ↔ donor parity tracker.",
  },
  {
    href: "/ios-settings",
    label: "iOS Settings",
    bucket: "lab",
    platform: "iphone",
    status: "shipped",
    swift: ["apps/ios/Talkie iOS/Views/Next/SettingsNext.swift"],
    blurb: "Flat extraction of every settings row — type, value, key, status.",
  },
];

/** Find the registry entry for a route. */
export function pageForPath(pathname: string | null): StudioPage | undefined {
  if (!pathname) return undefined;
  // Direct match first, then strip trailing index segments if needed.
  return STUDIO_PAGES.find((p) => p.href === pathname);
}

/** All pages in a bucket. */
export function pagesIn(bucket: StudioBucket): StudioPage[] {
  return STUDIO_PAGES.filter((p) => p.bucket === bucket);
}

/** Pages within a bucket grouped by platform; platforms appear in
 *  Mac → iPhone → Cross → System order regardless of registry order. */
export function pagesByPlatform(
  bucket: StudioBucket
): Array<{ platform: StudioPlatform; pages: StudioPage[] }> {
  const order: StudioPlatform[] = ["mac", "iphone", "cross", "system"];
  const byPlat = new Map<StudioPlatform, StudioPage[]>();
  for (const p of pagesIn(bucket)) {
    const plat = (p.platform ?? "system") as StudioPlatform;
    const list = byPlat.get(plat) ?? [];
    list.push(p);
    byPlat.set(plat, list);
  }
  return order
    .map((platform) => ({ platform, pages: byPlat.get(platform) ?? [] }))
    .filter((g) => g.pages.length > 0);
}

/** Family grouping inside a platform — primary first, variants nested.
 *  Lossy: we treat the first page added to a family as the primary, the
 *  rest as variants. Order in `STUDIO_PAGES` is the source of truth. */
export function familyGroups(pages: StudioPage[]): Array<{
  primary: StudioPage;
  variants: StudioPage[];
}> {
  const groups: Array<{ primary: StudioPage; variants: StudioPage[] }> = [];
  const byFamily = new Map<string, number>(); // family → index in groups
  for (const p of pages) {
    const fam = p.family ?? p.label;
    const existing = byFamily.get(fam);
    if (existing === undefined) {
      groups.push({ primary: p, variants: [] });
      byFamily.set(fam, groups.length - 1);
    } else {
      groups[existing].variants.push(p);
    }
  }
  return groups;
}

/** Human-readable platform label. */
export function platformLabel(platform: StudioPlatform): string {
  switch (platform) {
    case "mac":
      return "Mac";
    case "iphone":
      return "iPhone";
    case "cross":
      return "Cross-platform";
    case "system":
      return "System";
  }
}
