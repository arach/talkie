"use client";

import { IOS_THEMES } from "@/lib/themes";
import { StudioPage } from "@/components/StudioPage";

/**
 * Themes gallery — one detail card per iOS theme. Shows identity,
 * typography spec, palette swatches, behavior flags. Lives outside
 * a PhoneFrame so the type/palette comparison reads at scale.
 */

export default function ThemesGallery() {
  return (
    <StudioPage
      eyebrow="· Themes · Articulation"
      title="iOS theme system"
      help="edit lib/themes.ts + app/globals.css · this gallery + every theme study repaints"
    >
      <p className="mb-8 max-w-[760px] text-[13px] leading-relaxed text-studio-ink-faint">
        Each theme is a coherent designed system — typography, palette,
        behavior, identity bundled together. Type stack is shared across
        all themes (Newsreader display, Inter body, JetBrains Mono chrome —
        proxies for the custom family that'll replace them). Differentiation
        is color, weight, tracking, and glow behavior. Read this gallery
        first, then check{" "}
        <a
          href="/library"
          className="text-studio-ink underline-offset-4 hover:underline"
        >
          /library
        </a>{" "}
        and{" "}
        <a
          href="/compose"
          className="text-studio-ink underline-offset-4 hover:underline"
        >
          /compose
        </a>{" "}
        to see them applied.
      </p>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
        {IOS_THEMES.map((theme) => (
          <article
            key={theme.key}
            data-theme={theme.key}
            className="overflow-hidden rounded-[14px] border border-studio-edge"
          >
            {/* Hero — the theme paints its own header */}
            <div
              className="px-5 pt-5 pb-6"
              style={{
                background: "var(--theme-canvas)",
                color: "var(--theme-ink)",
                fontFamily: "var(--theme-font-body)",
              }}
            >
              <div
                className="text-[9px] font-semibold uppercase tracking-[0.26em]"
                style={{
                  color: "var(--theme-amber)",
                  fontFamily: "var(--theme-font-mono)",
                  textShadow: "0 0 4px var(--theme-amber-glow)",
                }}
              >
                · {theme.key.toUpperCase()}
              </div>
              <h2
                className="m-0 mt-1 text-[28px] leading-none"
                style={{
                  color: "var(--theme-ink)",
                  fontFamily: "var(--theme-font-display)",
                  fontWeight: theme.display.italicAccent ? "var(--theme-display-weight)" : 500,
                  letterSpacing: "var(--theme-display-tracking)",
                }}
              >
                {theme.name}
                {theme.display.italicAccent ? (
                  <>
                    .{" "}
                    <span
                      style={{
                        fontStyle: "italic",
                        color: "var(--theme-ink-dim)",
                      }}
                    >
                      Editorial.
                    </span>
                  </>
                ) : null}
              </h2>
              <p
                className="m-0 mt-2 text-[12px] leading-snug"
                style={{ color: "var(--theme-ink-muted)" }}
              >
                {theme.identity}
              </p>
            </div>

            {/* Body — studio-canvas; meta about the theme */}
            <div className="space-y-5 px-5 py-5">
              <p className="m-0 text-[12px] leading-relaxed text-studio-ink-faint">
                {theme.blurb}
              </p>

              <Row label="Display">
                <code className="font-mono text-[11px] text-studio-ink">
                  Newsreader
                </code>
                <span className="text-studio-ink-faint">·</span>
                <code className="font-mono text-[11px] text-studio-ink-faint">
                  {theme.display.weight}w · {theme.display.tracking}
                </code>
                {theme.display.italicAccent ? (
                  <span className="ml-1 text-[10px] italic text-studio-ink-faint">
                    italic
                  </span>
                ) : null}
              </Row>

              <Row label="Body">
                <code className="font-mono text-[11px] text-studio-ink">
                  Inter
                </code>
                <span className="text-studio-ink-faint">·</span>
                <span className="text-[11px] text-studio-ink-faint">
                  UI + paragraphs
                </span>
              </Row>

              <Row label="Chrome">
                <code className="font-mono text-[11px] text-studio-ink">
                  JetBrains Mono
                </code>
                <span className="text-studio-ink-faint">·</span>
                <span className="text-[11px] text-studio-ink-faint">
                  channel labels + eyebrows
                </span>
              </Row>

              <Row label="Behavior">
                <BehaviorPill on={theme.behavior.phosphorGlow}>
                  Glow
                </BehaviorPill>
                <BehaviorPill on={theme.behavior.graticule}>
                  Graticule
                </BehaviorPill>
                <BehaviorPill on={theme.behavior.darkSurface}>
                  Dark
                </BehaviorPill>
              </Row>

              <Row label="Palette">
                <div className="flex flex-wrap gap-1.5">
                  {theme.preview.map((p) => (
                    <span
                      key={p.label}
                      className="inline-flex items-center gap-1.5 rounded-full border border-studio-edge px-2 py-0.5"
                    >
                      <span
                        aria-hidden
                        className="inline-block h-2.5 w-2.5 rounded-full"
                        style={{
                          background: p.hex,
                          boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.15)",
                        }}
                      />
                      <span className="font-mono text-[9.5px] text-studio-ink-faint">
                        {p.label}
                      </span>
                    </span>
                  ))}
                </div>
              </Row>
            </div>
          </article>
        ))}
      </div>
    </StudioPage>
  );
}

function Row({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <div className="text-[8px] font-semibold uppercase tracking-[0.22em] text-studio-ink-faint">
        · {label}
      </div>
      <div className="flex flex-wrap items-center gap-1.5">{children}</div>
    </div>
  );
}

function BehaviorPill({
  on,
  children,
}: {
  on: boolean;
  children: React.ReactNode;
}) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-mono uppercase tracking-[0.14em]"
      style={
        on
          ? {
              background: "rgba(82, 82, 82, 0.10)",
              color: "#262626",
              border: "0.5px solid rgba(0,0,0,0.20)",
            }
          : {
              background: "transparent",
              color: "#A3A3A3",
              border: "0.5px solid rgba(0,0,0,0.10)",
            }
      }
    >
      <span aria-hidden>{on ? "●" : "○"}</span>
      {children}
    </span>
  );
}
