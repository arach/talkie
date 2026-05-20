"use client";

/**
 * Architecture map — every routable surface in the Next shell,
 * grouped by domain, with inbound/outbound edge counts and orphan
 * flagging. v1: list-grid layout. v2 (codex-talkie-canvas) will
 * upgrade this to a canvas-based UX journey map with embedded mini
 * views and SVG connection lines.
 *
 * Source-of-truth derived from grepping AppShellRouter.shared.openX
 * call sites across apps/ios/Talkie iOS/Views/Next. Update when
 * surfaces or edges change.
 */

type Domain = "root" | "capture" | "output" | "connect" | "system" | "dev";

interface Surface {
  code: string;
  name: string;
  domain: Domain;
  /** Sources that open this surface. "—" means no Next-surface entry. */
  inbound: string[];
  /** Destinations this surface opens. */
  outbound: string[];
  orphan?: boolean;
  deprecated?: boolean;
  devOnly?: boolean;
  note?: string;
}

const SURFACES: Surface[] = [
  // ── Roots ───────────────────────────────────────────────
  {
    code: "S00",
    name: "Home",
    domain: "root",
    inbound: ["every back button", "voice cmd return"],
    outbound: ["Settings", "Library", "Compose", "CaptureDetail", "MemoDetail"],
  },
  {
    code: "S01",
    name: "Library",
    domain: "root",
    inbound: ["Home · ALL ›"],
    outbound: ["Compose", "CaptureDetail", "MemoDetail", "Home"],
  },
  {
    code: "S02",
    name: "Settings",
    domain: "root",
    inbound: ["Home · gear", "Chrome topTrailing", "Camera corner"],
    outbound: ["Home"],
  },
  {
    code: "S03",
    name: "Onboarding",
    domain: "root",
    inbound: ["App first-launch", "showOnboardingNotification"],
    outbound: ["Home"],
  },

  // ── Capture domain ──────────────────────────────────────
  {
    code: "S04",
    name: "Compose",
    domain: "capture",
    inbound: [
      "Home · Recent (typed)",
      "Home · PICK UP Continue",
      "Library · row (typed)",
      "CaptureDetail · Refine",
      "VoiceMemoDetail · Refine",
      "DictationHistory · entry",
    ],
    outbound: ["Home"],
  },
  {
    code: "S05",
    name: "Camera",
    domain: "capture",
    inbound: ["Chrome tray · Camera"],
    outbound: ["Home", "Settings", "CaptureDetail"],
  },
  {
    code: "S06",
    name: "Web Browser",
    domain: "capture",
    inbound: ["—"],
    outbound: ["Home", "CaptureDetail"],
    orphan: true,
    note: "Only reachable via --browser launch arg.",
  },
  {
    code: "S07",
    name: "Capture Detail",
    domain: "capture",
    inbound: [
      "Home · Recent (link/scan)",
      "Library · row (link/scan)",
      "Camera · post-capture",
      "WebBrowser · post-capture",
    ],
    outbound: ["Home", "Compose"],
  },
  {
    code: "S08",
    name: "Voice Memo Detail",
    domain: "capture",
    inbound: ["Home · Recent (dictation)", "Library · row (dictation)"],
    outbound: ["Home", "Compose"],
  },
  {
    code: "S09",
    name: "Dictation History",
    domain: "capture",
    inbound: ["—"],
    outbound: ["Home", "Compose"],
    orphan: true,
    note: "Only reachable via --dictations launch arg.",
  },

  // ── Output domain ───────────────────────────────────────
  {
    code: "S10",
    name: "Read Aloud",
    domain: "output",
    inbound: ["—"],
    outbound: ["Home"],
    orphan: true,
    note: "Just landed. Needs Listen buttons on detail surfaces.",
  },
  {
    code: "S11",
    name: "Ask AI",
    domain: "output",
    inbound: ["Chrome tray · Ask AI"],
    outbound: ["Home"],
  },

  // ── Connect domain ──────────────────────────────────────
  {
    code: "S12",
    name: "Connection Center",
    domain: "connect",
    inbound: ["BridgeDetail · close (back)"],
    outbound: ["Home", "BridgeDetail"],
    orphan: true,
    note: "Only forward-reachable via --connection. Settings doesn't link to it.",
  },
  {
    code: "S13",
    name: "Bridge Detail",
    domain: "connect",
    inbound: ["ConnectionCenter · Mac Bridge"],
    outbound: ["ConnectionCenter", "Terminal"],
  },
  {
    code: "S14",
    name: "Terminal",
    domain: "connect",
    inbound: ["BridgeDetail · Sessions"],
    outbound: ["Home"],
  },
  {
    code: "S15",
    name: "Sign In",
    domain: "connect",
    inbound: ["—"],
    outbound: ["Home"],
    orphan: true,
    note: "No Next surface opens it. Needs Settings CONNECT row.",
  },

  // ── System ─────────────────────────────────────────────
  {
    code: "S16",
    name: "Keyboard Activation",
    domain: "system",
    inbound: ["Chrome bottomTrailing · Keyboard"],
    outbound: ["Home"],
  },
  {
    code: "S17",
    name: "Appearance",
    domain: "system",
    inbound: ["—"],
    outbound: ["Home"],
    orphan: true,
    deprecated: true,
    note: "Replaced by Settings LOOK panel. Retire surface case + view.",
  },
  {
    code: "S18",
    name: "Dictation Overlay Demo",
    domain: "dev",
    inbound: ["launch arg only"],
    outbound: ["Home"],
    devOnly: true,
  },
];

const DOMAINS: { key: Domain; label: string }[] = [
  { key: "root", label: "ROOTS" },
  { key: "capture", label: "CAPTURE" },
  { key: "output", label: "OUTPUT" },
  { key: "connect", label: "CONNECT" },
  { key: "system", label: "SYSTEM" },
  { key: "dev", label: "DEV ONLY" },
];

const PROPOSED_WIRES = [
  {
    title: "Listen-anywhere",
    detail:
      "CaptureDetailNext · VoiceMemoDetailNext · AskAINext (post-response) → action chip → openReadAloud(). Closes S10's orphan status.",
  },
  {
    title: "Sign in from Settings",
    detail:
      "SettingsNext CONNECT panel → 'Sign in with Apple' row when account empty → openSignIn(). Closes S15's orphan status.",
  },
  {
    title: "Promote Web Browser to tray",
    detail:
      "ChromeOverlay tray → add 'Browse' slot (globe glyph) → openWebBrowser(). Tray becomes Browse · Camera · Mic · Ask AI · (Listen). Closes S06's orphan status.",
  },
  {
    title: "Connection Center as Settings link",
    detail:
      "SettingsNext CONNECT panel → 'View connections detail ›' row → openConnectionCenter(). Closes S12's forward-link gap.",
  },
  {
    title: "Dictation History in Library",
    detail:
      "LibraryNextView → add 'Dictations' filter tab → openDictationHistory(). Closes S09's orphan status.",
  },
  {
    title: "Retire Appearance",
    detail:
      "Delete AppearancePickerNext.swift + remove .appearance from Surface enum + drop openAppearance() + --appearance launch arg. Settings LOOK panel covers it.",
  },
];

const ORPHAN_TONE = "#d97757";

export function ArchitectureMap() {
  const orphanCount = SURFACES.filter((s) => s.orphan && !s.devOnly).length;

  return (
    <div className="flex flex-col gap-10">
      <div className="grid grid-cols-4 gap-4 border border-studio-edge rounded-md p-4">
        <Stat label="Surfaces" value={String(SURFACES.length)} />
        <Stat label="Domains" value={String(DOMAINS.length)} />
        <Stat label="Orphans" value={String(orphanCount)} warn />
        <Stat label="Proposed wires" value={String(PROPOSED_WIRES.length)} />
      </div>

      <div className="flex flex-col gap-10">
        {DOMAINS.map((domain) => {
          const surfaces = SURFACES.filter((s) => s.domain === domain.key);
          if (surfaces.length === 0) return null;
          return (
            <DomainSection key={domain.key} domain={domain} surfaces={surfaces} />
          );
        })}
      </div>

      <div className="flex flex-col gap-4">
        <Eyebrow label="PROPOSED WIRES" count={PROPOSED_WIRES.length} />
        <div className="grid grid-cols-2 gap-3">
          {PROPOSED_WIRES.map((wire) => (
            <WireCard key={wire.title} {...wire} />
          ))}
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        {label}
      </span>
      <span
        className="text-[26px] tabular-nums leading-none font-mono"
        style={{ color: warn ? ORPHAN_TONE : undefined }}
      >
        {value}
      </span>
    </div>
  );
}

function Eyebrow({ label, count }: { label: string; count?: number }) {
  return (
    <div className="flex items-baseline gap-3 pb-1.5 border-b border-studio-edge">
      <span className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        · {label}
      </span>
      {count !== undefined && (
        <span className="text-[10px] tabular-nums font-mono text-studio-ink-faint">
          {count}
        </span>
      )}
    </div>
  );
}

function DomainSection({
  domain,
  surfaces,
}: {
  domain: { label: string };
  surfaces: Surface[];
}) {
  return (
    <div className="flex flex-col gap-4">
      <Eyebrow label={domain.label} count={surfaces.length} />
      <div className="grid grid-cols-3 gap-3">
        {surfaces.map((surface) => (
          <SurfaceCard key={surface.code} surface={surface} />
        ))}
      </div>
    </div>
  );
}

function SurfaceCard({ surface }: { surface: Surface }) {
  const isOrphan = surface.orphan && !surface.devOnly;
  const borderStyle = isOrphan
    ? { borderColor: "rgba(217, 119, 87, 0.45)" }
    : undefined;
  return (
    <div
      className="flex flex-col gap-2 rounded-md border border-studio-edge p-3"
      style={{
        ...borderStyle,
        opacity: surface.deprecated ? 0.65 : 1,
      }}
    >
      <div className="flex items-baseline justify-between">
        <span
          className="text-[9px] font-semibold uppercase tracking-eyebrow font-mono"
          style={{ color: isOrphan ? ORPHAN_TONE : undefined }}
        >
          {surface.code}
        </span>
        <StatusPill surface={surface} />
      </div>

      <div className="text-[14px] font-medium leading-tight text-studio-ink">
        {surface.name}
      </div>

      <div className="flex flex-col gap-1.5 pt-1">
        <EdgeRow
          arrow="←"
          items={surface.inbound}
          orphan={isOrphan && surface.inbound[0] === "—"}
        />
        <EdgeRow arrow="→" items={surface.outbound} />
      </div>

      {surface.note && (
        <div className="mt-2 text-[10px] leading-snug text-studio-ink-faint">
          {surface.note}
        </div>
      )}
    </div>
  );
}

function StatusPill({ surface }: { surface: Surface }) {
  if (surface.devOnly) return <Pill label="DEV" color="var(--studio-ink-faint, #888)" />;
  if (surface.deprecated) return <Pill label="DEPRECATED" color="var(--studio-ink-faint, #888)" />;
  if (surface.orphan) return <Pill label="ORPHAN" color={ORPHAN_TONE} />;
  return null;
}

function Pill({ label, color }: { label: string; color: string }) {
  return (
    <span
      className="rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono"
      style={{ color, border: `1px solid ${color}` }}
    >
      {label}
    </span>
  );
}

function EdgeRow({
  arrow,
  items,
  orphan = false,
}: {
  arrow: string;
  items: string[];
  orphan?: boolean;
}) {
  const count = items.length === 1 && items[0] === "—" ? 0 : items.length;
  return (
    <div className="flex items-start gap-2">
      <span
        className="text-[10px] tabular-nums font-mono"
        style={{
          color: orphan ? ORPHAN_TONE : undefined,
          minWidth: 22,
        }}
      >
        {arrow} {count}
      </span>
      <span
        className="text-[10px] leading-snug text-studio-ink-faint"
        style={{ color: orphan ? ORPHAN_TONE : undefined }}
      >
        {items.join(" · ")}
      </span>
    </div>
  );
}

function WireCard({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-studio-edge p-3">
      <div className="text-[13px] font-medium text-studio-ink">{title}</div>
      <div className="text-[11px] leading-snug text-studio-ink-faint">{detail}</div>
    </div>
  );
}
