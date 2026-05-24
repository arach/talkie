import Link from "next/link";
import { notFound } from "next/navigation";
import { EngMarkdown } from "@/components/EngMarkdown";
import { EngDocHeader } from "@/components/EngDocHeader";
import { getEngDoc } from "@/lib/eng-docs";
import "../eng-doc.css";

export const dynamic = "force-dynamic";

export default async function EngDocPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const doc = await getEngDoc(slug);
  if (!doc) notFound();

  return (
    <main className="mx-auto max-w-[820px] px-7 pt-4 pb-20">
      <nav className="mb-2 font-mono text-[10px] text-studio-ink-faint">
        <Link href="/eng" className="hover:text-studio-ink transition-colors">
          ← Engineering docs
        </Link>
      </nav>

      <EngDocHeader doc={doc} />

      <div className="mt-8">
        <EngMarkdown body={doc.body} fromSlug={doc.slug} />
      </div>
    </main>
  );
}
