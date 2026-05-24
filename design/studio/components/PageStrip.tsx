"use client";

import { usePathname } from "next/navigation";
import { pageForPath, platformLabel, type StudioPage } from "@/lib/studio-pages";

/**
 * Per-page header strip rendered at the top of every studio page,
 * just below the global top bar. Reads the registry entry for the
 * current route and shows: family · platform · status · linked Swift
 * file(s). Pages without an entry get no strip — the shell still
 * renders fine.
 *
 * This is the "what am I looking at" affordance — the studio's page
 * metadata becomes scannable instead of buried in code comments.
 */
export function PageStrip() {
  const pathname = usePathname();
  const page = pageForPath(pathname);
  if (!page) return null;

  return (
    <div className="border-b border-studio-edge bg-studio-canvas/95 px-7 py-2.5 font-mono text-[10px]">
      <div className="flex flex-wrap items-baseline gap-3">
        <Crumbs page={page} />
        <Sep />
        <StatusPill status={page.status} />
        {page.swift && page.swift.length > 0 ? (
          <>
            <Sep />
            <SwiftRefs files={page.swift} />
          </>
        ) : null}
        {page.blurb ? (
          <>
            <span className="mx-1 text-studio-ink-faint/40">·</span>
            <span className="font-sans text-[11px] italic text-studio-ink-faint/85">
              {page.blurb}
            </span>
          </>
        ) : null}
      </div>
    </div>
  );
}

function Crumbs({ page }: { page: StudioPage }) {
  const bucketLabel =
    page.bucket === "foundations"
      ? "Foundations"
      : page.bucket === "surfaces"
        ? "Surfaces"
        : "Lab";
  const platform = page.platform ? platformLabel(page.platform) : null;

  return (
    <div className="flex items-baseline gap-1.5 uppercase tracking-eyebrow text-studio-ink-faint">
      <span>{bucketLabel}</span>
      {platform ? (
        <>
          <Chevron />
          <span>{platform}</span>
        </>
      ) : null}
      {page.family && page.family !== page.label.toLowerCase() ? (
        <>
          <Chevron />
          <span>{page.family}</span>
        </>
      ) : null}
      <Chevron />
      <span className="text-studio-ink">{page.label}</span>
    </div>
  );
}

function StatusPill({ status }: { status?: StudioPage["status"] }) {
  if (!status) return null;
  const palette: Record<NonNullable<StudioPage["status"]>, { fg: string; bg: string; label: string }> = {
    shipped: { fg: "#1F5A2E", bg: "#E2F0E5", label: "SHIPPED" },
    wip: { fg: "#7A4A0E", bg: "#F5E6CC", label: "WIP" },
    concept: { fg: "#5A554C", bg: "#ECECEB", label: "CONCEPT" },
    deprecated: { fg: "#8A3030", bg: "#F0DCDC", label: "DEPRECATED" },
  };
  const tone = palette[status];
  return (
    <span
      className="rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold tracking-[0.18em]"
      style={{ color: tone.fg, background: tone.bg }}
    >
      {tone.label}
    </span>
  );
}

function SwiftRefs({ files }: { files: string[] }) {
  return (
    <div className="flex items-baseline gap-1.5 text-studio-ink-faint/85">
      <span className="text-[9px] uppercase tracking-eyebrow text-studio-ink-faint/60">
        swift
      </span>
      {files.map((file, i) => (
        <span key={file} className="inline-flex items-baseline gap-1">
          <code className="rounded-[2px] bg-studio-canvas-alt px-1 py-px text-[9.5px] text-studio-ink/85">
            {basename(file)}
          </code>
          {i < files.length - 1 ? <span className="text-studio-ink-faint/50">,</span> : null}
        </span>
      ))}
    </div>
  );
}

function basename(path: string): string {
  const i = path.lastIndexOf("/");
  return i >= 0 ? path.slice(i + 1) : path;
}

function Sep() {
  return (
    <span aria-hidden className="h-3 w-px shrink-0 bg-studio-edge" />
  );
}

function Chevron() {
  return (
    <span aria-hidden className="text-studio-ink-faint/40">
      ›
    </span>
  );
}
