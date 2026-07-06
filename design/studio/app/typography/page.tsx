"use client";

import { StudioPage } from "@/components/StudioPage";

/**
 * Typography spec — current state.
 *
 * Snapshot of every `.font(...)` configuration used by the macOS
 * Capture HUD, Capture Bar, Tray Viewer, and Command Palette as of the
 * scan. Read from the Swift source, not invented. No proposals here —
 * this page exists to make drift visible.
 *
 * Linked donors:
 *   apps/macos/Talkie/Services/Capture/CaptureBarPanel.swift
 *   apps/macos/Talkie/Services/Capture/CaptureHUDPanel.swift
 *   apps/macos/Talkie/Services/Tray/TrayViewer.swift
 *   apps/macos/Talkie/Views/CommandPalette/CommandPaletteView.swift
 *
 * Rendered samples use Inter (SF Pro proxy) and JetBrains Mono (SF Mono
 * proxy) — studio's house fonts, declared in tailwind.config.ts.
 */

type Design = "default" | "monospaced" | "rounded";
type Weight =
  | "thin"
  | "light"
  | "regular"
  | "medium"
  | "semibold"
  | "bold";

interface TypeRow {
  /** Rendered text in the sample column. Keep it representative of usage. */
  sample: string;
  size: number;
  weight: Weight;
  design?: Design;
  /** Swift `.tracking(value)` in points. */
  tracking?: number;
  /** Whether the source applies `.textCase(.uppercase)`. */
  uppercase?: boolean;
  /** Where this token shows up in the UI. */
  usage: string;
}

interface Surface {
  name: string;
  file: string;
  blurb: string;
  rows: TypeRow[];
}

const SURFACES: Surface[] = [
  {
    name: "Command Palette",
    file: "Views/CommandPalette/CommandPaletteView.swift",
    blurb:
      "Quick-search overlay (⌘⇧K). Porcelain card, amber accents, two-line keyboard nav.",
    rows: [
      {
        sample: "· PALETTE · cmd ⇧ K",
        size: 9,
        weight: "semibold",
        design: "monospaced",
        tracking: 2.0,
        usage: "Chrome strip label",
      },
      {
        sample: "⌕",
        size: 18,
        weight: "medium",
        usage: "Search field magnifier icon",
      },
      {
        sample: "Search commands...",
        size: 18,
        weight: "regular",
        usage: "Search field input + prompt",
      },
      {
        sample: "×",
        size: 16,
        weight: "regular",
        usage: "Search clear button icon",
      },
      {
        sample: "NAVIGATION",
        size: 11,
        weight: "semibold",
        tracking: 0.6,
        uppercase: true,
        usage: "Section header",
      },
      {
        sample: "◎",
        size: 14,
        weight: "semibold",
        usage: "Row command icon",
      },
      {
        sample: "Go to Library",
        size: 13,
        weight: "regular",
        usage: "Row title — unselected",
      },
      {
        sample: "Go to Home",
        size: 13,
        weight: "semibold",
        usage: "Row title — selected",
      },
      {
        sample: "⌘L",
        size: 11,
        weight: "medium",
        design: "monospaced",
        usage: "Row keyboard shortcut chip",
      },
      {
        sample: "⌕",
        size: 36,
        weight: "light",
        usage: "Empty state icon",
      },
      {
        sample: "No commands found",
        size: 14,
        weight: "medium",
        usage: "Empty state title",
      },
      {
        sample: "↑↓",
        size: 10,
        weight: "semibold",
        design: "rounded",
        usage: "Footer key hint chip",
      },
      {
        sample: "navigate",
        size: 11,
        weight: "regular",
        usage: "Footer key hint label",
      },
      {
        sample: "⌘⇧K",
        size: 10,
        weight: "semibold",
        design: "monospaced",
        usage: "Footer brand chip",
      },
    ],
  },
  {
    name: "Capture HUD",
    file: "Services/Capture/CaptureHUDPanel.swift",
    blurb:
      "Top-center floating chord menu with Screenshot/Video mode tabs, A/S/D primary cells, and M/C/N/V/T extras. Themed by wallpaper luminance; all-uppercase eyebrows and monospaced key caps.",
    rows: [
      {
        sample: "SCREENSHOT",
        size: 9,
        weight: "semibold",
        tracking: 1.6,
        uppercase: true,
        usage: "Mode tab label",
      },
      {
        sample: "MODE",
        size: 8,
        weight: "semibold",
        tracking: 1.3,
        uppercase: true,
        usage: "Mode switch hint label",
      },
      {
        sample: "←",
        size: 9,
        weight: "bold",
        design: "monospaced",
        usage: "Small key cap (← → Esc ↵)",
      },
      {
        sample: "REGION",
        size: 9,
        weight: "medium",
        tracking: 1.2,
        uppercase: true,
        usage: "Primary cell label",
      },
      {
        sample: "A",
        size: 10,
        weight: "bold",
        design: "monospaced",
        usage: "Primary cell key chip",
      },
      {
        sample: "CANCEL",
        size: 9,
        weight: "medium",
        tracking: 0.9,
        uppercase: true,
        usage: "Keyboard legend label (Cancel · Start)",
      },
      {
        sample: "MARKUP",
        size: 8,
        weight: "medium",
        tracking: 0.7,
        uppercase: true,
        usage: "Extra cell label",
      },
      {
        sample: "3",
        size: 8,
        weight: "bold",
        design: "monospaced",
        usage: "Extra cell tray badge",
      },
    ],
  },
  {
    name: "Capture Bar (legacy LiquidGlass)",
    file: "Services/Capture/CaptureBarPanel.swift",
    blurb:
      "Older Hyper-chord bar — pill mode tabs, A/S/D chord keys with suffix labels, and M/C/N/V/T extras. Still in the codebase.",
    rows: [
      {
        sample: "◉",
        size: 10,
        weight: "medium",
        usage: "Mode tab icon (SF Symbol)",
      },
      {
        sample: "Screenshot",
        size: 11,
        weight: "semibold",
        usage: "Active mode tab label",
      },
      {
        sample: "Video",
        size: 11,
        weight: "medium",
        usage: "Inactive mode tab label",
      },
      {
        sample: "A",
        size: 12,
        weight: "bold",
        design: "monospaced",
        usage: "Chord key letter",
      },
      {
        sample: "rea",
        size: 12,
        weight: "medium",
        usage: "Chord key suffix label",
      },
      {
        sample: "M",
        size: 11,
        weight: "bold",
        design: "monospaced",
        usage: "Extra key letter (M / C / N / V / T)",
      },
      {
        sample: "✎",
        size: 9,
        weight: "regular",
        usage: "Extra key companion icon",
      },
      {
        sample: "3",
        size: 10,
        weight: "semibold",
        design: "rounded",
        usage: "Tray count badge",
      },
    ],
  },
  {
    name: "Tray Viewer",
    file: "Services/Tray/TrayViewer.swift",
    blurb:
      "Floating mini gallery (Hyper+W). Three view modes — gallery / list / carousel — plus per-item detail preview. Largest font surface in the audit.",
    rows: [
      {
        sample: "Tray",
        size: 13,
        weight: "semibold",
        usage: "Header title",
      },
      {
        sample: "2",
        size: 11,
        weight: "bold",
        design: "rounded",
        usage: "Pinned count badge",
      },
      {
        sample: "3 selected",
        size: 10,
        weight: "medium",
        design: "monospaced",
        usage: "Header selection overlay",
      },
      {
        sample: "3 selected",
        size: 11,
        weight: "medium",
        design: "monospaced",
        usage: "Bottom-bar selection label",
      },
      {
        sample: "2 screenshots",
        size: 10,
        weight: "medium",
        usage: "Bottom-bar selection action summary",
      },
      {
        sample: "Clear Selection",
        size: 11,
        weight: "regular",
        usage: "Bottom-bar clear link",
      },
      {
        sample: "Save as Note",
        size: 12,
        weight: "medium",
        usage: "Bottom-bar action button",
      },
      {
        sample: "No captures",
        size: 12,
        weight: "medium",
        usage: "Empty state title",
      },
      {
        sample: "Hyper+S to capture",
        size: 11,
        weight: "regular",
        design: "monospaced",
        usage: "Empty state hint",
      },
      {
        sample: "Slack",
        size: 10,
        weight: "regular",
        usage: "List / carousel row app name",
      },
      {
        sample: "1440×900",
        size: 9,
        weight: "regular",
        design: "monospaced",
        usage: "List row dimensions",
      },
      {
        sample: "0:24",
        size: 9,
        weight: "medium",
        design: "monospaced",
        usage: "List row clip duration",
      },
      {
        sample: "2m ago",
        size: 9,
        weight: "medium",
        usage: "List / carousel row time-ago",
      },
      {
        sample: "All",
        size: 11,
        weight: "medium",
        usage: "Detail preview back label",
      },
      {
        sample: "1440 × 900",
        size: 10,
        weight: "regular",
        design: "monospaced",
        usage: "Detail / carousel metadata dimensions",
      },
      {
        sample: "Region",
        size: 10,
        weight: "regular",
        usage: "Detail preview mode / metadata",
      },
      {
        sample: "Lorem ipsum dolor sit amet",
        size: 13,
        weight: "medium",
        design: "monospaced",
        usage: "Text selection body / preview body",
      },
      {
        sample: "SELECTION",
        size: 10,
        weight: "bold",
        design: "monospaced",
        usage: "Selection preview eyebrow",
      },
      {
        sample: "TXT",
        size: 7,
        weight: "bold",
        design: "monospaced",
        usage: "Thumbnail placeholder label",
      },
      {
        sample: "Lorem ipsu…",
        size: 8,
        weight: "medium",
        design: "monospaced",
        usage: "Thumbnail text preview snippet",
      },
    ],
  },
];

// ── Helpers ──────────────────────────────────────────────────────────

const WEIGHT_CLASS: Record<Weight, string> = {
  thin: "font-thin",
  light: "font-light",
  regular: "font-normal",
  medium: "font-medium",
  semibold: "font-semibold",
  bold: "font-bold",
};

const WEIGHT_NUMERIC: Record<Weight, number> = {
  thin: 100,
  light: 300,
  regular: 400,
  medium: 500,
  semibold: 600,
  bold: 700,
};

function familyClass(design: Design | undefined): string {
  if (design === "monospaced") return "font-mono";
  // SwiftUI's `.rounded` has no clean web proxy; fall through to sans
  // and flag in the meta cell rather than fake a face.
  return "font-sans";
}

function rowSummary(row: TypeRow): string {
  const parts: string[] = [`${row.size}`, row.weight];
  if (row.design && row.design !== "default") parts.push(row.design);
  if (typeof row.tracking === "number") parts.push(`tr ${row.tracking}`);
  if (row.uppercase) parts.push("UPPER");
  return parts.join(" · ");
}

// ── Page ─────────────────────────────────────────────────────────────

export default function TypographySpec() {
  const allRows = SURFACES.flatMap((s) => s.rows);
  const distinctSizes = Array.from(new Set(allRows.map((r) => r.size))).sort(
    (a, b) => a - b,
  );
  const monoCount = allRows.filter((r) => r.design === "monospaced").length;
  const uppercaseCount = allRows.filter((r) => r.uppercase).length;

  return (
    <StudioPage
      eyebrow="· Typography · Audit"
      title="macOS chrome — type spec"
      help="snapshot · capture HUD · capture bar · tray · palette"
    >
      <div className="mb-6 max-w-[760px] space-y-3 text-[13px] leading-relaxed text-studio-ink-faint">
        <p>
          Every <code className="font-mono text-[12px] text-studio-ink">.font(...)</code> configuration in
          use by the in-scope macOS surfaces, read straight from Swift. No
          proposals — drift first, then we talk scale.
        </p>
        <p>
          Samples are rendered with Inter (SF Pro Text proxy) and JetBrains Mono
          (SF Mono proxy). SwiftUI's <code className="font-mono text-[12px] text-studio-ink">.rounded</code>{" "}
          design has no clean web equivalent and falls through to sans here.
        </p>
      </div>

      <div className="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Distinct rows" value={allRows.length} />
        <Stat label="Unique sizes" value={distinctSizes.length} />
        <Stat label="Monospaced" value={monoCount} />
        <Stat label="Uppercase" value={uppercaseCount} />
      </div>

      <div className="mb-8 rounded-md border border-studio-edge bg-white/40 p-4">
        <div className="mb-2 text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          · Sizes in play (pt)
        </div>
        <div className="flex flex-wrap gap-1.5 font-mono text-[11px]">
          {distinctSizes.map((s) => (
            <span
              key={s}
              className="rounded-sm border border-studio-edge bg-studio-canvas px-1.5 py-0.5 text-studio-ink"
            >
              {s}
            </span>
          ))}
        </div>
      </div>

      <div className="space-y-10">
        {SURFACES.map((surface) => (
          <SurfaceBlock key={surface.name} surface={surface} />
        ))}
      </div>
    </StudioPage>
  );
}

// ── Subcomponents ────────────────────────────────────────────────────

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-md border border-studio-edge bg-white/40 p-3">
      <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        {label}
      </div>
      <div className="mt-1 font-display text-[24px] leading-none text-studio-ink">
        {value}
      </div>
    </div>
  );
}

function SurfaceBlock({ surface }: { surface: Surface }) {
  return (
    <section>
      <header className="mb-3 border-b border-studio-edge pb-2">
        <h2 className="m-0 font-display text-[20px] font-medium leading-tight text-studio-ink">
          {surface.name}
        </h2>
        <div className="mt-1 flex flex-wrap items-baseline gap-3">
          <code className="font-mono text-[10.5px] text-studio-ink-faint">
            {surface.file}
          </code>
          <span className="text-[11px] text-studio-ink-faint">
            {surface.rows.length} configs
          </span>
        </div>
        <p className="mt-2 max-w-[760px] text-[12px] leading-relaxed text-studio-ink-faint">
          {surface.blurb}
        </p>
      </header>

      <div className="overflow-hidden rounded-md border border-studio-edge">
        <table className="w-full border-collapse">
          <thead>
            <tr className="border-b border-studio-edge bg-studio-canvas-alt">
              <th className="w-[280px] px-3 py-2 text-left text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
                Sample
              </th>
              <th className="w-[180px] px-3 py-2 text-left text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
                Token
              </th>
              <th className="px-3 py-2 text-left text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
                Usage
              </th>
            </tr>
          </thead>
          <tbody>
            {surface.rows.map((row, idx) => (
              <TypeRowCell key={`${surface.name}-${idx}`} row={row} />
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function TypeRowCell({ row }: { row: TypeRow }) {
  const style: React.CSSProperties = {
    fontSize: `${row.size}px`,
    fontWeight: WEIGHT_NUMERIC[row.weight],
    lineHeight: 1.15,
  };
  if (typeof row.tracking === "number") {
    // Swift `.tracking()` is added per character in pts at the rendered
    // size — closest CSS analog is letter-spacing in px at that size.
    style.letterSpacing = `${row.tracking}px`;
  }
  if (row.uppercase) style.textTransform = "uppercase";

  return (
    <tr className="border-b border-studio-edge last:border-b-0">
      <td className="px-3 py-3 align-middle">
        <span
          className={`${familyClass(row.design)} ${WEIGHT_CLASS[row.weight]} text-studio-ink`}
          style={style}
        >
          {row.sample}
        </span>
      </td>
      <td className="px-3 py-3 align-middle">
        <code className="font-mono text-[10.5px] text-studio-ink">
          {rowSummary(row)}
        </code>
      </td>
      <td className="px-3 py-3 align-middle text-[12px] text-studio-ink-faint">
        {row.usage}
      </td>
    </tr>
  );
}
