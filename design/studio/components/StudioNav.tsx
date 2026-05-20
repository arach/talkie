"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const LINKS = [
  { href: "/themes", label: "Themes" },
  { href: "/complications", label: "Complications" },
  { href: "/home", label: "Home" },
  { href: "/library", label: "Library" },
  { href: "/compose", label: "Compose" },
  { href: "/recording-sheet", label: "Recording Sheet" },
  { href: "/agent-bay", label: "Agent Bay" },
  { href: "/iphone-themes", label: "iPhone Themes" },
  { href: "/mac-home", label: "Mac · Home" },
  { href: "/mac-home-wide", label: "Mac · Home Wide" },
  { href: "/mac-memo-wide", label: "Mac · Memo Wide" },
  { href: "/mac-dictation-wide", label: "Mac · Dictation Wide" },
  { href: "/mac-library", label: "Mac · Library" },
  { href: "/mac-compose", label: "Mac · Compose" },
  { href: "/mac-memo-detail", label: "Mac · Memo Detail" },
  { href: "/mac-talkie-button", label: "Mac · Talkie Button" },
  { href: "/mac-recording-state", label: "Mac · Recording" },
  { href: "/mac-record-to-memo", label: "Mac · Record → Memo" },
  { href: "/mac-library-empty", label: "Mac · Library Empty" },
  { href: "/mac-notch-settings", label: "Mac · Notch Settings" },
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
