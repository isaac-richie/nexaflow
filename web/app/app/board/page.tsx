"use client";

import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import {
  IS_DEPLOYED,
  PAYMENT_TOKEN_SYMBOL,
  STAGE_PRESETS,
} from "@/lib/contracts/config";
import { useAllStageMemberships, useMember } from "@/hooks/use-membership";
import {
  ConnectPrompt,
  LoadingPanel,
  NotDeployedNotice,
  NotRegisteredNotice,
} from "@/components/app/states";
import { LiveBoard } from "@/components/app/live-board";
import { cn, formatCount, formatToken, shortAddress } from "@/lib/format";

export default function BoardPage() {
  const { isConnected } = useAccount();
  const { isRegistered, isLoading: memberLoading } = useMember();
  const { stages, currentStage, isLoading } = useAllStageMemberships();
  const [expandedStage, setExpandedStage] = useState<number | null>(null);
  const initialStageOpened = useRef(false);

  useEffect(() => {
    if (!initialStageOpened.current && currentStage >= 0) {
      initialStageOpened.current = true;
      setExpandedStage(currentStage);
    }
  }, [currentStage]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold sm:text-3xl">
          My Boards
        </h1>
        <p className="mt-1 text-sm text-muted">
          Open any stage to see completed boards, your current cycle and live
          positions.
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
        <div className="space-y-3">
          {STAGE_PRESETS.map((preset) => {
            const membership = stages?.[preset.stageId];
            const enrolled = Boolean(membership?.enrolled);
            const expanded = expandedStage === preset.stageId;
            const filled = Number(membership?.slotsFilledBelow ?? 0n);
            const completed = Number(membership?.rolloverCount ?? 0n);
            const totalRecorded = completed * preset.slots + filled;
            const currentBoard = completed + 1;
            const panelId = `stage-board-${preset.stageId}`;

            return (
              <section
                key={preset.stageId}
                className={cn(
                  "relative overflow-hidden rounded-2xl border transition-colors",
                  expanded
                    ? "panel-sheen border-gold/40 bg-surface-1 shadow-[0_20px_50px_-30px_hsl(var(--gold)/0.35)]"
                    : "border-line bg-surface-1/80",
                )}
              >
                <button
                  type="button"
                  onClick={() =>
                    setExpandedStage(expanded ? null : preset.stageId)
                  }
                  aria-expanded={expanded}
                  aria-controls={panelId}
                  className="flex min-h-20 w-full items-center gap-3 p-4 text-left sm:gap-5 sm:p-5"
                >
                  <div
                    className={cn(
                      "flex h-11 w-11 shrink-0 items-center justify-center rounded-xl font-display text-sm font-bold",
                      enrolled
                        ? "bg-gold text-bg"
                        : "border border-line bg-surface-2 text-faint",
                    )}
                  >
                    {preset.stageId + 1}
                  </div>

                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <h2 className="font-display text-sm font-semibold sm:text-base">
                        {preset.label}
                      </h2>
                      <span
                        className={cn(
                          "rounded-full px-2 py-0.5 text-[10px] font-medium",
                          enrolled
                            ? "bg-up/10 text-up"
                            : "bg-surface-3 text-faint",
                        )}
                      >
                        {enrolled ? "Active" : "Not joined"}
                      </span>
                    </div>

                    {enrolled ? (
                      <div className="mt-1 flex flex-wrap gap-x-4 gap-y-0.5 text-[11px] text-muted sm:text-xs">
                        <span>{completed} completed</span>
                        <span>{filled}/{preset.slots} current positions</span>
                        <span>{formatToken(membership?.stageEarnings)} {PAYMENT_TOKEN_SYMBOL} earned</span>
                      </div>
                    ) : (
                      <p className="mt-1 text-[11px] text-faint sm:text-xs">
                        Activate earlier stages first to reach this board.
                      </p>
                    )}
                  </div>

                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    className={cn(
                      "shrink-0 text-muted transition-transform duration-200",
                      expanded && "rotate-180 text-gold",
                    )}
                    aria-hidden="true"
                  >
                    <path d="m6 9 6 6 6-6" />
                  </svg>
                </button>

                {expanded && (
                  <div id={panelId} className="border-t border-line p-4 sm:p-5">
                    {!enrolled || !membership ? (
                      <div className="rounded-xl border border-dashed border-line bg-surface-2/50 p-5 text-sm text-muted">
                        This stage has not been activated yet. Your board details
                        will appear here after you join it.
                      </div>
                    ) : (
                      <div className="space-y-4">
                        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                          <Cell label="Completed boards" value={formatCount(membership.rolloverCount)} />
                          <Cell label="Current board" value={`#${currentBoard}`} />
                          <Cell label="Placements recorded" value={totalRecorded.toLocaleString()} />
                          <Cell
                            label="Earned at this stage"
                            value={`${formatToken(membership.stageEarnings)} ${PAYMENT_TOKEN_SYMBOL}`}
                            accent
                          />
                        </div>

                        <div className="grid gap-4 lg:grid-cols-[minmax(0,1.35fr)_minmax(250px,.65fr)]">
                          <div className="rounded-xl border border-line bg-surface-2/45 p-3 sm:p-4">
                            <div className="mb-2 flex items-center justify-between gap-3">
                              <div>
                                <h3 className="text-sm font-semibold">
                                  Board #{currentBoard}
                                </h3>
                                <p className="mt-0.5 text-[11px] text-faint">
                                  {filled} filled and {preset.slots - filled} open
                                </p>
                              </div>
                              <span className="rounded-full bg-gold/10 px-2.5 py-1 text-[10px] font-medium text-gold">
                                Current cycle
                              </span>
                            </div>
                            <LiveBoard preset={preset} membership={membership} />
                          </div>

                          <div className="space-y-3">
                            <div className="rounded-xl border border-line bg-surface-2/45 p-4">
                              <div className="label">Direct positions</div>
                              <div className="mt-3 space-y-2">
                                <Slot label="Left" address={membership.left} />
                                <Slot label="Right" address={membership.right} />
                              </div>
                            </div>

                            <div className="rounded-xl border border-line bg-surface-2/45 p-4 text-xs leading-relaxed text-faint">
                              Completed cycles are preserved as the rollover
                              count. The live tree shows the current board after
                              the latest rollover.
                            </div>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                )}
              </section>
            );
          })}
        </div>
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
    <div className="rounded-xl border border-line bg-surface-2/60 p-3 sm:p-4">
      <div className="text-[10px] uppercase tracking-wider text-faint sm:text-[11px]">
        {label}
      </div>
      <div
        className={cn(
          "figure mt-1 font-display text-base font-bold sm:text-lg",
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
    <div className="flex items-center justify-between gap-3 rounded-lg border border-line bg-surface-1 px-3 py-2.5">
      <span className="text-[11px] uppercase tracking-wider text-faint">
        {label}
      </span>
      {empty ? (
        <span className="text-xs text-faint">Open</span>
      ) : (
        <span className="font-mono text-xs text-ink">
          {shortAddress(address, 5)}
        </span>
      )}
    </div>
  );
}
