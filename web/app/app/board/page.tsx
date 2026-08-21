"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { IS_DEPLOYED, STAGE_PRESETS, stageLabel } from "@/lib/contracts/config";
import { useAllStageMemberships, useMember } from "@/hooks/use-membership";
import {
  ConnectPrompt,
  LoadingPanel,
  NotDeployedNotice,
  NotRegisteredNotice,
} from "@/components/app/states";
import { cn, formatCount, formatToken, shortAddress } from "@/lib/format";

export default function BoardPage() {
  const { isConnected } = useAccount();
  const { isRegistered, isLoading: memberLoading } = useMember();
  const { stages, currentStage, isLoading } = useAllStageMemberships();
  const [selected, setSelected] = useState<number | null>(null);

  const stageId = selected ?? (currentStage >= 0 ? currentStage : 0);
  const membership = stages?.[stageId];
  const preset = STAGE_PRESETS[stageId];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold sm:text-3xl">My Board</h1>
        <p className="mt-1 text-sm text-muted">
          Positions beneath you at each stage, and what they have paid.
        </p>
      </div>

      {!IS_DEPLOYED ? (
        <NotDeployedNotice />
      ) : !isConnected ? (
        <ConnectPrompt />
      ) : memberLoading || isLoading ? (
        <LoadingPanel />
      ) : !isRegistered ? (
        <NotRegisteredNotice />
      ) : (
        <>
          <div className="flex flex-wrap gap-2">
            {STAGE_PRESETS.map((p) => {
              const enrolled = Boolean(stages?.[p.stageId]?.enrolled);
              return (
                <button
                  key={p.stageId}
                  onClick={() => setSelected(p.stageId)}
                  disabled={!enrolled}
                  className={cn(
                    "rounded-lg px-3 py-1.5 text-sm font-medium transition-colors",
                    p.stageId === stageId
                      ? "bg-surface-3 text-ink"
                      : enrolled
                        ? "bg-surface-2 text-muted hover:text-ink"
                        : "bg-surface-1 text-faint cursor-not-allowed",
                  )}
                >
                  {p.label}
                </button>
              );
            })}
          </div>

          {!membership?.enrolled ? (
            <div className="panel p-6 text-sm text-muted">
              You have not joined {stageLabel(stageId)} yet.
            </div>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Cell
                label="Filled"
                value={`${formatCount(membership.slotsFilledBelow)} / ${preset.slots}`}
              />
              <Cell
                label="Rollovers"
                value={formatCount(membership.rolloverCount)}
              />
              <Cell
                label="Earned here"
                value={`${formatToken(membership.stageEarnings)} RWAAN`}
                accent
              />
              <Cell
                label="Awarded"
                value={`${formatToken(membership.totalAwarded)} RWAAN`}
              />

              <div className="panel col-span-full p-5">
                <div className="label">Direct positions</div>
                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  <Slot label="Left" address={membership.left} />
                  <Slot label="Right" address={membership.right} />
                </div>
                <p className="mt-4 text-xs leading-relaxed text-faint">
                  Your board runs deeper than these two. Positions below them pay
                  you as well, and both slots reset each time the board rolls over.
                </p>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function Cell({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  return (
    <div className="panel p-4 sm:p-5">
      <div className="text-[11px] uppercase tracking-wider text-faint">
        {label}
      </div>
      <div
        className={cn(
          "figure mt-1 font-display text-xl font-bold",
          accent ? "gold-text" : "text-ink",
        )}
      >
        {value}
      </div>
    </div>
  );
}

function Slot({ label, address }: { label: string; address?: string }) {
  const empty =
    !address || address === "0x0000000000000000000000000000000000000000";

  return (
    <div className="rounded-xl border border-line bg-surface-2 p-4">
      <div className="text-[11px] uppercase tracking-wider text-faint">
        {label}
      </div>
      {empty ? (
        <div className="mt-1 text-sm text-faint">Open</div>
      ) : (
        <div className="mt-1 font-mono text-sm">{shortAddress(address, 6)}</div>
      )}
    </div>
  );
}
