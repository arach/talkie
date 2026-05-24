"use client";

import { useMemo, useState } from "react";
import type {
  SettingsPanel,
  SettingsRow,
  SettingsRowType,
  SettingsStatus,
} from "@/lib/ios-settings";

const PANEL_ORDER: SettingsPanel[] = [
  "voice",
  "look",
  "connect",
  "keys",
  "lab",
  "about",
];

const PANEL_LABEL: Record<SettingsPanel, string> = {
  voice: "Voice",
  look: "Look",
  connect: "Connect",
  keys: "Keys",
  lab: "Lab",
  about: "About",
};

const TYPE_LABEL: Record<SettingsRowType, string> = {
  field: "field",
  cycle: "cycle",
  toggle: "toggle",
  text: "text",
  metric: "metric",
  install: "install",
  action: "action",
  nav: "nav",
  swatch: "swatch",
};

const STATUS_PALETTE: Record<
  SettingsStatus,
  { fg: string; bg: string; label: string }
> = {
  wired: { fg: "#1F5A2E", bg: "#E2F0E5", label: "WIRED" },
  computed: { fg: "#7A4A0E", bg: "#F5E6CC", label: "COMPUTED" },
  conditional: { fg: "#8A4B17", bg: "#F4DEC2", label: "COND" },
  todo: { fg: "#8A3030", bg: "#F0DCDC", label: "TODO" },
  debug: { fg: "#5A554C", bg: "#ECECEB", label: "DEBUG" },
};

export function IOSSettingsTable({ rows }: { rows: SettingsRow[] }) {
  const [activePanel, setActivePanel] = useState<SettingsPanel | "all">("all");
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((r) => {
      if (activePanel !== "all" && r.panel !== activePanel) return false;
      if (!q) return true;
      const hay = [
        r.label,
        r.value ?? "",
        r.hint ?? "",
        r.setting ?? "",
        r.section ?? "",
        r.note ?? "",
      ]
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [rows, activePanel, query]);

  // Per-panel counts for the chip bar (uses the unfiltered list so chip
  // numbers stay stable as the user filters by text).
  const panelCounts = useMemo(() => {
    const counts: Record<SettingsPanel | "all", number> = {
      all: rows.length,
      voice: 0,
      look: 0,
      connect: 0,
      keys: 0,
      lab: 0,
      about: 0,
    };
    for (const r of rows) counts[r.panel]++;
    return counts;
  }, [rows]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <PanelChip
          active={activePanel === "all"}
          onClick={() => setActivePanel("all")}
          label="All"
          count={panelCounts.all}
        />
        {PANEL_ORDER.map((p) => (
          <PanelChip
            key={p}
            active={activePanel === p}
            onClick={() => setActivePanel(p)}
            label={PANEL_LABEL[p]}
            count={panelCounts[p]}
          />
        ))}
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Filter labels, settings keys, hints…"
          className="ml-auto w-full max-w-sm rounded border border-studio-edge bg-studio-canvas px-3 py-1.5 text-[12.5px] text-studio-ink placeholder:text-studio-ink-faint/60 focus:border-studio-edge-strong focus:outline-none"
        />
      </div>

      <div className="overflow-hidden rounded border border-studio-edge bg-studio-canvas/95">
        <table className="w-full border-collapse text-left">
          <thead>
            <tr className="border-b border-studio-edge bg-studio-canvas-warm/60">
              <Th>Panel</Th>
              <Th>Section</Th>
              <Th>Type</Th>
              <Th>Label</Th>
              <Th>Value</Th>
              <Th>Setting key</Th>
              <Th>Status</Th>
              <Th className="text-right">Line</Th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r, i) => (
              <tr
                key={`${r.panel}-${r.label}-${r.line}-${i}`}
                className="border-b border-studio-edge/60 last:border-b-0 hover:bg-studio-canvas-warm/40"
              >
                <Td>
                  <span className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint/80">
                    {PANEL_LABEL[r.panel]}
                  </span>
                </Td>
                <Td>
                  {r.section ? (
                    <span className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint/80">
                      {r.section}
                    </span>
                  ) : (
                    <span className="text-studio-ink-faint/40">—</span>
                  )}
                </Td>
                <Td>
                  <span className="font-mono text-[11px] text-studio-ink/80">
                    {TYPE_LABEL[r.type]}
                  </span>
                </Td>
                <Td>
                  <div className="font-medium text-studio-ink">{r.label}</div>
                  {r.hint && (
                    <div className="mt-0.5 text-[11px] text-studio-ink-faint/75">
                      {r.hint}
                    </div>
                  )}
                  {r.note && (
                    <div className="mt-1 text-[11px] italic text-studio-ink-faint/65">
                      {r.note}
                    </div>
                  )}
                </Td>
                <Td>
                  {r.value === null ? (
                    <span className="text-studio-ink-faint/40">—</span>
                  ) : (
                    <code className="font-mono text-[11.5px] text-studio-ink/90">
                      {r.value}
                    </code>
                  )}
                </Td>
                <Td>
                  {r.setting ? (
                    <code className="font-mono text-[11px] text-studio-ink/80">
                      {r.setting}
                    </code>
                  ) : (
                    <span className="text-studio-ink-faint/40">—</span>
                  )}
                </Td>
                <Td>
                  <StatusPill status={r.status} />
                </Td>
                <Td className="text-right">
                  <code className="font-mono text-[11px] text-studio-ink-faint/70">
                    {r.line}
                  </code>
                </Td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td
                  colSpan={8}
                  className="px-4 py-10 text-center text-[12px] text-studio-ink-faint/60"
                >
                  No rows match.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function PanelChip({
  active,
  onClick,
  label,
  count,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  count: number;
}) {
  return (
    <button
      onClick={onClick}
      className={
        "rounded-[3px] border px-2.5 py-1 font-mono text-[10.5px] font-semibold uppercase tracking-eyebrow transition-colors " +
        (active
          ? "border-studio-edge-strong bg-studio-ink text-studio-canvas"
          : "border-studio-edge bg-studio-canvas text-studio-ink-faint/85 hover:bg-studio-canvas-warm/60")
      }
    >
      {label} <span className="opacity-60">· {count}</span>
    </button>
  );
}

function StatusPill({ status }: { status: SettingsStatus }) {
  const tone = STATUS_PALETTE[status];
  return (
    <span
      className="inline-block rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold tracking-[0.18em]"
      style={{ color: tone.fg, background: tone.bg }}
    >
      {tone.label}
    </span>
  );
}

function Th({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <th
      className={
        "px-3 py-2 font-mono text-[9.5px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint/80 " +
        (className ?? "")
      }
    >
      {children}
    </th>
  );
}

function Td({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <td className={"px-3 py-2.5 align-top text-[12.5px] " + (className ?? "")}>
      {children}
    </td>
  );
}
