/** No signing keys here. Dependencies are injected for deterministic safety tests. */
export type Intent = { hash: `0x${string}`; raw: `0x${string}`; nonce: number; stage: number; work: number; contract: string; createdAt: number };
export type KeeperStore = {
  acquire(): Promise<boolean>;
  release(): Promise<void>;
  pending(): Promise<Intent | null>;
  cursor(): Promise<number>;
  // Atomically check lease ownership, empty pending slot, rolling budget, then persist.
  reserve(intent: Intent, costGwei: number, budgetGwei: number): Promise<boolean>;
  complete(hash: string): Promise<boolean>;
};
export type KeeperChain = {
  verify(): Promise<void>;
  recovery(): Promise<boolean>;
  queues(): Promise<bigint[]>;
  receipt(hash: `0x${string}`): Promise<"pending" | "success" | "reverted" | "no_progress">;
  prepare(stage: number): Promise<{ intent: Intent; costGwei: number } | null>;
  broadcast(intent: Intent): Promise<void>;
};
export async function runQueueKeeper(store: KeeperStore, chain: KeeperChain, options: { dryRun: boolean; contract: string; budgetGwei: number; now: number }) {
  if (!await store.acquire()) return { status: "busy" };
  try {
    await chain.verify();
    const pending = await store.pending();
    if (pending) {
      if (pending.contract.toLowerCase() !== options.contract.toLowerCase()) return { status: "pending_deployment_mismatch" };
      const receipt = await chain.receipt(pending.hash);
      if (receipt !== "pending") {
        if (!await store.complete(pending.hash)) return { status: "lease_lost" };
        // Never send another transaction in the same invocation as settlement.
        return { status: receipt === "success" ? "confirmed" : receipt, hash: pending.hash };
      }
      if (await chain.recovery()) return { status: "recovery_pending", hash: pending.hash };
      if (options.now - pending.createdAt > 15 * 60_000) return { status: "pending_stalled", hash: pending.hash };
      if (options.dryRun) return { status: "dry_run_pending", hash: pending.hash };
      // Only rebroadcast identical persisted bytes; never create a replacement/nonce.
      await chain.broadcast(pending);
      return { status: "pending", hash: pending.hash };
    }
    if (await chain.recovery()) return { status: "recovery" };
    const queues = await chain.queues();
    if (queues.every(n => n === 0n)) return { status: "idle" };
    if (options.dryRun) return { status: "dry_run", queues: queues.map(String) };
    // Persisted rotation is independent of scheduler interval or missed runs.
    const first = await store.cursor();
    if (!Number.isInteger(first) || first < 0 || first > 5) throw new Error("Invalid keeper stage cursor");
    for (let offset = 0; offset < 6; offset++) {
      const stage = (first + offset) % 6;
      if (queues[stage] === 0n) continue;
      const prepared = await chain.prepare(stage);
      if (!prepared) continue; // simulation says no progress: no gas spent
      if (!await store.reserve(prepared.intent, prepared.costGwei, options.budgetGwei)) return { status: "budget_or_lease_blocked" };
      // A crash from this point is recoverable using the persisted raw tx.
      await chain.broadcast(prepared.intent);
      return { status: "submitted", hash: prepared.intent.hash, stage: stage + 1 };
    }
    return { status: "no_progress" };
  } finally {
    await store.release();
  }
}
