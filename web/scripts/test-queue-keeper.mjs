import assert from "node:assert/strict";
import { test } from "node:test";
import { loadV6 } from "./v6-test-loader.mjs";
import { privateKeyToAccount } from "viem/accounts";
import { keccak256, parseTransaction } from "viem";
const { runQueueKeeper } = loadV6("lib/server/queue-keeper-core.ts");
const contract = "0x2222222222222222222222222222222222222222";
const intent = { contract, hash: `0x${"33".repeat(32)}`, raw: "0xf800", nonce: 0, stage: 0, work: 16, createdAt: 1000 };
function setup(patch = {}) {
  const state = { pending: null, locked: false, broadcasts: [], prepared: [], spent: 0, ...patch };
  const store = {
    acquire: async () => { if (state.locked) return false; state.locked = true; return true; },
    release: async () => { state.locked = false; }, pending: async () => state.pending, cursor: async () => state.cursor ?? 0,
    reserve: async (i, cost, budget) => { if (state.reserveFails || state.pending || state.spent + cost > budget) return false; state.pending = i; state.spent += cost; state.cursor=(i.stage+1)%6; return true; },
    complete: async hash => { assert.equal(state.pending.hash, hash); state.pending = null; return true; },
  };
  const chain = {
    verify: async () => { if (state.identityFails) throw Error("identity"); }, recovery: async () => state.recovery ?? false,
    queues: async () => state.queues ?? [1n,0n,0n,0n,0n,0n], receipt: async () => state.receipt ?? "pending",
    prepare: async stage => { state.prepared.push(stage); return state.zeroProgress ? null : { intent: { ...intent, stage }, costGwei: 100 }; },
    broadcast: async i => { assert.equal(state.pending.hash, i.hash, "must persist before broadcasting"); state.broadcasts.push(i.raw); if (state.broadcastFails) throw Error("uncertain submission"); },
  };
  const run = options => runQueueKeeper(store, chain, { dryRun: false, contract, budgetGwei: 1000, now: 2000, ...options });
  return { state, store, chain, run };
}
test("overlapping invocations submit at most one intent", async () => {
  const f = setup(); const results = await Promise.all([f.run(), f.run()]);
  assert.equal(f.state.broadcasts.length, 1); assert.ok(results.some(r => r.status === "busy"));
});
test("uncertain broadcast retains intent and retries only identical bytes", async () => {
  const f = setup({ broadcastFails: true }); await assert.rejects(f.run());
  assert.ok(f.state.pending); f.state.broadcastFails = false;
  assert.equal((await f.run()).status, "pending");
  assert.equal(f.state.prepared.length, 1); assert.equal(f.state.spent, 100);
  assert.equal(f.state.broadcasts[0], f.state.broadcasts[1]);
});
test("budget rejection, lost reservation, identity failure and recovery never broadcast", async () => {
  for (const options of [{ spent: 1000 }, { reserveFails: true }, { identityFails: true }, { recovery: true }]) {
    const f = setup(options); try { await f.run(); } catch {}
    assert.equal(f.state.broadcasts.length, 0); assert.equal(f.state.locked, false);
  }
});
test("empty queues, dry run and zero progress do not sign or broadcast", async () => {
  const idle = setup({ queues: Array(6).fill(0n) }); assert.equal((await idle.run()).status, "idle");
  const dry = setup(); assert.equal((await dry.run({ dryRun: true })).status, "dry_run"); assert.equal(dry.state.prepared.length, 0);
  const stalled = setup({ zeroProgress: true }); assert.equal((await stalled.run()).status, "no_progress");
  for (const f of [idle,dry,stalled]) assert.equal(f.state.broadcasts.length, 0);
});
test("pending success, revert and no-progress receipt settle without a second submission", async () => {
  for (const receipt of ["success","reverted","no_progress"]) {
    const f = setup({ pending: intent, receipt, spent: 100 });
    assert.equal((await f.run()).status, receipt === "success" ? "confirmed" : receipt);
    assert.equal(f.state.pending, null); assert.equal(f.state.spent, 100); assert.equal(f.state.broadcasts.length, 0);
  }
});
test("old pending, recovery and deployment mismatch stop rebroadcasting", async () => {
  for (const [patch, options, expected] of [
    [{ pending: intent }, { now: 1000000 }, "pending_stalled"],
    [{ pending: intent, recovery: true }, {}, "recovery_pending"],
    [{ pending: { ...intent, contract: "different" } }, {}, "pending_deployment_mismatch"],
  ]) { const f=setup(patch); assert.equal((await f.run(options)).status,expected); assert.equal(f.state.broadcasts.length,0); assert.ok(f.state.pending); }
});
test("stage rotation covers all six stages and skips non-progressing queues", async () => {
  for (let stage=0;stage<6;stage++) { const f=setup({queues:Array(6).fill(1n),cursor:stage}); await f.run(); assert.equal(f.state.prepared[0],stage); assert.equal(f.state.cursor,(stage+1)%6); assert.equal(f.state.broadcasts.length,1); }
});
test("storage read failure releases lock and never prepares a transaction", async () => {
  const f=setup(); f.store.pending=async()=>{throw Error("storage down")}; await assert.rejects(f.run()); assert.equal(f.state.prepared.length,0); assert.equal(f.state.broadcasts.length,0);
});

// Public deterministic unit-test key. Never fund this account.
const testKey = `0x${"11".repeat(32)}`;
const keeper = privateKeyToAccount(testKey).address;
function adapter(overrides = {}) {
  const sent=[];
  const client={
    getChainId:async()=>56, getCode:async()=>"0x6000",
    multicall:async request=>request.contracts[0].functionName==="root" ? [contract,contract,contract,false,false] : [1n,0n,0n,0n,0n,0n],
    readContract:async()=>false, simulateContract:async()=>({result:1n}), getGasPrice:async()=>50000000n,
    estimateContractGas:async()=>300000n, getTransactionCount:async()=>0, getBalance:async()=>10000000000000000n,
    sendRawTransaction:async request=>{sent.push(request);return keccak256(request.serializedTransaction)},
    ...overrides,
  };
  let chain;
  const module=loadV6("lib/server/queue-keeper.ts",{
    "server-only":{}, viem:{...awaitlessViem,createPublicClient:()=>client},
    "./queue-keeper-store":{redisKeeperStore:()=>({})},
    "./queue-keeper-core":{runQueueKeeper:async(_s,c)=>{chain=c;return {status:"captured"}}},
  });
  const env={KEEPER_ENABLED:"true",KEEPER_DRY_RUN:"false",VERCEL_ENV:"production",NEXT_PUBLIC_CHAIN:"bsc",NEXT_PUBLIC_MEMBERSHIP_VERSION:"v6",NEXT_PUBLIC_MEMBERSHIP_ADDRESS:contract,NEXT_PUBLIC_V6_RUNTIME_HASH:keccak256("0x6000"),KEEPER_WALLET_ADDRESS:keeper,KEEPER_PRIVATE_KEY:testKey,BSC_RPC_URL:"https://unit.invalid",UPSTASH_REDIS_REST_URL:"https://unit.invalid",UPSTASH_REDIS_REST_TOKEN:"test"};
  return {module,env,sent,client,chain:async()=>{await module.queueKeeper(env);return chain}};
}
import * as awaitlessViem from "viem";
test("adapter signs only bounded zero-value queue work, validates bytes before broadcast", async()=>{
  const f=adapter(), c=await f.chain(); await c.verify(); const p=await c.prepare(2);
  assert.equal(f.sent.length,0); const tx=parseTransaction(p.intent.raw);
  assert.equal(tx.to.toLowerCase(),contract); assert.equal(tx.value??0n,0n); assert.equal(tx.chainId,56); assert.equal(tx.gas,375000n);
  await c.broadcast(p.intent); assert.equal(f.sent.length,1);
  await assert.rejects(c.broadcast({...p.intent,stage:3})); assert.equal(f.sent.length,1);
});
test("adapter reduces work to fit gas cap",async()=>{
  const f=adapter({estimateContractGas:async r=>r.args[1]===16n?3000000n:300000n}); const c=await f.chain(); const p=await c.prepare(0); assert.equal(p.intent.work,4);
});
test("adapter rejects nonce conflict, insufficient BNB, gas caps and wrong signer",async()=>{
  for(const overrides of [{getTransactionCount:async r=>r.blockTag==="pending"?1:0},{getBalance:async()=>0n},{getGasPrice:async()=>999999999999n},{estimateContractGas:async()=>9000000n}]) {
    const f=adapter(overrides),c=await f.chain(); await assert.rejects(c.prepare(0)); assert.equal(f.sent.length,0);
  }
  const f=adapter(); f.env.KEEPER_WALLET_ADDRESS=contract; const c=await f.chain(); await assert.rejects(c.prepare(0));
});
test("adapter rejects privileged wallet, wrong code and wrong chain",async()=>{
  for(const overrides of [{getChainId:async()=>97},{getCode:async()=>"0x6001"},{multicall:async()=>[contract,contract,contract,true,false]}]) {
    const f=adapter(overrides),c=await f.chain(); await assert.rejects(c.verify()); assert.equal(f.sent.length,0);
  }
});
test("disabled is default, live preview prohibited, cron auth constant-time exact bearer",async()=>{
  const f=adapter(); assert.equal((await f.module.queueKeeper({})).status,"disabled");
  await assert.rejects(f.module.queueKeeper({...f.env,VERCEL_ENV:"preview"}));
  const secret="x".repeat(32); assert.equal(f.module.keeperAuthorized(`Bearer ${secret}`,secret),true);
  for(const header of [null,"Bearer wrong",secret])assert.equal(f.module.keeperAuthorized(header,secret),false);
  assert.equal(f.module.keeperAuthorized("Bearer tiny","tiny"),false);
});
test("route rejects unauthorized requests and redacts all internal errors",async()=>{
  let calls=0;
  const route=loadV6("app/api/keeper/route.ts",{"@/lib/server/queue-keeper":{keeperAuthorized:h=>h==="Bearer test",queueKeeper:async()=>{calls++;throw Error("private key and RPC credentials")}}},{Response,Request});
  assert.equal((await route.GET(new Request("https://unit.invalid"))).status,401); assert.equal(calls,0);
  const r=await route.GET(new Request("https://unit.invalid",{headers:{authorization:"Bearer test"}}));assert.equal(r.status,503);assert.doesNotMatch(await r.text(),/private key|RPC credentials/);
});
