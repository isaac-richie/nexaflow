import assert from "node:assert/strict";
import { test } from "node:test";
import { encodeEventTopics, encodeAbiParameters, zeroAddress } from "viem";
import { loadV6 } from "./v6-test-loader.mjs";

const model = loadV6("lib/v6.ts");
const { BINARY_MEMBERSHIP_V6_ABI: abi } = loadV6("lib/contracts/binaryMembershipV6Abi.ts");
const address = "0x1111111111111111111111111111111111111111";
const membership = "0x2222222222222222222222222222222222222222";
const token = "0x3333333333333333333333333333333333333333";
const hash = `0x${"44".repeat(32)}`;
const fee = 20n * 10n ** 18n;
function fixture(options = {}) {
  const state = [], refs = [], simulations = [], writes = [], reads = [], waits = [];
  let cursor = 0, refCursor = 0;
  const snapshot = { registered: false, highestStage: 0, paused: false, recovery: false, balance: fee, allowance: fee, claimable: fee, stages: [{ fee }], ...options.snapshot };
  const receipt = { status: "success", transactionHash: hash, logs: options.logs ?? [{ address: membership,
    topics: encodeEventTopics({ abi, eventName: "PositionOpened", args: { id: 7n, member: address, stage: 0 } }),
    data: encodeAbiParameters([{ type: "uint256" }, { type: "uint64" }, { type: "bool" }], [1n, 1n, true]),
  }], ...options.receipt };
  const client = {
    readContract: async request => { reads.push(request); return request.functionName === "allowance" ? fee : options.unknownSponsor ? false : true; },
    simulateContract: async request => { simulations.push(request); if (options.simulationError) throw new Error("PlacementUnavailable"); return { request }; },
    waitForTransactionReceipt: async request => { waits.push(request); if (options.replaced) request.onReplaced({ reason: options.replaced, transactionReceipt: receipt }); return receipt; },
  };
  const wallet = { getChainId: async () => options.walletChain ?? 56, getAddresses: async () => [options.walletAddress ?? address], writeContract: async request => { writes.push(request); if (options.rejected) throw new Error("User rejected the request"); return hash; } };
  const hooks = loadV6("hooks/use-v6.ts", {
    react: { useState: initial => { const i = cursor++; if (!(i in state)) state[i] = initial; return [state[i], value => { state[i] = value; }]; }, useRef: initial => { const i = refCursor++; return refs[i] ?? (refs[i] = { current: initial }); } },
    "@tanstack/react-query": { useQueryClient: () => ({ invalidateQueries: async () => {} }) },
    wagmi: { useAccount: () => ({ address, chainId: 56 }), usePublicClient: () => client, useWalletClient: () => ({ data: wallet }) },
    "@/lib/contracts/config": { ACTIVE_CHAIN: { id: 56 }, IS_DEPLOYED: true, IS_V6: true, MEMBERSHIP_ADDRESS: membership, PAYMENT_TOKEN_ADDRESS: token, V6_RUNTIME_HASH: hash },
    "@/lib/contracts/binaryMembershipV6Abi": { BINARY_MEMBERSHIP_V6_ABI: abi },
    "@/lib/v6": { ...model, readV6Snapshot: async () => { if (options.identityError) throw new Error("Contract identity check failed"); return snapshot; } },
    "@/lib/rpc-policy": { NO_BACKGROUND_RPC: {}, RPC_CACHE_MS: {}, RPC_POLLING_INTERVAL_MS: 8000 },
  });
  const hook = hooks.useV6Transaction();
  const result = () => { cursor = 0; refCursor = 0; return hooks.useV6Transaction(); };
  return { hook, result, simulations, writes, reads, waits };
}
test("V6 registration simulates the correct one-argument ABI and checks receipt before success", async () => {
  const f = fixture(); await f.hook.execute("purchase", { stage: 0, fee, sponsor: zeroAddress });
  assert.equal(f.simulations[0].functionName, "register");
  assert.deepEqual(Array.from(f.simulations[0].args), [zeroAddress]);
  assert.equal(f.writes[0].account, address); assert.equal(f.writes[0].chain.id, 56);
  assert.equal(f.waits[0].confirmations, 2); assert.equal(f.waits[0].pollingInterval, 8000);
  assert.match(f.result().message, /joined successfully/); assert.equal(f.result().error, undefined);
});
test("approval is exact, simulated, and never reported as a joined stage", async () => {
  const f = fixture(); await f.hook.execute("approve", { stage: 0, fee });
  assert.equal(f.writes[0].address, token); assert.equal(f.writes[0].functionName, "approve");
  assert.equal(f.writes[0].args[0], membership); assert.equal(f.writes[0].args[1], fee);
  assert.match(f.result().message, /Now select Join/); assert.doesNotMatch(f.result().message, /joined successfully/);
});
test("no signature is requested for identity mismatch, changed wallet, pause or missing allowance", async () => {
  for (const options of [{ identityError: true }, { walletChain: 97 }, { walletAddress: token }, { snapshot: { paused: true } }, { snapshot: { recovery: true } }, { snapshot: { allowance: 0n } }]) {
    const f = fixture(options); await f.hook.execute("purchase", { stage: 0, fee });
    assert.equal(f.writes.length, 0); assert.ok(f.result().error);
  }
});
test("failed simulation and rejected signatures never show success", async () => {
  for (const options of [{ simulationError: true }, { rejected: true }]) {
    const f = fixture(options); await f.hook.execute("purchase", { stage: 0, fee });
    assert.equal(f.waits.length, 0); assert.ok(f.result().error); assert.equal(f.result().message, undefined);
  }
});
test("reverted, cancelled or unrelated replacement receipts do not show joined success", async () => {
  for (const options of [{ receipt: { status: "reverted" } }, { replaced: "cancelled" }, { replaced: "replaced", logs: [] }, { logs: [] }]) {
    const f = fixture(options); await f.hook.execute("purchase", { stage: 0, fee });
    assert.ok(f.result().error); assert.equal(f.result().message, undefined); assert.equal(f.result().hash, hash);
  }
});
test("unknown sponsor prevents approval and duplicate clicks submit only once", async () => {
  const unknown = fixture({ unknownSponsor: true }); await unknown.hook.execute("approve", { stage: 0, fee, sponsor: token });
  assert.equal(unknown.writes.length, 0);
  const f = fixture(); await Promise.all([f.hook.execute("purchase", { stage: 0, fee }), f.hook.execute("purchase", { stage: 0, fee })]);
  assert.equal(f.writes.length, 1);
});
test("sequential upgrade uses uint8 stage only, not V5 parent or side arguments", async () => {
  const f = fixture({ snapshot: { registered: true, stages: [{ fee }, { fee }] } });
  await f.hook.execute("purchase", { stage: 1, fee });
  assert.equal(f.simulations[0].functionName, "joinStage"); assert.deepEqual(Array.from(f.simulations[0].args), [1]);
  // Fixture event is for Stage 1 (index 0), so an upgrade must reject it.
  assert.match(f.result().error, /Receipt did not confirm/);
});
