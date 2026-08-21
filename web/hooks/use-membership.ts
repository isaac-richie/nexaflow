"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { BINARY_MEMBERSHIP_ABI } from "@/lib/contracts/binaryMembershipAbi";
import {
  IS_DEPLOYED,
  MAX_STAGES,
  MEMBERSHIP_ADDRESS,
  ZERO_ADDRESS,
} from "@/lib/contracts/config";
import { NO_BACKGROUND_RPC, RPC_CACHE_MS } from "@/lib/rpc-policy";

const base = {
  address: MEMBERSHIP_ADDRESS,
  abi: BINARY_MEMBERSHIP_ABI,
} as const;

/**
 * Every hook here is gated on `IS_DEPLOYED`. Before an address is configured
 * the queries stay disabled and return `undefined`, so the UI can render an
 * honest "not deployed" state. The alternative — querying 0x0 and getting
 * zeroes back — would render a confident dashboard full of numbers that mean
 * nothing, which is worse than showing nothing.
 */

export type MemberSummary = {
  active: boolean;
  sponsor: `0x${string}`;
  joinedAt: bigint;
  totalEarned: bigint;
};

export function useMember(address?: `0x${string}`) {
  const { address: connected } = useAccount();
  const target = address ?? connected;

  const query = useReadContract({
    ...base,
    functionName: "getMember",
    args: target ? [target] : undefined,
    query: {
      enabled: IS_DEPLOYED && Boolean(target),
      staleTime: RPC_CACHE_MS.member,
      ...NO_BACKGROUND_RPC,
    },
  });

  return {
    ...query,
    member: query.data as MemberSummary | undefined,
    isRegistered: Boolean((query.data as MemberSummary | undefined)?.active),
  };
}

export type StageMembership = {
  enrolled: boolean;
  parent: `0x${string}`;
  side: number;
  left: `0x${string}`;
  right: `0x${string}`;
  slotsFilledBelow: bigint;
  rolloverCount: bigint;
  lastAwardedRollover: bigint;
  stageEarnings: bigint;
  totalAwarded: bigint;
};

/** All six stage memberships for one member, in a single multicall. */
export function useAllStageMemberships(address?: `0x${string}`) {
  const { address: connected } = useAccount();
  const target = address ?? connected;

  const query = useReadContracts({
    contracts: Array.from({ length: MAX_STAGES }, (_, stageId) => ({
      ...base,
      functionName: "getStageMembership" as const,
      args: target ? ([target, BigInt(stageId)] as const) : undefined,
    })),
    query: {
      enabled: IS_DEPLOYED && Boolean(target),
      staleTime: RPC_CACHE_MS.board,
      ...NO_BACKGROUND_RPC,
    },
  });

  const stages = query.data?.map(
    (r) => (r.status === "success" ? (r.result as StageMembership) : undefined),
  );

  /** Highest stage the member is enrolled in, or -1 if none. */
  const currentStage =
    stages?.reduce(
      (acc, s, i) => (s?.enrolled ? i : acc),
      -1,
    ) ?? -1;

  return { ...query, stages, currentStage };
}

export type StageConfig = {
  fee: bigint;
  nodeReward: bigint;
  treeSlots: bigint;
  treeDepth: bigint;
  rolloversForAward: bigint;
};

/**
 * On-chain stage configuration. Read rather than hardcoded because admin can
 * retune fees and thresholds at runtime — a UI showing stale presets would be
 * quoting a price the contract will not honour.
 */
export function useStageConfigs() {
  const query = useReadContracts({
    contracts: Array.from({ length: MAX_STAGES }, (_, stageId) => ({
      ...base,
      functionName: "getStageConfig" as const,
      args: [BigInt(stageId)] as const,
    })),
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.stageConfig,
      ...NO_BACKGROUND_RPC,
    },
  });

  const configs = query.data?.map(
    (r) => (r.status === "success" ? (r.result as StageConfig) : undefined),
  );

  return { ...query, configs };
}

/** One stage config when a screen does not need to fetch the full ladder. */
export function useStageConfig(stageId: number) {
  const query = useReadContract({
    ...base,
    functionName: "getStageConfig",
    args: [BigInt(stageId)],
    query: {
      enabled: IS_DEPLOYED && stageId >= 0 && stageId < MAX_STAGES,
      staleTime: RPC_CACHE_MS.stageConfig,
      ...NO_BACKGROUND_RPC,
    },
  });

  return { ...query, config: query.data as StageConfig | undefined };
}

export type StagePaymentQuote = {
  feeAmount: bigint;
  rewardAmount: bigint;
  priceUsd18: bigint;
  updatedAt: bigint;
};

function toStagePaymentQuote(
  raw: readonly [bigint, bigint, bigint, bigint] | undefined,
): StagePaymentQuote | undefined {
  if (!raw) return undefined;
  return {
    feeAmount: raw[0],
    rewardAmount: raw[1],
    priceUsd18: raw[2],
    updatedAt: raw[3],
  };
}

/** Live RWAAN amounts calculated from the contract's current oracle price. */
export function useStagePaymentQuotes() {
  const query = useReadContracts({
    contracts: Array.from({ length: MAX_STAGES }, (_, stageId) => ({
      ...base,
      functionName: "quoteStagePayment" as const,
      args: [BigInt(stageId)] as const,
    })),
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.priceQuote,
      ...NO_BACKGROUND_RPC,
    },
  });

  const quotes = query.data?.map((r) => {
    if (r.status !== "success") return undefined;
    const raw = r.result as readonly [bigint, bigint, bigint, bigint];
    return toStagePaymentQuote(raw);
  });

  return { ...query, quotes };
}

/** One live stage quote; paid actions explicitly refetch it before signing. */
export function useStagePaymentQuote(stageId: number) {
  const query = useReadContract({
    ...base,
    functionName: "quoteStagePayment",
    args: [BigInt(stageId)],
    query: {
      enabled: IS_DEPLOYED && stageId >= 0 && stageId < MAX_STAGES,
      staleTime: RPC_CACHE_MS.priceQuote,
      ...NO_BACKGROUND_RPC,
    },
  });

  const raw = query.data as
    | readonly [bigint, bigint, bigint, bigint]
    | undefined;
  return { ...query, quote: toStagePaymentQuote(raw) };
}

/**
 * Whether the contract can price a stage right now.
 *
 * The oracle is a PancakeSwap V2 TWAP that someone must advance by calling
 * `update()`. If the last update is older than the contract's `maxPriceAge`,
 * every quote and every paid action reverts with `StalePrice` — which is the
 * safety feature working, not a fault, but it means registration is closed
 * until the price is refreshed.
 *
 * Without this the member sees a form with no amount on it and no reason why,
 * or signs a transaction that reverts in their wallet. Both look like a broken
 * app rather than a temporary pricing gap.
 */
export function useOraclePriceHealth() {
  const query = useReadContract({
    ...base,
    functionName: "latestAssetPriceUsd",
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.priceQuote,
      // A stale price is a legitimate contract state, not a flaky call.
      // Retrying just burns RPC budget and delays the honest message.
      retry: false,
      ...NO_BACKGROUND_RPC,
    },
  });

  // viem nests the custom error; the name is the reliable signal across
  // wrapper layers, so match on the serialised message rather than trying to
  // unwrap every possible error shape.
  const message = query.error ? String(query.error.message ?? query.error) : "";
  const isStale = message.includes("StalePrice");

  return {
    ...query,
    priceUsd18: query.data as bigint | undefined,
    isStale,
    /** True only when we positively know pricing works. */
    isPriceable: !query.isLoading && !query.isError,
  };
}

export type AwardInfo = {
  totalAwarded: bigint;
  lastAwardedRollover: bigint;
  rolloverCount: bigint;
  nextMilestone: bigint;
  eligible: boolean;
};

export function useAwardInfo(stageId: number, address?: `0x${string}`) {
  const { address: connected } = useAccount();
  const target = address ?? connected;

  const query = useReadContract({
    ...base,
    functionName: "getAwardInfo",
    args: target ? [target, BigInt(stageId)] : undefined,
    query: {
      enabled:
        IS_DEPLOYED && Boolean(target) && stageId >= 0 && stageId < MAX_STAGES,
      staleTime: RPC_CACHE_MS.award,
      ...NO_BACKGROUND_RPC,
    },
  });

  const raw = query.data as
    | readonly [bigint, bigint, bigint, bigint, boolean]
    | undefined;

  const award: AwardInfo | undefined = raw
    ? {
        totalAwarded: raw[0],
        lastAwardedRollover: raw[1],
        rolloverCount: raw[2],
        nextMilestone: raw[3],
        eligible: raw[4],
      }
    : undefined;

  return { ...query, award };
}

/**
 * Where a new member would be placed. This is the ONLY placement call the UI
 * should make: it walks the sponsor chain, keeps the recruit inside their own
 * lineage, and falls back to the stage anchor on its own. Calling
 * `findSponsorSlot` directly means handling two failure modes by hand.
 */
export function usePlacementSlot(sponsor?: `0x${string}`, stageId = 0) {
  const query = useReadContract({
    ...base,
    functionName: "findPlacementSlot",
    args: sponsor ? [sponsor, BigInt(stageId)] : undefined,
    query: {
      enabled: IS_DEPLOYED && Boolean(sponsor),
      staleTime: RPC_CACHE_MS.placement,
      ...NO_BACKGROUND_RPC,
    },
  });

  const raw = query.data as readonly [`0x${string}`, number] | undefined;

  return {
    ...query,
    parent: raw?.[0],
    side: raw?.[1],
  };
}

/**
 * Whether the protocol can actually take a member yet.
 *
 * Deployment and opening are two different events. The contract can be live and
 * fully configured while `stageAnchor(0)` is still zero, because the designated
 * root has not registered — and until it does, `findPlacementSlot` reverts and
 * every join fails. Without this check the join page would offer a form that
 * cannot succeed and blame the user's wallet for the revert.
 */
export function useProtocolOpen() {
  const query = useReadContract({
    ...base,
    functionName: "stageAnchor",
    args: [0n],
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.protocolOpen,
      ...NO_BACKGROUND_RPC,
    },
  });

  const anchor = query.data as `0x${string}` | undefined;

  return {
    ...query,
    anchor,
    isOpen: Boolean(anchor && anchor !== ZERO_ADDRESS),
  };
}

/** Protocol-wide counters for the dashboard header. */
export function useProtocolStats() {
  const query = useReadContracts({
    contracts: [
      { ...base, functionName: "memberCount" },
      { ...base, functionName: "totalPoolPaid" },
      { ...base, functionName: "totalTreasuryPaid" },
    ],
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.protocolStats,
      ...NO_BACKGROUND_RPC,
    },
  });

  const [members, poolPaid, treasuryPaid] = query.data ?? [];

  return {
    ...query,
    memberCount: members?.status === "success" ? (members.result as bigint) : undefined,
    totalPoolPaid: poolPaid?.status === "success" ? (poolPaid.result as bigint) : undefined,
    totalTreasuryPaid:
      treasuryPaid?.status === "success" ? (treasuryPaid.result as bigint) : undefined,
  };
}
