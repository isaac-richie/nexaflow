import { erc20Abi, isAddress, keccak256, zeroAddress, type Address, type Hex, type PublicClient } from "viem";
import { BINARY_MEMBERSHIP_V6_ABI as abi } from "./contracts/binaryMembershipV6Abi";

export type V6Deployment = { chainId: number; address: Address; token: Address; runtimeHash?: Hex };
export type V6Position = {
  owner: Address; stage: number; filled: number; closed: boolean; queued: boolean;
  cycle: bigint; parent: bigint; left: bigint; right: bigint; reserve: bigint;
};
export type V6Stage = {
  id: number; fee: bigint; reward: bigint; slots: number; depth: number; reserveSlots: number;
  enrolled: boolean; boards: bigint; activeId: bigint; latestId: bigint;
  latest?: V6Position; completed: bigint; earned: bigint;
};
export type V6Snapshot = {
  block: bigint; root: Address; paused: boolean; recovery: boolean; registered: boolean;
  highestStage: number; sponsor: Address; earned: bigint; claimable: bigint;
  balance: bigint; allowance: bigint; stages: V6Stage[];
};

export function validateV6Deployment(d: V6Deployment) {
  if (![56, 97, 31337].includes(d.chainId) || !isAddress(d.address) || !isAddress(d.token) ||
    d.address === zeroAddress || d.token === zeroAddress || !/^0x[\da-fA-F]{64}$/.test(d.runtimeHash ?? "")) {
    throw new Error("Registration is temporarily unavailable. Please try again later.");
  }
}

/** Fail closed for an old address, empty code, wrong token or wrong RPC chain. */
export async function verifyV6(client: PublicClient, d: V6Deployment, block?: bigint) {
  validateV6Deployment(d);
  if (await client.getChainId() !== d.chainId) throw new Error("Network mismatch. Please switch to the supported network.");
  const code = await client.getCode({ address: d.address, blockNumber: block });
  if (!code || code === "0x" || keccak256(code).toLowerCase() !== d.runtimeHash!.toLowerCase()) {
    throw new Error("Contract identity check failed. No approval or payment will be requested.");
  }
  const token = await client.readContract({ address: d.address, abi, functionName: "asset", blockNumber: block });
  if (token.toLowerCase() !== d.token.toLowerCase()) throw new Error("Payment token mismatch.");
  const decimals = await client.readContract({ address: d.token, abi: erc20Abi, functionName: "decimals", blockNumber: block });
  if (decimals !== 18) throw new Error("Unsupported payment token decimals.");
}

/** All member data is read at one block, not combined across a rollover. */
export async function readV6Snapshot(client: PublicClient, d: V6Deployment, member: Address): Promise<V6Snapshot> {
  const block = await client.getBlockNumber({ cacheTime: 0 });
  await verifyV6(client, d, block);
  const base = { address: d.address, abi } as const;
  const values = await client.multicall({ allowFailure: false, blockNumber: block, contracts: [
    { ...base, functionName: "root" }, { ...base, functionName: "paused" },
    { ...base, functionName: "emergencyRecovery" },
    { ...base, functionName: "registered", args: [member] },
    { ...base, functionName: "highestStage", args: [member] },
    { ...base, functionName: "sponsorOf", args: [member] },
    { ...base, functionName: "earnings", args: [member] },
    { ...base, functionName: "claimable", args: [member] },
    { address: d.token, abi: erc20Abi, functionName: "balanceOf", args: [member] },
    { address: d.token, abi: erc20Abi, functionName: "allowance", args: [member, d.address] },
  ] as const });
  const [configs, counts, active] = await Promise.all([
    client.multicall({ allowFailure: false, blockNumber: block, contracts: Array.from({ length: 6 }, (_, id) => ({ ...base, functionName: "stages", args: [id] } as const)) }),
    client.multicall({ allowFailure: false, blockNumber: block, contracts: Array.from({ length: 6 }, (_, id) => ({ ...base, functionName: "boardCount", args: [member, id] } as const)) }),
    client.multicall({ allowFailure: false, blockNumber: block, contracts: Array.from({ length: 6 }, (_, id) => ({ ...base, functionName: "activePosition", args: [member, id] } as const)) }),
  ]);
  const stages: V6Stage[] = [];
  const known = counts.map((count, id) => ({ count, id })).filter(s => s.count > 0n);
  const ids = known.length ? await client.multicall({ allowFailure: false, blockNumber: block,
    contracts: known.map(s => ({ ...base, functionName: "boardIdAt", args: [member, s.id, s.count - 1n] } as const)) }) : [];
  const positions = ids.length ? await client.multicall({ allowFailure: false, blockNumber: block,
    contracts: ids.map(id => ({ ...base, functionName: "getPosition", args: [id] } as const)) }) : [];
  for (let id = 0; id < 6; id++) {
    const [fee, reward, slots, depth, reserveSlots] = configs[id];
    const index = known.findIndex(s => s.id === id);
    const latest = index < 0 ? undefined : positions[index];
    const enrolled = values[3] && id <= values[4];
    if (enrolled !== (counts[id] > 0n) || (latest && (latest.owner.toLowerCase() !== member.toLowerCase() || latest.stage !== id || latest.cycle !== counts[id]))) {
      throw new Error("Inconsistent board data. Please refresh before continuing.");
    }
    if (latest && (latest.filled > slots || (latest.closed ? active[id] !== 0n : active[id] !== ids[index]))) throw new Error("Inconsistent active board.");
    const completed = counts[id] === 0n ? 0n : counts[id] - 1n + (latest?.closed ? 1n : 0n);
    // V6 fees/rewards are immutable. Every filled credit pays reward once;
    // older positions in this member's history must have completed to re-enter.
    const earned = counts[id] === 0n ? 0n : ((counts[id] - 1n) * BigInt(slots) + BigInt(latest!.filled)) * reward;
    stages.push({ id, fee, reward, slots, depth, reserveSlots, enrolled, boards: counts[id], activeId: active[id], latestId: index < 0 ? 0n : ids[index], latest, completed, earned });
  }
  if (stages.reduce((sum, stage) => sum + stage.earned, 0n) !== values[6]) throw new Error("Earnings reconciliation failed. Please refresh.");
  return { block, root: values[0], paused: values[1], recovery: values[2], registered: values[3], highestStage: values[4], sponsor: values[5], earned: values[6], claimable: values[7], balance: values[8], allowance: values[9], stages };
}

export function purchaseStage(s: V6Snapshot) { return s.registered ? s.highestStage + 1 : 0; }
export function checkV6Purchase(s: V6Snapshot, member: Address, sponsor: Address, stage: number, reviewedFee: bigint) {
  if (s.recovery || s.paused) throw new Error("Registration is paused. No payment is needed now.");
  if (!Number.isInteger(stage) || stage < 0 || stage > 5 || stage !== purchaseStage(s)) throw new Error("Your next stage has changed. Refresh to review it.");
  if (reviewedFee !== s.stages[stage].fee) throw new Error("Entry amount changed. Review it before paying.");
  if (!isAddress(sponsor) || (!s.registered && sponsor.toLowerCase() === member.toLowerCase())) throw new Error("Choose a valid sponsor other than yourself.");
  if (s.balance < reviewedFee) throw new Error("Not enough USDT for this stage.");
}

/** Bounded historical reads; no all-history scan on page load. */
export async function readV6History(client: PublicClient, d: V6Deployment, member: Address, stage: number, count: bigint, offset: number, block: bigint) {
  if (!Number.isInteger(stage) || stage < 0 || stage > 5 || !Number.isSafeInteger(offset) || offset < 0) throw new Error("Invalid history page");
  const remaining = count - BigInt(offset);
  const length = Number(remaining > 10n ? 10n : remaining > 0n ? remaining : 0n);
  if (!length) return [];
  const base = { address: d.address, abi } as const;
  const ids = await client.multicall({ allowFailure: false, blockNumber: block, contracts: Array.from({ length }, (_, i) => ({ ...base, functionName: "boardIdAt", args: [member, stage, count - 1n - BigInt(offset + i)] } as const)) });
  const positions = await client.multicall({ allowFailure: false, blockNumber: block, contracts: ids.map(id => ({ ...base, functionName: "getPosition", args: [id] } as const)) });
  return positions.map((position, i) => {
    if (position.owner.toLowerCase() !== member.toLowerCase() || position.stage !== stage) throw new Error("Invalid historical board");
    return { id: ids[i], position };
  });
}

export async function readV6Tree(client: PublicClient, d: V6Deployment, id: bigint, position: V6Position, depth: number, block: bigint) {
  const nodes: Array<{ id: bigint; position?: V6Position }> = [{ id, position }];
  for (let level = 0; level < Math.min(depth, 3); level++) {
    const start = 2 ** level - 1;
    const parents = nodes.slice(start, start + 2 ** level);
    const children = parents.flatMap(n => [n.position?.left ?? 0n, n.position?.right ?? 0n]);
    const existing = children.filter(child => child !== 0n);
    const results = existing.length ? await client.multicall({ allowFailure: false, blockNumber: block, contracts: existing.map(child => ({ address: d.address, abi, functionName: "getPosition", args: [child] } as const)) }) : [];
    let cursor = 0;
    for (const child of children) nodes.push({ id: child, position: child === 0n ? undefined : results[cursor++] });
  }
  return nodes;
}
