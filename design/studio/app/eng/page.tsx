import Link from "next/link";
import { listEngDocs, statusPalette } from "@/lib/eng-docs";

export const dynamic = "force-dynamic";

export default async function EngIndex() {
  const docs = await listEngDocs();

  const byStatus = {
    draft: docs.filter((d) => d.status === "draft").length,
    accepted: docs.filter((d) => d.status === "accepted").length,
    implemented: docs.filter((d) => d.status === "implemented").length,
    deprecated: docs.filter((d) => d.status === "deprecated").length,
  };

  return (
    <main className="mx-auto max-w-page px-7 py-6 pb-16">
      <header className="mb-6 flex items-baseline gap-4 border-b border-studio-edge pb-4 pt-1.5">
        <div>
          <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
            Engineering · TLK series
          </div>
          <h1 className="m-0 font-display text-[28px] font-medium leading-none tracking-tight text-studio-ink">
            Engineering Docs
          </h1>
        </div>
        <div className="ml-auto flex items-baseline gap-3 font-mono text-[10px] text-studio-ink-faint">
          <span>{docs.length} docs</span>
          <Sep />
          <span>{byStatus.draft} draft</span>
          <span>{byStatus.accepted} accepted</span>
          <span>{byStatus.implemented} implemented</span>
          {byStatus.deprecated > 0 ? (
            <span>{byStatus.deprecated} deprecated</span>
          ) : null}
        </div>
      </header>

      <p className="max-w-[640px] font-sans text-[13px] leading-relaxed text-studio-ink-faint mb-8">
        Decision docs for the Talkie codebase. Source of truth lives at{" "}
        <code className="font-mono text-[11px] text-studio-ink">docs/specs/</code>.
        Edits to the markdown files appear here on next request — no copy
        step.
      </p>

      <ul className="grid gap-2">
        {docs.map((d) => {
          const tone = statusPalette(d.status);
          return (
            <li key={d.slug}>
              <Link
                href={`/eng/${d.slug}`}
                className="group block rounded-md border border-studio-edge px-5 py-4 transition-colors hover:border-studio-ink"
              >
                <div className="flex items-baseline gap-3">
                  <span className="font-mono text-[10px] font-semibold tracking-eyebrow text-studio-ink-faint group-hover:text-studio-ink transition-colors">
                    TLK-{String(d.number).padStart(3, "0")}
                  </span>
                  <span className="font-display text-[18px] font-medium tracking-tight text-studio-ink">
                    {d.title}
                  </span>
                  <span
                    className="rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold tracking-[0.18em]"
                    style={{ color: tone.fg, background: tone.bg }}
                  >
                    {tone.label}
                  </span>
                  {d.owner && d.owner !== "TBD" ? (
                    <span className="text-[9.5px] font-mono uppercase tracking-eyebrow text-studio-ink-faint">
                      owner: {d.owner}
                    </span>
                  ) : null}
                </div>
                {d.summary ? (
                  <p className="mt-1.5 ml-[68px] font-sans text-[13px] leading-relaxed text-studio-ink-faint line-clamp-3">
                    {d.summary}
                  </p>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </main>
  );
}

function Sep() {
  return <span aria-hidden className="h-3 w-px shrink-0 bg-studio-edge" />;
}
