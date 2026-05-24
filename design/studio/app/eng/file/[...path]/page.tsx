import Link from "next/link";
import { notFound } from "next/navigation";
import { CodeViewer } from "@/components/CodeViewer";
import { loadRepoFile } from "@/lib/repo-file";

export const dynamic = "force-dynamic";

export default async function FileViewerPage({
  params,
  searchParams,
}: {
  params: Promise<{ path: string[] }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { path: parts } = await params;
  const { from } = await searchParams;
  const file = await loadRepoFile(parts);
  if (!file) notFound();

  const backHref = from ?? "/eng";
  const backLabel = from?.startsWith("/eng/") ? "← Back to doc" : "← Engineering docs";
  const dir = file.relativePath.includes("/")
    ? file.relativePath.slice(0, file.relativePath.lastIndexOf("/"))
    : "";

  const lines = file.content.split("\n").length;
  const kb = (file.bytes / 1024).toFixed(1);

  return (
    <main className="mx-auto max-w-[1100px] px-7 pt-4 pb-20">
      <nav className="mb-2 font-mono text-[10px] text-studio-ink-faint">
        <Link href={backHref} className="hover:text-studio-ink transition-colors">
          {backLabel}
        </Link>
      </nav>

      <div className="-mx-7 border-y border-studio-edge bg-studio-canvas/95 px-7 py-2.5 font-mono text-[10px]">
        <div className="flex flex-wrap items-baseline gap-3">
          <div className="flex items-baseline gap-1.5 uppercase tracking-eyebrow text-studio-ink-faint">
            <span>File</span>
            {dir ? (
              <>
                <span aria-hidden className="text-studio-ink-faint/40">›</span>
                <span className="normal-case tracking-normal text-studio-ink-faint/85">
                  {dir}
                </span>
              </>
            ) : null}
            <span aria-hidden className="text-studio-ink-faint/40">›</span>
            <span className="text-studio-ink normal-case tracking-normal">
              {file.filename}
            </span>
          </div>
          <span aria-hidden className="h-3 w-px shrink-0 bg-studio-edge" />
          <span className="text-studio-ink-faint">
            {lines.toLocaleString()} lines
          </span>
          <span aria-hidden className="h-3 w-px shrink-0 bg-studio-edge" />
          <span className="text-studio-ink-faint">{kb} KB</span>
          {file.truncated ? (
            <>
              <span aria-hidden className="h-3 w-px shrink-0 bg-studio-edge" />
              <span
                className="rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold tracking-[0.18em]"
                style={{ color: "#7A4A0E", background: "#F5E6CC" }}
              >
                TRUNCATED
              </span>
            </>
          ) : null}
        </div>
      </div>

      <div className="mt-5 overflow-hidden rounded-lg border border-studio-edge">
        <CodeViewer content={file.content} filename={file.filename} />
      </div>
    </main>
  );
}
