"use client";

import { ACTIVE_CHAIN, MEMBERSHIP_ADDRESS } from "@/lib/contracts/config";
import { ConnectButton } from "./connect-button";

/**
 * The "we have nothing real to show you" states.
 *
 * Each one says what is true and what to do next. A dashboard that renders
 * zeroes when it simply cannot reach a contract teaches members to distrust
 * every number on it, so these are deliberately explicit.
 */

export function NotDeployedNotice() {
  return (
    <div className="panel panel-sheen p-6 sm:p-8">
      <div className="flex items-start gap-4">
        <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gold/12">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden>
            <path
              d="M12 8v5M12 16.5v.5"
              stroke="hsl(var(--gold))"
              strokeWidth="2"
              strokeLinecap="round"
            />
            <circle cx="12" cy="12" r="9" stroke="hsl(var(--gold))" strokeWidth="1.6" />
          </svg>
        </div>
        <div>
          <h2 className="font-display text-lg font-semibold">
            Contract not deployed yet
          </h2>
          <p className="mt-1.5 max-w-lg text-sm leading-relaxed text-muted">
            The membership contract has no address on {ACTIVE_CHAIN.name} yet, so
            there is nothing to read. This dashboard is wired and will populate
            the moment a deployment address is configured. No figures are shown
            until then, because any number here would be fabricated.
          </p>
          <div className="mt-4 rounded-lg border border-line bg-surface-2 px-3 py-2">
            <div className="text-[11px] uppercase tracking-wider text-faint">
              Configured address
            </div>
            <code className="font-mono text-xs text-muted">
              {MEMBERSHIP_ADDRESS}
            </code>
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * Deployed and configured, but not yet accepting members.
 *
 * `stageAnchor(0)` is still zero until the designated root registers. Every
 * join would revert until then, so the app says so plainly rather than offering
 * a form that fails and letting the user think their wallet is at fault.
 */
export function ProtocolNotOpenNotice() {
  return (
    <div className="panel panel-sheen p-6 sm:p-8">
      <div className="flex items-start gap-4">
        <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gold/12">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden>
            <circle cx="12" cy="12" r="9" stroke="hsl(var(--gold))" strokeWidth="1.6" />
            <path
              d="M12 7v5l3 2"
              stroke="hsl(var(--gold))"
              strokeWidth="1.8"
              strokeLinecap="round"
            />
          </svg>
        </div>
        <div>
          <h2 className="font-display text-lg font-semibold">
            Registration is not open yet
          </h2>
          <p className="mt-1.5 max-w-lg text-sm leading-relaxed text-muted">
            The contract is live on {ACTIVE_CHAIN.name} and fully configured, but
            the first position has not been created yet, so there is nowhere to
            place a new member. Joining will open as soon as it is.
          </p>
          <a
            href={`https://bscscan.com/address/${MEMBERSHIP_ADDRESS}`}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-4 inline-flex items-center gap-1.5 text-sm text-gold hover:underline"
          >
            View the contract on BscScan
            <span aria-hidden>↗</span>
          </a>
        </div>
      </div>
    </div>
  );
}

/**
 * Pricing is temporarily unavailable.
 *
 * Entry amounts are quoted from a TWAP oracle that has to be advanced on a
 * schedule. When the last update is older than `maxPriceAge` the contract
 * refuses to quote, so no amount can be shown and no join can succeed. Saying
 * that plainly beats an empty form or a wallet-level revert, both of which
 * read as a broken product.
 */
export function PriceUnavailableNotice() {
  return (
    <div className="panel p-6 sm:p-8">
      <div className="flex items-start gap-4">
        <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gold/12">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden>
            <circle cx="12" cy="12" r="9" stroke="hsl(var(--gold))" strokeWidth="1.6" />
            <path
              d="M12 7.5v5l3 1.8"
              stroke="hsl(var(--gold))"
              strokeWidth="1.8"
              strokeLinecap="round"
            />
          </svg>
        </div>
        <div>
          <h2 className="font-display text-lg font-semibold">
            Pricing is refreshing
          </h2>
          <p className="mt-1.5 max-w-lg text-sm leading-relaxed text-muted">
            Entry amounts are quoted live in {" "}
            <span className="text-ink">RWAAN</span> from an on-chain price
            feed. That feed is between updates right now, so the contract will
            not quote an amount, and joining is paused until it refreshes.
          </p>
          <p className="mt-3 max-w-lg text-sm leading-relaxed text-muted">
            Nothing is wrong with your wallet and no funds are affected. Check
            back shortly.
          </p>
        </div>
      </div>
    </div>
  );
}

export function ConnectPrompt() {
  return (
    <div className="panel panel-sheen flex flex-col items-center p-10 text-center sm:p-14">
      <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gold/12">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
          <path
            d="M3 8.5A2.5 2.5 0 015.5 6H18a2 2 0 012 2v1"
            stroke="hsl(var(--gold))"
            strokeWidth="1.7"
            strokeLinecap="round"
          />
          <rect
            x="3"
            y="9"
            width="18"
            height="9"
            rx="2"
            stroke="hsl(var(--gold))"
            strokeWidth="1.7"
          />
          <circle cx="16.5" cy="13.5" r="1.3" fill="hsl(var(--gold))" />
        </svg>
      </div>
      <h2 className="mt-4 font-display text-xl font-semibold">
        Connect your wallet
      </h2>
      <p className="mt-2 max-w-sm text-sm leading-relaxed text-muted">
        Your boards, earnings and stage progress are read from your wallet
        address. Nothing is stored on our side.
      </p>
      <ConnectButton className="mt-6" />
    </div>
  );
}

export function NotRegisteredNotice() {
  return (
    <div className="panel panel-sheen p-6 sm:p-8">
      <h2 className="font-display text-lg font-semibold">
        This wallet is not a member yet
      </h2>
      <p className="mt-1.5 max-w-lg text-sm leading-relaxed text-muted">
        You need a sponsor&rsquo;s referral to join. Once you register at Stage 1
        your board opens and this dashboard fills in.
      </p>
      <a href="/app/join" className="btn-gold mt-5 inline-flex px-5 py-2.5 text-sm">
        Join NexaFlow
      </a>
    </div>
  );
}

export function LoadingPanel({ label = "Reading chain…" }: { label?: string }) {
  return (
    <div className="panel flex items-center justify-center gap-3 p-10 text-sm text-muted">
      <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-line border-t-gold" />
      {label}
    </div>
  );
}
