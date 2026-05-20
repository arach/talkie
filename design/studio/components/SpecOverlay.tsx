"use client";

import { useEffect, useState } from "react";

/**
 * Hover-to-inspect overlay for studio pages.
 *
 * Activate with `?spec=1` on any page, or toggle with `Shift+?`. Hover
 * any element to see its computed box model + type stack in a fixed
 * panel; press `Escape` to dismiss. Designed to read like a real dev
 * tool — paddings/margins/font stacks/colors visible without round-
 * tripping through DevTools, which means the porting checklist that
 * follows from `bun run swift:hints` can be written against actual
 * computed values instead of guessed-at Tailwind classes.
 */

const PANEL_ID = "studio-spec-panel";
const OUTLINE_ID = "studio-spec-outline";

interface SpecInfo {
  tag: string;
  className: string;
  width: number;
  height: number;
  padding: string;
  margin: string;
  borderRadius: string;
  font: {
    family: string;
    size: string;
    lineHeight: string;
    letterSpacing: string;
    weight: string;
  };
  color: string;
  background: string;
  rect: { top: number; left: number; width: number; height: number };
}

function isSpecActive(): boolean {
  if (typeof window === "undefined") return false;
  return new URLSearchParams(window.location.search).has("spec");
}

function shorten(value: string, max: number): string {
  return value.length > max ? value.slice(0, max - 1) + "…" : value;
}

function normalizeColor(value: string): string {
  // Collapse `rgb(232, 154, 60)` → `#E89A3C`. Keep rgba() as-is so alpha is visible.
  const rgb = value.match(/^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/);
  if (rgb) {
    const hex = [rgb[1], rgb[2], rgb[3]]
      .map((c) => parseInt(c, 10).toString(16).padStart(2, "0").toUpperCase())
      .join("");
    return `#${hex}`;
  }
  return value;
}

function compactSpacing(t: string, r: string, b: string, l: string): string {
  // Mirror the CSS shorthand: collapse identical values.
  if (t === r && r === b && b === l) return t;
  if (t === b && l === r) return `${t} ${r}`;
  if (l === r) return `${t} ${r} ${b}`;
  return `${t} ${r} ${b} ${l}`;
}

function readSpec(el: HTMLElement): SpecInfo {
  const cs = getComputedStyle(el);
  const rect = el.getBoundingClientRect();
  return {
    tag: el.tagName.toLowerCase(),
    className: typeof el.className === "string" ? el.className : "",
    width: Math.round(rect.width),
    height: Math.round(rect.height),
    padding: compactSpacing(cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft),
    margin: compactSpacing(cs.marginTop, cs.marginRight, cs.marginBottom, cs.marginLeft),
    borderRadius: cs.borderRadius,
    font: {
      family: cs.fontFamily.split(",")[0].replace(/['"]/g, "").trim(),
      size: cs.fontSize,
      lineHeight: cs.lineHeight,
      letterSpacing: cs.letterSpacing,
      weight: cs.fontWeight,
    },
    color: normalizeColor(cs.color),
    background: normalizeColor(cs.backgroundColor),
    rect: { top: rect.top, left: rect.left, width: rect.width, height: rect.height },
  };
}

export function SpecOverlay() {
  const [active, setActive] = useState(false);
  const [info, setInfo] = useState<SpecInfo | null>(null);

  useEffect(() => {
    setActive(isSpecActive());
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "?" && e.shiftKey) {
        e.preventDefault();
        setActive((v) => !v);
      } else if (e.key === "Escape") {
        setActive(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (!active) {
      setInfo(null);
      return;
    }

    let rafId = 0;
    let lastTarget: HTMLElement | null = null;

    const onMove = (e: MouseEvent) => {
      if (rafId) return;
      rafId = requestAnimationFrame(() => {
        rafId = 0;
        const target = document.elementFromPoint(e.clientX, e.clientY) as HTMLElement | null;
        if (!target || target === lastTarget) return;
        if (target.closest(`#${PANEL_ID}`)) return;
        lastTarget = target;
        setInfo(readSpec(target));
      });
    };

    document.addEventListener("mousemove", onMove, { passive: true });
    return () => {
      document.removeEventListener("mousemove", onMove);
      if (rafId) cancelAnimationFrame(rafId);
    };
  }, [active]);

  if (!active) return null;

  return (
    <>
      {info && (
        <div
          id={OUTLINE_ID}
          style={{
            position: "fixed",
            top: info.rect.top,
            left: info.rect.left,
            width: info.rect.width,
            height: info.rect.height,
            boxShadow:
              "inset 0 0 0 1px rgba(99, 102, 241, 0.65), 0 0 0 1px rgba(99, 102, 241, 0.30)",
            background: "rgba(99, 102, 241, 0.06)",
            pointerEvents: "none",
            zIndex: 99998,
            transition: "all 60ms linear",
          }}
        />
      )}
      <SpecPanel info={info} />
    </>
  );
}

function SpecPanel({ info }: { info: SpecInfo | null }) {
  return (
    <div
      id={PANEL_ID}
      style={{
        position: "fixed",
        top: 12,
        right: 12,
        width: 320,
        maxHeight: "78vh",
        overflow: "auto",
        background: "rgba(14, 16, 22, 0.94)",
        backdropFilter: "blur(14px)",
        WebkitBackdropFilter: "blur(14px)",
        color: "#EDEDF2",
        fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace",
        fontSize: 11,
        lineHeight: 1.55,
        padding: "12px 14px 14px",
        borderRadius: 8,
        border: "1px solid rgba(99, 102, 241, 0.35)",
        boxShadow: "0 12px 36px rgba(0, 0, 0, 0.40)",
        pointerEvents: "none",
        zIndex: 99999,
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 10,
          paddingBottom: 8,
          borderBottom: "1px solid rgba(255,255,255,0.08)",
          fontSize: 9,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: "rgba(255,255,255,0.55)",
        }}
      >
        <span style={{ color: "#A5B4FC" }}>SPEC</span>
        <span>hover · esc to close · shift+? toggle</span>
      </div>
      {info ? <SpecBody info={info} /> : (
        <div style={{ opacity: 0.5 }}>Hover an element to inspect.</div>
      )}
    </div>
  );
}

function SpecBody({ info }: { info: SpecInfo }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "auto 1fr", columnGap: 10, rowGap: 4 }}>
      <SpecRow label="tag" value={info.tag} />
      <SpecRow label="size" value={`${info.width} × ${info.height}`} />
      <SpecRow label="padding" value={info.padding} />
      <SpecRow label="margin" value={info.margin} />
      {info.borderRadius !== "0px" && <SpecRow label="radius" value={info.borderRadius} />}
      <SpecRow
        label="font"
        value={`${info.font.family} · ${info.font.size} / ${info.font.lineHeight} · ${info.font.weight}`}
      />
      {info.font.letterSpacing !== "normal" && (
        <SpecRow label="tracking" value={info.font.letterSpacing} />
      )}
      <SpecRow label="color" value={info.color} swatch={info.color} />
      <SpecRow label="bg" value={info.background} swatch={info.background} />
      {info.className && (
        <SpecRow label="class" value={shorten(info.className, 220)} mono />
      )}
    </div>
  );
}

function SpecRow({
  label,
  value,
  swatch,
  mono,
}: {
  label: string;
  value: string;
  swatch?: string;
  mono?: boolean;
}) {
  return (
    <>
      <div style={{ color: "rgba(255,255,255,0.45)" }}>{label}</div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          wordBreak: "break-all",
          fontFamily: mono ? "ui-monospace, 'SF Mono', Menlo, monospace" : undefined,
          fontSize: mono ? 10 : 11,
          color: "#F2F2F7",
        }}
      >
        {swatch && (
          <span
            style={{
              display: "inline-block",
              width: 10,
              height: 10,
              borderRadius: 2,
              background: swatch,
              border: "1px solid rgba(255,255,255,0.20)",
              flexShrink: 0,
            }}
          />
        )}
        <span>{value}</span>
      </div>
    </>
  );
}
