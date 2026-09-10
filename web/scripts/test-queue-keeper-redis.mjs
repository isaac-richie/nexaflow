import assert from "node:assert/strict";
import { test } from "node:test";
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadV6 } from "./v6-test-loader.mjs";
const exec = promisify(execFile);
const { RESERVE_SCRIPT, COMPLETE_SCRIPT } = loadV6("lib/server/queue-keeper-store.ts", {"server-only":{}});

test("real Redis Lua: atomic reservation, rolling budget, lease fencing, durable pending, cursor", async t => {
  try { await exec("redis-server",["--version"]); await exec("redis-cli",["--version"]); }
  catch { t.skip("Install Redis locally to run the real storage integration test"); return; }
  const dir=mkdtempSync(join(tmpdir(),"nexaflow-keeper-test-")), socket=join(dir,"redis.sock");
  const server=spawn("redis-server",["--port","0","--unixsocket",socket,"--save","","--appendonly","no"],{stdio:"ignore"});
  const command=async(...args)=>(await exec("redis-cli",["-s",socket,"--raw",...args.map(String)])).stdout.trim();
  try {
    let ready=false; for(let i=0;i<60;i++){try{ready=await command("PING")==="PONG";if(ready)break}catch{} await new Promise(r=>setTimeout(r,25));} assert.ok(ready);
    const lock="test:lock",state="test:state",owner="worker-a";
    await command("SET",lock,owner,"PX",120000);
    const intent={hash:"0x123",raw:"public-test-payload",stage:4,nonce:0,createdAt:Date.now()};
    const reserve=()=>command("EVAL",RESERVE_SCRIPT,2,lock,state,owner,JSON.stringify(intent),60,100);
    assert.equal(await reserve(),"0","missing state must fail closed");
    await command("SET",state,JSON.stringify({costs:[],cursor:0}),"NX");
    const races=await Promise.all([reserve(),reserve(),reserve()]);assert.equal(races.filter(x=>x==="1").length,1);
    let saved=JSON.parse(await command("GET",state));assert.equal(saved.pending.hash,intent.hash);assert.equal(saved.costs.length,1);assert.equal(saved.cursor,5);
    assert.equal(await command("TTL",state),"-1","pending record must not expire");
    assert.equal(await command("EVAL",COMPLETE_SCRIPT,2,lock,state,"wrong-owner",intent.hash),"0");
    assert.equal(await command("EVAL",COMPLETE_SCRIPT,2,lock,state,owner,"wrong-hash"),"0");
    assert.equal(await command("EVAL",COMPLETE_SCRIPT,2,lock,state,owner,intent.hash),"1");
    assert.equal(await reserve(),"0","60+60 exceeds rolling 100 budget");
    saved=JSON.parse(await command("GET",state));saved.costs[0].at=Date.now()-86401000;await command("SET",state,JSON.stringify(saved));
    assert.equal(await reserve(),"1","expired reservations no longer consume budget");
    await command("EVAL",COMPLETE_SCRIPT,2,lock,state,owner,intent.hash);
    await command("SET",lock,"worker-b","PX",120000);
    assert.equal(await reserve(),"0","expired worker cannot commit after lease changes");
  } finally { server.kill("SIGTERM"); await new Promise(resolve=>server.once("exit",resolve)); }
});
