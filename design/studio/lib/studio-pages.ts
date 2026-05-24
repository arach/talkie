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
    href: "/mac-notch-settings",
    label: "Notch Settings",
    bucket: "surfaces",
    platform: "mac",
    family: "chrome",
    status: "wip",
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
