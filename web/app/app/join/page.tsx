"use client";

import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import { getAddress, isAddress } from "viem";
import {
  ACTIVE_CHAIN,
  IS_DEPLOYED,
  MAX_STAGES,
  MEMBERSHIP_ADDRESS,
  STAGE_PRESETS,
  ZERO_ADDRESS,
} from "@/lib/contracts/config";
import {
  useAllStageMemberships,
  useMember,
  usePlacementSlot,
  useProtocolOpen,
  useStageConfig,
} from "@/hooks/use-membership";
import { useJoin } from "@/hooks/use-join";
import {
  ConnectPrompt,
  LoadingPanel,
  NotDeployedNotice,
  ProtocolNotOpenNotice,
} from "@/components/app/states";
import { formatToken, shortAddress } from "@/lib/format";

/**
 * V4 is intentionally sequential: a first-time member buys Stage 1, which
 * immediately unlocks Stage 2. Each later board unlocks only after the prior
 * one has been joined. Fees are fixed USDT amounts read from the contract.
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
    currentStage,
    isLoading: stagesLoading,
    refetch: refetchStages,
  } = useAllStageMemberships();
  const { anchor: protocolRoot, isOpen, isLoading: openLoading } = useProtocolOpen();

  const [sponsor, setSponsor] = useState("");
  const [submittedStageId, setSubmittedStageId] = useState<number>();
  const [successToast, setSuccessToast] = useState<{
    title: string;
    message: string;
  }>();
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

  const stageId = isRegistered ? currentStage + 1 : 0;
  const allStagesJoined = isRegistered && stageId >= MAX_STAGES;
  const stageAvailable = stageId >= 0 && stageId < MAX_STAGES && !allStagesJoined;
  const selectedPreset = STAGE_PRESETS[stageId] ?? STAGE_PRESETS[MAX_STAGES - 1];
  const storedSponsor =
    member?.sponsor && member.sponsor !== ZERO_ADDRESS ? member.sponsor : undefined;
  const placementSponsor = isRegistered ? storedSponsor : effectiveSponsor;
  const { config } = useStageConfig(stageId);
  const {
    parent,
    side,
    isLoading: slotLoading,
    error: slotError,
    refetch: refetchPlacement,
  } = usePlacementSlot(stageAvailable ? placementSponsor : undefined, stageId);
  const join = useJoin();
  const fee = config?.fee;
  const reward = config?.nodeReward;

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
      // The referral still works from the URL when storage is unavailable.
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
      // Private browsing can deny storage without affecting the join flow.
    }
  }, [referralStorageKey, sponsor, sponsorIsSelf, sponsorValid]);

  useEffect(() => {
    if (!join.isConfirmed) return;
    if (join.action === "approve") join.refetchAllowance();
    if (join.action === "register" || join.action === "joinStage") {
      const completed = STAGE_PRESETS[submittedStageId ?? stageId];
      setSuccessToast({
        title: join.action === "register" ? "Welcome to NexaFlow" : `${completed.label} joined`,
        message:
          join.action === "register"
            ? `${completed.label} is open. Stage 2 is now unlocked whenever you are ready.`
            : `${completed.label} is open. The next stage is now unlocked whenever you are ready.`,
      });
      refetchMember();
      refetchStages();
    }
  }, [join.isConfirmed]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!successToast) return;
    const timeout = window.setTimeout(() => setSuccessToast(undefined), 8_000);
    return () => window.clearTimeout(timeout);
  }, [successToast]);

  async function approveExactFee() {
    if (fee !== undefined) await join.approve(fee);
  }

  async function joinFreshPlacement() {
    const placementResult = await refetchPlacement();
    const freshPlacement = placementResult.data as
      | readonly [`0x${string}`, number]
      | undefined;
    if (!freshPlacement || !stageAvailable || fee === undefined) return;
    if (join.needsApproval(fee)) {
      await join.approve(fee);
      return;
    }

    setSubmittedStageId(stageId);
    if (isRegistered) {
      await join.joinStage(stageId, freshPlacement[0], freshPlacement[1]);
    } else if (effectiveSponsor) {
      await join.register(effectiveSponsor, freshPlacement[0], freshPlacement[1]);
    }
  }

  if (!IS_DEPLOYED) return <Shell><NotDeployedNotice /></Shell>;
  if (openLoading) return <Shell><LoadingPanel /></Shell>;
  if (!isOpen) return <Shell><ProtocolNotOpenNotice /></Shell>;
  if (!isConnected) return <Shell><ConnectPrompt /></Shell>;
  if (memberLoading || (isRegistered && stagesLoading)) return <Shell><LoadingPanel /></Shell>;

  const needsApproval = fee !== undefined && join.needsApproval(fee);
  const canAfford = fee !== undefined && join.hasBalance(fee);
  const ready =
    stageAvailable &&
    Boolean(placementSponsor) &&
    Boolean(parent) &&
    fee !== undefined;
  const busy = join.isSigning || join.isConfirming;

  return (
    <Shell>
      {successToast && (
        <div role="status" className="fixed bottom-4 right-4 z-50 w-[calc(100%-2rem)] max-w-sm rounded-2xl border border-up/30 bg-surface-2 p-4 shadow-2xl shadow-black/40">
          <div className="flex items-start gap-3">
            <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-up/15 text-xs font-bold text-up">✓</span>
            <div className="min-w-0 flex-1">
              <p className="font-display text-sm font-semibold text-ink">{successToast.title}</p>
              <p className="mt-1 text-xs leading-relaxed text-muted">{successToast.message}</p>
              <a href="/app/board" className="mt-2 inline-block text-xs font-medium text-gold hover:underline">View my board →</a>
            </div>
            <button type="button" onClick={() => setSuccessToast(undefined)} aria-label="Dismiss success message" className="text-muted transition-colors hover:text-ink">×</button>
          </div>
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
        <section className="panel panel-sheen p-5 sm:p-6">
          {!isRegistered && (
            <>
              <h2 className="font-display text-lg font-semibold">Step 1 · Your sponsor</h2>
              <p className="mt-1 text-sm text-muted">
                Add the wallet of the member who referred you. If you came alone, leave this blank and you will start under the protocol, then build your own tree from your referral link.
              </p>
              <label htmlFor="sponsor" className="label mt-5 block">Sponsor address <span className="text-faint">(optional)</span></label>
              <input id="sponsor" value={sponsor} onChange={(e) => setSponsor(e.target.value.trim())} placeholder="Leave blank to start under the protocol" spellCheck={false} autoComplete="off" disabled={busy} className="mt-2 w-full rounded-xl border border-line bg-surface-2 px-4 py-3 font-mono text-sm text-ink placeholder:text-faint focus:border-gold/50 focus:outline-none disabled:opacity-60" />
              {sponsor && <button type="button" onClick={() => setSponsor("")} disabled={busy} className="mt-2 text-xs text-muted underline-offset-2 hover:text-ink hover:underline disabled:opacity-50">Clear saved sponsor</button>}
              {usingProtocolRoot && <div className="mt-3 rounded-xl border border-gold/20 bg-gold/8 p-3 text-sm text-muted">No sponsor selected. You will start under the protocol. After joining, your own referral link starts your tree.</div>}
              {sponsor && !sponsorValid && <p className="mt-2 text-sm text-down">That is not a valid wallet address.</p>}
              {sponsorIsSelf && <p className="mt-2 text-sm text-down">You cannot use your own wallet as your sponsor.</p>}
            </>
          )}

          <div className={isRegistered ? "" : "mt-6 border-t border-line pt-6"}>
            <h2 className="font-display text-lg font-semibold">
              {allStagesJoined ? "All stages joined" : isRegistered ? `Your next stage · ${selectedPreset.label}` : "Step 2 · Start with Stage 1"}
            </h2>
            <p className="mt-1 text-sm text-muted">
              Stages unlock in order. Joining a stage immediately unlocks the next one; no board-fill wait is required.
            </p>
            <div className="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-3">
              {STAGE_PRESETS.map((preset) => {
                const enrolled = Boolean(stages?.[preset.stageId]?.enrolled);
                const next = stageAvailable && preset.stageId === stageId;
                return <div key={preset.stageId} className={["rounded-xl border p-3", enrolled ? "border-up/30 bg-up/5" : next ? "border-gold/60 bg-gold/10" : "border-line bg-surface-2 opacity-60"].join(" ")}>
                  <div className="text-sm font-medium">{preset.label}</div>
                  <div className={["mt-1 text-xs", enrolled ? "text-up" : next ? "text-gold" : "text-faint"].join(" ")}>
                    {enrolled ? "Joined" : next ? "Unlocked now" : "Locked"}
                  </div>
                </div>;
              })}
            </div>
            {allStagesJoined && <div className="mt-4 rounded-xl border border-up/20 bg-up/5 p-3 text-sm text-muted">You have joined all six stages. Your boards continue earning as positions fill beneath them.</div>}
          </div>

          {stageAvailable && placementSponsor && !allStagesJoined && <div className="mt-4 rounded-xl border border-line bg-surface-2 p-4">
            <div className="label">Your {selectedPreset.label} position</div>
            {slotLoading && <p className="mt-2 text-sm text-muted">Finding your slot…</p>}
            {slotError && <p className="mt-2 text-sm text-down">This stage is not ready for a placement yet. Please refresh and try again.</p>}
            {parent && <dl className="mt-2 space-y-1 text-sm"><div className="flex justify-between"><dt className="text-muted">Placed under</dt><dd className="font-mono">{shortAddress(parent, 6)}</dd></div><div className="flex justify-between"><dt className="text-muted">Side</dt><dd>{side === 1 ? "Left" : side === 2 ? "Right" : "—"}</dd></div></dl>}
          </div>}

          {!allStagesJoined && <div className="mt-6 space-y-3">
            {needsApproval ? <button onClick={approveExactFee} disabled={!ready || busy || !canAfford} className="btn-gold w-full py-3.5 disabled:opacity-50">{busy ? "Confirm in wallet…" : `Approve ${formatToken(fee, join.decimals)} ${join.symbol}`}</button> : <button onClick={joinFreshPlacement} disabled={!ready || busy} className="btn-gold w-full py-3.5 disabled:opacity-50">{busy ? "Confirm in wallet…" : `Join ${selectedPreset.label}`}</button>}
            {!canAfford && fee !== undefined && <p className="text-center text-sm text-down">Not enough {join.symbol}. You need {formatToken(fee, join.decimals)} and hold {formatToken(join.balance, join.decimals)}.</p>}
            <p className="text-center text-xs text-faint">{needsApproval ? "Step 1 of 2 — approve the exact fixed entry amount." : `Step 2 of 2 — joining ${selectedPreset.label} places you and pays your uplines.`}</p>
          </div>}

          {join.hash && <a href={`${ACTIVE_CHAIN.blockExplorers?.default.url}/tx/${join.hash}`} target="_blank" rel="noopener noreferrer" className="mt-4 block text-center text-sm text-gold hover:underline">{join.isConfirming ? "Waiting for confirmation…" : "View transaction ↗"}</a>}
          {join.error && <p className="mt-3 break-words text-sm text-down">{join.error.message.split("\n")[0]}</p>}
        </section>

        <aside className="panel p-5 sm:p-6">
          <div className="label">What you are joining</div>
          <div className="mt-3 flex items-baseline gap-2"><span className="font-display text-3xl font-bold gold-text">{formatToken(fee, join.decimals)}</span><span className="text-sm text-muted">{join.symbol} entry</span></div>
          <p className="mt-1 text-xs text-faint">A fixed on-chain USDT amount. There is no price oracle or quote refresh.</p>
          <dl className="mt-5 space-y-3 text-sm">
            <Row label="Positions on your board" value={`${config?.treeSlots ?? selectedPreset.slots}`} />
            <Row label="You receive per position" value={formatToken(reward, join.decimals)} />
            <Row label="A full board pays you" value={formatToken(reward && config ? reward * config.treeSlots : undefined, join.decimals)} accent />
          </dl>
          <p className="mt-5 text-xs leading-relaxed text-faint">Positions fill as new members join beneath you, whether you introduced them or not. Your earnings depend entirely on people joining after you. A full board is not guaranteed, and entry fees are not refundable.</p>
        </aside>
      </div>
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return <div className="space-y-6"><div><h1 className="font-display text-2xl font-bold sm:text-3xl">Join</h1><p className="mt-1 text-sm text-muted">Begin with Stage 1, then unlock each next stage in order.</p></div>{children}</div>;
}

function Row({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return <div className="flex items-center justify-between border-b border-line pb-2.5"><dt className="text-muted">{label}</dt><dd className={accent ? "figure font-semibold gold-text" : "figure"}>{value}</dd></div>;
}
