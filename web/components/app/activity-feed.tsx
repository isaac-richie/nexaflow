"use client";

import { useAccount, useReadContract } from "wagmi";
import { BINARY_MEMBERSHIP_ABI } from "@/lib/contracts/binaryMembershipAbi";
import {
  IS_DEPLOYED,
  MEMBERSHIP_ADDRESS,
  PAYMENT_TOKEN_SYMBOL,
} from "@/lib/contracts/config";
import { formatToken } from "@/lib/format";

type Activity = {
  icon: "slot" | "rollover" | "award" | "join";
  label: string;
  detail: string;
  accent?: boolean;
};

export function ActivityFeed({ stageId }: { stageId: number }) {
  const { address } = useAccount();

  const { data: membership } = useReadContract({
    address: MEMBERSHIP_ADDRESS,
    abi: BINARY_MEMBERSHIP_ABI,
    functionName: "getStageMembership",
    args: address ? [address, BigInt(stageId)] : undefined,
    query: { enabled: IS_DEPLOYED && Boolean(address) && stageId >= 0 },
  });

  const m = membership as {
    enrolled: boolean;
    slotsFilledBelow: bigint;
    rolloverCount: bigint;
    stageEarnings: bigint;
    totalAwarded: bigint;
  } | undefined;

  if (!m?.enrolled) return null;

  const filled = Number(m.slotsFilledBelow);
  const rollovers = Number(m.rolloverCount);
  const activities: Activity[] = [];

  if (Number(m.totalAwarded) > 0) {
    activities.push({
      icon: "award",
      label: "Award received",
      detail: `${formatToken(m.totalAwarded)} ${PAYMENT_TOKEN_SYMBOL}`,
      accent: true,
    });
  }

  if (rollovers > 0) {
    activities.push({
      icon: "rollover",
      label: `Board cycled ${rollovers} time${rollovers > 1 ? "s" : ""}`,
      detail: `Full board cleared and restarted`,
    });
  }

  if (filled > 0) {
    activities.push({
      icon: "slot",
      label: `${filled} position${filled > 1 ? "s" : ""} filled`,
      detail: `${formatToken(m.stageEarnings)} ${PAYMENT_TOKEN_SYMBOL} earned`,
    });
  }

  activities.push({
    icon: "join",
    label: `Joined Stage ${stageId + 1}`,
    detail: "Board opened",
  });

  return (
    <section className="panel panel-sheen p-4 sm:p-5">
      <h2 className="text-sm font-semibold">Board summary</h2>
      <p className="mt-0.5 text-xs text-faint">
        Live totals from your current board.
      </p>
      <div className="mt-3 space-y-0">
        {activities.map((a, i) => (
          <div
            key={i}
            className="flex items-start gap-3 py-2.5"
            style={i < activities.length - 1 ? { borderBottom: "1px solid hsl(var(--line) / 0.5)" } : undefined}
          >
            <div className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full ${
              a.icon === "award"
                ? "bg-gold/15 text-gold"
                : a.icon === "rollover"
                  ? "bg-up/15 text-up"
                  : a.icon === "slot"
                    ? "bg-up/10 text-up"
                    : "bg-surface-3 text-muted"
            }`}>
              {a.icon === "award" && (
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <circle cx="12" cy="8" r="6" /><path d="M8.21 13.89 7 23l5-3 5 3-1.21-9.12" />
                </svg>
              )}
              {a.icon === "rollover" && (
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path d="M3 3v5h5" />
                  <path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16" /><path d="M16 16h5v5" />
                </svg>
              )}
              {a.icon === "slot" && (
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" />
                  <path d="M22 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" />
                </svg>
              )}
              {a.icon === "join" && (
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" /><polyline points="10 17 15 12 10 7" /><line x1="15" y1="12" x2="3" y2="12" />
                </svg>
              )}
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-sm font-medium leading-tight">{a.label}</div>
              <div className={`mt-0.5 text-xs ${a.accent ? "text-gold" : "text-faint"}`}>{a.detail}</div>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
