"use client";

/**
 * Mac Bridge — replaces the legacy BridgeSettingsView sheet. Live
 * status, link-health metric strip, nearby pairing, saved sessions,
 * actions. Same row chrome vocabulary as SettingsNext Inspector:
 * 44pt rows, full-width hairlines, channel-label section heads.
 */

import { StatusBar } from "./primitives/StatusBar";

export type BridgeVariant = "paired" | "unpaired";

export const BRIDGE_VARIANTS: { key: BridgeVariant; label: string }[] = [
  { key: "paired", label: "Paired" },
  { key: "unpaired", label: "Unpaired" },
];

export function BridgeDetailStudy({ variant }: { variant: BridgeVariant }) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header />
      <Divider />
      <div className="flex-1 overflow-auto px-4 pt-2 pb-20">
        <PanelEyebrow text={`INSPECTOR · STATUS`} />
        {variant === "paired" ? <PairedSections /> : <UnpairedSections />}
      </div>
    </div>
  );
}

function Header() {
  return (
    <div className="flex items-center justify-between px-5 pt-3 pb-2.5">
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.28em",
        }}
      >
        TALKIE · MAC BRIDGE
      </span>
      <CloseButton />
    </div>
  );
}

function Divider() {
  return (
    <div
      className="h-px w-full"
      style={{ background: "var(--theme-edge-faint)" }}
    />
  );
}

function CloseButton() {
  return (
    <button
      aria-label="Close"
      className="flex h-7 w-7 items-center justify-center rounded-full"
      style={{
        background: "var(--theme-edge-faint)",
        color: "var(--theme-ink-faint)",
      }}
    >
      <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none">
        <path
          d="M2 2 L 10 10 M 10 2 L 2 10"
          stroke="currentColor"
          strokeWidth={1.2}
          strokeLinecap="round"
        />
      </svg>
    </button>
  );
}

function PanelEyebrow({ text }: { text: string }) {
  return (
    <div className="pt-3 pb-2">
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        {text}
      </span>
    </div>
  );
}

function SectionHeader({ text }: { text: string }) {
  return (
    <div
      className="flex items-center pt-4 pb-1.5"
      style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        {text}
      </span>
    </div>
  );
}

function Row({
  label,
  hint,
  value,
  valueColor = "var(--theme-amber)",
  divider = true,
}: {
  label: string;
  hint?: string;
  value: string;
  valueColor?: string;
  divider?: boolean;
}) {
  return (
    <div
      className="flex items-baseline gap-2"
      style={{
        height: 44,
        borderBottom: divider ? "0.5px solid var(--theme-edge-faint)" : "none",
      }}
    >
      <span
        className="text-[12px]"
        style={{ color: "var(--theme-ink)" }}
      >
        {label}
      </span>
      {hint && (
        <span
          className="truncate text-[10px] font-light"
          style={{ color: "var(--theme-ink-faint)" }}
        >
          · {hint}
        </span>
      )}
      <div className="flex-1" />
      <span
        className="text-[12px] tabular-nums"
        style={{ color: valueColor, fontFamily: "var(--theme-font-mono)" }}
      >
        {value}
      </span>
    </div>
  );
}

function ActionRow({
  label,
  tone = "neutral",
  divider = true,
}: {
  label: string;
  tone?: "neutral" | "accent" | "warn";
  divider?: boolean;
}) {
  const color =
    tone === "warn"
      ? "#d97757"
      : tone === "accent"
        ? "var(--theme-amber)"
        : "var(--theme-ink-faint)";
  return (
    <div
      className="flex items-center"
      style={{
        height: 44,
        borderBottom: divider ? "0.5px solid var(--theme-edge-faint)" : "none",
      }}
    >
      <span className="text-[12px]" style={{ color: "var(--theme-ink)" }}>
        {label}
      </span>
      <div className="flex-1" />
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color,
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.20em",
        }}
      >
        RUN
      </span>
    </div>
  );
}

function MetricStrip() {
  const cells = [
    { label: "RTT", value: "12ms" },
    { label: "SENT", value: "4.2k" },
    { label: "QUEUED", value: "0" },
  ];
  return (
    <div
      className="flex"
      style={{
        borderTop: "0.5px solid var(--theme-edge-faint)",
        borderBottom: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      {cells.map((c, i) => (
        <div
          key={c.label}
          className="flex flex-1 flex-col items-center justify-center gap-1 py-3"
          style={{
            borderRight:
              i < cells.length - 1
                ? "0.5px solid var(--theme-edge-faint)"
                : "none",
          }}
        >
          <span
            className="text-[9px] font-medium uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.22em",
            }}
          >
            {c.label}
          </span>
          <span
            className="text-[15px] tabular-nums"
            style={{ color: "var(--theme-ink)", fontFamily: "var(--theme-font-mono)" }}
          >
            {c.value}
          </span>
        </div>
      ))}
    </div>
  );
}

function PairedSections() {
  return (
    <>
      <Row label="Status" value="Paired · Mini" />
      <Row label="Host" hint="art@mini.local · 192.168.1.42" value="local" />
      <Row label="Last sync" value="2 min ago" />

      <div className="mt-1">
        <SectionHeader text="LINK HEALTH" />
        <MetricStrip />
      </div>

      <SectionHeader text="SESSIONS" />
      <Row label="Mini · workshop" hint="active" value="Open ›" valueColor="var(--theme-amber)" />
      <Row label="studio.tail.ts.net" hint="2 days ago" value="Open ›" valueColor="var(--theme-amber)" />

      <SectionHeader text="ACTIONS" />
      <ActionRow label="Re-pair Mac" tone="neutral" />
      <ActionRow label="Forget pair" tone="warn" divider={false} />
    </>
  );
}

function UnpairedSections() {
  return (
    <>
      <Row label="Status" value="Not paired" valueColor="var(--theme-ink-faint)" />

      <div className="flex flex-col items-center gap-3 px-4 py-8">
        <svg viewBox="0 0 16 16" className="h-10 w-10" fill="none" style={{ color: "var(--theme-ink-faint)" }}>
          <rect x={2.5} y={3.5} width={11} height={8} rx={1} stroke="currentColor" strokeWidth={1} />
          <path d="M 5 6.5 L 5 8.5 M 11 6.5 L 11 8.5" stroke="currentColor" strokeWidth={1} strokeLinecap="round" />
        </svg>
        <div className="text-[15px] font-light" style={{ color: "var(--theme-ink)" }}>
          No Mac paired yet
        </div>
        <div className="max-w-[20ch] text-center text-[11px]" style={{ color: "var(--theme-ink-faint)" }}>
          Open Talkie on your Mac, then scan the QR.
        </div>
        <button
          className="mt-2 rounded-full px-4 py-2 text-[10px] font-medium uppercase"
          style={{
            background: "var(--theme-amber)",
            color: "var(--theme-paper)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.22em",
          }}
        >
          Scan QR ›
        </button>
      </div>
    </>
  );
}
