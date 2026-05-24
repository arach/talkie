"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { cn } from "@/lib/utils";
import {
  STUDIO_PAGES,
  familyGroups,
  pagesByPlatform,
  platformLabel,
  type StudioBucket,
  type StudioPage,
} from "@/lib/studio-pages";

/**
 * Persistent left sidebar. Three buckets — Foundations / Surfaces /
 * Lab — with Surfaces sub-grouped by platform. Variants of the same
 * family collapse under their primary page; click the primary to
 * navigate, click the chevron to expand the variant list.
 *
 * Width is locked at 220pt to mirror the Mac app's own donor sidebar.
 */
export function StudioSidebar() {
  const pathname = usePathname();

  return (
    <aside
      className={cn(
        "fixed left-0 top-0 z-30 flex h-screen w-[220px] flex-col",
        "border-r border-studio-edge bg-studio-canvas",
        "overflow-y-auto"
      )}
    >
      <SidebarHeader />

      <nav className="flex flex-col gap-7 px-4 pb-10 pt-3 font-mono text-[10.5px]">
        <BucketSection title="Foundations" bucket="foundations" pathname={pathname} />
        <BucketSection title="Surfaces" bucket="surfaces" pathname={pathname} platformGrouped />
        <BucketSection title="Lab" bucket="lab" pathname={pathname} />
      </nav>

      <SidebarFooter />
    </aside>
  );
}

function SidebarHeader() {
  return (
    <div className="flex items-center gap-2 border-b border-studio-edge px-4 py-3.5">
      <div
        aria-hidden
        className="h-2 w-2 rounded-full"
        style={{ background: "#9A6A22" }}
      />
      <Link
        href="/"
        className="font-mono text-[10px] font-semibold uppercase tracking-eyebrow text-studio-ink"
      >
        Studio
      </Link>
    </div>
  );
}

function SidebarFooter() {
  return (
    <div className="mt-auto border-t border-studio-edge px-4 py-3 font-mono text-[8.5px] uppercase tracking-eyebrow text-studio-ink-faint/60">
      <span>Talkie</span>
      <span className="mx-1.5">·</span>
      <span>{STUDIO_PAGES.length} pages</span>
    </div>
  );
}

function BucketSection({
  title,
  bucket,
  pathname,
  platformGrouped = false,
}: {
  title: string;
  bucket: StudioBucket;
  pathname: string | null;
  platformGrouped?: boolean;
}) {
  return (
    <section>
      <SectionTitle>{title}</SectionTitle>
      <div className="mt-1.5 flex flex-col gap-3">
        {platformGrouped ? (
          pagesByPlatform(bucket).map(({ platform, pages }) => (
            <PlatformBlock
              key={platform}
              label={platformLabel(platform)}
              groups={familyGroups(pages)}
              pathname={pathname}
            />
          ))
        ) : (
          <div className="flex flex-col">
            {familyGroups(
              STUDIO_PAGES.filter((p) => p.bucket === bucket)
            ).map((group) => (
              <PageItem key={group.primary.href} group={group} pathname={pathname} />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink-faint/70">
      · {children}
    </h2>
  );
}

function PlatformBlock({
  label,
  groups,
  pathname,
}: {
  label: string;
  groups: ReturnType<typeof familyGroups>;
  pathname: string | null;
}) {
  return (
    <div>
      <h3 className="mb-1 font-mono text-[8.5px] uppercase tracking-[0.20em] text-studio-ink-faint/55">
        {label}
      </h3>
      <div className="flex flex-col">
        {groups.map((group) => (
          <PageItem key={group.primary.href} group={group} pathname={pathname} />
        ))}
      </div>
    </div>
  );
}

function PageItem({
  group,
  pathname,
}: {
  group: { primary: StudioPage; variants: StudioPage[] };
  pathname: string | null;
}) {
  const { primary, variants } = group;
  const hasVariants = variants.length > 0;
  const activeHere = primary.href === pathname;
  const variantActive = variants.some((v) => v.href === pathname);
  const [expanded, setExpanded] = useState(activeHere || variantActive);

  return (
    <div>
      <div className="flex items-center">
        <SidebarLink href={primary.href} active={activeHere} className="flex-1">
          <span className="flex-1 truncate">{primary.label}</span>
          {primary.status === "wip" ? (
            <Dot title="WIP" color="#C47D1C" />
          ) : primary.status === "concept" ? (
            <Dot title="Concept" color="#76767A" />
          ) : null}
        </SidebarLink>
        {hasVariants ? (
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className={cn(
              "ml-1 grid h-5 w-5 place-items-center rounded-[3px]",
              "text-studio-ink-faint hover:text-studio-ink hover:bg-studio-canvas-alt"
            )}
            aria-label={expanded ? "Collapse variants" : "Expand variants"}
          >
            <span className="text-[9px]">{expanded ? "−" : "+"}</span>
          </button>
        ) : null}
      </div>
      {hasVariants && expanded ? (
        <div className="ml-3 flex flex-col border-l border-studio-edge/70 pl-2.5">
          {variants.map((v) => (
            <SidebarLink
              key={v.href}
              href={v.href}
              active={v.href === pathname}
              muted
            >
              <span className="flex-1 truncate">{v.label}</span>
              {v.status === "wip" ? (
                <Dot title="WIP" color="#C47D1C" />
              ) : v.status === "concept" ? (
                <Dot title="Concept" color="#76767A" />
              ) : null}
            </SidebarLink>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function SidebarLink({
  href,
  active,
  muted,
  className,
  children,
}: {
  href: string;
  active: boolean;
  muted?: boolean;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className={cn(
        "flex items-center gap-1.5 rounded-[3px] px-2 py-1 transition-colors",
        active
          ? "bg-studio-canvas-alt text-studio-ink"
          : muted
            ? "text-studio-ink-faint/85 hover:bg-studio-canvas-alt/60 hover:text-studio-ink"
            : "text-studio-ink-faint hover:bg-studio-canvas-alt/60 hover:text-studio-ink",
        className
      )}
    >
      {children}
    </Link>
  );
}

function Dot({ color, title }: { color: string; title: string }) {
  return (
    <span
      aria-label={title}
      title={title}
      className="h-1.5 w-1.5 shrink-0 rounded-full"
      style={{ background: color }}
    />
  );
}
