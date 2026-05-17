/**
 * Page chrome shared by every study. Provides:
 *  - max-width wrapper at studio's `--max-w-page`
 *  - top header strip (eyebrow + title + optional help text)
 *
 * Studies pass their own toggle bars + grid as children.
 */

interface StudioPageProps {
  eyebrow: string;
  title: string;
  help?: string;
  children: React.ReactNode;
}

export function StudioPage({ eyebrow, title, help, children }: StudioPageProps) {
  return (
    <main className="mx-auto max-w-page px-7 py-6 pb-16">
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
