"use client";

import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import { getAddress, isAddress } from "viem";
import {
  IS_DEPLOYED,
  STAGE_PRESETS,
  ACTIVE_CHAIN,
  MEMBERSHIP_ADDRESS,
  ZERO_ADDRESS,
} from "@/lib/contracts/config";
import {
  useAllStageMemberships,
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

// RWAAN is priced by an on-chain TWAP. The contract still receives a strict
// maximum payment, but giving that cap a small disclosed margin prevents a
// harmless price move between the fresh quote and block inclusion from making
// a valid registration revert. The user is charged the actual fee, never this
// upper bound.
const QUOTE_TOLERANCE_BPS = 100n; // 1%
const BPS_DENOMINATOR = 10_000n;

function maximumPaymentForQuote(fee: bigint) {
  return (
    (fee * (BPS_DENOMINATOR + QUOTE_TOLERANCE_BPS) + BPS_DENOMINATOR - 1n) /
    BPS_DENOMINATOR
  );
}

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
  const {
    isRegistered,
    member,
    isLoading: memberLoading,
    refetch: refetchMember,
  } = useMember();
  const {
    stages,
    isLoading: stagesLoading,
    refetch: refetchStages,
  } = useAllStageMemberships();
  const { anchor: protocolRoot, isOpen, isLoading: openLoading } = useProtocolOpen();
  const { isStale: priceStale, isLoading: priceLoading } = useOraclePriceHealth();

  const [sponsor, setSponsor] = useState("");
  const [selectedStage, setSelectedStage] = useState<number>();
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

  // V3 makes boards independent: a member can start at any stage and later
  // add any board they have not already joined.
  const firstUnjoinedStage = stages?.findIndex((stage) => !stage?.enrolled);
  const stageId =
    selectedStage ??
    (isRegistered && firstUnjoinedStage !== undefined && firstUnjoinedStage >= 0
      ? firstUnjoinedStage
      : 0);
  const stageAvailable = !isRegistered || !stages?.[stageId]?.enrolled;
  const allStagesJoined = isRegistered && Boolean(stages?.every((stage) => stage?.enrolled));
  const storedSponsor =
    member?.sponsor && member.sponsor !== ZERO_ADDRESS ? member.sponsor : undefined;
  const placementSponsor = isRegistered ? storedSponsor : effectiveSponsor;
  const { config } = useStageConfig(stageId);
  const { quote, refetch: refetchQuote } = useStagePaymentQuote(stageId);

  const {
    parent,
    side,
    isLoading: slotLoading,
    error: slotError,
    refetch: refetchPlacement,
  } = usePlacementSlot(
    stageAvailable ? placementSponsor : undefined,
    stageId,
  );

  const join = useJoin();

  // V3 stores the package value in USD and quotes the actual RWAAN amount from
  // the current on-chain oracle price.
  const fee = quote?.feeAmount;
  const maximumPayment = fee === undefined ? undefined : maximumPaymentForQuote(fee);

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
      if (join.action === "register" || join.action === "joinStage") {
        refetchStages();
        setSelectedStage(undefined);
      }
    }
  }, [join.isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  async function approveFreshQuote() {
    const result = await refetchQuote();
    const raw = result.data as
      | readonly [bigint, bigint, bigint, bigint]
      | undefined;
    if (raw) await join.approve(maximumPaymentForQuote(raw[0]));
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
    if (!freshQuote || !freshPlacement || !stageAvailable) return;

    // A lower token price can make an earlier exact approval insufficient.
    // Re-approve the new exact amount rather than submitting a doomed join.
    const freshMaximumPayment = maximumPaymentForQuote(freshQuote[0]);
    if (join.needsApproval(freshMaximumPayment)) {
      await join.approve(freshMaximumPayment);
      return;
    }
    if (isRegistered) {
      await join.joinStage(
        stageId,
        freshPlacement[0],
        freshPlacement[1],
        freshMaximumPayment,
      );
    } else if (effectiveSponsor) {
      await join.registerAtStage(
        stageId,
        effectiveSponsor,
        freshPlacement[0],
        freshPlacement[1],
        freshMaximumPayment,
      );
    }
  }

  if (!IS_DEPLOYED) return <Shell><NotDeployedNotice /></Shell>;
  if (openLoading || priceLoading) return <Shell><LoadingPanel /></Shell>;
  if (!isOpen) return <Shell><ProtocolNotOpenNotice /></Shell>;
  // Before the wallet check: a member cannot act on a price the contract will
  // not quote, so asking them to connect first only wastes the step.
  if (priceStale) return <Shell><PriceUnavailableNotice /></Shell>;
  if (!isConnected) return <Shell><ConnectPrompt /></Shell>;
  if (memberLoading || (isRegistered && stagesLoading)) return <Shell><LoadingPanel /></Shell>;

  const needsApproval =
    maximumPayment !== undefined && join.needsApproval(maximumPayment);
  const canAfford =
    maximumPayment !== undefined && join.hasBalance(maximumPayment);
  const ready =
    stageAvailable && Boolean(placementSponsor) && Boolean(parent) && fee !== undefined;
  const busy = join.isSigning || join.isConfirming;
  const selectedPreset = STAGE_PRESETS[stageId];
  const paymentMovedBeyondTolerance = Boolean(
    join.error?.message.includes("PaymentExceedsMaximum"),
  );
  return (
    <Shell>
      <div className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
        <section className="panel panel-sheen p-5 sm:p-6">
          {!isRegistered && (
            <>
              <h2 className="font-display text-lg font-semibold">
                Step 1 &middot; Your sponsor
              </h2>
              <p className="mt-1 text-sm text-muted">
                Add the wallet of the member who referred you. If you came alone,
                leave this blank and you will start under the protocol, then build
                your own tree from your own referral link.
              </p>

              <label htmlFor="sponsor" className="label mt-5 block">
                Sponsor address <span className="text-faint">(optional)</span>
              </label>
              <input
                id="sponsor"
                value={sponsor}
                onChange={(e) => setSponsor(e.target.value.trim())}
                placeholder="Leave blank to start under the protocol"
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
                  No sponsor selected. You will start under the protocol. After
                  joining, your own referral link starts your tree.
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
            </>
          )}

          <div className={isRegistered ? "" : "mt-6 border-t border-line pt-6"}>
            <h2 className="font-display text-lg font-semibold">
              {isRegistered ? "Choose a stage" : "Step 2 · Choose your starting stage"}
            </h2>
            <p className="mt-1 text-sm text-muted">
              Every stage is independently available. Choose the board that fits
              your budget now, then add any other stage whenever you are ready.
            </p>
            <div className="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-3">
              {STAGE_PRESETS.map((preset) => {
                const enrolled = Boolean(stages?.[preset.stageId]?.enrolled);
                const selected = preset.stageId === stageId;
                return (
                  <button
                    key={preset.stageId}
                    type="button"
                    onClick={() => setSelectedStage(preset.stageId)}
                    disabled={busy}
                    className={[
                      "rounded-xl border p-3 text-left transition-colors disabled:opacity-60",
                      selected
                        ? "border-gold/60 bg-gold/10"
                        : "border-line bg-surface-2 hover:border-gold/30",
                    ].join(" ")}
                  >
                    <div className="text-sm font-medium">{preset.label}</div>
                    <div
                      className={[
                        "mt-1 text-xs",
                        enrolled ? "text-up" : "text-gold",
                      ].join(" ")}
                    >
                      {enrolled ? "Joined" : isRegistered ? "Ready to join" : "Start here"}
                    </div>
                  </button>
                );
              })}
            </div>
            {allStagesJoined && (
              <div className="mt-4 rounded-xl border border-up/20 bg-up/5 p-3 text-sm text-muted">
                You have joined all six stages. Your boards continue earning as
                positions fill beneath them.
              </div>
            )}
            {!allStagesJoined && !stageAvailable && (
              <div className="mt-4 rounded-xl border border-line bg-surface-2 p-3 text-sm text-muted">
                You have already joined {selectedPreset.label}. Choose any other
                stage to open another board.
              </div>
            )}
          </div>

          {stageAvailable && placementSponsor && !allStagesJoined && (
            <div className="mt-4 rounded-xl border border-line bg-surface-2 p-4">
              <div className="label">
                {isRegistered ? `Your ${selectedPreset.label} position` : "Step 2 · Your position"}
              </div>
              {slotLoading && (
                <p className="mt-2 text-sm text-muted">Finding your slot…</p>
              )}
              {slotError && (
                <p className="mt-2 text-sm text-down">
                  This stage is not ready for a placement yet. The protocol must
                  open its board before members can join it.
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
          {!allStagesJoined && (
            <div className="mt-6 space-y-3">
              {needsApproval ? (
                <button
                  onClick={approveFreshQuote}
                  disabled={!ready || busy || !canAfford}
                  className="btn-gold w-full py-3.5 disabled:opacity-50"
                >
                  {busy
                    ? "Confirm in wallet…"
                  : `Approve up to ${formatToken(maximumPayment, join.decimals)} ${join.symbol}`}
                </button>
              ) : (
                <button
                  onClick={registerFreshPlacementAndQuote}
                  disabled={!ready || busy}
                  className="btn-gold w-full py-3.5 disabled:opacity-50"
                >
                  {busy ? "Confirm in wallet…" : `Join ${selectedPreset.label}`}
                </button>
              )}

              {!canAfford && fee !== undefined && (
                <p className="text-center text-sm text-down">
                  Not enough {join.symbol}. You need up to {formatToken(maximumPayment, join.decimals)} and hold{" "}
                  {formatToken(join.balance, join.decimals)}.
                </p>
              )}

              <p className="text-center text-xs text-faint">
                {needsApproval
                  ? "Step 1 of 2 — this approval includes a 1% price-movement buffer."
                  : `Step 2 of 2 — joining ${selectedPreset.label} places you and pays your uplines.`}
              </p>
            </div>
          )}

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

          {paymentMovedBeyondTolerance ? (
            <p className="mt-3 text-sm text-down">
              The live price moved beyond the 1% tolerance before confirmation.
              No RWAAN was collected. Refresh the quote and approve the new
              maximum to try again.
            </p>
          ) : join.error && (
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
            {selectedPreset.fee.toLocaleString("en-US", { style: "currency", currency: "USD" })}
            {quote ? ` at $${formatToken(quote.priceUsd18, 18, 8)} per ${join.symbol}` : " at the live oracle price"}
          </p>
          {maximumPayment !== undefined && (
            <p className="mt-1 text-xs text-faint">
              You will pay the live amount, up to {formatToken(maximumPayment, join.decimals)} {join.symbol}.
            </p>
          )}

          <dl className="mt-5 space-y-3 text-sm">
            <Row label="Positions on your board" value={`${selectedPreset.slots}`} />
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
          Choose the stage that fits your plan and open your board.
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
