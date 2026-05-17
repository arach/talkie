/**
 * iOS status bar — time / dynamic-island notch / signal / wifi /
 * battery. Pure presentational; reads `--theme-ink` for ink color
 * so it inverts correctly on dark themes.
 */

export function StatusBar({ time = "9:41" }: { time?: string }) {
  return (
    <div
      className="relative flex items-center justify-between px-5 pt-2 pb-1.5 text-[12px] font-semibold"
      style={{
        color: "var(--theme-ink)",
        fontFamily: "-apple-system, 'SF Pro Display', sans-serif",
        height: 38,
      }}
    >
      <span>{time}</span>
      <span
        className="absolute left-1/2 top-1 -translate-x-1/2 rounded-[14px]"
        style={{ width: 88, height: 22, background: "#000" }}
      />
      <span className="flex items-center gap-1.5">
        <SignalBars />
        <WifiGlyph />
        <Battery />
      </span>
    </div>
  );
}

function SignalBars() {
  return (
    <span className="inline-flex items-end gap-[1.5px]" style={{ height: 10 }}>
      {[3, 5, 7, 10].map((h, i) => (
        <i
          key={i}
          className="block w-[2.5px] rounded-[0.5px]"
          style={{ height: h, background: "var(--theme-ink)" }}
        />
      ))}
    </span>
  );
}

function WifiGlyph() {
  return (
    <svg
      width={13}
      height={9}
      viewBox="0 0 16 11"
      fill="none"
      style={{ color: "var(--theme-ink)" }}
    >
      <path
        d="M8 9.5a.9.9 0 100-1.8.9.9 0 000 1.8zM4 6.2a5.5 5.5 0 018 0M2 4a8.5 8.5 0 0112 0"
        stroke="currentColor"
        strokeWidth={1.1}
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}

function Battery() {
  return (
    <span
      className="relative inline-block rounded-[3px] p-[1.5px]"
      style={{
        width: 22,
        height: 11,
        border: "1px solid var(--theme-ink)",
      }}
    >
      <span
        className="block h-full rounded-[1px]"
        style={{ width: "76%", background: "#5fc97a" }}
      />
      <span
        className="absolute"
        style={{
          right: -3,
          top: 3,
          width: 1.5,
          height: 5,
          background: "var(--theme-ink)",
          borderRadius: "0 1px 1px 0",
        }}
      />
    </span>
  );
}
