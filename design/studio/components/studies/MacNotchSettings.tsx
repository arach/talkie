"use client";

/**
 * Mac Notch Settings — interactive simplification study.
 *
 * The shipping `SurfaceSettingsView.swift` exposes ~40 user-facing
 * controls across three tabs (Overlay / Tray / Hover Zone). User
 * verdict: too many toggles, too many ways to get things wrong.
 *
 * This prototype consolidates that surface to ~10 controls on the
 * main panel + an "Advanced" disclosure per section for tuning knobs
 * that previously shipped to users by accident. Every control is wired
 * to React state and feeds a live notch preview on the right so the
 * effect of each setting is visible, not narrated.
 *
 * Three guiding moves:
 *  - Collapse "Dot Strip" + "Standalone Badge" into one **Tray Indicator**
 *    with a Placement picker (auto / inside / below). One concept, one
 *    toggle, one decision.
 *  - Replace four hover-zone steppers (Width / Height / PadX / PadY)
 *    with one **Sensitivity** preset picker (Subtle / Normal / Aggressive).
 *  - Tuck all geometry / size / opacity tuning behind a per-section
 *    "Advanced" disclosure that's invisible until requested.
 *
 * Studio responsibility: show the consolidated surface as the user
 * would see it, with the live notch preview demonstrating each
 * decision. The advanced disclosure expands inline so reviewers can
 * judge whether the hidden knobs are actually hideable.
 */

import React, { useState } from "react";

const AMBER = "#C47D1C";
const AMBER_GLOW = "#E89A3C";
const INK = "#2A2620";
const INK_DIM = "#5A554C";
const INK_FAINT = "#A8A29E";
const EDGE = "#E0DCD3";
const EDGE_FAINT = "#ECE7DD";
const CREAM = "#FBFBFA";
const PAPER = "#F4F1EA";

// ─── Setting types ───────────────────────────────────────────────────

type Shape = "auto" | "island" | "notch";
type Placement = "auto" | "inside" | "below";
type Sensitivity = "subtle" | "normal" | "aggressive";

interface NotchConfig {
  // Notch tab
  enabled: boolean;
  alwaysVisible: boolean;
  shape: Shape;
  // Notch · advanced
  opacity: number;          // 0..1
  cornerRadius: number;     // 0..28
  hoverExpansion: number;   // 0..90
  activeExpansion: number;  // 0..120

  // Tray tab
  trayIndicator: boolean;
  trayPlacement: Placement;
  showPreviewWhileRecording: boolean;
  // Tray · advanced
  indicatorWidth: number;   // 30..200
  dotSize: number;          // 1..8
  maxDots: number;          // 1..12

  // Hover zone tab
  hoverSensitivity: Sensitivity;
  // Hover · advanced
  manualWidth: number;      // 40..240
  manualHeight: number;     // 8..48
}

const DEFAULTS: NotchConfig = {
  enabled: true,
  alwaysVisible: false,
  shape: "auto",
  opacity: 1.0,
  cornerRadius: 14,
  hoverExpansion: 38,
  activeExpansion: 58,
  trayIndicator: true,
  trayPlacement: "auto",
  showPreviewWhileRecording: true,
  indicatorWidth: 80,
  dotSize: 3,
  maxDots: 5,
  hoverSensitivity: "normal",
  manualWidth: 180,
  manualHeight: 24,
};

interface PreviewState {
  trayItemCount: number;
  hovering: boolean;
  recording: boolean;
}

// ─── Composition root ────────────────────────────────────────────────

type Tab = "notch" | "tray" | "hover";

export function MacNotchSettings() {
  const [config, setConfig] = useState<NotchConfig>(DEFAULTS);
  const [preview, setPreview] = useState<PreviewState>({
    trayItemCount: 2,
    hovering: false,
    recording: false,
  });
  const [tab, setTab] = useState<Tab>("notch");
  const [advancedOpen, setAdvancedOpen] = useState<Record<Tab, boolean>>({
    notch: false,
    tray: false,
    hover: false,
  });

  const update = <K extends keyof NotchConfig>(k: K, v: NotchConfig[K]) =>
    setConfig((c) => ({ ...c, [k]: v }));

  return (
    <div className="flex flex-col gap-6">
      <Disclaimer />
      <div className="flex gap-6">
        <SettingsPanel
          config={config}
          update={update}
          tab={tab}
          setTab={setTab}
          advancedOpen={advancedOpen}
          setAdvancedOpen={setAdvancedOpen}
        />
        <PreviewPanel config={config} preview={preview} setPreview={setPreview} />
      </div>
      <CountReadout config={config} advancedOpen={advancedOpen} />
    </div>
  );
}

// ─── Disclaimer / framing ────────────────────────────────────────────

function Disclaimer() {
  return (
    <div
      className="flex items-baseline gap-3 rounded-md px-4 py-3"
      style={{ background: PAPER, border: `0.5px solid ${EDGE}` }}
    >
      <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-[#9A6A22]">
        · proposal
      </span>
      <span className="text-[12px] text-studio-ink">
        Live mockup of the consolidated notch settings — ~10 main controls + per-section Advanced disclosure.
      </span>
      <span className="ml-auto font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        from ~40 controls to ~10
      </span>
    </div>
  );
}

// ─── Settings panel (left) ───────────────────────────────────────────

function SettingsPanel({
  config,
  update,
  tab,
  setTab,
  advancedOpen,
  setAdvancedOpen,
}: {
  config: NotchConfig;
  update: <K extends keyof NotchConfig>(k: K, v: NotchConfig[K]) => void;
  tab: Tab;
  setTab: (t: Tab) => void;
  advancedOpen: Record<Tab, boolean>;
  setAdvancedOpen: (s: Record<Tab, boolean>) => void;
}) {
  return (
    <div
      className="flex flex-col rounded-md overflow-hidden"
      style={{ width: 420, background: CREAM, border: `0.5px solid ${EDGE}` }}
    >
      <TabBar tab={tab} setTab={setTab} />
      <div className="px-5 py-4">
        {tab === "notch" && (
          <NotchTab
            config={config}
            update={update}
            advancedOpen={advancedOpen.notch}
            setAdvancedOpen={(v) => setAdvancedOpen({ ...advancedOpen, notch: v })}
          />
        )}
        {tab === "tray" && (
          <TrayTab
            config={config}
            update={update}
            advancedOpen={advancedOpen.tray}
            setAdvancedOpen={(v) => setAdvancedOpen({ ...advancedOpen, tray: v })}
          />
        )}
        {tab === "hover" && (
          <HoverTab
            config={config}
            update={update}
            advancedOpen={advancedOpen.hover}
            setAdvancedOpen={(v) => setAdvancedOpen({ ...advancedOpen, hover: v })}
          />
        )}
      </div>
    </div>
  );
}

function TabBar({ tab, setTab }: { tab: Tab; setTab: (t: Tab) => void }) {
  const tabs: { key: Tab; label: string; count: string }[] = [
    { key: "notch", label: "Notch", count: "3" },
    { key: "tray",  label: "Tray",  count: "3" },
    { key: "hover", label: "Hover", count: "1" },
  ];
  return (
    <div className="flex items-center" style={{ background: PAPER, borderBottom: `0.5px solid ${EDGE}` }}>
      {tabs.map((t) => {
        const active = t.key === tab;
        return (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className="flex flex-1 items-baseline justify-center gap-2 px-4 py-2.5"
            style={{
              background: active ? CREAM : "transparent",
              borderBottom: active ? `1.5px solid ${AMBER}` : "1.5px solid transparent",
            }}
          >
            <span
              className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em]"
              style={{ color: active ? INK : INK_DIM }}
            >
              {t.label}
            </span>
            <span
              className="font-mono text-[9px] tracking-[0.06em]"
              style={{ color: active ? AMBER : INK_FAINT }}
            >
              {t.count}
            </span>
          </button>
        );
      })}
    </div>
  );
}

// ─── Tab: Notch ──────────────────────────────────────────────────────

function NotchTab({
  config,
  update,
  advancedOpen,
  setAdvancedOpen,
}: {
  config: NotchConfig;
  update: <K extends keyof NotchConfig>(k: K, v: NotchConfig[K]) => void;
  advancedOpen: boolean;
  setAdvancedOpen: (v: boolean) => void;
}) {
  return (
    <div className="flex flex-col gap-4">
      <ToggleRow
        label="Enable notch"
        hint="The notch surface appears when an action is live (recording, camera, etc.)"
        value={config.enabled}
        onChange={(v) => update("enabled", v)}
      />
      <ToggleRow
        label="Always visible"
        hint="Keep the notch surface present even when no action is live."
        value={config.alwaysVisible}
        onChange={(v) => update("alwaysVisible", v)}
        disabled={!config.enabled}
      />
      <PickerRow
        label="Shape on external displays"
        hint="Built-in notch Macs always use the hardware notch."
        value={config.shape}
        onChange={(v) => update("shape", v as Shape)}
        options={[
          { value: "auto",   label: "Auto" },
          { value: "island", label: "Island" },
          { value: "notch",  label: "Notch" },
        ]}
        disabled={!config.enabled}
      />

      <AdvancedDisclosure open={advancedOpen} setOpen={setAdvancedOpen} count={4}>
        <SliderRow
          label="Opacity"
          value={config.opacity}
          min={0.4} max={1} step={0.05}
          format={(v) => `${Math.round(v * 100)}%`}
          onChange={(v) => update("opacity", v)}
        />
        <SliderRow
          label="Corner radius"
          value={config.cornerRadius}
          min={0} max={28} step={1}
          format={(v) => `${v}pt`}
          onChange={(v) => update("cornerRadius", v)}
        />
        <SliderRow
          label="Hover expansion"
          value={config.hoverExpansion}
          min={0} max={90} step={2}
          format={(v) => `${v}pt`}
          onChange={(v) => update("hoverExpansion", v)}
        />
        <SliderRow
          label="Active expansion"
          value={config.activeExpansion}
          min={0} max={120} step={2}
          format={(v) => `${v}pt`}
          onChange={(v) => update("activeExpansion", v)}
        />
      </AdvancedDisclosure>
    </div>
  );
}

// ─── Tab: Tray ───────────────────────────────────────────────────────

function TrayTab({
  config,
  update,
  advancedOpen,
  setAdvancedOpen,
}: {
  config: NotchConfig;
  update: <K extends keyof NotchConfig>(k: K, v: NotchConfig[K]) => void;
  advancedOpen: boolean;
  setAdvancedOpen: (v: boolean) => void;
}) {
  return (
    <div className="flex flex-col gap-4">
      <ToggleRow
        label="Tray indicator"
        hint="Show a dot strip when items are in the tray. Replaces both 'Dot Strip' and 'Standalone Badge' from the legacy surface."
        value={config.trayIndicator}
        onChange={(v) => update("trayIndicator", v)}
      />
      <PickerRow
        label="Placement"
        hint="Auto picks based on display — inside the notch on built-in displays, below on external."
        value={config.trayPlacement}
        onChange={(v) => update("trayPlacement", v as Placement)}
        options={[
          { value: "auto",   label: "Auto" },
          { value: "inside", label: "Inside notch" },
          { value: "below",  label: "Floating below" },
        ]}
        disabled={!config.trayIndicator}
      />
      <ToggleRow
        label="Show tray preview while recording"
        hint="If off, the tray drawer hides during recording. Most users want this on."
        value={config.showPreviewWhileRecording}
        onChange={(v) => update("showPreviewWhileRecording", v)}
      />

      <AdvancedDisclosure open={advancedOpen} setOpen={setAdvancedOpen} count={3}>
        <SliderRow
          label="Indicator width"
          value={config.indicatorWidth}
          min={30} max={200} step={2}
          format={(v) => `${v}pt`}
          onChange={(v) => update("indicatorWidth", v)}
        />
        <SliderRow
          label="Dot size"
          value={config.dotSize}
          min={1} max={8} step={0.2}
          format={(v) => `${v.toFixed(1)}pt`}
          onChange={(v) => update("dotSize", v)}
        />
        <SliderRow
          label="Max dots"
          value={config.maxDots}
          min={1} max={12} step={1}
          format={(v) => `${v}`}
          onChange={(v) => update("maxDots", v)}
        />
      </AdvancedDisclosure>
    </div>
  );
}

// ─── Tab: Hover ──────────────────────────────────────────────────────

function HoverTab({
  config,
  update,
  advancedOpen,
  setAdvancedOpen,
}: {
  config: NotchConfig;
  update: <K extends keyof NotchConfig>(k: K, v: NotchConfig[K]) => void;
  advancedOpen: boolean;
  setAdvancedOpen: (v: boolean) => void;
}) {
  const presets: { value: Sensitivity; label: string; sub: string }[] = [
    { value: "subtle",     label: "Subtle",     sub: "narrow zone · less accidental hover" },
    { value: "normal",     label: "Normal",     sub: "default · 180pt wide on laptop, 80pt external" },
    { value: "aggressive", label: "Aggressive", sub: "wide zone · easier to trigger" },
  ];
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <div>
          <div className="font-display text-[14px] font-medium text-studio-ink">
            Hover sensitivity
          </div>
          <div className="text-[11px] text-studio-ink-faint">
            How easy it is to wake the notch by moving your cursor near the top of the screen.
          </div>
        </div>
        <div className="mt-1 flex flex-col gap-1.5">
          {presets.map((p) => {
            const active = p.value === config.hoverSensitivity;
            return (
              <button
                key={p.value}
                onClick={() => update("hoverSensitivity", p.value)}
                className="flex items-center gap-3 rounded-[4px] px-3 py-2 text-left"
                style={{
                  background: active ? "#F2EFE6" : "transparent",
                  border: `0.5px solid ${active ? INK : EDGE}`,
                }}
              >
                <span
                  aria-hidden
                  className="h-2.5 w-2.5 rounded-full"
                  style={{
                    background: active ? AMBER : "transparent",
                    border: `1.5px solid ${active ? AMBER : EDGE}`,
                  }}
                />
                <div className="flex flex-col">
                  <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.16em] text-studio-ink">
                    {p.label}
                  </span>
                  <span className="font-mono text-[9px] uppercase tracking-[0.14em] text-studio-ink-faint">
                    {p.sub}
                  </span>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      <AdvancedDisclosure
        open={advancedOpen}
        setOpen={setAdvancedOpen}
        count={2}
        label="Per-display custom"
      >
        <SliderRow
          label="Zone width"
          value={config.manualWidth}
          min={40} max={240} step={4}
          format={(v) => `${v}pt`}
          onChange={(v) => update("manualWidth", v)}
        />
        <SliderRow
          label="Zone height"
          value={config.manualHeight}
          min={8} max={48} step={1}
          format={(v) => `${v}pt`}
          onChange={(v) => update("manualHeight", v)}
        />
        <div className="mt-1 text-[10px] text-studio-ink-faint">
          Overrides the preset for this display only.
        </div>
      </AdvancedDisclosure>
    </div>
  );
}

// ─── Reusable controls ───────────────────────────────────────────────

function ToggleRow({
  label,
  hint,
  value,
  onChange,
  disabled = false,
}: {
  label: string;
  hint?: string;
  value: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-start gap-3" style={{ opacity: disabled ? 0.4 : 1 }}>
      <div className="flex flex-1 flex-col gap-0.5">
        <div className="font-display text-[14px] font-medium text-studio-ink">{label}</div>
        {hint && <div className="text-[11px] leading-[1.4] text-studio-ink-faint">{hint}</div>}
      </div>
      <button
        onClick={() => !disabled && onChange(!value)}
        disabled={disabled}
        className="relative h-[18px] w-[30px] rounded-full"
        style={{
          background: value ? AMBER : "#D8D2C7",
          border: `0.5px solid ${value ? "#A86715" : "#B8B0A4"}`,
          cursor: disabled ? "not-allowed" : "pointer",
          transition: "background 150ms ease",
        }}
        aria-pressed={value}
      >
        <span
          aria-hidden
          className="absolute top-[1.5px] block h-[13px] w-[13px] rounded-full"
          style={{
            left: value ? "14px" : "2px",
            background: "#FFFFFF",
            boxShadow: "0 1px 2px rgba(0,0,0,0.18)",
            transition: "left 150ms ease",
          }}
        />
      </button>
    </div>
  );
}

function PickerRow({
  label,
  hint,
  value,
  onChange,
  options,
  disabled = false,
}: {
  label: string;
  hint?: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
  disabled?: boolean;
}) {
  return (
    <div className="flex flex-col gap-1.5" style={{ opacity: disabled ? 0.4 : 1 }}>
      <div>
        <div className="font-display text-[14px] font-medium text-studio-ink">{label}</div>
        {hint && <div className="text-[11px] leading-[1.4] text-studio-ink-faint">{hint}</div>}
      </div>
      <div
        className="flex items-center rounded-[3px] p-[2px]"
        style={{ background: PAPER, border: `0.5px solid ${EDGE}`, width: "fit-content" }}
      >
        {options.map((o) => {
          const active = o.value === value;
          return (
            <button
              key={o.value}
              onClick={() => !disabled && onChange(o.value)}
              disabled={disabled}
              className="rounded-[2px] px-2.5 py-1"
              style={{
                background: active ? CREAM : "transparent",
                border: active ? `0.5px solid ${EDGE}` : "0.5px solid transparent",
                cursor: disabled ? "not-allowed" : "pointer",
              }}
            >
              <span
                className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em]"
                style={{ color: active ? INK : INK_DIM }}
              >
                {o.label}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function SliderRow({
  label,
  value,
  min,
  max,
  step,
  onChange,
  format,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
  format?: (v: number) => string;
}) {
  return (
    <div className="flex items-center gap-3">
      <div className="flex-1 font-mono text-[10px] uppercase tracking-[0.14em] text-studio-ink">
        {label}
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        style={{ width: 140, accentColor: AMBER }}
      />
      <div className="w-12 text-right font-mono text-[10px] tracking-[0.06em] text-studio-ink-faint">
        {format ? format(value) : value}
      </div>
    </div>
  );
}

function AdvancedDisclosure({
  open,
  setOpen,
  count,
  label = "Advanced",
  children,
}: {
  open: boolean;
  setOpen: (v: boolean) => void;
  count: number;
  label?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      className="rounded-[4px]"
      style={{ background: open ? PAPER : "transparent", border: `0.5px solid ${open ? EDGE : "transparent"}` }}
    >
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center gap-2 px-3 py-2"
      >
        <span
          aria-hidden
          className="font-mono text-[11px]"
          style={{ color: AMBER, transform: open ? "rotate(90deg)" : "rotate(0deg)", transition: "transform 150ms ease" }}
        >
          ›
        </span>
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-studio-ink">
          {label}
        </span>
        <span className="font-mono text-[9px] tracking-[0.06em] text-studio-ink-faint">
          {count} knob{count === 1 ? "" : "s"}
        </span>
      </button>
      {open && <div className="flex flex-col gap-2 px-3 pb-3">{children}</div>}
    </div>
  );
}

// ─── Preview panel (right) ───────────────────────────────────────────

function PreviewPanel({
  config,
  preview,
  setPreview,
}: {
  config: NotchConfig;
  preview: PreviewState;
  setPreview: (p: PreviewState) => void;
}) {
  return (
    <div className="flex flex-1 flex-col gap-3">
      <NotchScreen config={config} preview={preview} setHovering={(v) => setPreview({ ...preview, hovering: v })} />
      <PreviewControls preview={preview} setPreview={setPreview} />
    </div>
  );
}

// The simulated screen showing the notch at the top, hover zone, and
// tray indicator. Sized to fit the studio canvas, not to mimic exact
// pixel ratios. Reads as a screen sliver: status bar at top, content
// below, with the notch protruding.
function NotchScreen({
  config,
  preview,
  setHovering,
}: {
  config: NotchConfig;
  preview: PreviewState;
  setHovering: (v: boolean) => void;
}) {
  const SCREEN_WIDTH = 600;
  const SCREEN_HEIGHT = 240;
  const NOTCH_BASE_WIDTH = 180;

  // Resolve hover-zone width from sensitivity preset (or manual override)
  const sensitivityWidth: Record<Sensitivity, number> = {
    subtle: 120,
    normal: 180,
    aggressive: 260,
  };
  const hoverZoneWidth = sensitivityWidth[config.hoverSensitivity];

  // Resolve notch shape — "auto" defaults to "notch" for the studio canvas
  const resolvedShape = config.shape === "auto" ? "notch" : config.shape;

  // Decide whether the notch is expanded based on state
  const expanded =
    config.enabled &&
    (config.alwaysVisible || preview.hovering || preview.recording);

  // Compute notch width given state
  const notchWidth =
    NOTCH_BASE_WIDTH +
    (expanded
      ? preview.recording
        ? config.activeExpansion
        : config.hoverExpansion
      : 0);

  // Decide where the tray indicator renders given placement + display
  const showIndicator = config.trayIndicator && preview.trayItemCount > 0;
  // "auto" on the studio canvas = inside (we're simulating built-in display)
  const placement: Exclude<Placement, "auto"> =
    config.trayPlacement === "auto" ? "inside" : config.trayPlacement;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-baseline justify-between">
        <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
          · preview · simulated display
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {expanded ? (preview.recording ? "recording" : "hovering") : config.alwaysVisible ? "always-on" : "idle"}
        </span>
      </div>

      <div
        className="relative overflow-hidden rounded-[4px]"
        style={{
          width: SCREEN_WIDTH,
          height: SCREEN_HEIGHT,
          background: "linear-gradient(180deg, #E0DCD3 0%, #C8C2B6 100%)",
          border: `0.5px solid ${INK_DIM}`,
        }}
      >
        {/* Faux desktop content — a few horizontal lines so the
            screen reads as a real Mac display, not an empty rectangle. */}
        <div className="absolute inset-0 flex flex-col gap-1.5 px-6 pt-8 opacity-30">
          {Array.from({ length: 9 }).map((_, i) => (
            <span
              key={i}
              className="block h-1.5 rounded-full"
              style={{
                background: "#FBFBFA",
                width: `${[88, 64, 76, 92, 58, 70, 84, 50, 80][i]}%`,
              }}
            />
          ))}
        </div>

        {/* Hover zone outline (always-visible studio affordance) */}
        <HoverZoneOutline
          width={hoverZoneWidth}
          height={config.hoverSensitivity === "subtle" ? 18 : config.hoverSensitivity === "aggressive" ? 34 : 24}
          screenWidth={SCREEN_WIDTH}
        />

        {/* The notch */}
        {config.enabled && (
          <NotchShape
            shape={resolvedShape}
            width={notchWidth}
            screenWidth={SCREEN_WIDTH}
            cornerRadius={config.cornerRadius}
            opacity={config.opacity}
            expanded={expanded}
            recording={preview.recording}
            onHoverEnter={() => setHovering(true)}
            onHoverLeave={() => setHovering(false)}
          />
        )}

        {/* Tray indicator inside the notch */}
        {showIndicator && placement === "inside" && config.enabled && (
          <TrayIndicator
            placement="inside"
            width={config.indicatorWidth}
            dotSize={config.dotSize}
            maxDots={config.maxDots}
            count={preview.trayItemCount}
            screenWidth={SCREEN_WIDTH}
            notchWidth={notchWidth}
          />
        )}

        {/* Tray indicator floating below */}
        {showIndicator && placement === "below" && (
          <TrayIndicator
            placement="below"
            width={config.indicatorWidth}
            dotSize={config.dotSize}
            maxDots={config.maxDots}
            count={preview.trayItemCount}
            screenWidth={SCREEN_WIDTH}
            notchWidth={notchWidth}
          />
        )}
      </div>
    </div>
  );
}

function HoverZoneOutline({
  width,
  height,
  screenWidth,
}: {
  width: number;
  height: number;
  screenWidth: number;
}) {
  const left = (screenWidth - width) / 2;
  return (
    <div
      aria-hidden
      style={{
        position: "absolute",
        top: 0,
        left,
        width,
        height,
        border: `1px dashed ${AMBER_GLOW}`,
        borderTop: "none",
        opacity: 0.4,
      }}
    />
  );
}

function NotchShape({
  shape,
  width,
  screenWidth,
  cornerRadius,
  opacity,
  expanded,
  recording,
  onHoverEnter,
  onHoverLeave,
}: {
  shape: Exclude<Shape, "auto">;
  width: number;
  screenWidth: number;
  cornerRadius: number;
  opacity: number;
  expanded: boolean;
  recording: boolean;
  onHoverEnter: () => void;
  onHoverLeave: () => void;
}) {
  const HEIGHT = expanded ? 40 : 28;
  const left = (screenWidth - width) / 2;
  const borderRadius =
    shape === "island"
      ? `${HEIGHT / 2}px`
      : `0 0 ${cornerRadius}px ${cornerRadius}px`;

  return (
    <div
      onMouseEnter={onHoverEnter}
      onMouseLeave={onHoverLeave}
      style={{
        position: "absolute",
        top: shape === "island" ? 6 : 0,
        left,
        width,
        height: HEIGHT,
        background: recording ? "#2A1614" : "#0E1518",
        borderRadius,
        opacity,
        boxShadow: expanded ? `0 4px 12px rgba(0,0,0,0.32)` : "none",
        transition: "all 180ms ease",
        cursor: "pointer",
      }}
    >
      {/* Recording indicator inside the notch */}
      {recording && (
        <div className="flex h-full items-center justify-center gap-2 px-3">
          <span
            aria-hidden
            className="h-1.5 w-1.5 rounded-full"
            style={{ background: "#E53E3E", boxShadow: "0 0 6px rgba(229,62,62,0.7)" }}
          />
          <span className="font-mono text-[9px] uppercase tracking-[0.20em]" style={{ color: "#FBE2DC" }}>
            REC 0:14
          </span>
        </div>
      )}
    </div>
  );
}

function TrayIndicator({
  placement,
  width,
  dotSize,
  maxDots,
  count,
  screenWidth,
  notchWidth,
}: {
  placement: "inside" | "below";
  width: number;
  dotSize: number;
  maxDots: number;
  count: number;
  screenWidth: number;
  notchWidth: number;
}) {
  const renderCount = Math.min(count, maxDots);
  const dots = Array.from({ length: renderCount });
  const containerLeft = (screenWidth - width) / 2;

  if (placement === "inside") {
    // Inside the notch — centered horizontally, near the bottom
    return (
      <div
        aria-hidden
        className="flex items-center justify-center gap-1.5"
        style={{
          position: "absolute",
          top: 18,
          left: (screenWidth - notchWidth) / 2,
          width: notchWidth,
          height: 10,
          zIndex: 2,
        }}
      >
        {dots.map((_, i) => (
          <span
            key={i}
            style={{
              width: dotSize,
              height: dotSize,
              borderRadius: "50%",
              background: AMBER_GLOW,
              boxShadow: `0 0 4px ${AMBER_GLOW}`,
            }}
          />
        ))}
      </div>
    );
  }

  // Floating below the notch
  return (
    <div
      aria-hidden
      className="flex items-center justify-center gap-1.5 rounded-full"
      style={{
        position: "absolute",
        top: 36,
        left: containerLeft,
        width,
        height: 14,
        background: "rgba(14,21,24,0.85)",
        border: `0.5px solid ${AMBER}`,
        boxShadow: `0 2px 6px rgba(0,0,0,0.18)`,
      }}
    >
      {dots.map((_, i) => (
        <span
          key={i}
          style={{
            width: dotSize,
            height: dotSize,
            borderRadius: "50%",
            background: AMBER_GLOW,
          }}
        />
      ))}
    </div>
  );
}

// ─── Preview controls (below the screen) ─────────────────────────────

function PreviewControls({
  preview,
  setPreview,
}: {
  preview: PreviewState;
  setPreview: (p: PreviewState) => void;
}) {
  return (
    <div
      className="flex items-center gap-4 rounded-md px-4 py-3"
      style={{ background: PAPER, border: `0.5px solid ${EDGE}` }}
    >
      <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        · simulate
      </span>

      <button
        onClick={() => setPreview({ ...preview, recording: !preview.recording })}
        className="rounded-[3px] px-3 py-1.5"
        style={{
          background: preview.recording ? "#E53E3E" : "transparent",
          border: `0.5px solid ${preview.recording ? "#E53E3E" : EDGE}`,
          color: preview.recording ? "#FFFFFF" : INK,
        }}
      >
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em]">
          {preview.recording ? "stop" : "record"}
        </span>
      </button>

      <span className="h-4 w-px" style={{ background: EDGE }} />

      <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-studio-ink">
        tray items
      </span>
      <input
        type="range"
        min={0}
        max={8}
        step={1}
        value={preview.trayItemCount}
        onChange={(e) => setPreview({ ...preview, trayItemCount: Number(e.target.value) })}
        style={{ width: 100, accentColor: AMBER }}
      />
      <span className="font-mono text-[10px] tracking-[0.06em] text-studio-ink-faint">
        {preview.trayItemCount}
      </span>

      <div className="ml-auto font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        hover the notch to expand
      </div>
    </div>
  );
}

// ─── Count readout (bottom) ──────────────────────────────────────────

function CountReadout({
  config,
  advancedOpen,
}: {
  config: NotchConfig;
  advancedOpen: Record<Tab, boolean>;
}) {
  const mainVisible = 3 + 3 + 1; // notch=3, tray=3, hover=1
  const advancedVisible =
    (advancedOpen.notch ? 4 : 0) +
    (advancedOpen.tray ? 3 : 0) +
    (advancedOpen.hover ? 2 : 0);
  const totalToday = 40; // approximate count from the live SurfaceSettingsView

  return (
    <div className="flex items-baseline gap-4 font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint">
      <span>· state</span>
      <span>
        main surface · <span className="text-studio-ink">{mainVisible} controls</span>
      </span>
      <span>·</span>
      <span>
        advanced expanded · <span className="text-studio-ink">{advancedVisible} knobs</span>
      </span>
      <span className="ml-auto">
        legacy surface · <span className="text-studio-ink">{totalToday}+ controls</span>
      </span>
    </div>
  );
}
