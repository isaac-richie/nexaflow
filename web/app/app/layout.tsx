import type { Metadata } from "next";
import Link from "next/link";
import { ConnectButton } from "@/components/app/connect-button";
import { AppNav } from "@/components/app/app-nav";

export const metadata: Metadata = {
  title: "Dashboard",
  description: "Your boards, earnings and stage progress.",
};

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-bg">
      <header className="sticky top-0 z-30 border-b border-line bg-bg/85 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6">
          <Link href="/" className="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 32 32" fill="none" aria-hidden>
              <path
                d="M6 26 C6 18, 16 18, 16 10 M26 26 C26 18, 16 18, 16 10"
                stroke="hsl(var(--gold))"
                strokeWidth="2.2"
                strokeLinecap="round"
              />
              <circle cx="16" cy="7" r="4" fill="hsl(var(--gold-hi))" />
              <circle cx="6" cy="27" r="2.6" fill="hsl(var(--gold))" />
              <circle cx="26" cy="27" r="2.6" fill="hsl(var(--gold))" />
            </svg>
            <span className="font-display text-lg font-bold">
              Nexa<span className="text-gold">Flow</span>
            </span>
          </Link>

          <AppNav variant="inline" />
          <ConnectButton />
        </div>

        {/* On mobile the three destinations move to their own row rather than
            into a menu button, so Join stays one tap away. */}
        <div className="border-t border-line px-4 py-2 md:hidden">
          <AppNav variant="strip" />
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-8 sm:px-6 sm:py-10">
        {children}
      </main>
    </div>
  );
}
