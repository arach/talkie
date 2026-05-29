/**
 * Page chrome shared by every study. Provides:
 *  - max-width wrapper at studio's `--max-w-page`
 *  - top header strip (eyebrow + title + optional help text)
 *  - optional back link rendered above the title for detail surfaces
 *
 * Studies pass their own toggle bars + grid as children.
 */

import Link from "next/link";

interface StudioPageProps {
  eyebrow: string;
  title: string;
  help?: string;
  back?: { href: string; label: string };
  children: React.ReactNode;
}

export function StudioPage({ eyebrow, title, help, back, children }: StudioPageProps) {
  return (
    <main className="mx-auto max-w-page px-7 py-6 pb-16">
      {back ? (
        <Link
          href={back.href}
          className="mb-4 inline-flex items-center gap-1.5 rounded-[4px] border border-studio-edge bg-white px-2.5 py-1 font-mono text-[11px] font-semibold uppercase tracking-[0.12em] text-studio-ink-faint transition-colors hover:border-studio-ink hover:text-studio-ink"
        >
          <span aria-hidden className="text-[13px] leading-none">←</span>
          <span>{back.label}</span>
        </Link>
      ) : null}
      <header className="mb-5 flex items-baseline gap-4 border-b border-studio-edge pb-4 pt-1.5">
        <div>
          <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
            {eyebrow}
          </div>
          <h1 className="m-0 font-display text-[28px] font-medium leading-none tracking-tight text-studio-ink">
            {title}
          </h1>
        </div>
        {help ? (
          <div className="ml-auto text-[10px] tracking-[0.12em] text-studio-ink-faint">
            {help}
          </div>
        ) : null}
      </header>
      {children}
    </main>
  );
}
