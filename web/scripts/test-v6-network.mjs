import assert from "node:assert/strict";
import { test } from "node:test";
import * as viem from "viem";
import { loadV6 } from "./v6-test-loader.mjs";

const root = "0x1111111111111111111111111111111111111111";
const a = "0x2222222222222222222222222222222222222222";
const b = "0x3333333333333333333333333333333333333333";
const contract = "0x4444444444444444444444444444444444444444";
const hash = `0x${"aa".repeat(32)}`;
function index(options = {}) {
  const events = [];
  const client = {
    getChainId: async () => options.wrongChain ? 97 : 56,
    getCode: async () => "0x6000",
    getBlockNumber: async () => 150n,
    getBlock: async ({ blockNumber }) => ({ timestamp: blockNumber + 1000n }),
    getLogs: async request => {
      events.push(request.event.name);
      assert.equal(request.fromBlock, 100n);
      if (request.event.name === "PositionOpened") return options.missingRoot ? [] : [{ args: { id: 1n, member: root, stage: 0, parent: 0n, cycle: 1n, funded: false }, blockNumber: 100n, logIndex: 4, transactionHash: hash }];
      return [
        { args: { member: b, sponsor: a }, blockNumber: 105n, logIndex: 9, transactionHash: hash },
        { args: { member: a, sponsor: root }, blockNumber: 105n, logIndex: 2, transactionHash: hash },
        { args: { member: b, sponsor: a }, blockNumber: 105n, logIndex: 9, transactionHash: hash },
      ];
    },
  };
  const module = loadV6("lib/server/registration-index.ts", {
    "server-only": {}, "next/cache": { unstable_cache: fn => fn },
    viem: { ...viem, createPublicClient: () => client },
  }, { process: { env: { NEXT_PUBLIC_MEMBERSHIP_VERSION: "v6", NEXT_PUBLIC_CHAIN: "bsc", NEXT_PUBLIC_MEMBERSHIP_ADDRESS: contract, NEXT_PUBLIC_V6_RUNTIME_HASH: options.badHash ? hash : viem.keccak256("0x6000"), MEMBERSHIP_DEPLOYMENT_BLOCK: "100" } } });
  return { ...module, events };
}
test("V6 network uses Registered plus constructor root, orders same-block logs and deduplicates", async () => {
  const source = index(); const result = await source.getRegistrationSnapshot();
  assert.deepEqual(source.events, ["Registered", "PositionOpened"]);
  assert.equal(result.syncedBlock, 130);
  assert.equal(result.records.length, 3);
  assert.deepEqual(Array.from(result.records, r => r.member.toLowerCase()), [root, a, b]);
  assert.deepEqual(Array.from(result.records, r => r.memberId), [1, 2, 3]);
  assert.equal(result.records[0].sponsor, viem.zeroAddress);
  const { summarizeNetwork } = loadV6("lib/network-graph.ts");
  const network = summarizeNetwork(result.records, root, 1, 0, 20);
  assert.equal(network.personalReferrals, 1); assert.equal(network.totalTeam, 2);
});
test("V6 network rejects wrong runtime and wrong RPC chain before reading logs", async () => {
  for (const option of [{ badHash: true }, { wrongChain: true }]) {
    const source = index(option); await assert.rejects(source.getRegistrationSnapshot()); assert.equal(source.events.length, 0);
  }
});
test("stale V5 deployment block cannot silently create a rootless V6 network", async () => {
  const source = index({ missingRoot: true });
  await assert.rejects(source.getRegistrationSnapshot(), /deployment block/);
  assert.deepEqual(source.events, ["Registered", "PositionOpened"]);
});
