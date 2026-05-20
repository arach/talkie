"use client";

/**
 * Terminal — Talkie's SSH session surface. Saved hosts list with
 * status dots, last-connected timestamps, source labels. Mirrors
 * the iOS TerminalNext composition: TALKIE · TERMINAL wordmark,
 * SAVED HOSTS section eyebrow with "ADD HOST" trailing action,
 * 44pt host rows with terminal glyph · title/subtitle · trailing
 * timestamp + status indicator.
 *
 * Two variants:
 *  - populated: 3 saved hosts including one active
 *  - empty: "No saved hosts" with a generous CTA
 */

import { useState } from "react";
import { StatusBar } from "./primitives/StatusBar";

export type TerminalVariant = "populated" | "empty";

export const TERMINAL_VARIANTS: { key: TerminalVariant; label: string }[] = [
  { key: "populated", label: "Populated" },
  { key: "empty", label: "Empty" },
];

const HOSTS: Array<{
  title: string;
  subtitle: string;
  lastUsed: string;
  source: string;
  active: boolean;
}> = [
  {
    title: "Mini · workshop",
    subtitle: "art@mini.local · 192.168.1.42",
    lastUsed: "May 20 14:32",
    source: "QR",
    active: true,
  },
  {
    title: "studio.tail.ts.net",
    subtitle: "art@studio.tail.ts.net",
    lastUsed: "May 18 09:12",
    source: "QR",
    active: false,
  },
  {
    title: "ovh-paris",
    subtitle: "ubuntu@51.38.176.12",
    lastUsed: "May 12 22:48",
    source: "Manual",
    active: false,
  },
];

export function TerminalStudy({ variant }: { variant: TerminalVariant }) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header />
      <Divider />
      <div className="flex-1 overflow-hidden">
        <div className="px-4 pt-3">
          <PanelHeader />
          {variant === "populated" ? <HostList /> : <EmptyState />}
        </div>
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
        TALKIE · TERMINAL
      </span>
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

function PanelHeader() {
  return (
    <div
      className="flex items-center justify-between pb-2"
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
        SAVED HOSTS
      </span>
      <button
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.20em",
        }}
      >
        ADD HOST
      </button>
    </div>
  );
}

function HostList() {
  return (
    <div>
      {HOSTS.map((host, i) => (
        <HostRow key={host.title} {...host} divider={i < HOSTS.length - 1} />
      ))}
    </div>
  );
}

function HostRow({
  title,
  subtitle,
  lastUsed,
  source,
  active,
  divider,
}: {
  title: string;
  subtitle: string;
  lastUsed: string;
  source: string;
  active: boolean;
  divider: boolean;
}) {
  return (
    <div
      className="flex items-center gap-2.5 py-2.5"
      style={{
        borderBottom: divider ? "0.5px solid var(--theme-edge-faint)" : "none",
      }}
    >
      <span
        aria-hidden
        className="inline-flex h-5 w-5 items-center justify-center"
        style={{ color: "var(--theme-amber)" }}
      >
        <svg viewBox="0 0 16 16" className="h-3.5 w-3.5" fill="none">
          <rect
            x={2}
            y={3}
            width={12}
            height={10}
            rx={1.5}
            stroke="currentColor"
            strokeWidth={1}
          />
          <path
            d="M 4.5 6.5 L 6.5 8 L 4.5 9.5 M 7.5 10 L 11.5 10"
            stroke="currentColor"
            strokeWidth={1}
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
          />
        </svg>
      </span>

      <div className="min-w-0 flex-1">
        <div
          className="truncate text-[13px] font-medium leading-tight"
          style={{ color: "var(--theme-ink)" }}
        >
          {title}
        </div>
        <div
          className="mt-0.5 truncate text-[10px] leading-tight"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {subtitle}
        </div>
      </div>

      <div className="flex flex-col items-end gap-1">
        <span
          className="text-[10px] tabular-nums"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {lastUsed}
        </span>
        <div className="flex items-center gap-1">
          <span
            aria-hidden
            className="h-1.5 w-1.5 rounded-full"
            style={{
              background: active
                ? "var(--theme-amber)"
                : "var(--theme-ink-faint)",
              opacity: active ? 1 : 0.35,
            }}
          />
          <span
            className="text-[8px] font-medium uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.22em",
            }}
          >
            {source}
          </span>
        </div>
      </div>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center gap-3.5 pt-12">
      <svg
        viewBox="0 0 16 16"
        className="h-10 w-10"
        fill="none"
        style={{ color: "var(--theme-ink-faint)", opacity: 0.7 }}
      >
        <rect
          x={2}
          y={3}
          width={12}
          height={10}
          rx={1.5}
          stroke="currentColor"
          strokeWidth={1}
        />
        <path
          d="M 4.5 6.5 L 6.5 8 L 4.5 9.5 M 7.5 10 L 11.5 10"
          stroke="currentColor"
          strokeWidth={1}
          strokeLinecap="round"
          strokeLinejoin="round"
          fill="none"
        />
      </svg>
      <div
        className="text-[18px] font-light leading-tight"
        style={{ color: "var(--theme-ink)" }}
      >
        No saved hosts
      </div>
      <div
        className="max-w-[18ch] text-center text-[11px] leading-snug"
        style={{ color: "var(--theme-ink-faint)" }}
      >
        Pair a Mac to get a one-tap terminal here.
      </div>
      <button
        className="mt-3 rounded-full px-4 py-2 text-[10px] font-medium uppercase"
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
  );
}
