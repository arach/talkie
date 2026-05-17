"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const LINKS = [
  { href: "/themes", label: "Themes" },
  { href: "/agent-bay", label: "Agent Bay" },
  { href: "/recording-sheet", label: "Recording Sheet" },
  { href: "/library", label: "Library" },
  { href: "/compose", label: "Compose" },
  { href: "/iphone-themes", label: "iPhone Themes" },
];

export function StudioNav() {
  const pathname = usePathname();
  return (
    <nav className="flex items-center gap-4 border-b border-studio-edge px-7 py-3 font-mono text-[9px] font-semibold uppercase tracking-eyebrow">
      <Link
        href="/"
        className="text-studio-ink-faint transition-colors hover:text-studio-ink"
      >
        · Studio
      </Link>
      {LINKS.map((link) => {
        const active = pathname?.startsWith(link.href);
        return (
          <Link
            key={link.href}
            href={link.href}
            className={cn(
              "border-b border-transparent pb-0.5 transition-colors",
              active
                ? "text-studio-ink border-studio-ink"
                : "text-studio-ink-faint hover:text-studio-ink"
            )}
          >
            {link.label}
          </Link>
        );
      })}
    </nav>
  );
}
