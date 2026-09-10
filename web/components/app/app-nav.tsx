"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import styles from "./member-ui.module.css";

const LINKS = [
  { href: "/app", label: "Overview", path: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z" },
  { href: "/app/board", label: "My boards", path: "M9 3h6v5H9z M2 16h6v5H2z M16 16h6v5h-6z M12 8v4M5 16v-4h14v4" },
  { href: "/app/network", label: "Network", path: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M16 3a4 4 0 0 1 0 8 M22 21v-2a4 4 0 0 0-3-3.9 M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0" },
  { href: "/app/join", label: "Join / unlock", path: "M12 5v14M5 12h14" },
];

/**
 * App navigation.
 *
 * Desktop sidebar and safe-area-aware mobile bottom bar. Join remains visible;
 * prefetched wallet routes are disabled to avoid unnecessary route downloads.
 */
export function AppNav({ variant }: { variant: "inline" | "strip" }) {
  const pathname = usePathname();

  return (
    <nav
      className={variant === "inline" ? styles.nav : styles.bottomNav}
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
            prefetch={false}
            aria-current={active ? "page" : undefined}
            className={styles.navLink}
          >
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={l.path} /></svg>
            <span>{l.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
