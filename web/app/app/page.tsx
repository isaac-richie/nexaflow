"use client";

import { useAccount } from "wagmi";
import { formatUnits } from "viem";
import {
  IS_DEPLOYED,
  PAYMENT_TOKEN_SYMBOL,
  STAGE_PRESETS,
  stageLabel,
} from "@/lib/contracts/config";
import {
  useAllStageMemberships,
  useAwardInfo,
  useMember,
  useProtocolStats,
} from "@/hooks/use-membership";
import {
  ConnectPrompt,
  NotDeployedNotice,
  NotRegisteredNotice,
} from "@/components/app/states";
import { formatCount, formatToken } from "@/lib/format";
import { ReferralCard } from "@/components/app/referral-card";
import { DashboardBg } from "@/components/app/dashboard-bg";
import { LiveBoard } from "@/components/app/live-board";
import { StageRing } from "@/components/app/stage-ring";
import { CountUp } from "@/components/app/count-up";
import { ActivityFeed } from "@/components/app/activity-feed";
import { DashboardSkeleton } from "@/components/app/shimmer-skeleton";

export default function DashboardPage() {
  const { address, isConnected } = useAccount();
  const { isRegistered, member, isLoading: memberLoading } = useMember();
  const { stages, currentStage, isLoading: stagesLoading } =
    useAllStageMemberships();
  const stats = useProtocolStats();
  const { award } = useAwardInfo(currentStage);

  const loading = memberLoading || stagesLoading;

  return (
    <div className="relative space-y-4 sm:space-y-6">
      <DashboardBg />

      <div>
        <h1 className="font-display text-xl font-bold sm:text-3xl">Dashboard</h1>
        <p className="mt-0.5 text-xs text-muted sm:mt-1 sm:text-sm">
          Everything below is read directly from the contract.
        </p>
      </div>

      {!IS_DEPLOYED ? (
        <NotDeployedNotice />
      ) : !isConnected ? (
        <ConnectPrompt />
      ) : loading ? (
        <DashboardSkeleton />
      ) : !isRegistered ? (
        <NotRegisteredNotice />
      ) : (
        <>
          {/* ── Stat cards: 2×2 on mobile, 4 on desktop ── */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
            <StatCard
              label="Total earned"
              rawValue={member?.totalEarned}
              suffix={` ${PAYMENT_TOKEN_SYMBOL}`}
              accent
            />
            <StatCard
              label="Current stage"
              text={stageLabel(currentStage)}
            />
            <StatCard
              label="Rollovers"
              rawValue={stages?.[currentStage]?.rolloverCount}
              decimals={0}
            />
            <StatCard
              label="Next award"
              text={award ? `${formatCount(award.nextMilestone)} cycles` : "—"}
              hint={award?.eligible ? "Eligible now" : undefined}
            />
          </div>

          {/* ── Live board tree ── */}
          {currentStage >= 0 && stages?.[currentStage] && (
            <section className="panel panel-sheen p-4 sm:p-6">
              <div className="flex items-start justify-between gap-3 mb-3 sm:mb-4">
                <div>
                  <h2 className="font-display text-base font-semibold sm:text-lg">
                    Your {STAGE_PRESETS[currentStage].label} board
                  </h2>
                  <p className="mt-0.5 text-xs text-muted sm:text-sm">
                    Green = paid you. Dashed = waiting.
                  </p>
                </div>
                <span className="shrink-0 rounded-full border border-up/25 bg-up/10 px-2.5 py-0.5 text-[10px] font-medium text-up sm:px-3 sm:py-1 sm:text-xs">
                  Active
                </span>
              </div>
              <LiveBoard
                preset={STAGE_PRESETS[currentStage]}
                membership={stages[currentStage]}
              />
            </section>
          )}

          {/* ── Referral card ── */}
          <ReferralCard address={address} />

          {/* ── Stage progress: horizontal scroll on mobile ── */}
          <section className="panel panel-sheen p-4 sm:p-6">
            <h2 className="font-display text-base font-semibold sm:text-lg">
              Your stages
            </h2>
            <p className="mt-0.5 text-xs text-muted sm:text-sm">
              Each position filled pays you once.
            </p>

            {/* Mobile: horizontal scroll cards */}
            <div className="mt-4 stage-scroll sm:hidden">
              {STAGE_PRESETS.map((preset) => {
                const s = stages?.[preset.stageId];
                const enrolled = Boolean(s?.enrolled);
                const filled = Number(s?.slotsFilledBelow ?? 0);
                const pct = enrolled ? Math.min(100, (filled / preset.slots) * 100) : 0;
                const isActive = preset.stageId === currentStage;

                return (
                  <div
                    key={preset.stageId}
                    className={`stage-snap relative w-[160px] rounded-xl border p-3 ${
                      isActive
                        ? "stage-active border-up/20"
                        : "border-line bg-surface-2/60"
                    }`}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-medium">{preset.label}</span>
                      <span className={enrolled
                        ? "h-1.5 w-1.5 rounded-full bg-up shadow-[0_0_4px_hsl(var(--up)/0.5)]"
                        : "h-1.5 w-1.5 rounded-full bg-faint"
                      } />
                    </div>

                    <div className="flex justify-center my-2">
                      {enrolled ? (
                        <StageRing
                          filled={filled}
                          total={preset.slots}
                          size={56}
                          label={`${Math.round(pct)}%`}
                        />
                      ) : (
                        <div className="flex h-14 w-14 items-center justify-center rounded-full border border-dashed border-line">
                          <span className="text-xs text-faint">${preset.fee}</span>
                        </div>
                      )}
                    </div>

                    <div className="text-center">
                      <div className={`figure text-sm font-semibold ${
                        enrolled && Number(s?.stageEarnings ?? 0n) > 0
                          ? "text-up" : "text-ink"
                      }`}>
                        {formatToken(s?.stageEarnings)} <span className="text-[10px] text-faint">{PAYMENT_TOKEN_SYMBOL}</span>
                      </div>
                      {enrolled && (
                        <div className="mt-1 text-[10px] text-faint">
                          {filled}/{preset.slots} · {formatCount(s?.rolloverCount)} cycles
                        </div>
                      )}
                      {!enrolled && (
                        <div className="mt-1 text-[10px] text-faint">Not joined</div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Desktop: list with rings */}
            <div className="mt-5 hidden space-y-2 sm:block">
              {STAGE_PRESETS.map((preset) => {
                const s = stages?.[preset.stageId];
                const enrolled = Boolean(s?.enrolled);
                const filled = Number(s?.slotsFilledBelow ?? 0);
                const pct = enrolled
                  ? Math.min(100, (filled / preset.slots) * 100)
                  : 0;
                const isActive = preset.stageId === currentStage;

                return (
                  <div
                    key={preset.stageId}
                    className={`stage-card relative rounded-xl border p-4 ${
                      isActive
                        ? "stage-active border-up/20"
                        : "border-line bg-surface-2/60"
                    }`}
                  >
                    <div className="flex items-center gap-4">
                      {enrolled ? (
                        <StageRing
                          filled={filled}
                          total={preset.slots}
                          label={`${Math.round(pct)}%`}
                        />
                      ) : (
                        <div className="flex h-[52px] w-[52px] items-center justify-center
                                        rounded-full border border-dashed border-line">
                          <span className="text-[10px] text-faint">${preset.fee}</span>
                        </div>
                      )}

                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className={
                            enrolled
                              ? "h-2 w-2 rounded-full bg-up shadow-[0_0_6px_hsl(var(--up)/0.5)]"
                              : "h-2 w-2 rounded-full bg-faint"
                          } />
                          <span className="font-medium">{preset.label}</span>
                          {!enrolled && (
                            <span className="text-xs text-faint">Not joined</span>
                          )}
                        </div>
                        {enrolled && (
                          <div className="mt-1.5 flex items-center gap-3 text-[11px] text-faint">
                            <span>{filled} of {preset.slots} positions</span>
                            <span className="h-3 w-px bg-line" />
                            <span>{formatCount(s?.rolloverCount)} rollovers</span>
                          </div>
                        )}
                      </div>

                      <div className="text-right shrink-0">
                        <div className={`figure text-sm ${
                          enrolled && Number(s?.stageEarnings ?? 0n) > 0
                            ? "text-up" : "text-ink"
                        }`}>
                          {formatToken(s?.stageEarnings)} {PAYMENT_TOKEN_SYMBOL}
                        </div>
                        <div className="text-[11px] text-faint">earned</div>
                      </div>
                    </div>

                    {enrolled && (
                      <div className="mt-3 ml-[68px]">
                        <div className="h-1 overflow-hidden rounded-full bg-surface-3">
                          <div
                            className="h-full rounded-full bg-gradient-to-r from-goldHi to-gold transition-[width] duration-700 ease-out"
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

          {/* ── Activity feed ── */}
          {currentStage >= 0 && <ActivityFeed stageId={currentStage} />}

          {/* ── Protocol stats ── */}
          <section className="grid grid-cols-3 gap-3 sm:gap-4">
            <MiniStat label="Members" rawValue={stats.memberCount} />
            <MiniStat
              label="Paid out"
              rawValue={stats.totalPoolPaid}
              suffix={` ${PAYMENT_TOKEN_SYMBOL}`}
            />
            <MiniStat
              label="Treasury"
              rawValue={stats.totalTreasuryPaid}
              suffix={` ${PAYMENT_TOKEN_SYMBOL}`}
            />
          </section>
        </>
      )}
    </div>
  );
}

function toNum(raw?: bigint, decimals = 18): number {
  if (raw == null) return 0;
  return Number(formatUnits(raw, decimals));
}

function StatCard({
  label,
  rawValue,
  text,
  suffix = "",
  decimals = 2,
  accent,
  hint,
}: {
  label: string;
  rawValue?: bigint;
  text?: string;
  suffix?: string;
  decimals?: number;
  accent?: boolean;
  hint?: string;
}) {
  const num = rawValue != null ? toNum(rawValue) : undefined;

  return (
    <div className={`panel p-3 sm:p-5 ${accent ? "stat-glow stat-glow-accent" : "stat-glow"}`}>
      <div className="text-[10px] uppercase tracking-wider text-faint sm:text-[11px]">
        {label}
      </div>
      <div className={`figure mt-1 font-display font-bold ${
        accent ? "stat-shimmer text-xl sm:text-2xl" : "text-lg text-ink sm:text-2xl"
      }`}>
        {text != null ? (
          text
        ) : num != null ? (
          <CountUp value={num} decimals={decimals} suffix={suffix} />
        ) : (
          "—"
        )}
      </div>
      {hint && (
        <div className="mt-0.5 flex items-center gap-1.5 text-[10px] text-up sm:text-[11px]">
          <span className="relative flex h-1.5 w-1.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-up opacity-60" />
            <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-up" />
          </span>
          {hint}
        </div>
      )}
    </div>
  );
}

function MiniStat({
  label,
  rawValue,
  suffix = "",
}: {
  label: string;
  rawValue?: bigint;
  suffix?: string;
}) {
  const num = rawValue != null ? toNum(rawValue) : 0;
  const isCount = !suffix;

  return (
    <div className="panel stat-glow p-3 sm:p-4">
      <div className="text-[9px] uppercase tracking-wider text-faint sm:text-[11px]">
        {label}
      </div>
      <div className="figure mt-1 text-sm font-bold text-ink sm:text-lg">
        <CountUp
          value={num}
          decimals={isCount ? 0 : 2}
          suffix={suffix}
        />
      </div>
    </div>
  );
}
