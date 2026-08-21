"use client";

import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import { getAddress, isAddress } from "viem";
import {
  IS_DEPLOYED,
  STAGE_PRESETS,
  ACTIVE_CHAIN,
  MEMBERSHIP_ADDRESS,
} from "@/lib/contracts/config";
import {
  useOraclePriceHealth,
  useMember,
  usePlacementSlot,
  useProtocolOpen,
  useStageConfig,
  useStagePaymentQuote,
} from "@/hooks/use-membership";
import { useJoin } from "@/hooks/use-join";
import {
  ConnectPrompt,
  LoadingPanel,
  NotDeployedNotice,
  ProtocolNotOpenNotice,
  PriceUnavailableNotice,
} from "@/components/app/states";
import { formatToken, shortAddress } from "@/lib/format";

/**
 * Registration.
 *
 * Placement goes through `findPlacementSlot` and nothing else. It walks the
 * sponsor chain, keeps a recruit inside their own upline where possible, and
 * falls back to the stage anchor by itself. The lower-level `findSponsorSlot`
 * has two routine failure modes a caller would otherwise handle by hand, and
 * getting either wrong silently breaks placement.
 */
export default function JoinPage() {
  const { address: connectedAddress, isConnected } = useAccount();
  const { isRegistered, isLoading: memberLoading, refetch: refetchMember } = useMember();
  const { anchor: protocolRoot, isOpen, isLoading: openLoading } = useProtocolOpen();
  const { isStale: priceStale, isLoading: priceLoading } = useOraclePriceHealth();
  const { config } = useStageConfig(0);
  const { quote, refetch: refetchQuote } = useStagePaymentQuote(0);

  const [sponsor, setSponsor] = useState("");
  const referralHydrated = useRef(false);
  const sponsorValid = isAddress(sponsor);
  const sponsorIsSelf =
    sponsorValid &&
    Boolean(connectedAddress) &&
    sponsor.toLowerCase() === connectedAddress?.toLowerCase();
  const sponsorUsable = sponsorValid && !sponsorIsSelf;
  const noSponsor = !sponsor.trim();
  const effectiveSponsor = sponsorUsable
    ? (getAddress(sponsor) as `0x${string}`)
    : noSponsor && protocolRoot
      ? protocolRoot
      : undefined;
  const usingProtocolRoot = noSponsor && Boolean(effectiveSponsor);
  const referralStorageKey = `nexaflow:sponsor:${ACTIVE_CHAIN.id}:${MEMBERSHIP_ADDRESS.toLowerCase()}`;

  const {
    parent,
    side,
    isLoading: slotLoading,
    error: slotError,
    refetch: refetchPlacement,
  } = usePlacementSlot(
    effectiveSponsor,
    0,
  );

  const join = useJoin();

  // V2 stores the package value in USD and quotes the actual RWAAN amount from
  // the current on-chain oracle price.
  const fee = quote?.feeAmount;
  const preset = STAGE_PRESETS[0];

  // A direct address link is canonical. The /r/<code> route resolves to the
  // same query parameter, and storage protects the sponsor through refreshes.
  useEffect(() => {
    try {
      const ref = new URLSearchParams(window.location.search).get("ref");
      if (ref && isAddress(ref)) {
        const normalized = getAddress(ref);
        setSponsor(normalized);
        window.localStorage.setItem(referralStorageKey, normalized);
      } else {
        const saved = window.localStorage.getItem(referralStorageKey);
        if (saved && isAddress(saved)) setSponsor(getAddress(saved));
      }
    } catch {
      // The referral remains usable from the URL even when storage is denied.
    } finally {
      referralHydrated.current = true;
    }
  }, [referralStorageKey]);

  useEffect(() => {
    if (!referralHydrated.current) return;
    try {
      if (sponsorValid && !sponsorIsSelf) {
        window.localStorage.setItem(referralStorageKey, getAddress(sponsor));
      } else if (!sponsor.trim()) {
        window.localStorage.removeItem(referralStorageKey);
      }
    } catch {
      // Private browsing and hardened wallets may deny storage. The URL and
      // current form value remain fully functional without persistence.
    }
  }, [referralStorageKey, sponsor, sponsorIsSelf, sponsorValid]);

  useEffect(() => {
    if (join.isConfirmed) {
      // Only refresh state touched by the confirmed transaction. Approval does
      // not change membership, and registration does not need another
      // allowance read before this page redirects to the member dashboard.
      if (join.action === "approve") join.refetchAllowance();
      if (join.action === "register") refetchMember();
    }
  }, [join.isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  async function approveFreshQuote() {
    const result = await refetchQuote();
    const raw = result.data as
      | readonly [bigint, bigint, bigint, bigint]
      | undefined;
    if (raw) await join.approve(raw[0]);
  }

  async function registerFreshPlacementAndQuote() {
    const [quoteResult, placementResult] = await Promise.all([
      refetchQuote(),
      refetchPlacement(),
    ]);
    const freshQuote = quoteResult.data as
      | readonly [bigint, bigint, bigint, bigint]
      | undefined;
    const freshPlacement = placementResult.data as
      | readonly [`0x${string}`, number]
      | undefined;
    if (!freshQuote || !freshPlacement || !effectiveSponsor) return;

    // A lower token price can make an earlier exact approval insufficient.
    // Re-approve the new exact amount rather than submitting a doomed join.
    if (join.needsApproval(freshQuote[0])) {
      await join.approve(freshQuote[0]);
      return;
    }
    await join.register(
      effectiveSponsor,
      freshPlacement[0],
      freshPlacement[1],
      freshQuote[0],
    );
  }

  if (!IS_DEPLOYED) return <Shell><NotDeployedNotice /></Shell>;
  if (openLoading || priceLoading) return <Shell><LoadingPanel /></Shell>;
  if (!isOpen) return <Shell><ProtocolNotOpenNotice /></Shell>;
  // Before the wallet check: a member cannot act on a price the contract will
  // not quote, so asking them to connect first only wastes the step.
  if (priceStale) return <Shell><PriceUnavailableNotice /></Shell>;
  if (!isConnected) return <Shell><ConnectPrompt /></Shell>;
  if (memberLoading) return <Shell><LoadingPanel /></Shell>;

  if (isRegistered) {
    return (
      <Shell>
        <div className="panel panel-sheen p-6">
          <h2 className="font-display text-lg font-semibold">
            You are already a member
          </h2>
          <p className="mt-1.5 text-sm text-muted">
            This wallet is registered. Your boards are on the dashboard.
          </p>
          <a href="/app" className="btn-gold mt-5 inline-flex px-5 py-2.5 text-sm">
            Go to dashboard
          </a>
        </div>
      </Shell>
    );
  }

  const needsApproval = fee !== undefined && join.needsApproval(fee);
  const canAfford = fee !== undefined && join.hasBalance(fee);
  const ready = Boolean(effectiveSponsor) && Boolean(parent) && fee !== undefined;
  const busy = join.isSigning || join.isConfirming;

  return (
    <Shell>
      <div className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
        <section className="panel panel-sheen p-5 sm:p-6">
          <h2 className="font-display text-lg font-semibold">
            Step 1 &middot; Your sponsor
          </h2>
          <p className="mt-1 text-sm text-muted">
            Add the wallet of the member who referred you. If you came alone,
            leave this blank and you will enter under the protocol root, then
            build your own tree from your own referral link.
          </p>

          <label htmlFor="sponsor" className="label mt-5 block">
            Sponsor address <span className="text-faint">(optional)</span>
          </label>
          <input
            id="sponsor"
            value={sponsor}
            onChange={(e) => setSponsor(e.target.value.trim())}
            placeholder="Leave blank to start fresh under protocol root"
            spellCheck={false}
            autoComplete="off"
            disabled={busy}
            className="mt-2 w-full rounded-xl border border-line bg-surface-2 px-4
                       py-3 font-mono text-sm text-ink placeholder:text-faint
                       focus:border-gold/50 focus:outline-none disabled:opacity-60"
          />
          {sponsor && (
            <button
              type="button"
              onClick={() => setSponsor("")}
              disabled={busy}
              className="mt-2 text-xs text-muted underline-offset-2 hover:text-ink hover:underline disabled:opacity-50"
            >
              Clear saved sponsor
            </button>
          )}
          {usingProtocolRoot && (
            <div className="mt-3 rounded-xl border border-gold/20 bg-gold/8 p-3 text-sm text-muted">
              No sponsor selected. You will start under the protocol root{" "}
              <span className="font-mono text-ink">
                {shortAddress(effectiveSponsor, 6)}
              </span>
              . After joining, your own referral link starts your tree.
            </div>
          )}
          {sponsor && !sponsorValid && (
            <p className="mt-2 text-sm text-down">
              That is not a valid wallet address.
            </p>
          )}
          {sponsorIsSelf && (
            <p className="mt-2 text-sm text-down">
              You cannot use your own wallet as your sponsor. Use the referral link
              from the member who invited you.
            </p>
          )}

          {effectiveSponsor && (
            <div className="mt-4 rounded-xl border border-line bg-surface-2 p-4">
              <div className="label">Step 2 &middot; Your position</div>
              {slotLoading && (
                <p className="mt-2 text-sm text-muted">Finding your slot…</p>
              )}
              {slotError && (
                <p className="mt-2 text-sm text-down">
                  No placement available under that sponsor. Check the address,
                  or ask them to confirm they have joined.
                </p>
              )}
              {parent && (
                <dl className="mt-2 space-y-1 text-sm">
                  <div className="flex justify-between">
                    <dt className="text-muted">Placed under</dt>
                    <dd className="font-mono">{shortAddress(parent, 6)}</dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-muted">Side</dt>
                    <dd>{side === 1 ? "Left" : side === 2 ? "Right" : "—"}</dd>
                  </div>
                </dl>
              )}
            </div>
          )}

          {/* Two transactions, shown as two steps. Hiding the approval behind a
              single button is what trains people to sign things blindly. */}
          <div className="mt-6 space-y-3">
            {needsApproval ? (
              <button
                onClick={approveFreshQuote}
                disabled={!ready || busy || !canAfford}
                className="btn-gold w-full py-3.5 disabled:opacity-50"
              >
                {busy
                  ? "Confirm in wallet…"
                  : `Approve ${formatToken(fee, join.decimals)} ${join.symbol}`}
              </button>
            ) : (
              <button
                onClick={registerFreshPlacementAndQuote}
                disabled={!ready || busy}
                className="btn-gold w-full py-3.5 disabled:opacity-50"
              >
                {busy ? "Confirm in wallet…" : `Join ${preset.label}`}
              </button>
            )}

            {!canAfford && fee !== undefined && (
              <p className="text-center text-sm text-down">
                Not enough {join.symbol}. You need {formatToken(fee, join.decimals)} and hold{" "}
                {formatToken(join.balance, join.decimals)}.
              </p>
            )}

            <p className="text-center text-xs text-faint">
              {needsApproval
                ? "Step 1 of 2 — approving lets the contract collect the fee."
                : "Step 2 of 2 — this places you and pays your uplines."}
            </p>
          </div>

          {join.hash && (
            <a
              href={`${ACTIVE_CHAIN.blockExplorers?.default.url}/tx/${join.hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-4 block text-center text-sm text-gold hover:underline"
            >
              {join.isConfirming ? "Waiting for confirmation…" : "View transaction ↗"}
            </a>
          )}

          {join.error && (
            <p className="mt-3 break-words text-sm text-down">
              {join.error.message.split("\n")[0]}
            </p>
          )}
        </section>

        <aside className="panel p-5 sm:p-6">
          <div className="label">What you are joining</div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="font-display text-3xl font-bold gold-text">
              {formatToken(fee, join.decimals)}
            </span>
            <span className="text-sm text-muted">{join.symbol} entry</span>
          </div>
          <p className="mt-1 text-xs text-faint">
            {preset.fee.toLocaleString("en-US", { style: "currency", currency: "USD" })}
            {quote ? ` at $${formatToken(quote.priceUsd18, 18, 8)} per ${join.symbol}` : " at the live oracle price"}
          </p>

          <dl className="mt-5 space-y-3 text-sm">
            <Row label="Positions on your board" value={`${preset.slots}`} />
            <Row
              label="You receive per position"
              value={formatToken(quote?.rewardAmount, join.decimals)}
            />
            <Row
              label="A full board pays you"
              value={formatToken(
                quote && config
                  ? quote.rewardAmount * config.treeSlots
                  : undefined,
                join.decimals,
              )}
              accent
            />
          </dl>

          <p className="mt-5 text-xs leading-relaxed text-faint">
            Positions fill as new members join beneath you, whether you
            introduced them or not. Your earnings depend entirely on people
            joining after you. A full board is not guaranteed, and entry fees are
            not refundable.
          </p>
        </aside>
      </div>
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold sm:text-3xl">Join</h1>
        <p className="mt-1 text-sm text-muted">
          Register at Stage 1 and open your first board.
        </p>
      </div>
      {children}
    </div>
  );
}

function Row({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  return (
    <div className="flex items-center justify-between border-b border-line pb-2.5">
      <dt className="text-muted">{label}</dt>
      <dd className={accent ? "figure font-semibold gold-text" : "figure"}>
        {value}
      </dd>
    </div>
  );
}
