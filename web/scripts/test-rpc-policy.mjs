import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const source = fs.readFileSync(new URL("../lib/rpc-policy.ts", import.meta.url), "utf8");

function loadPolicy(env = {}) {
  const javascript = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;
  const module = { exports: {} };
  const context = vm.createContext({
    exports: module.exports,
    module,
    process: { env },
    Error,
    Number,
    String,
  });
  vm.runInContext(javascript, context, { filename: "rpc-policy.js" });
  return module.exports;
}

const defaults = loadPolicy();
assert.equal(defaults.RPC_POLLING_INTERVAL_MS, 8_000);
assert.equal(defaults.RPC_MULTICALL_WAIT_MS, 40);
assert.equal(defaults.NO_BACKGROUND_RPC.refetchInterval, false);
assert.equal(defaults.NO_BACKGROUND_RPC.refetchOnWindowFocus, false);
assert.equal(defaults.NO_BACKGROUND_RPC.refetchOnReconnect, false);
assert.equal(defaults.RPC_CACHE_MS.placement, 20_000);
assert.equal(defaults.RPC_CACHE_MS.priceQuote, 45_000);
assert.equal(defaults.RPC_CACHE_MS.protocolStats, 120_000);
assert.equal(defaults.RPC_CACHE_MS.stageConfig, 600_000);
assert.equal(defaults.RPC_CACHE_MS.garbageCollection, 900_000);

const clampedLow = loadPolicy({
  NEXT_PUBLIC_RPC_POLLING_INTERVAL_MS: "1",
  NEXT_PUBLIC_RPC_MULTICALL_WAIT_MS: "-5",
});
assert.equal(clampedLow.RPC_POLLING_INTERVAL_MS, 5_000);
assert.equal(clampedLow.RPC_MULTICALL_WAIT_MS, 0);

const clampedHigh = loadPolicy({
  NEXT_PUBLIC_RPC_POLLING_INTERVAL_MS: "999999",
  NEXT_PUBLIC_RPC_MULTICALL_WAIT_MS: "999999",
});
assert.equal(clampedHigh.RPC_POLLING_INTERVAL_MS, 30_000);
assert.equal(clampedHigh.RPC_MULTICALL_WAIT_MS, 100);

const invalid = loadPolicy({
  NEXT_PUBLIC_RPC_POLLING_INTERVAL_MS: "not-a-number",
  NEXT_PUBLIC_RPC_MULTICALL_WAIT_MS: "not-a-number",
});
assert.equal(invalid.RPC_POLLING_INTERVAL_MS, 8_000);
assert.equal(invalid.RPC_MULTICALL_WAIT_MS, 40);
assert.equal(invalid.isRateLimitError(new Error("HTTP 429")), true);
assert.equal(invalid.isRateLimitError(new Error("too many requests")), true);
assert.equal(invalid.isPermanentRpcRequestError(new Error("HTTP 400")), true);
assert.equal(invalid.isPermanentRpcRequestError(new Error("temporary 503")), false);

console.log("RPC policy checks passed");
