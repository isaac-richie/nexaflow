import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { encodeFunctionData, decodeFunctionData, zeroAddress } from "viem";
import { loadV6 } from "./v6-test-loader.mjs";

const model = loadV6("lib/v6.ts");
const { BINARY_MEMBERSHIP_V6_ABI: abi } = loadV6("lib/contracts/binaryMembershipV6Abi.ts");
const member = "0x1111111111111111111111111111111111111111";
const other = "0x2222222222222222222222222222222222222222";
const d = { chainId: 56, address: member, token: other, runtimeHash: `0x${"11".repeat(32)}` };
const unit = 10n ** 18n;
const sample = () => ({ block: 100n, root: other, sponsor: other, registered: true, highestStage: 0, paused: false, recovery: false, earned: 0n, claimable: 0n, balance: 10000n * unit, allowance: 0n,
  stages: [20,60,180,540,1620,4860].map((fee, id) => ({ id, fee: BigInt(fee) * unit, reward: BigInt([5,10,25,80,250,800][id]) * unit, slots: id === 0 ? 6 : 14, depth: id === 0 ? 2 : 3, reserveSlots: id === 0 ? 4 : 8, enrolled: id === 0, boards: id === 0 ? 1n : 0n, completed: 0n, earned: 0n, latestId: 7n, activeId: 7n, latest: id === 0 ? { owner: member, stage: 0, filled: 0, closed: false, queued: false, cycle: 1n, parent: 1n, left: 0n, right: 0n, reserve: 0n } : undefined })) });

test("generated V6 ABI exactly matches the release candidate artifact", () => {
  const artifact = JSON.parse(readFileSync(new URL("../../out/BinaryMembershipV6.sol/BinaryMembershipV6.json", import.meta.url), "utf8"));
  assert.equal(JSON.stringify(abi), JSON.stringify(artifact.abi));
  for (const [name, args] of [["register", [zeroAddress]], ["joinStage", [5]], ["claim", [member]], ["processReentries", [0, 4n]]]) {
    const decoded = decodeFunctionData({ abi, data: encodeFunctionData({ abi, functionName: name, args }) });
    assert.equal(decoded.functionName, name); assert.equal(decoded.args.length, args.length);
  }
});
test("V6 identity fails closed for missing hash, zero address, wrong chain and old bytecode", async () => {
  for (const override of [{ runtimeHash: undefined }, { address: zeroAddress }, { chainId: 1 }]) assert.throws(() => model.validateV6Deployment({ ...d, ...override }));
  await assert.rejects(model.verifyV6({ getChainId: async () => 97 }, d), /Network/);
  for (const code of [undefined, "0x", "0x6000"]) await assert.rejects(model.verifyV6({ getChainId: async () => 56, getCode: async () => code }, d), /identity/);
});
test("purchase preconditions reject paused, recovery, skipped stages, stale fees, self-referral and insufficient balance", () => {
  const s = sample();
  model.checkV6Purchase(s, member, other, 1, 60n * unit);
  for (const patch of [{ paused: true }, { recovery: true }, { highestStage: 2 }, { balance: 1n }]) assert.throws(() => model.checkV6Purchase({ ...s, ...patch }, member, other, 1, 60n * unit));
  for (const stage of [-1, 0, 2, 6, 1.5]) assert.throws(() => model.checkV6Purchase(s, member, other, stage, 60n * unit));
  assert.throws(() => model.checkV6Purchase(s, member, other, 1, 59n * unit));
  assert.throws(() => model.checkV6Purchase({ ...s, registered: false }, member, member, 0, 20n * unit));
  model.checkV6Purchase({ ...s, registered: false }, member, zeroAddress, 0, 20n * unit);
  assert.equal(model.purchaseStage({ ...s, highestStage: 5 }), 6);
});
test("history is paginated to ten reads and rejects bad offsets/stages", async () => {
  const calls = [];
  const client = { multicall: async request => { calls.push(request); return request.contracts.map((c, i) => c.functionName === "boardIdAt" ? BigInt(i + 1) : { owner: member, stage: 0 }); } };
  const result = await model.readV6History(client, d, member, 0, 50000n, 0, 12n);
  assert.equal(result.length, 10); assert.equal(calls.length, 2); assert.equal(calls[0].blockNumber, 12n);
  assert.equal(calls[0].contracts[0].args[2], 49999n);
  await assert.rejects(model.readV6History(client, d, member, 6, 2n, 0, 12n));
  await assert.rejects(model.readV6History(client, d, member, 0, 2n, -1, 12n));
});

const config = { ACTIVE_CHAIN: { id: 56, name: "BNB Smart Chain", blockExplorers: { default: { url: "https://bscscan.com" } } }, IS_DEPLOYED: true, MEMBERSHIP_ADDRESS: other };
function render(view = "overview", options = {}) {
  const s = options.snapshot ?? sample();
  const account = { address: member, chainId: options.chainId ?? 56, isConnected: options.connected ?? true };
  const simple = name => () => React.createElement("div", null, name);
  const module = loadV6("components/app/v6-member.tsx", {
    "wagmi": { useAccount: () => account },
    "@tanstack/react-query": { useQuery: () => ({ isPending: false, data: [] }) },
    "@/lib/contracts/config": config,
    "@/lib/member-dashboard": loadV6("lib/member-dashboard.ts"),
    "@/lib/v6": model,
    "@/hooks/use-v6": { useV6Snapshot: () => ({ account, data: s, client: {}, isPending: options.loading, isError: options.error, error: options.error ? new Error("Contract identity check failed") : undefined }), useV6Transaction: () => ({ busy: false }), v6Error: e => e.message, v6Scope: [], v6Deployment: d },
    "@/lib/rpc-policy": { NO_BACKGROUND_RPC: {}, RPC_CACHE_MS: { board: 45000 } },
    "./states": { ConnectPrompt: simple("Connect wallet"), LoadingPanel: simple("Loading"), NotDeployedNotice: simple("Not configured"), NotRegisteredNotice: simple("Not registered") },
    "./connect-button": { ConnectButton: simple("Switch network") },
    "./referral-card": { ReferralCard: simple("Referral link") },
    "./network-overview": { NetworkOverview: simple("Network") },
    "./member-ui.module.css": new Proxy({}, { get: (_, key) => String(key) }),
  });
  return renderToStaticMarkup(React.createElement(module.V6Member, { view }));
}
test("all six V6 stages render with no invented V5 award counters or treasury totals", () => {
  const html = render();
  for (let i = 1; i <= 6; i++) assert.match(html, new RegExp(`Stage ${i}`));
  assert.match(html, /Board rewards allocated/); assert.match(html, /Completed boards/);
  assert.doesNotMatch(html, /Awards recorded|totalTreasury|Company profit|Award milestone/);
  assert.match(html, /aria-expanded/);
});
test("disconnected, wrong-chain, loading and failed identity do not show a payment button", () => {
  for (const o of [{ connected: false }, { chainId: 97 }, { loading: true }, { error: true }]) assert.doesNotMatch(render("join", o), /Approve .*USDT|>Join Stage/);
});
test("recovery shows reserves as records and disables joining; first join remains Stage 1", () => {
  const s = sample(); s.recovery = true; s.paused = true;
  assert.match(render("join", { snapshot: s }), /Emergency recovery in progress/);
  assert.match(render("join", { snapshot: s }), /disabled=""/);
  assert.match(render("boards", { snapshot: s }), /not confirmation of funds currently held/);
  const fresh = sample(); fresh.registered = false;
  const html = render("join", { snapshot: fresh });
  assert.match(html, /Join Stage 1/); assert.match(html, /20.00 USDT/); assert.match(html, /Sponsor address \(optional\)/);
});

test("public membership copy uses the brand without release labels", () => {
  for (const view of ["overview", "boards", "join", "network"]) {
    const text = render(view).replace(/<[^>]*>/g, " ");
    assert.match(text, /NexaFlow/);
    assert.doesNotMatch(text, /\bV[456]\b|tests? (?:done|passed|complete)/i);
  }
  const layout = readFileSync(new URL("../app/app/layout.tsx", import.meta.url), "utf8");
  assert.doesNotMatch(layout, /V5ReleaseNotice|v5-release-notice|Returning member/i);
  assert.match(layout, /Legal disclosures/);
});

test("copy cleanup preserves the stored consent version and reserve disclosures", () => {
  const { CONSENT_VERSION } = loadV6("lib/consent.ts", {}, { process: { env: { NEXT_PUBLIC_MEMBERSHIP_VERSION: "v6" } } });
  assert.equal(CONSENT_VERSION, "2026-09-08-v6");
  const gate = readFileSync(new URL("../components/consent-gate.tsx", import.meta.url), "utf8");
  assert.match(gate, /version: CONSENT_VERSION/);
  assert.doesNotMatch(gate, /Consent version \{CONSENT_VERSION\}/);
  const legal = readFileSync(new URL("../app/legal/page.tsx", import.meta.url), "utf8");
  assert.match(legal, /title="Re-entry and reserve custody"/);
  assert.match(legal, /A single administrator can move all re-entry reserves/);
  assert.match(legal, /not automatically transferred here/);
});
