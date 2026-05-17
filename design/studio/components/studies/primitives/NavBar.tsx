/**
 * iOS modal nav bar — left action · centered title · right action.
 * All theme-aware. Title uses display face at theme weight/tracking.
 *
 * Both left/right actions are optional and accept any node; pass
 * a button, a pill, or a small icon glyph.
 */

interface NavBarProps {
  left?: React.ReactNode;
  title: string;
  right?: React.ReactNode;
}

export function NavBar({ left, title, right }: NavBarProps) {
  return (
    <div
      className="relative flex items-center justify-between px-4"
      style={{ height: 46, background: "var(--theme-canvas)" }}
    >
      <div className="flex-1">{left}</div>
      <h1
        className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 m-0 text-[17px] font-semibold leading-none"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-display)",
          letterSpacing: "-0.022em",
        }}
      >
        {title}
      </h1>
      <div className="flex flex-1 justify-end">{right}</div>
    </div>
  );
}

/**
 * Pill-shaped nav action — used for Done / Copy / etc.
 * Takes its background from --theme-paper so it reads as
 * a tactile button sitting on the canvas.
 */
export function NavPill({
  children,
  accent = false,
}: {
  children: React.ReactNode;
  accent?: boolean;
}) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-3 py-1 text-[13px] font-medium"
      style={{
        background: "var(--theme-paper)",
        color: accent ? "var(--theme-amber)" : "var(--theme-ink-dim)",
        boxShadow: "0 1px 2px rgba(0,0,0,0.04), inset 0 0 0 0.5px var(--theme-edge-faint)",
        fontFamily: "var(--theme-font-body)",
      }}
    >
      {children}
    </span>
  );
}
