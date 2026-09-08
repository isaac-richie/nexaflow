"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getAddress } from "viem";
import {
  referralCodeForAddress,
  referralPathForAddress,
} from "@/lib/referrals";
import type { NetworkSummary } from "@/lib/network-graph";
import { ACTIVE_CHAIN, MEMBERSHIP_ADDRESS, MEMBERSHIP_VERSION } from "@/lib/contracts/config";

type NetworkResponse = NetworkSummary & { syncedBlock: number };

const PAGE_SIZE = 20;

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/** Full-precision for small counts, compact ("12.3K") once the number stops
 *  fitting comfortably in a stat card. The exact value is still available
 *  via the `title` attribute wherever the compact form is rendered. */
function formatCount(value: number | undefined): string {
  if (value == null) return "—";
  if (value >= 10_000) {
    return new Intl.NumberFormat("en-US", {
      notation: "compact",
      maximumFractionDigits: 1,
    }).format(value);
  }
  return new Intl.NumberFormat("en-US").format(value);
}

function formatExact(value: number | undefined): string | undefined {
  if (value == null) return undefined;
  return new Intl.NumberFormat("en-US").format(value);
}

export function NetworkOverview({ address }: { address?: `0x${string}` }) {
  return <WalletNetwork key={address?.toLowerCase() ?? "none"} address={address} />;
}

function WalletNetwork({ address }: { address?: `0x${string}` }) {
  const owner = useMemo(() => (address ? getAddress(address) : undefined), [address]);
  const [root, setRoot] = useState<`0x${string}` | undefined>(owner);
  const [generation, setGeneration] = useState(1);
  const [offset, setOffset] = useState(0);
  const [result, setResult] = useState<{ key: string; data: NetworkResponse }>();
  const [loading, setLoading] = useState(true);
  const [failure, setFailure] = useState<{ key: string; message: string }>();
  const [retry, setRetry] = useState(0);
  const [cooldown, setCooldown] = useState(false);
  const refreshTimer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(refreshTimer.current), []);
  const refreshNetwork = () => {
    if (loading || cooldown) return;
    setCooldown(true);
    setRetry(value => value + 1);
    refreshTimer.current = setTimeout(() => setCooldown(false), 15_000);
  };
  const requestKey = `${root}:${generation}:${offset}:${retry}`;
  const data = result?.key === requestKey ? result.data : undefined;
  const error = failure?.key === requestKey ? failure.message : "";

  useEffect(() => {
    setRoot(owner);
    setGeneration(1);
    setOffset(0);
  }, [owner]);

  useEffect(() => {
    if (!root) return;
    const controller = new AbortController();
    const params = new URLSearchParams({
      address: root,
      generation: String(generation),
      offset: String(offset),
      limit: String(PAGE_SIZE),
      contract: MEMBERSHIP_ADDRESS.toLowerCase(),
      version: MEMBERSHIP_VERSION,
      chain: String(ACTIVE_CHAIN.id),
    });

    setLoading(true);
    setFailure(undefined);
    fetch(`/api/network?${params}`, { signal: controller.signal })
      .then(async (response) => {
        const payload = (await response.json()) as
          | NetworkResponse
          | { error?: string };
        if (!response.ok) {
          throw new Error(
            "error" in payload && payload.error
              ? payload.error
              : "Network request failed",
          );
        }
        return payload as NetworkResponse;
      })
      .then(payload => {
        if (!controller.signal.aborted) setResult({ key: requestKey, data: payload });
      })
      .catch((requestError: unknown) => {
        if (controller.signal.aborted) return;
        setFailure({ key: requestKey, message: requestError instanceof Error
            ? requestError.message
            : "Your network is temporarily unavailable." });
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [root, generation, offset, requestKey]);

  const openBranch = useCallback((member: `0x${string}`) => {
    setResult(undefined);
    setRoot(getAddress(member));
    setGeneration(1);
    setOffset(0);
  }, []);

  const returnToOwner = useCallback(() => {
    if (!owner) return;
    setResult(undefined);
    setRoot(owner);
    setGeneration(1);
    setOffset(0);
  }, [owner]);

  const selectGeneration = useCallback((nextGeneration: number) => {
    setGeneration(nextGeneration);
    setOffset(0);
  }, []);

  if (!owner || !root) return null;

  const isOwnNetwork = root.toLowerCase() === owner.toLowerCase();
  const selectedCount =
    data?.generationCounts.find((item) => item.generation === generation)?.count ?? 0;
  const totalTeam = data?.totalTeam;
  const personalReferrals = data?.personalReferrals;
  const generations = data?.generations ?? 0;
  const dailyRegistrations = data?.dailyRegistrations ?? [];
  const lastWeekJoins = dailyRegistrations.slice(-7).reduce((s, d) => s + d.count, 0);

  return (
    <section
      className="panel panel-sheen overflow-hidden rounded-2xl p-4 sm:p-6"
      aria-labelledby="network-title"
    >
      {/* -------- Header: one confident line, breadcrumb on branch view ---- */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2
              id="network-title"
              className="font-display text-base font-semibold sm:text-lg"
            >
              {isOwnNetwork ? "My Network" : "Branch view"}
            </h2>
            <span className="rounded-full border border-up/20 bg-up/10 px-2 py-0.5 text-[10px] font-medium text-up">
              On-chain
            </span>
          </div>
          <p className="mt-1 truncate text-xs text-muted sm:text-sm">
            {isOwnNetwork ? (
              <>
                <span className="figure text-ink">{data ? generations : "—"}</span>{" "}
                {generations === 1 ? "generation" : "generations"} deep
              </>
            ) : (
              <>
                My Network{" "}
                <span aria-hidden="true" className="text-faint">
                  /
                </span>{" "}
                <span className="font-mono text-ink">{shortAddress(root)}</span>
              </>
            )}
          </p>
        </div>
        <button type="button" onClick={refreshNetwork} disabled={loading || cooldown} className="btn-ghost min-h-11 px-3 py-2 text-xs disabled:opacity-50">{loading ? "Updating…" : cooldown ? "Please wait" : "Refresh network"}</button>
        {!isOwnNetwork && (
          <button
            type="button"
            onClick={returnToOwner}
            className="btn-ghost inline-flex min-h-10 items-center gap-1.5 px-3 py-2 text-xs"
          >
            <span aria-hidden="true">←</span> My network
          </button>
        )}
      </div>

      {/* -------- Hero stats: one hero + one secondary, asymmetric ---------- */}
      <div className="mt-4 grid grid-cols-5 gap-2 sm:mt-5 sm:gap-3">
        <HeroStat
          className="col-span-3"
          label="Total team"
          value={totalTeam}
          loading={loading && !data}
          accent
          demoted={!isOwnNetwork}
          chart={
            dailyRegistrations.length > 0 ? (
              <Sparkline series={dailyRegistrations} accent />
            ) : undefined
          }
          badge={
            dailyRegistrations.length > 0 && lastWeekJoins > 0 ? (
              <DeltaChip value={lastWeekJoins} />
            ) : undefined
          }
        />
        <HeroStat
          className="col-span-2"
          label="Personal referrals"
          value={personalReferrals}
          loading={loading && !data}
          demoted={!isOwnNetwork}
        />
      </div>

      {/* -------- Browser: always visible, no collapse ---------------------- */}
      {error ? (
        <div
          className="mt-5 rounded-xl border border-down/20 bg-down/10 p-3 text-sm text-down"
          role="alert"
        >
          {error}
          <button type="button" className="btn-ghost mt-3 block px-4 py-2" disabled={loading || cooldown} onClick={refreshNetwork}>Retry network</button>
        </div>
      ) : (
        <div className="mt-5 sm:mt-6">
          {(data?.generationCounts.length ?? 0) > 0 ? (
            <>
              <LevelStrip
                counts={data?.generationCounts ?? []}
                selected={generation}
                onSelect={selectGeneration}
              />
              <MemberList
                loading={loading}
                loadedGeneration={data?.selectedGeneration}
                currentGeneration={generation}
                selectedCount={selectedCount}
                members={data?.members ?? []}
                onOpenBranch={openBranch}
              />
              {(offset > 0 || data?.hasMore) && (
                <Pagination
                  offset={offset}
                  pageSize={data?.members.length ?? 0}
                  selectedCount={selectedCount}
                  hasMore={Boolean(data?.hasMore)}
                  loading={loading}
                  onPrev={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
                  onNext={() => setOffset(offset + PAGE_SIZE)}
                />
              )}
            </>
          ) : loading || !data ? (
            <NetworkRowsSkeleton />
          ) : (
            <EmptyState address={owner} />
          )}
        </div>
      )}

      {/* -------- One quiet legal line ------------------------------------- */}
      <p className="mt-4 text-[10px] leading-relaxed text-faint sm:text-[11px]">
        Referral lineage is permanent and independent from stage-board placement. Addresses shortened for privacy.
      </p>
    </section>
  );
}

/* ==================================================================== *
 * Stat card                                                             *
 * ==================================================================== */

function HeroStat({
  className,
  label,
  value,
  loading,
  accent,
  demoted,
  chart,
  badge,
}: {
  className?: string;
  label: string;
  value?: number;
  loading: boolean;
  accent?: boolean;
  demoted?: boolean;
  chart?: React.ReactNode;
  badge?: React.ReactNode;
}) {
  const surface = accent
    ? "border-gold/25 bg-gold/[0.06]"
    : "border-line bg-surface-2/65";
  return (
    <div
      className={`relative overflow-hidden rounded-xl border p-3 sm:p-4 ${surface} ${className ?? ""}`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="text-[9px] uppercase leading-tight tracking-[0.14em] text-faint sm:text-[10px]">
          {label}
        </div>
        {badge}
      </div>
      {loading ? (
        <div
          className={`mt-2 animate-pulse rounded bg-surface-3 ${accent ? "h-8 w-24 sm:h-10 sm:w-32" : "h-6 w-16 sm:h-8 sm:w-20"}`}
        />
      ) : (
        <div
          className={`figure mt-1 truncate font-display font-bold leading-tight ${
            accent
              ? demoted
                ? "text-xl text-gold/80 sm:text-3xl"
                : "text-2xl text-gold sm:text-4xl"
              : demoted
                ? "text-base text-ink/80 sm:text-xl"
                : "text-lg text-ink sm:text-2xl"
          }`}
          title={formatExact(value)}
        >
          {formatCount(value)}
        </div>
      )}
      {chart && !loading ? <div className="mt-2 sm:mt-3">{chart}</div> : null}
    </div>
  );
}

/* ==================================================================== *
 * Sparkline — pure inline SVG, no library. 30 bars, gold on brand       *
 * ground, endpoint tick highlighted. Reads as one motif with the        *
 * hero number above it.                                                 *
 * ==================================================================== */

function Sparkline({
  series,
  accent,
}: {
  series: Array<{ day: string; count: number }>;
  accent?: boolean;
}) {
  const width = 220;
  const height = 32;
  const gap = 2;
  const bars = series.length;
  const barWidth = Math.max(1, (width - gap * (bars - 1)) / bars);
  const max = Math.max(1, ...series.map((d) => d.count));

  const fmtDay = (day: string) => {
    // "YYYY-MM-DD" → "Mon 03" style label used inside the tooltip only
    const date = new Date(`${day}T00:00:00Z`);
    return date.toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
  };
  const total30 = series.reduce((s, d) => s + d.count, 0);
  const last = series[series.length - 1];

  return (
    <div>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={`New joins per day, last ${bars} days`}
        className="block h-8 w-full"
      >
        <title>
          {total30} new members in the last {bars} days · {last?.count ?? 0} on {last ? fmtDay(last.day) : ""}
        </title>
        {series.map((d, i) => {
          const barHeight = d.count === 0 ? 1 : Math.max(1.5, (d.count / max) * (height - 2));
          const x = i * (barWidth + gap);
          const y = height - barHeight;
          const isLast = i === series.length - 1;
          const empty = d.count === 0;
          return (
            <rect
              key={d.day}
              x={x}
              y={y}
              width={barWidth}
              height={barHeight}
              rx={barWidth > 3 ? 1 : 0}
              fill={
                empty
                  ? accent
                    ? "rgba(240,185,11,0.14)"
                    : "rgba(234,236,239,0.10)"
                  : isLast
                    ? "#FCD535"
                    : accent
                      ? "rgba(240,185,11,0.55)"
                      : "rgba(234,236,239,0.55)"
              }
            />
          );
        })}
      </svg>
      <div className="mt-1 flex items-center justify-between text-[10px] text-faint">
        <span>{bars}-day activity</span>
        <span className="figure">{formatCount(total30)} new</span>
      </div>
    </div>
  );
}

/* ==================================================================== *
 * Delta chip — small gold "+N this week" tag next to the label          *
 * ==================================================================== */

function DeltaChip({ value }: { value: number }) {
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-full border border-gold/25 bg-gold/10 px-2 py-0.5 text-[10px] font-medium text-gold"
      title={`${new Intl.NumberFormat("en-US").format(value)} new members joined in the last 7 days`}
    >
      <svg width="8" height="8" viewBox="0 0 10 10" aria-hidden="true">
        <path d="M5 1 L9 6 L6 6 L6 9 L4 9 L4 6 L1 6 Z" fill="currentColor" />
      </svg>
      +{formatCount(value)} · 7d
    </span>
  );
}

/* ==================================================================== *
 * Level strip — gold dot marks the active level, more scannable than a  *
 * bg tint alone                                                         *
 * ==================================================================== */

function LevelStrip({
  counts,
  selected,
  onSelect,
}: {
  counts: Array<{ generation: number; count: number }>;
  selected: number;
  onSelect: (generation: number) => void;
}) {
  return (
    <div
      role="tablist"
      aria-label="Referral generations"
      className="flex gap-2 overflow-x-auto pb-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
    >
      {counts.map((item) => {
        const active = selected === item.generation;
        return (
          <button
            key={item.generation}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onSelect(item.generation)}
            className={`inline-flex min-h-10 shrink-0 items-center gap-2 rounded-lg border px-2.5 text-xs font-medium transition-colors sm:px-3 ${
              active
                ? "border-gold/40 bg-gold/10 text-gold"
                : "border-line bg-surface-3 text-muted hover:border-gold/25 hover:text-ink"
            }`}
          >
            {active && (
              <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full bg-gold" />
            )}
            <span>Level {item.generation}</span>
            <span className="figure text-faint">·</span>
            <span className="figure">{formatCount(item.count)}</span>
          </button>
        );
      })}
    </div>
  );
}

/* ==================================================================== *
 * Member list                                                           *
 * ==================================================================== */

function MemberList({
  loading,
  loadedGeneration,
  currentGeneration,
  selectedCount,
  members,
  onOpenBranch,
}: {
  loading: boolean;
  loadedGeneration?: number;
  currentGeneration: number;
  selectedCount: number;
  members: NetworkSummary["members"];
  onOpenBranch: (member: `0x${string}`) => void;
}) {
  const stale = loading && loadedGeneration !== currentGeneration;

  return (
    <>
      <div className="mt-3 flex items-center justify-between gap-3 text-[11px] uppercase tracking-wider text-faint">
        <span>Level {currentGeneration} members</span>
        <span className="figure normal-case tracking-normal">
          {formatCount(selectedCount)} total
        </span>
      </div>

      <ul
        className="divide-y divide-line"
        aria-live="polite"
        aria-busy={loading}
      >
        {stale ? (
          <NetworkRowsSkeleton />
        ) : members.length ? (
          members.map((member) => (
            <li key={member.member}>
              <div className="flex items-center gap-3 py-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                    <a
                      href={`https://bscscan.com/address/${member.member}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="font-mono text-[13px] font-medium text-ink hover:text-gold hover:underline"
                    >
                      {shortAddress(member.member)}
                      <span aria-hidden="true" className="ml-1 text-faint">
                        ↗
                      </span>
                    </a>
                    <span className="text-[10px] text-faint">
                      #{member.memberId}
                    </span>
                  </div>
                  <div className="figure mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11px] text-muted">
                    <span title={formatExact(member.directCount)}>
                      <span className="text-ink">{formatCount(member.directCount)}</span>{" "}
                      direct
                    </span>
                    <span title={formatExact(member.teamCount)}>
                      <span className="text-ink">{formatCount(member.teamCount)}</span>{" "}
                      team
                    </span>
                    <span className="ml-auto font-mono text-faint sm:ml-0">
                      via {shortAddress(member.sponsor)}
                    </span>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => onOpenBranch(member.member)}
                  aria-label={`View ${shortAddress(member.member)}'s branch`}
                  className="btn-ghost inline-flex min-h-10 min-w-10 shrink-0 items-center justify-center rounded-lg px-3 text-sm"
                >
                  <span aria-hidden="true">→</span>
                </button>
              </div>
            </li>
          ))
        ) : (
          <li className="py-6 text-center text-xs text-faint">
            No members in this generation yet.
          </li>
        )}
      </ul>
    </>
  );
}

/* ==================================================================== *
 * Pagination                                                            *
 * ==================================================================== */

function Pagination({
  offset,
  pageSize,
  selectedCount,
  hasMore,
  loading,
  onPrev,
  onNext,
}: {
  offset: number;
  pageSize: number;
  selectedCount: number;
  hasMore: boolean;
  loading: boolean;
  onPrev: () => void;
  onNext: () => void;
}) {
  return (
    <div className="mt-3 flex items-center justify-between gap-3 border-t border-line pt-3">
      <button
        type="button"
        onClick={onPrev}
        disabled={offset === 0 || loading}
        className="btn-ghost inline-flex min-h-10 items-center gap-1.5 px-3 py-2 text-xs disabled:opacity-40"
      >
        <span aria-hidden="true">←</span> Prev
      </button>
      <span className="figure whitespace-nowrap text-[10px] text-faint sm:text-[11px]">
        {offset + 1}–{Math.min(offset + pageSize, selectedCount)} of {formatCount(selectedCount)}
      </span>
      <button
        type="button"
        onClick={onNext}
        disabled={!hasMore || loading}
        className="btn-ghost inline-flex min-h-10 items-center gap-1.5 px-3 py-2 text-xs disabled:opacity-40"
      >
        Next <span aria-hidden="true">→</span>
      </button>
    </div>
  );
}

/* ==================================================================== *
 * Empty state — real CTA, not "share your link above"                   *
 * ==================================================================== */

function EmptyState({ address }: { address: `0x${string}` }) {
  const [origin, setOrigin] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => setOrigin(window.location.origin), []);

  const shareUrl = useMemo(
    () => (origin ? `${origin}${referralPathForAddress(address)}` : ""),
    [origin, address],
  );
  const code = referralCodeForAddress(address);

  async function copy() {
    if (!shareUrl) return;
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(shareUrl);
      } else {
        const el = document.createElement("textarea");
        el.value = shareUrl;
        el.style.position = "fixed";
        el.style.opacity = "0";
        document.body.appendChild(el);
        el.select();
        document.execCommand("copy");
        el.remove();
      }
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      /* silent — the ReferralCard above is the source of truth for errors */
    }
  }

  async function share() {
    if (!shareUrl) return;
    if (navigator.share) {
      try {
        await navigator.share({ title: "Join NexaFlow", url: shareUrl });
        return;
      } catch {
        /* user cancelled — fall through to copy */
      }
    }
    void copy();
  }

  return (
    <div className="rounded-xl border border-dashed border-line bg-surface-2/40 px-4 py-8 text-center sm:px-6">
      <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full border border-gold/25 bg-gold/10 text-gold">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path d="M4 12h13m0 0-5-5m5 5-5 5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>
      <p className="mt-3 text-sm font-medium text-ink">Ready to grow.</p>
      <p className="mt-1 text-xs text-muted">
        Send your link to your first invite. Every registration under it appears here in the same transaction.
      </p>
      <div className="mx-auto mt-4 flex max-w-sm items-center gap-2">
        <div className="flex min-w-0 flex-1 items-center gap-2 rounded-lg border border-line bg-surface-3 px-3 py-2 text-left">
          <span className="rounded-md bg-gold/10 px-1.5 py-0.5 font-mono text-[10px] text-gold">
            {code.slice(0, 8)}…
          </span>
          <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-muted">
            {shareUrl || "Preparing…"}
          </span>
        </div>
        <button
          type="button"
          onClick={share}
          disabled={!shareUrl}
          className="btn-gold min-h-10 px-4 py-2 text-xs disabled:opacity-50"
        >
          {copied ? "Copied" : "Share"}
        </button>
      </div>
    </div>
  );
}

/* ==================================================================== *
 * Skeleton                                                              *
 * ==================================================================== */

function NetworkRowsSkeleton() {
  return (
    <div className="space-y-2 py-3" aria-hidden="true">
      {[0, 1, 2].map((item) => (
        <div
          key={item}
          className="animate-pulse rounded-lg border border-line bg-surface-3/40 p-3"
        >
          <div className="h-3 w-28 rounded bg-surface-3" />
          <div className="mt-2 h-2.5 w-48 max-w-full rounded bg-surface-3" />
        </div>
      ))}
    </div>
  );
}
