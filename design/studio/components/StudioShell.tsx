"use client";

import { useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { StudioSidebar } from "@/components/StudioSidebar";
import { PageStrip } from "@/components/PageStrip";

/**
 * Top-level shell — persistent sidebar + per-page header strip.
 *
 * Persistence rule: chrome is ALWAYS rendered by default. Pages that
 * want a full-bleed canvas opt out explicitly via `?focus=1` (or the
 * underlying `?focus=true`). The previous nav strip would silently
 * disappear on some surfaces and force a back-button trip — this
 * shell prevents that by being the layout, not a sibling of it.
 */
export function StudioShell({ children }: { children: React.ReactNode }) {
  return (
    <Suspense fallback={<ShellFallback>{children}</ShellFallback>}>
      <ShellInner>{children}</ShellInner>
    </Suspense>
  );
}

function ShellInner({ children }: { children: React.ReactNode }) {
  const params = useSearchParams();
  const focusMode = params.get("focus") === "1" || params.get("focus") === "true";

  if (focusMode) {
    // Intentional escape hatch — page renders without sidebar / strip.
    // Useful for fullscreen screenshots or presentation mode.
    return <main className="min-h-screen">{children}</main>;
  }

  return (
    <div className="min-h-screen">
      <StudioSidebar />
      <div className="ml-[220px] flex min-h-screen flex-col">
        <PageStrip />
        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}

/** Server-render-safe fallback used before client hydration resolves
 *  the focus-mode query. Renders the same shell unconditionally so
 *  there's no hydration jank or content shift. */
function ShellFallback({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen">
      <StudioSidebar />
      <div className="ml-[220px] flex min-h-screen flex-col">
        <PageStrip />
        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}
