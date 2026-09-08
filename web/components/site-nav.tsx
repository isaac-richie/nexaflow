"use client";

import Link from "next/link";

import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useState } from "react";

// Must stay in sync with the section ids in app/page.tsx. The old list still
// pointed at #how and #network after those sections were merged away, which
// left two links that scrolled nowhere.
const LINKS = [
  { href: "#how", label: "How it works" },
  { href: "#stages", label: "Stages" },
  { href: "#security", label: "Security" },
];

export function SiteNav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  // Lock the page behind the mobile sheet so it doesn't scroll underneath.
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <header
      className={`safe-x fixed inset-x-0 top-0 z-50 transition-all duration-300 ${
        scrolled
          ? "border-b border-line bg-bg/85 backdrop-blur-xl"
          : "border-b border-transparent"
      }`}
    >
      <nav
        className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5 sm:px-6"
        aria-label="Primary"
      >
        <a href="#top" className="flex items-center gap-2.5" onClick={() => setOpen(false)}>
          <Mark />
          <span className="font-display text-[17px] font-bold tracking-tight">
            Nexa<span className="gold-text">Flow</span>
          </span>
        </a>

        <div className="hidden items-center gap-9 md:flex">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="relative text-sm text-muted transition-colors hover:text-ink"
            >
              {l.label}
            </a>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <Link href="/app" className="btn-gold hidden px-5 py-2 text-sm md:inline-flex">
            Launch App
          </Link>

          <button
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-label={open ? "Close menu" : "Open menu"}
            className="grid h-10 w-10 place-items-center rounded-lg border border-line bg-surface-2 md:hidden"
          >
            <span className="relative block h-3.5 w-4">
              <motion.span
                className="absolute left-0 block h-[1.5px] w-full rounded bg-ink"
                animate={open ? { rotate: 45, top: "50%" } : { rotate: 0, top: 0 }}
                transition={{ duration: 0.25 }}
              />
              <motion.span
                className="absolute left-0 top-1/2 block h-[1.5px] w-full rounded bg-ink"
                animate={{ opacity: open ? 0 : 1 }}
                transition={{ duration: 0.15 }}
              />
              <motion.span
                className="absolute left-0 block h-[1.5px] w-full rounded bg-ink"
                animate={open ? { rotate: -45, bottom: "50%" } : { rotate: 0, bottom: 0 }}
                transition={{ duration: 0.25 }}
              />
            </span>
          </button>
        </div>
      </nav>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.22 }}
            className="border-t border-line bg-bg/98 px-5 pb-8 pt-4 backdrop-blur-xl md:hidden"
          >
            <div className="flex flex-col">
              {LINKS.map((l, i) => (
                <motion.a
                  key={l.href}
                  href={l.href}
                  onClick={() => setOpen(false)}
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.04 * i + 0.05 }}
                  className="border-b border-line py-4 text-base text-ink"
                >
                  {l.label}
                </motion.a>
              ))}
              <Link href="/app" onClick={() => setOpen(false)} className="btn-gold mt-6 w-full py-3.5">Launch App</Link>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  );
}

/**
 * NexaFlow brand mark: the "N" with its right leg extended as an upward
 * arrow — the letterform IS the bullish trend. Inlined (not <Image src=".."/>)
 * so it ships in the same paint as the header, with no request or layout shift.
 */
export function Mark({ size = 28 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 64 64"
      fill="none"
      aria-hidden="true"
      className="shrink-0"
    >
      <defs>
        <linearGradient id="nf-mark-gold" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#FCD535" />
          <stop offset="100%" stopColor="#F0B90B" />
        </linearGradient>
        <linearGradient id="nf-mark-gold-hi" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#FFE066" />
          <stop offset="55%" stopColor="#FCD535" />
          <stop offset="100%" stopColor="#E0A800" />
        </linearGradient>
        <linearGradient id="nf-mark-sheen" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#ffffff" stopOpacity="0.30" />
          <stop offset="45%" stopColor="#ffffff" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d="M8 10 h11 v46 h-11 z" fill="url(#nf-mark-gold-hi)" />
      <path d="M19 10 h9 l17 32 v14 h-9 l-17 -32 z" fill="url(#nf-mark-gold)" />
      <path d="M45 22 h11 v34 h-11 z M39 22 h23 l-11.5 -18 z" fill="url(#nf-mark-gold-hi)" />
      <path
        d="M8 10 h11 v3 h-11 z M39 22 h23 l-3.5 -5 h-16 z"
        fill="url(#nf-mark-sheen)"
      />
    </svg>
  );
}
