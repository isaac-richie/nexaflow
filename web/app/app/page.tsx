"use client";

import { useAccount } from "wagmi";
import { IS_DEPLOYED, STAGE_PRESETS, stageLabel } from "@/lib/contracts/config";
import {
  useAllStageMemberships,
  useAwardInfo,
  useMember,
  useProtocolStats,
} from "@/hooks/use-membership";
import {
  ConnectPrompt,
  LoadingPanel,
  NotDeployedNotice,
  NotRegisteredNotice,
} from "@/components/app/states";
import { formatCount, formatToken } from "@/lib/format";
import { ReferralCard } from "@/components/app/referral-card";

export default function DashboardPage() {
  const { address, isConnected } = useAccount();
  const { isRegistered, member, isLoading: memberLoading } = useMember();
  const { stages, currentStage, isLoading: stagesLoading } =
    useAllStageMemberships();
  const stats = useProtocolStats();
  const { award } = useAwardInfo(currentStage);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold sm:text-3xl">Dashboard</h1>
        <p className="mt-1 text-sm text-muted">
          Everything below is read directly from the contract.
        </p>
      </div>

      {/* The order of these guards matters: the deepest blocker first, so a
          member is never asked to connect a wallet to an app that has no
          contract to talk to. */}
      {!IS_DEPLOYED ? (
        <NotDeployedNotice />
      ) : !isConnected ? (
        <ConnectPrompt />
      ) : memberLoading || stagesLoading ? (
        <LoadingPanel />
      ) : !isRegistered ? (
        <NotRegisteredNotice />
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat
              label="Total earned"
              value={`${formatToken(member?.totalEarned)} RWAAN`}
              accent
            />
            <Stat label="Current stage" value={stageLabel(currentStage)} />
            <Stat
              label="Rollovers here"
              value={formatCount(stages?.[currentStage]?.rolloverCount)}
            />
            <Stat
              label="Next award at"
              value={
                award ? `${formatCount(award.nextMilestone)} rollovers` : "—"
              }
              hint={award?.eligible ? "Eligible now" : undefined}
            />
          </div>

          <ReferralCard address={address} />

          <section className="panel panel-sheen p-5 sm:p-6">
            <h2 className="font-display text-lg font-semibold">Your stages</h2>
            <p className="mt-1 text-sm text-muted">
              A board opens at every stage you enter. Each position filled pays
              you once.
            </p>

            <div className="mt-5 space-y-2">
              {STAGE_PRESETS.map((preset) => {
                const s = stages?.[preset.stageId];
                const enrolled = Boolean(s?.enrolled);
                const filled = Number(s?.slotsFilledBelow ?? 0);
                const pct = enrolled
                  ? Math.min(100, (filled / preset.slots) * 100)
                  : 0;

                return (
                  <div
                    key={preset.stageId}
                    className="rounded-xl border border-line bg-surface-2 p-4"
                  >
                    <div className="flex items-center justify-between gap-4">
                      <div className="flex items-center gap-3">
                        <span
                          className={
                            enrolled
                              ? "h-2 w-2 rounded-full bg-up"
                              : "h-2 w-2 rounded-full bg-faint"
                          }
                        />
                        <span className="font-medium">{preset.label}</span>
                        {!enrolled && (
                          <span className="text-xs text-faint">Not joined</span>
                        )}
                      </div>
                      <div className="text-right">
                        <div className="figure text-sm">
                          {formatToken(s?.stageEarnings)} RWAAN
                        </div>
                        <div className="text-[11px] text-faint">earned</div>
                      </div>
                    </div>

                    {enrolled && (
                      <div className="mt-3">
                        <div className="flex justify-between text-[11px] text-faint">
                          <span>
                            {filled} of {preset.slots} positions
                          </span>
                          <span>
                            {formatCount(s?.rolloverCount)} rollovers
                          </span>
                        </div>
                        <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-surface-3">
                          <div
                            className="h-full rounded-full bg-gradient-to-r from-goldHi to-gold transition-[width] duration-500"
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </section>

          <section className="grid gap-4 sm:grid-cols-3">
            <Stat
              label="Members"
              value={formatCount(stats.memberCount)}
              small
            />
            <Stat
              label="Paid to members"
              value={`${formatToken(stats.totalPoolPaid)} RWAAN`}
              small
            />
            <Stat
              label="Treasury"
              value={`${formatToken(stats.totalTreasuryPaid)} RWAAN`}
              small
            />
          </section>
        </>
      )}
    </div>
  );
}

function Stat({
  label,
  value,
  hint,
  accent,
  small,
}: {
  label: string;
  value: string;
  hint?: string;
  accent?: boolean;
  small?: boolean;
}) {
  return (
    <div className="panel p-4 sm:p-5">
      <div className="text-[11px] uppercase tracking-wider text-faint">
        {label}
      </div>
      <div
        className={[
          "figure mt-1 font-display font-bold",
          small ? "text-lg" : "text-2xl",
          accent ? "gold-text" : "text-ink",
        ].join(" ")}
      >
        {value}
      </div>
      {hint && <div className="mt-0.5 text-[11px] text-up">{hint}</div>}
    </div>
  );
}
