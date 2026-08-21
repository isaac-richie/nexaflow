/**
 * One place for every client-side RPC budget decision.
 *
 * React Query deduplicates identical reads while they are in flight and keeps
 * the result for the stale window below. Viem additionally combines nearby
 * `readContract` calls into one Multicall3 `eth_call` (configured in wagmi.ts).
 * No policy here is applied to writes, simulations, or explicit user refreshes.
 */

function boundedMilliseconds(
  raw: string | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.trunc(parsed)));
}

/** Receipt/block polling only runs while an operation explicitly watches. */
export const RPC_POLLING_INTERVAL_MS = boundedMilliseconds(
  process.env.NEXT_PUBLIC_RPC_POLLING_INTERVAL_MS,
  8_000,
  5_000,
  30_000,
);

/** Small batching window that groups reads mounted during the same render. */
export const RPC_MULTICALL_WAIT_MS = boundedMilliseconds(
  process.env.NEXT_PUBLIC_RPC_MULTICALL_WAIT_MS,
  40,
  0,
  100,
);

/** Viem's short exact-request cache catches duplicate calls between hooks. */
export const RPC_CLIENT_CACHE_MS = 6_000;

export const RPC_CACHE_MS = {
  wallet: 30_000,
  placement: 20_000,
  member: 45_000,
  board: 45_000,
  award: 45_000,
  priceQuote: 45_000,
  protocolStats: 120_000,
  protocolOpen: 120_000,
  stageConfig: 10 * 60_000,
  tokenMetadata: Number.POSITIVE_INFINITY,
  garbageCollection: 15 * 60_000,
} as const;

/**
 * Reads refresh on first mount after their own stale window, or when code/user
 * explicitly refetches. They never poll invisibly in a background tab.
 */
export const NO_BACKGROUND_RPC = {
  refetchInterval: false,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
} as const;

export function isRateLimitError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  const lower = message.toLowerCase();
  return message.includes("429") || lower.includes("too many requests");
}

export function isPermanentRpcRequestError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  const lower = message.toLowerCase();
  return message.includes("400") || lower.includes("bad request");
}
