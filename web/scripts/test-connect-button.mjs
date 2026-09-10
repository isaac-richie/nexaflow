import assert from "node:assert/strict";
import { test } from "node:test";
import { loadV6 } from "./v6-test-loader.mjs";

function fixture(options = {}) {
  const state = [];
  let cursor = 0, loginCalls = 0, connectCalls = 0;
  let loginCallbacks, connectCallbacks;
  const privy = { ready: true, authenticated: false, logout: async () => {}, ...options.privy };
  const account = { isConnected: false, address: undefined, chainId: undefined, ...options.account };
  const login = async () => { loginCalls++; if (options.loginError) throw new Error("private provider detail"); };
  const connectWallet = async () => { connectCalls++; if (options.connectError) throw new Error("private provider detail"); };
  const { ConnectButton } = loadV6("components/app/connect-button.tsx", {
    react: { useState: initial => { const i = cursor++; if (!(i in state)) state[i] = initial;
      return [state[i], value => { state[i] = typeof value === "function" ? value(state[i]) : value; }]; },
      useEffect: () => {} },
    "react-dom": { createPortal: value => value },
    "@privy-io/react-auth": {
      usePrivy: () => ({ ...privy, login }),
      useLogin: callbacks => { loginCallbacks = callbacks; return { login }; },
      useConnectWallet: callbacks => { connectCallbacks = callbacks; return { connectWallet }; },
    },
    wagmi: { useAccount: () => account, useSwitchChain: () => ({ switchChain: () => {}, isPending: false }) },
    "framer-motion": { AnimatePresence: "div", motion: { div: "div" } },
    "@/lib/contracts/config": { ACTIVE_CHAIN: { id: 56, name: "BNB Smart Chain" } },
    "@/lib/format": { cn: (...values) => values.filter(Boolean).join(" "), shortAddress: address => address },
  });
  const render = () => { cursor = 0; return ConnectButton({}); };
  const nodes = node => !node || typeof node !== "object" ? [] : [node, ...[node.props?.children].flat().flatMap(nodes)];
  const button = () => nodes(render()).find(node => node.type === "button");
  const alert = () => nodes(render()).find(node => node.props?.role === "alert")?.props.children;
  return { render, button, alert, counts: () => ({ loginCalls, connectCalls }),
    loginFailure: () => loginCallbacks.onError("unknown_error"),
    connectFailure: () => connectCallbacks.onError("unknown_error") };
}

test("new visitors open login", async () => {
  const f = fixture(); await f.button().props.onClick();
  assert.deepEqual(f.counts(), { loginCalls: 1, connectCalls: 0 });
});
test("existing login without a wallet opens reconnect, not the ignored login call", async () => {
  const f = fixture({ privy: { authenticated: true } }); await f.button().props.onClick();
  assert.deepEqual(f.counts(), { loginCalls: 0, connectCalls: 1 });
});
test("a stale address is not treated as an active connected wallet", async () => {
  const f = fixture({ privy: { authenticated: true }, account: { address: "0x1111111111111111111111111111111111111111", isConnected: false } });
  await f.button().props.onClick();
  assert.deepEqual(f.counts(), { loginCalls: 0, connectCalls: 1 });
});
test("wallet action rejections produce safe feedback instead of unhandled promises", async () => {
  for (const authenticated of [false, true]) {
    const f = fixture({ privy: { authenticated }, loginError: true, connectError: true });
    await assert.doesNotReject(async () => f.button().props.onClick());
    assert.match(f.alert(), /try again/i);
    assert.doesNotMatch(f.alert(), /private provider detail/);
  }
});
test("SDK login and connection failure callbacks are visible", () => {
  const f = fixture(); f.render(); f.loginFailure(); assert.match(f.alert(), /try again/i);
  const g = fixture({ privy: { authenticated: true } }); g.render(); g.connectFailure(); assert.match(g.alert(), /try again/i);
});
test("pending initialization never exposes an actionable connect button", () => {
  assert.equal(fixture({ privy: { ready: false } }).button(), undefined);
});
test("connected users keep their account menu and wrong-chain switch", async () => {
  const address = "0x1111111111111111111111111111111111111111";
  const f = fixture({ privy: { authenticated: true }, account: { address, isConnected: true, chainId: 56 } });
  await f.button().props.onClick(); assert.deepEqual(f.counts(), { loginCalls: 0, connectCalls: 0 });
  const g = fixture({ privy: { authenticated: true }, account: { address, isConnected: true, chainId: 97 } });
  assert.match(JSON.stringify(g.button().props.children), /Switch to/);
});
