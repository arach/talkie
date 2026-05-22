"use client";

/**
 * Settings — fresh exploration. Three directional sketches for what
 * Talkie's Settings surface could become now that the legacy
 * SettingsView is gone. Each variant renders the SAME information
 * domain but with a different organizing pattern.
 *
 * Domains shown across all variants (real Talkie capabilities):
 *  - Voice / engine — transcription model, input device
 *  - Look — theme, density
 *  - Connect — iCloud sync, Mac Bridge, account
 *  - Keyboard — dictation engine, formatting
 *  - Lab — reset onboarding / auth / tooltip, log viewer (debug)
 *  - About — version, build
 *
 * Theme-aware via `--theme-*` CSS vars.
 */

import { useState } from "react";
import { StatusBar } from "./primitives/StatusBar";

export type SettingsVariant = "console" | "stations" | "inspector";

export const SETTINGS_VARIANTS: {
  key: SettingsVariant;
  label: string;
}[] = [
  { key: "console", label: "Console" },
  { key: "stations", label: "Stations" },
  { key: "inspector", label: "Inspector" },
];

// ─────────────────────────────────────────────────────────────
// Console — section-treatment sub-variants
// ─────────────────────────────────────────────────────────────

export type ConsoleSection = "hairline" | "eyebrow" | "side";

export const CONSOLE_SECTIONS: {
  key: ConsoleSection;
  label: string;
}[] = [
  { key: "hairline", label: "Hairline" },
  { key: "eyebrow", label: "Eyebrow code" },
  { key: "side", label: "Side label" },
];

// ─────────────────────────────────────────────────────────────

export function Settings({
  variant,
  consoleSection = "hairline",
}: {
  variant: SettingsVariant;
  consoleSection?: ConsoleSection;
}) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header variant={variant} consoleSection={consoleSection} />
      <div className="flex-1 overflow-hidden">
        {variant === "console" && <ConsoleVariant treatment={consoleSection} />}
        {variant === "stations" && <StationsVariant />}
        {variant === "inspector" && <InspectorVariant />}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Header — shared chrome
// ─────────────────────────────────────────────────────────────

function Header({
  variant,
  consoleSection,
}: {
  variant: SettingsVariant;
  consoleSection: ConsoleSection;
}) {
  return (
    <div className="px-5 pt-4 pb-3 flex items-center justify-between">
      <div className="text-[10px] font-mono tracking-[0.32em] uppercase opacity-70">
        TALKIE · SETTINGS
      </div>
      <div className="text-[9px] font-mono tracking-[0.22em] uppercase opacity-50">
        {variant === "console" && `CONSOLE · ${consoleSection.toUpperCase()}`}
        {variant === "stations" && "STATIONS · 6"}
        {variant === "inspector" && "INSPECTOR"}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// VARIANT 1 — Console (3 section treatments)
// ─────────────────────────────────────────────────────────────

const CONSOLE_SECTIONS_DATA: Array<{
  code: string;
  name: string;
  rows: Array<{
    k: string;
    v: string;
    status?: "ok" | "warn";
    pill?: boolean;
    action?: boolean;
  }>;
}> = [
  {
    code: "C01",
    name: "VOICE",
    rows: [
      { k: "Engine", v: "Parakeet 0.4" },
      { k: "Input", v: "Built-in mic" },
      { k: "Sample rate", v: "48 kHz" },
    ],
  },
  {
    code: "C02",
    name: "LOOK",
    rows: [
      { k: "Theme", v: "Tactical", pill: true },
      { k: "Density", v: "Standard" },
    ],
  },
  {
    code: "C03",
    name: "CONNECT",
    rows: [
      { k: "iCloud sync", v: "On", status: "ok" },
      { k: "Mac Bridge", v: "Paired · Mini", status: "ok" },
      { k: "Account", v: "art@…" },
    ],
  },
  {
    code: "C04",
    name: "KEYBOARD",
    rows: [
      { k: "Dictation engine", v: "On-device" },
      { k: "Auto-format", v: "Smart" },
      { k: "Punctuation", v: "Inferred" },
    ],
  },
  {
    code: "C05",
    name: "LAB",
    rows: [
      { k: "Reset onboarding", v: "—", action: true },
      { k: "Reset auth", v: "—", action: true },
      { k: "Log viewer", v: "OPEN", action: true },
    ],
  },
  {
    code: "C06",
    name: "ABOUT",
    rows: [{ k: "Version", v: "0.13.6 (442)" }],
  },
];

function ConsoleVariant({ treatment }: { treatment: ConsoleSection }) {
  return (
    <div className="h-full overflow-auto px-5 pt-2 pb-24">
      {CONSOLE_SECTIONS_DATA.map((s) => (
        <ConsoleSectionBlock key={s.code} section={s} treatment={treatment} />
      ))}
    </div>
  );
}

function ConsoleSectionBlock({
  section,
  treatment,
}: {
  section: (typeof CONSOLE_SECTIONS_DATA)[number];
  treatment: ConsoleSection;
}) {
  if (treatment === "hairline") {
    return (
      <div className="mb-4">
        <div
          className="text-[9px] font-mono tracking-[0.22em] uppercase mb-1.5 pb-1.5 border-b"
          style={{ borderColor: "var(--theme-edge-faint)", opacity: 0.7 }}
        >
          {section.code} · {section.name}
        </div>
        <div>
          {section.rows.map((r) => (
            <Row key={r.k} {...r} />
          ))}
        </div>
      </div>
    );
  }

  if (treatment === "eyebrow") {
    return (
      <div className="mb-5">
        <div className="flex items-baseline gap-2 mb-2">
          <span
            className="text-[8px] font-mono tracking-[0.32em] uppercase"
            style={{ color: "var(--theme-amber)" }}
          >
            {section.code}
          </span>
          <span
            className="text-[15px] font-medium"
            style={{ color: "var(--theme-ink)" }}
          >
            {section.name.charAt(0) + section.name.slice(1).toLowerCase()}
          </span>
        </div>
        <div>
          {section.rows.map((r) => (
            <Row key={r.k} {...r} />
          ))}
        </div>
      </div>
    );
  }

  // side label — rotated vertical type. Code stays horizontal at the
  // top of the rail as the anchor; section name runs 90° down the
  // rail along the rows. Reads like a radio band / hardware fader.
  return (
    <div className="mb-4 flex gap-3">
      <div
        className="flex-shrink-0 flex flex-col items-center pt-2 pb-1 w-7"
        style={{ borderRight: "1px solid var(--theme-edge-faint)" }}
      >
        <div
          className="text-[8px] font-mono tracking-[0.22em] uppercase"
          style={{ color: "var(--theme-amber)" }}
        >
          {section.code}
        </div>
        <div
          className="mt-2 text-[9px] font-mono tracking-[0.32em] uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            writingMode: "vertical-rl",
            transform: "rotate(180deg)",
          }}
        >
          {section.name}
        </div>
      </div>
      <div className="flex-1">
        {section.rows.map((r) => (
          <Row key={r.k} {...r} />
        ))}
      </div>
    </div>
  );
}

function Row({
  k,
  v,
  status,
  pill,
  action,
}: {
  k: string;
  v: string;
  status?: "ok" | "warn";
  pill?: boolean;
  action?: boolean;
}) {
  return (
    <div
      className="flex items-center justify-between py-2 border-b"
      style={{ borderColor: "var(--theme-edge-faint)" }}
    >
      <div className="text-[13px]" style={{ color: "var(--theme-ink)" }}>
        {k}
      </div>
      <div className="flex items-center gap-2">
        {status === "ok" && (
          <span
            className="inline-block w-1.5 h-1.5 rounded-full"
            style={{ background: "var(--theme-amber)" }}
          />
        )}
        {pill ? (
          <span
            className="text-[10px] font-mono tracking-[0.18em] uppercase px-2 py-0.5 rounded"
            style={{
              border: "1px solid var(--theme-edge-faint)",
              color: "var(--theme-ink)",
            }}
          >
            {v}
          </span>
        ) : (
          <span
            className={`text-[12px] ${
              action ? "font-mono tracking-[0.18em] uppercase" : ""
            }`}
            style={{
              color: action ? "var(--theme-amber)" : "var(--theme-ink-faint)",
            }}
          >
            {v}
          </span>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// VARIANT 2 — Stations
// ─────────────────────────────────────────────────────────────

function StationsVariant() {
  const stations: Array<{
    code: string;
    name: string;
    preview: string;
    accent?: boolean;
  }> = [
    { code: "ST · 01", name: "Voice", preview: "Parakeet 0.4", accent: true },
    { code: "ST · 02", name: "Look", preview: "Tactical · standard" },
    { code: "ST · 03", name: "Connect", preview: "iCloud + Mini" },
    { code: "ST · 04", name: "Keyboard", preview: "On-device · smart" },
    { code: "ST · 05", name: "Lab", preview: "Resets · logs" },
    { code: "ST · 06", name: "About", preview: "0.13.6 (442)" },
  ];

  return (
    <div className="h-full overflow-auto px-4 pt-2 pb-24">
      <div className="grid grid-cols-2 gap-3">
        {stations.map((s) => (
          <Station key={s.code} {...s} />
        ))}
      </div>
    </div>
  );
}

function Station({
  code,
  name,
  preview,
  accent,
}: {
  code: string;
  name: string;
  preview: string;
  accent?: boolean;
}) {
  return (
    <div
      className="flex flex-col justify-between rounded-md p-3 aspect-[4/3]"
      style={{
        background: "var(--theme-paper)",
        border: "1px solid var(--theme-edge-faint)",
      }}
    >
      <div
        className="text-[8px] font-mono tracking-[0.22em] uppercase"
        style={{ color: accent ? "var(--theme-amber)" : "var(--theme-ink-faint)" }}
      >
        {code}
      </div>
      <div>
        <div
          className="text-[18px] font-medium leading-tight"
          style={{ color: "var(--theme-ink)" }}
        >
          {name}
        </div>
        <div
          className="text-[11px] mt-1"
          style={{ color: "var(--theme-ink-faint)" }}
        >
          {preview}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// VARIANT 3 — Inspector (grown: clickable chips, 5 real panels)
// ─────────────────────────────────────────────────────────────

type InspectorChip = "VOICE" | "LOOK" | "CONNECT" | "KEYS" | "LAB" | "ABOUT";

function InspectorVariant() {
  const [active, setActive] = useState<InspectorChip>("VOICE");
  const chips: InspectorChip[] = [
    "VOICE",
    "LOOK",
    "CONNECT",
    "KEYS",
    "LAB",
    "ABOUT",
  ];

  return (
    <div className="flex h-full">
      {/* Left rail — rotated chip labels. Matches Console "side label" */}
      <div
        className="flex flex-col flex-shrink-0 w-9"
        style={{ borderRight: "1px solid var(--theme-edge-faint)" }}
      >
        {chips.map((c, i) => {
          const isActive = c === active;
          return (
            <button
              key={c}
              onClick={() => setActive(c)}
              className="flex-1 flex items-center justify-center"
              style={{
                background: isActive ? "var(--theme-ink)" : "transparent",
                borderBottom:
                  i < chips.length - 1
                    ? "1px solid var(--theme-edge-faint)"
                    : "none",
              }}
            >
              <span
                className="text-[9px] font-mono tracking-[0.32em] uppercase"
                style={{
                  color: isActive
                    ? "var(--theme-amber)"
                    : "var(--theme-ink-faint)",
                  writingMode: "vertical-rl",
                  transform: "rotate(180deg)",
                }}
              >
                {c}
              </span>
            </button>
          );
        })}
      </div>

      {/* Right panel — active section's content */}
      <div className="flex-1 overflow-auto px-4 pt-3 pb-24">
        <div
          className="text-[10px] font-mono tracking-[0.22em] uppercase mb-2"
          style={{ color: "var(--theme-ink-faint)" }}
        >
          INSPECTOR · {active}
        </div>

        {active === "VOICE" && <VoicePanel />}
        {active === "LOOK" && <LookPanel />}
        {active === "CONNECT" && <ConnectPanel />}
        {active === "KEYS" && <KeysPanel />}
        {active === "LAB" && <LabPanel />}
        {active === "ABOUT" && <AboutPanel />}
      </div>
    </div>
  );
}

// — Inspector panels —

function VoicePanel() {
  return (
    <>
      <Field label="Engine" value="Parakeet 0.4" hint="On-device · 392 MB" />
      <Field label="Input device" value="Built-in mic" />
      <Field label="Sample rate" value="48 kHz" />
      <Field label="Channels" value="Mono" />
      <Field label="Gain" value="+3 dB" hint="Auto-leveled when low" />
      <Field label="Pre-roll" value="200 ms" />
      <Field label="Noise gate" value="Soft" />
      <MetricStrip
        title="ENGINE TELEMETRY"
        metrics={[
          { label: "LATENCY", value: "180ms" },
          { label: "WER", value: "3.2%" },
          { label: "LOADED", value: "12s" },
        ]}
      />
    </>
  );
}

function LookPanel() {
  return (
    <>
      <Field label="Theme" value="Tactical" hint="Gunmetal + orange chrome" />
      <Field label="Density" value="Standard" />
      <Field label="Accent intensity" value="0.85" />
      <Field label="Wordmark style" value="Mono" />
      <Field label="Reduce motion" value="System" />
      <div
        className="mt-4 pt-3 border-t flex gap-2"
        style={{ borderColor: "var(--theme-edge-faint)" }}
      >
        {["scope", "midnight", "tactical", "ghost", "lift"].map((t) => (
          <div
            key={t}
            className="flex-1 aspect-square rounded"
            style={{
              background:
                t === "tactical"
                  ? "var(--theme-amber)"
                  : "var(--theme-paper)",
              border: "1px solid var(--theme-edge-faint)",
            }}
            title={t}
          />
        ))}
      </div>
    </>
  );
}

function ConnectPanel() {
  return (
    <>
      <Field label="iCloud sync" value="On" hint="Last sync 2 min ago" />
      <Field label="Mac Bridge" value="Paired · Mini" hint="art@mini.local · 192.168.1.42" />
      <Field label="Account" value="art@…" hint="Sign in with Apple" />
      <MetricStrip
        title="LINK HEALTH"
        metrics={[
          { label: "RTT", value: "12ms" },
          { label: "SENT", value: "4.2k" },
          { label: "QUEUED", value: "0" },
        ]}
      />
      <ActionRow label="Re-pair Mac" />
      <ActionRow label="Sign out" tone="warn" />
    </>
  );
}

function KeysPanel() {
  return (
    <>
      <Field label="Dictation engine" value="On-device" />
      <Field label="Auto-format" value="Smart" hint="Sentences + lists" />
      <Field label="Punctuation" value="Inferred" />
      <Field label="Auto-capitalize" value="On" />
      <Field label="Trailing space" value="Smart" />
      <Field label="Voice activation" value="Long-press" />
      <Field label="Haptic feedback" value="Soft" />
    </>
  );
}

function LabPanel() {
  return (
    <>
      <div
        className="text-[10px] mb-3"
        style={{ color: "var(--theme-ink-faint)" }}
      >
        Debug-only. These won't ship in release builds.
      </div>
      <ActionRow label="Reset onboarding" />
      <ActionRow label="Reset auth state" />
      <ActionRow label="Reset resume tooltip" />
      <ActionRow label="Open log viewer" tone="accent" />
      <ActionRow label="Dump shared store" />
      <ActionRow label="Force iCloud refresh" />
    </>
  );
}

function AboutPanel() {
  return (
    <>
      <Field label="Version" value="0.13.6" />
      <Field label="Build" value="442" />
      <Field label="Channel" value="Debug" />
      <Field label="Engine bundle" value="parakeet-0.4-en" />
      <Field label="Mac bridge protocol" value="v2.1" />
    </>
  );
}

// — Inspector primitives —

function Field({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <div
      className="flex items-baseline justify-between py-2 border-b"
      style={{ borderColor: "var(--theme-edge-faint)" }}
    >
      <div>
        <div className="text-[12px]" style={{ color: "var(--theme-ink)" }}>
          {label}
        </div>
        {hint && (
          <div
            className="text-[10px] mt-0.5"
            style={{ color: "var(--theme-ink-faint)" }}
          >
            {hint}
          </div>
        )}
      </div>
      <div
        className="text-[12px] font-mono"
        style={{ color: "var(--theme-amber)" }}
      >
        {value}
      </div>
    </div>
  );
}

function ActionRow({
  label,
  tone,
}: {
  label: string;
  tone?: "accent" | "warn";
}) {
  return (
    <div
      className="flex items-center justify-between py-2 border-b"
      style={{ borderColor: "var(--theme-edge-faint)" }}
    >
      <div className="text-[12px]" style={{ color: "var(--theme-ink)" }}>
        {label}
      </div>
      <div
        className="text-[10px] font-mono tracking-[0.18em] uppercase"
        style={{
          color:
            tone === "warn"
              ? "#d97757"
              : tone === "accent"
              ? "var(--theme-amber)"
              : "var(--theme-ink-faint)",
        }}
      >
        RUN
      </div>
    </div>
  );
}

function MetricStrip({
  title,
  metrics,
}: {
  title: string;
  metrics: Array<{ label: string; value: string }>;
}) {
  return (
    <div className="mt-4">
      <div
        className="text-[10px] font-mono tracking-[0.22em] uppercase mb-2 pb-1.5 border-b"
        style={{
          borderColor: "var(--theme-edge-faint)",
          color: "var(--theme-ink-faint)",
        }}
      >
        {title}
      </div>
      <div className="grid grid-cols-3 gap-3">
        {metrics.map((m) => (
          <div
            key={m.label}
            className="rounded-md p-2"
            style={{
              background: "var(--theme-paper)",
              border: "1px solid var(--theme-edge-faint)",
            }}
          >
            <div
              className="text-[8px] font-mono tracking-[0.22em] uppercase"
              style={{ color: "var(--theme-ink-faint)" }}
            >
              {m.label}
            </div>
            <div
              className="text-[15px] font-mono mt-0.5"
              style={{ color: "var(--theme-ink)" }}
            >
              {m.value}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
