import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import vm from "node:vm";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";

const require = createRequire(import.meta.url);
function load(path, mocks = {}, globals = {}) {
  const source = readFileSync(new URL(path, import.meta.url), "utf8");
  const js = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true,
  } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(js, { exports: module.exports, module,
    require: name => Object.hasOwn(mocks, name) ? mocks[name] : require(name),
    Intl, console, setTimeout, clearTimeout, ...globals,
  });
  return module.exports;
}
const model = load("../lib/member-dashboard.ts");
const unit = 10n ** 18n;
const address = "0x1111111111111111111111111111111111111111";
const zero = "0x0000000000000000000000000000000000000000";
const member = { active: true, sponsor: zero, joinedAt: 1n, totalEarned: 405n * unit };
const configs = [20n, 60n, 180n, 540n, 1620n, 4860n].map((fee, id) => ({
  fee: fee * unit, nodeReward: BigInt(id + 5) * unit, treeSlots: id === 0 ? 6n : 14n,
  treeDepth: id === 0 ? 2n : 3n, rolloversForAward: id === 0 ? 0n : 10n,
}));
const memberships = Array.from({ length: 6 }, (_, id) => ({
  enrolled: id < 3, parent: zero, side: 0, left: zero, right: zero,
  slotsFilledBelow: id < 3 ? 3n : 0n, rolloverCount: id < 3 ? BigInt(3 - id) : 0n,
  lastAwardedRollover: 0n, stageEarnings: id < 3 ? BigInt(id + 1) * unit : 0n,
  totalAwarded: id === 2 ? 5n * unit : 0n,
}));
test("live model counts completed cycles and keeps awards separate from earnings", () => {
  const result = model.buildMemberDashboard(member, memberships, configs);
  assert.equal(result.earned, 405n * unit);
  assert.equal(result.totalAwarded, 5n * unit);
  assert.equal(result.activeStages, 3);
  assert.equal(result.completedBoards, 6n);
  assert.equal(result.currentStage, 2);
  assert.deepEqual(Array.from(result.stages, s => s.state), ["active", "active", "active", "available", "locked", "locked"]);
});
test("a missing multicall result is not a zero, locked stage, or complete total", () => {
  for (let i = 0; i < 6; i++) {
    const partial = memberships.slice(); partial[i] = undefined;
    const result = model.buildMemberDashboard(member, partial, configs);
    assert.equal(result.stages[i].state, "unavailable");
    assert.equal(result.completedBoards, undefined);
    assert.equal(result.activeStages, undefined);
    assert.equal(result.currentStage, undefined);
    assert.equal(result.totalAwarded, undefined);
    assert.equal(result.earned, member.totalEarned);
    assert.equal(result.partial, true);
  }
});
test("missing previous-stage result does not falsely declare a stage locked", () => {
  const partial = memberships.slice(); partial[2] = undefined;
  assert.equal(model.buildMemberDashboard(member, partial, configs).stages[3].state, "unavailable");
});
test("missing or invalid config disables stage details instead of using preset fees", () => {
  for (const value of [undefined, { ...configs[0], treeSlots: 0n }]) {
    const unknown = configs.slice(); unknown[0] = value;
    const result = model.buildMemberDashboard(member, memberships, unknown);
    assert.equal(result.stages[0].state, "unavailable");
    assert.equal(result.stages[0].remaining, undefined);
  }
  const changed = configs.map(c => ({ ...c, fee: 777n * unit }));
  assert.equal(model.buildMemberDashboard(member, memberships, changed).stages[3].config.fee, 777n * unit);
});
test("six activated stages do not advertise another paid unlock", () => {
  const all = memberships.map(m => ({ ...m, enrolled: true }));
  assert.ok(model.buildMemberDashboard(member, all, configs).stages.every(s => s.state === "active"));
});
test("milestones match V5 getter and stage one has no award milestone", () => {
  const ms = memberships.map(m => ({ ...m, rolloverCount: 18n, lastAwardedRollover: 10n }));
  const result = model.buildMemberDashboard(member, ms, configs);
  assert.equal(result.stages[0].nextMilestone, undefined);
  assert.equal(result.stages[0].milestoneReached, false);
  assert.equal(result.stages[1].nextMilestone, 20n);
  assert.equal(result.stages[1].milestoneReached, false);
  ms[1].rolloverCount = 20n;
  assert.equal(model.buildMemberDashboard(member, ms, configs).stages[1].milestoneReached, true);
});
test("integer money formatting preserves very large balances and rounds half up", () => {
  assert.equal(model.memberAmount(undefined), "—");
  assert.equal(model.memberAmount(0n), "0.00");
  assert.equal(model.memberAmount(1005n * 10n ** 15n), "1.01");
  assert.equal(model.memberAmount(999999n * 10n ** 12n), "1.00");
  assert.equal(model.memberAmount(9007199254740993123n * unit), "9,007,199,254,740,993,123.00");
});
test("1,000 synthetic six-stage snapshots preserve exact rollover totals and bounded remaining slots", () => {
  let seed = 123456;
  const random = () => (seed = (seed * 1664525 + 1013904223) >>> 0);
  for (let n = 0; n < 1000; n++) {
    const active = random() % 6 + 1;
    const samples = memberships.map((m, i) => ({ ...m, enrolled: i < active,
      rolloverCount: i < active ? BigInt(random()) * 100000000000n : 0n,
      slotsFilledBelow: i < active ? BigInt(random() % Number(configs[i].treeSlots)) : 0n,
    }));
    const result = model.buildMemberDashboard(member, samples, configs);
    assert.equal(result.completedBoards, samples.reduce((sum, m) => sum + m.rolloverCount, 0n));
    assert.equal(result.activeStages, active);
    assert.equal(result.currentStage, active - 1);
    for (const stage of result.stages.filter(s => s.state === "active")) {
      assert.equal(stage.currentBoard, samples[stage.id].rolloverCount + 1n);
      assert.equal(stage.remaining, configs[stage.id].treeSlots - samples[stage.id].slotsFilledBelow);
    }
  }
});
test("read state distinguishes disconnected, wrong chain, loading, failure and genuinely unregistered", () => {
  const ready = { connected: true, deployed: true, wrongChain: false, loading: false, member };
  for (const [overrides, expected] of [
    [{ deployed: false }, "unconfigured"], [{ connected: false }, "disconnected"],
    [{ wrongChain: true }, "wrong-chain"], [{ member: undefined, loading: true }, "loading"],
    [{ member: undefined }, "unavailable"], [{ member: { ...member, active: false } }, "unregistered"],
    [{ loading: true }, "ready"],
  ]) assert.equal(model.memberReadState({ ...ready, ...overrides }), expected);
});

const css = new Proxy({}, { get: (_t, key) => key === "__esModule" ? false : String(key) });
const Link = ({ href, children, prefetch: _prefetch, ...props }) => React.createElement("a", { href, ...props }, children);
const { MemberStages } = load("../components/app/member-stages.tsx", {
  "next/link": Link, "./member-ui.module.css": css,
  "@/lib/member-dashboard": model,
  "@/lib/contracts/config": { STAGE_PRESETS: configs.map((_c, stageId) => ({ stageId })), ZERO_ADDRESS: zero },
  "./live-board": { LiveBoard: ({ preset }) => React.createElement("div", null, `diagram:${preset.slots}`) },
});
const stagesHtml = (stages, currentStage) => renderToStaticMarkup(React.createElement(MemberStages, { stages, currentStage }));
test("real stages render six accessible controls, one expanded board and real counts", () => {
  const data = model.buildMemberDashboard(member, memberships, configs);
  const html = stagesHtml(data.stages, 0);
  for (let i = 0; i < 6; i++) {
    assert.match(html, new RegExp(`aria-controls="member-stage-${i}"`));
    assert.match(html, new RegExp(`id="member-stage-${i}"`));
  }
  assert.equal((html.match(/aria-expanded="true"/g) ?? []).length, 1);
  assert.match(html, /diagram:6/);
  assert.match(html, /Current board #4/);
  assert.match(html, /Progress illustration, not an exact map/);
  assert.doesNotMatch(html, /Fuel Saver|claimable|reserved for re-entry/i);
});
test("only an available stage includes entry action; locked and unreadable stages never do", () => {
  const data = model.buildMemberDashboard(member, memberships, configs);
  assert.match(stagesHtml(data.stages, 3), /Review Stage 4 entry/);
  assert.doesNotMatch(stagesHtml(data.stages, 4), /href="\/app\/join"/);
  const missing = configs.slice(); missing[3] = undefined;
  assert.doesNotMatch(stagesHtml(model.buildMemberDashboard(member, memberships, missing).stages, 3), /href="\/app\/join"/);
});

function dashboardHtml({ connected = true, chainId = 56, missing = false, error = false, active = true, view = "overview" } = {}) {
  const stub = text => () => React.createElement("div", null, text);
  const { MemberDashboard } = load("../components/app/member-dashboard.tsx", {
    wagmi: { useAccount: () => ({ address, isConnected: connected, chainId }) },
    "next/link": Link, "./member-ui.module.css": css,
    "@/lib/contracts/config": { ACTIVE_CHAIN: { id: 56, name: "BNB Smart Chain" }, IS_DEPLOYED: true },
    "@/lib/member-dashboard": model,
    "@/hooks/use-membership": {
      useMember: () => ({ member: missing ? undefined : { ...member, active }, isLoading: false, isError: error }),
      useAllStageMemberships: () => ({ stages: memberships, isLoading: false }),
      useStageConfigs: () => ({ configs, isLoading: false }),
    },
    "./states": { ConnectPrompt: stub("connect wallet"), LoadingPanel: stub("loading"), NotDeployedNotice: stub("not deployed"), NotRegisteredNotice: stub("not registered") },
    "./connect-button": { ConnectButton: stub("switch wallet network") },
    "./member-stages": { MemberStages },
    "./referral-card": { ReferralCard: stub("referral link") },
    "./network-overview": { NetworkOverview: stub("real network") },
  });
  return renderToStaticMarkup(React.createElement(MemberDashboard, { view }));
}
test("dashboard gates missing account, wrong network and failed membership without showing fake balances", () => {
  assert.match(dashboardHtml({ connected: false }), /connect wallet/);
  assert.doesNotMatch(dashboardHtml({ connected: false }), /405\.00/);
  assert.match(dashboardHtml({ chainId: 1 }), /Switch to BNB Smart Chain/);
  assert.doesNotMatch(dashboardHtml({ chainId: 1 }), /405\.00/);
  assert.match(dashboardHtml({ missing: true, error: true }), /couldn’t load your membership/);
  assert.doesNotMatch(dashboardHtml({ missing: true, error: true }), /not registered|405\.00/);
  assert.match(dashboardHtml({ active: false }), /not registered/);
  assert.doesNotMatch(dashboardHtml({ active: false, error: true }), /not registered/);
  assert.match(dashboardHtml({ active: false, error: true }), /couldn’t load your membership/);
});
test("cached values are visibly labelled when refresh fails; public dashboard omits administrative figures", () => {
  const html = dashboardHtml({ error: true });
  assert.match(html, /last successful readings/);
  assert.match(html, /405\.00/);
  assert.match(html, /Royalty bonus/);
  assert.match(html, /Prediction market/);
  assert.doesNotMatch(html, /treasury|company wallet|claimable|Fuel Saver/i);
});
test("dedicated board and network routes render only their relevant detail sections", () => {
  assert.doesNotMatch(dashboardHtml({ view: "boards" }), /real network|Beyond the boards/);
  const html = dashboardHtml({ view: "network" });
  assert.match(html, /real network/);
  assert.doesNotMatch(html, /member-stage-|Beyond the boards/);
});
test("four member navigation links include Join with exactly one active destination", () => {
  for (const pathname of ["/app", "/app/board", "/app/network", "/app/join"]) {
    const { AppNav } = load("../components/app/app-nav.tsx", {
      "next/navigation": { usePathname: () => pathname }, "next/link": Link, "./member-ui.module.css": css,
    });
    const html = renderToStaticMarkup(React.createElement(AppNav, { variant: "strip" }));
    assert.equal((html.match(/aria-current="page"/g) ?? []).length, 1);
    assert.equal((html.match(/<a /g) ?? []).length, 4);
    assert.match(html, /href="\/app\/join"/);
  }
});
test("membership reads pin the configured chain and preserve disabled background polling", () => {
  const seen = [];
  const { useMember, useAllStageMemberships, useStageConfigs } = load("../hooks/use-membership.ts", {
    wagmi: {
      useAccount: () => ({ address }),
      useReadContract: options => { seen.push(options); return {}; },
      useReadContracts: options => { seen.push(options); return {}; },
    },
    "@/lib/contracts/binaryMembershipAbi": { BINARY_MEMBERSHIP_ABI: [] },
    "@/lib/contracts/config": { ACTIVE_CHAIN: { id: 56 }, IS_DEPLOYED: true, MAX_STAGES: 6, MEMBERSHIP_ADDRESS: address, ZERO_ADDRESS: zero },
    "@/lib/rpc-policy": { NO_BACKGROUND_RPC: { refetchInterval: false }, RPC_CACHE_MS: { member: 45000, board: 45000, stageConfig: 600000 } },
  });
  useMember(); useAllStageMemberships(); useStageConfigs();
  assert.equal(seen.length, 3);
  for (const query of seen) {
    assert.equal(query.query.refetchInterval, false);
    assert.ok(query.query.staleTime >= 45000);
    for (const contract of query.contracts ?? [query]) assert.equal(contract.chainId, 56);
  }
  assert.equal(seen[1].contracts.length, 6);
  assert.equal(seen[2].contracts.length, 6);
});

test("network account state remounts on wallet change and late aborted responses cannot replace a newer generation", async () => {
  // In-memory hook lifecycle, not a browser or a live RPC call.
  const slots = [], deps = [], cleanups = [], effects = [], requests = [];
  let cursor = 0;
  const hooks = {
    ...React,
    useState(initial) {
      const id = cursor++;
      if (!Object.hasOwn(slots, id)) slots[id] = typeof initial === "function" ? initial() : initial;
      return [slots[id], next => { slots[id] = typeof next === "function" ? next(slots[id]) : next; }];
    },
    useRef(value) {
      const id = cursor++;
      if (!Object.hasOwn(slots, id)) slots[id] = { current: value };
      return slots[id];
    },
    useMemo(factory) { cursor++; return factory(); },
    useCallback(fn) { cursor++; return fn; },
    useEffect(effect, nextDeps) {
      const id = cursor++;
      if (!deps[id] || nextDeps.some((value, i) => !Object.is(value, deps[id][i]))) {
        effects.push(() => { cleanups[id]?.(); cleanups[id] = effect(); });
        deps[id] = nextDeps;
      }
    },
  };
  const { NetworkOverview } = load("../components/app/network-overview.tsx", {
    react: hooks,
    "@/lib/contracts/config": { ACTIVE_CHAIN: { id: 56 }, MEMBERSHIP_ADDRESS: address, MEMBERSHIP_VERSION: "v5" },
    "@/lib/referrals": { referralCodeForAddress: () => "TEST", referralPathForAddress: () => "/r/TEST" },
  }, {
    AbortController, URLSearchParams,
    fetch: (url, options) => new Promise(resolve => requests.push({ url, options, resolve })),
  });
  const outer = NetworkOverview({ address });
  assert.notEqual(outer.key, NetworkOverview({ address: zero }).key);
  const render = () => {
    cursor = 0;
    const tree = outer.type(outer.props);
    effects.splice(0).forEach(effect => effect());
    return tree;
  };
  const findProp = (tree, prop) => {
    if (!tree || typeof tree !== "object") return undefined;
    if (tree.props?.[prop]) return tree.props[prop];
    for (const child of React.Children.toArray(tree.props?.children)) {
      const found = findProp(child, prop); if (found) return found;
    }
  };
  const payload = generation => ({ root: address, personalReferrals: 2, totalTeam: 12,
    generations: 3, protocolMembers: 13, selectedGeneration: generation,
    generationCounts: [1, 2, 3].map(generation => ({ generation, count: 4 })),
    members: [], offset: 0, limit: 20, hasMore: false, dailyRegistrations: [], syncedBlock: 1,
  });
  const settle = async (index, generation) => {
    requests[index].resolve({ ok: true, json: async () => payload(generation) });
    await new Promise(resolve => setImmediate(resolve));
  };
  render();
  assert.equal(requests.length, 1);
  await settle(0, 1);
  const select = findProp(render(), "onSelect");
  assert.equal(typeof select, "function");
  select(2); render();
  select(3); render();
  assert.equal(requests[1].options.signal.aborted, true);
  await settle(2, 3);
  assert.equal(findProp(render(), "loadedGeneration"), 3);
  await settle(1, 2);
  assert.equal(findProp(render(), "loadedGeneration"), 3);
  cleanups.forEach(cleanup => cleanup?.());
});
