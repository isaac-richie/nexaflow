import type { Metadata } from "next";
import Link from "next/link";
import { ConnectButton } from "@/components/app/connect-button";
import { AppNav } from "@/components/app/app-nav";
import { Mark } from "@/components/site-nav";
import { V5ReleaseNotice } from "@/components/app/v5-release-notice";
import styles from "@/components/app/member-ui.module.css";

export const metadata: Metadata = {
  title: "Dashboard",
  description: "Your boards, earnings and stage progress.",
};

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={styles.shell}>
      <a href="#member-content" className={styles.skip}>Skip to content</a>
      <aside className={styles.sidebar}>
          <Link href="/" className={styles.brand}>
            <Mark size={26} />
            <span className="font-display text-lg font-bold">
              Nexa<span className="text-gold">Flow</span>
            </span>
          </Link>

          <AppNav variant="inline" />
          <div className={styles.sidebarNote}><strong>Your journey, in view.</strong>Boards, progress and the people you bring together.</div>
      </aside>
      <div className={styles.workspace}>
      <header className={styles.header}>
          <span className={styles.headerLabel}>NexaFlow / Member space</span>
          <div className={styles.mobileBrand}><Link href="/" className={styles.brand}><Mark size={24}/><span>Nexa<span>Flow</span></span></Link></div>
          <ConnectButton />
      </header>

      <main id="member-content" tabIndex={-1} className={styles.main}>
        <V5ReleaseNotice />
        {children}
      </main>

      <footer className={styles.footer}>
        Participation and earnings involve risk.{" "}
        <Link href="/legal" className="text-muted underline underline-offset-2 hover:text-ink">
          Legal disclosures
        </Link>
      </footer>
      </div>
      <AppNav variant="strip" />
    </div>
  );
}
