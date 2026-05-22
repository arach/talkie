/**
 * List row — leading source icon · title (+ optional preview) ·
 * trailing meta. Incorporates mira's #1 critique for the Library
 * screen: leading icon is `variant`-driven (waveform for dictation,
 * keyboard for typed, link for clipped, etc.) so the column isn't
 * a wall of identical mics.
 */

export type ListRowSource = "dictation" | "typed" | "link" | "scan";

interface ListRowProps {
  source: ListRowSource;
  title: string;
  /** One-line transcript preview shown beneath the title (mira #1). */
  preview?: string;
  meta: string;
  /** Add a top hairline. First row in a list should be false. */
  divider?: boolean;
}

export function ListRow({
  source,
  title,
  preview,
  meta,
  divider = true,
}: ListRowProps) {
  // Two-line iOS-Notes-style: source glyph as small left rail · title
  // with inline right-aligned time on row 1 · preview on row 2. The
  // divider is inset under the title so the icon column reads as a
  // connected rail. The meta string is split — only the first segment
  // (the time) appears inline; the rest is dropped to keep the row
  // tight. If a row needs all of its meta visible, pass it via the
  // preview prop instead.
  const inlineTime = meta.split("·")[0]?.trim() ?? meta;

  return (
    <div className="relative pl-9 pr-3.5 py-2.5">
      {divider ? (
        <span
          aria-hidden
          className="absolute left-9 right-3.5 top-0 h-px"
          style={{ background: "var(--theme-edge-subtle)" }}
        />
      ) : null}

      <span
        aria-hidden
        className="absolute left-3.5 top-3 inline-flex h-4 w-4 items-center justify-center"
        style={{ color: "var(--theme-ink-faint)" }}
      >
        <SourceGlyph source={source} />
      </span>

      <div className="flex items-baseline gap-2">
        <span
          className="min-w-0 flex-1 truncate text-[15px] leading-tight"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-body)",
            fontWeight: 400,
            letterSpacing: "-0.003em",
          }}
        >
          {title}
        </span>
        <span
          className="flex-none text-[10px] tabular-nums"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            fontWeight: 400,
          }}
        >
          {inlineTime}
        </span>
      </div>

      {preview ? (
        <div
          className="mt-1 truncate text-[13px] leading-snug"
          style={{
            color: "var(--theme-ink-muted)",
            fontFamily: "var(--theme-font-body)",
            fontWeight: 400,
          }}
        >
          {preview}
        </div>
      ) : null}
    </div>
  );
}

function SourceGlyph({ source }: { source: ListRowSource }) {
  if (source === "dictation") {
    // Tiny waveform — sells "audio capture" without being a generic mic.
    return (
      <svg viewBox="0 0 16 16" fill="none" className="h-3.5 w-3.5">
        <g stroke="currentColor" strokeWidth={1} strokeLinecap="round">
          <line x1={2} y1={8} x2={2} y2={8} />
          <line x1={4} y1={6} x2={4} y2={10} />
          <line x1={6} y1={3} x2={6} y2={13} />
          <line x1={8} y1={5} x2={8} y2={11} />
          <line x1={10} y1={2} x2={10} y2={14} />
          <line x1={12} y1={6} x2={12} y2={10} />
          <line x1={14} y1={8} x2={14} y2={8} />
        </g>
      </svg>
    );
  }
  if (source === "typed") {
    // Keyboard glyph — typed capture.
    return (
      <svg viewBox="0 0 16 16" fill="none" className="h-3.5 w-3.5">
        <rect x={2} y={4.5} width={12} height={7} rx={1} stroke="currentColor" strokeWidth={0.9} />
        <g stroke="currentColor" strokeWidth={0.7} strokeLinecap="round">
          <line x1={4} y1={7} x2={4.3} y2={7} />
          <line x1={6.5} y1={7} x2={6.8} y2={7} />
          <line x1={9} y1={7} x2={9.3} y2={7} />
          <line x1={11.5} y1={7} x2={11.8} y2={7} />
          <line x1={5} y1={9.5} x2={11} y2={9.5} />
        </g>
      </svg>
    );
  }
  if (source === "link") {
    // Chain link — clipped from web / share extension.
    return (
      <svg viewBox="0 0 16 16" fill="none" className="h-3.5 w-3.5">
        <path
          d="M 6 9 L 10 5 M 5.2 8.5 a 2.2 2.2 0 0 1 0-3.1 l 1.2-1.2 a 2.2 2.2 0 0 1 3.1 3.1 l-0.5 0.5 M 9.8 6.5 a 2.2 2.2 0 0 1 0 3.1 l-1.2 1.2 a 2.2 2.2 0 0 1-3.1-3.1 l 0.5-0.5"
          stroke="currentColor"
          strokeWidth={0.9}
          strokeLinecap="round"
        />
      </svg>
    );
  }
  // scan
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-3.5 w-3.5">
      <g stroke="currentColor" strokeWidth={0.9} strokeLinecap="round">
        <path d="M 3 5 L 3 3 L 5 3" />
        <path d="M 11 3 L 13 3 L 13 5" />
        <path d="M 3 11 L 3 13 L 5 13" />
        <path d="M 11 13 L 13 13 L 13 11" />
        <line x1={3} y1={8} x2={13} y2={8} />
      </g>
    </svg>
  );
}
