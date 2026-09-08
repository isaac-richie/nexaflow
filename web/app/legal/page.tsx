import type { Metadata } from "next";
import Link from "next/link";
import { Mark } from "@/components/site-nav";
import { CONSENT_VERSION } from "@/lib/consent";
import { IS_V6 } from "@/lib/contracts/config";

export const metadata: Metadata = {
  title: "Legal disclosures",
  description: "NexaFlow participation, risk, privacy and jurisdiction disclosures.",
};

export default function LegalPage() {
  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-30 border-b border-line bg-bg/90 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-4xl items-center justify-between px-5 sm:px-6">
          <Link href="/" className="flex items-center gap-2.5">
            <Mark size={24} />
            <span className="font-display font-bold">Nexa<span className="gold-text">Flow</span></span>
          </Link>
          <Link href="/" className="text-sm text-muted transition-colors hover:text-ink">
            Back to website
          </Link>
        </div>
      </header>

      <main className="mx-auto max-w-4xl px-5 py-10 sm:px-6 sm:py-16">
        <div className="max-w-2xl">
          <div className="label">Consent version {CONSENT_VERSION}</div>
          <h1 className="mt-3 font-display text-3xl font-bold tracking-tight sm:text-4xl">
            Legal disclosures
          </h1>
          <p className="mt-4 text-sm leading-relaxed text-muted sm:text-base">
            Read these disclosures before using NexaFlow or approving a blockchain transaction.
          </p>
        </div>

        <div className="mt-10 space-y-5">
          <Disclosure id="terms" title="Terms of participation">
            <p>You must be at least 18, legally able to participate, and outside every restricted jurisdiction. You are responsible for your wallet, network fees, applicable taxes, and reviewing every transaction before approval.</p>
            <p>NexaFlow stages unlock sequentially beginning with Stage 1. Entry does not guarantee placement activity, completion of a board, earnings, profit, or recovery of fees.</p>
            {IS_V6 ? <p>Royalty bonus, gaming, solar power and prediction market program details remain subject to published eligibility and availability. Joining a stage does not confirm benefit eligibility or product delivery.</p> : <p>The registration package is connected to Fuel Saver. Solar Power benefits connected to Stages 5 and 6 remain subject to eligibility, verification, availability, fulfilment, and the official program conditions. Product delivery is not guaranteed merely because a stage is activated.</p>}
          </Disclosure>

          <Disclosure id="risk" title="Risk and income disclosure">
            <p>Rewards depend on eligible future participation beneath a member. If activity slows or stops, a board may remain partly filled and the member may receive little or nothing.</p>
            <p>NexaFlow does not presently have enough long-term participant data to state typical net earnings. You should therefore assume that you may earn zero and may lose all entry fees and network costs.</p>
            <p>Stage and board figures describe the contract&apos;s gross payment mechanics. They are not forecasts, typical results, investment returns, or promises of profit. Entry fees are non-refundable except where applicable law requires otherwise.</p>
          </Disclosure>

          {IS_V6 && <Disclosure id="v6-reserves" title="V6 re-entry and reserve custody">
            <p>Re-entry reserves are set aside from qualifying participation to fund another board position. They are not an extra cash bonus or a member-withdrawable balance. An incomplete board may retain its reserve indefinitely if qualifying activity stops.</p>
            <p>A single administrator can move all re-entry reserves to an external wallet during emergency recovery, without a second approver. New entries and re-entries then stop until reserves and unpaid payouts are fully backed again. The system cannot force that wallet to return the money; reserves may be unavailable indefinitely.</p>
            <p>Recorded unpaid payouts remain claimable during recovery. A failed direct payout may require a separate claim transaction and network fees. Earlier-version memberships and balances are not automatically transferred into V6.</p>
          </Disclosure>}

          <Disclosure id="blockchain" title="Blockchain and wallet notice">
            <p>NexaFlow operates through smart contracts on BNB Smart Chain and uses USDT for entry payments. Confirmed blockchain transactions are generally irreversible.</p>
            <p>You retain responsibility for your wallet, recovery phrase, private keys, device security, network selection, transaction details, and gas fees. NexaFlow will never ask for your recovery phrase or private key.</p>
          </Disclosure>

          <Disclosure id="jurisdictions" title="Restricted jurisdictions">
            <p>US residents and persons accessing from the United States may not participate.</p>
            <p>Participation is also prohibited from any country or territory where network-marketing programs, blockchain membership programs, digital-asset activity, USDT transactions, or this compensation structure are restricted or unlawful, as well as territories subject to applicable comprehensive sanctions.</p>
            <p>Restrictions can change. You are responsible for confirming that participation is lawful where you reside and where you access the platform. This section must be read together with the official lawyer-approved jurisdiction list when published.</p>
          </Disclosure>

          <Disclosure id="privacy" title="Privacy notice">
            <p>The website reads public blockchain information associated with the wallet you connect. Wallet addresses and transactions on a public blockchain are publicly visible and cannot be made private by NexaFlow.</p>
            <p>The website stores the consent version and acceptance time in your browser. Wallet, RPC, hosting, analytics, and other service providers may process technical information under their own policies.</p>
            <p>Consent to optional marketing must be requested separately. Declining marketing must not prevent access to the platform, and any marketing consent must be capable of withdrawal.</p>
          </Disclosure>
        </div>

        <div className="mt-10 rounded-xl border border-gold/20 bg-gold/5 p-4 text-xs leading-relaxed text-muted">
          These disclosures are written in plain language for community access. They do not replace independent legal, tax, or financial advice.
        </div>
      </main>
    </div>
  );
}

function Disclosure({ id, title, children }: { id: string; title: string; children: React.ReactNode }) {
  return (
    <section id={id} className="panel scroll-mt-24 p-5 sm:p-7">
      <h2 className="font-display text-lg font-semibold sm:text-xl">{title}</h2>
      <div className="mt-4 space-y-3 text-sm leading-relaxed text-muted">{children}</div>
    </section>
  );
}
