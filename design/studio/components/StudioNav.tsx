"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

interface NavLink {
  href: string;
  label: string;
}

interface NavGroup {
  label: string | null;
  links: NavLink[];
}

// Groups read left → right as the design journey: foundations, then
// the iPhone surfaces (older but still alive), then the Mac family
// (the active surface). Coverage lands separately at the far right
// as a destination, not part of the design journey.
const GROUPS: NavGroup[] = [
  {
    label: "Foundations",
    links: [
      { href: "/themes", label: "Themes" },
      { href: "/complications", label: "Complications" },
    ],
  },
  {
    label: "iPhone",
    links: [
      { href: "/home", label: "Home" },
      { href: "/library", label: "Library" },
      { href: "/compose", label: "Compose" },
      { href: "/recording-sheet", label: "Recording" },
      { href: "/agent-bay", label: "Agent Bay" },
      { href: "/iphone-themes", label: "Themes" },
    ],
  },
  {
    label: "Mac",
    links: [
      { href: "/mac-home", label: "Home" },
      { href: "/mac-home-wide", label: "Home Wide" },
      { href: "/mac-library", label: "Library" },
      { href: "/mac-library-empty", label: "Library Empty" },
      { href: "/mac-memo-detail", label: "Memo" },
      { href: "/mac-memo-wide", label: "Memo Wide" },
      { href: "/mac-dictation-wide", label: "Dictation" },
      { href: "/mac-dictation-detail", label: "Dictation Detail" },
      { href: "/mac-compose", label: "Compose" },
      { href: "/mac-notes", label: "Notes" },
      { href: "/mac-note-detail", label: "Note Detail" },
      { href: "/mac-capture-detail", label: "Capture Detail" },
      { href: "/mac-capture-hud", label: "Capture HUD" },
      { href: "/mac-onboarding", label: "Onboarding" },
      { href: "/mac-recording-state", label: "Recording" },
      { href: "/mac-record-to-memo", label: "Rec → Memo" },
      { href: "/mac-talkie-button", label: "Talkie Btn" },
      { href: "/mac-notch-settings", label: "Notch" },
    ],
  },
];

const COVERAGE: NavLink = { href: "/mac-coverage", label: "Coverage" };

export function StudioNav() {
  const pathname = usePathname();
  return (
    <nav className="flex items-baseline gap-5 overflow-x-auto border-b border-studio-edge px-7 py-2.5 font-mono text-[9px] font-semibold uppercase tracking-eyebrow">
      {/* Brand */}
      <Link
        href="/"
        className="shrink-0 text-studio-ink-faint transition-colors hover:text-studio-ink"
      >
        · Studio
      </Link>

      <Sep />

      {GROUPS.map((group, gi) => (
        <div key={gi} className="flex shrink-0 items-baseline gap-3.5">
          {group.label ? (
            <span className="text-[8px] tracking-[0.22em] text-studio-ink-faint/60">
              {group.label}
            </span>
          ) : null}
          {group.links.map((link) => (
            <NavItem key={link.href} link={link} pathname={pathname} />
          ))}
          {gi < GROUPS.length - 1 ? <Sep /> : null}
        </div>
      ))}

      {/* Coverage — separated CTA at the far right */}
      <div className="ml-auto flex shrink-0 items-baseline gap-3">
        <Sep />
        <CoverageCTA link={COVERAGE} pathname={pathname} />
      </div>
    </nav>
  );
}

function NavItem({
  link,
  pathname,
}: {
  link: NavLink;
  pathname: string | null;
}) {
  const active = pathname === link.href;
  return (
    <Link
      href={link.href}
      className={cn(
        "border-b border-transparent pb-0.5 transition-colors",
        active
          ? "border-studio-ink text-studio-ink"
          : "text-studio-ink-faint hover:text-studio-ink"
      )}
    >
      {link.label}
    </Link>
  );
}

function CoverageCTA({
  link,
  pathname,
}: {
  link: NavLink;
  pathname: string | null;
}) {
  const active = pathname === link.href;
  return (
    <Link
      href={link.href}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-[3px] border px-2 py-1 transition-colors",
        active
          ? "border-[#232423] bg-[#ECECEB] text-[#232423]"
          : "border-[#DEDEDD] text-studio-ink-faint hover:border-[#9A6A22] hover:text-[#9A6A22]"
      )}
    >
      <span
        aria-hidden
        className="h-1.5 w-1.5 rounded-full"
        style={{ background: "#9A6A22" }}
      />
      {link.label}
    </Link>
  );
}

function Sep() {
  return (
    <span
      aria-hidden
      className="h-3 w-px shrink-0 bg-studio-edge"
    />
  );
}
