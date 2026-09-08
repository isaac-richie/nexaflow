import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";
import ts from "typescript";

const source = readFileSync(new URL("../lib/server/registration-index.ts", import.meta.url), "utf8");
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
const v4 = "0xc1624d739b446f9986d51d2d83822d2b393419ae";
const v5 = "0xef7ede29c63abd3add2c829bdd70625b47e1a245";
function cacheKeys(overrides = {}) {
  const keys = [];
  vm.runInNewContext(compiled, {
    exports: {},
    process: { env: { NEXT_PUBLIC_CHAIN: "bsc", NEXT_PUBLIC_MEMBERSHIP_ADDRESS: v5, ...overrides } },
    require: (name) => {
      if (name === "server-only") return {};
      if (name === "next/cache") return { unstable_cache: (fn, key, options) => { keys.push({ key: [...key], revalidate: options.revalidate }); return fn; } };
      if (name === "viem") return { parseAbiItem: value => value };
      if (name === "viem/chains") return {};
      throw new Error(`Unexpected import ${name}`);
    },
  });
  return keys;
}
test("snapshot cache separates V4 and V5 without reducing refresh interval", () => {
  const before = cacheKeys({ NEXT_PUBLIC_MEMBERSHIP_ADDRESS: v4 });
  const after = cacheKeys();
  assert.notDeepEqual(before.at(-1).key, after.at(-1).key);
  assert.equal(after.at(-1).revalidate, 60);
  assert.equal(after[0].revalidate, false);
});
test("all persistent network caches distinguish mainnet and testnet", () => {
  const mainnet = cacheKeys();
  const testnet = cacheKeys({ NEXT_PUBLIC_CHAIN: "bscTestnet" });
  assert.equal(mainnet.length, 4);
  mainnet.forEach((cache, i) => assert.notDeepEqual(cache.key, testnet[i].key));
});
test("snapshot separates deployment blocks and respects server override", () => {
  const a = cacheKeys({ NEXT_PUBLIC_MEMBERSHIP_DEPLOYMENT_BLOCK: "118526709" });
  const b = cacheKeys({ NEXT_PUBLIC_MEMBERSHIP_DEPLOYMENT_BLOCK: "117789702" });
  assert.notDeepEqual(a.at(-1).key, b.at(-1).key);
  const c = cacheKeys({ MEMBERSHIP_DEPLOYMENT_BLOCK: "118526709", NEXT_PUBLIC_MEMBERSHIP_DEPLOYMENT_BLOCK: "117789702" });
  assert.deepEqual(a.at(-1).key, c.at(-1).key);
});
test("address casing and RPC credential rotation do not create redundant caches", () => {
  assert.deepEqual(cacheKeys().at(-1).key, cacheKeys({ NEXT_PUBLIC_MEMBERSHIP_ADDRESS: v5.toUpperCase(), BSC_RPC_URL: "https://example.invalid" }).at(-1).key);
});
test("V6 registration event caches cannot reuse V5 decoded records", () => {
  const v5 = cacheKeys();
  const v6 = cacheKeys({ NEXT_PUBLIC_MEMBERSHIP_VERSION: "v6" });
  for (const index of [0, 1, 3]) assert.notDeepEqual(v5[index].key, v6[index].key);
});
