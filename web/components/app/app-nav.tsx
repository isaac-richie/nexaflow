"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/format";

const LINKS = [
  { href: "/app", label: "Dashboard" },
  { href: "/app/join", label: "Join" },
  { href: "/app/board", label: "My Board" },
];

/**
 * App navigation.
 *
 * Rendered inline in the header on desktop and as a full-width strip beneath it
 * on mobile. It is deliberately never hidden behind a menu button: with only
 * three destinations, burying them costs a tap and hides the fact that Join
 * exists — which is the one route a new member needs to find.
 */
export function AppNav({ variant }: { variant: "inline" | "strip" }) {
  const pathname = usePathname();

  return (
    <nav
      className={cn(
        variant === "inline"
          ? "hidden items-center gap-1 md:flex"
          : "flex items-center gap-1 overflow-x-auto md:hidden",
      )}
      aria-label="Application"
    >
      {LINKS.map((l) => {
        // Exact match for the index, or /app/join would also light up /app.
        const active =
          l.href === "/app" ? pathname === "/app" : pathname.startsWith(l.href);

        return (
          <Link
            key={l.href}
            href={l.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "whitespace-nowrap rounded-lg px-3 py-1.5 text-sm font-medium transition-colors",
              active ? "bg-surface-2 text-ink" : "text-muted hover:text-ink",
            )}
          >
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}
