// Local Anvil only. Uses unlocked synthetic accounts, never .env or real keys.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, http, keccak256, zeroAddress } from "viem";
import { foundry } from "viem/chains";
import { multicall3Bytecode } from "../node_modules/viem/_esm/constants/contracts.js";
import { loadV6 } from "./v6-test-loader.mjs";

const { readV6Snapshot, readV6History, readV6Tree, checkV6Purchase } = loadV6("lib/v6.ts");
const { BINARY_MEMBERSHIP_V6_ABI: abi } = loadV6("lib/contracts/binaryMembershipV6Abi.ts");
const artifact = name => JSON.parse(readFileSync(new URL(`../../out/${name}.sol/${name}.json`, import.meta.url), "utf8"));
const candidate = artifact("BinaryMembershipV6");
const tokenArtifact = JSON.parse(readFileSync(new URL("../../out/BinaryMembershipV6Prototype.t.sol/V6AdversarialToken.json", import.meta.url), "utf8"));
const anvil = spawn("anvil", ["--host", "127.0.0.1", "--port", "18546", "--accounts", "30", "--silent"], { stdio: ["ignore", "ignore", "pipe"] });
let startupError = "";
anvil.stderr.on("data", b => { startupError += b.toString(); });
const transport = http("http://127.0.0.1:18546", { retryCount: 0 });
let client = createPublicClient({ chain: foundry, transport, cacheTime: 0 });
const wallet = createWalletClient({ chain: foundry, transport });
let checks = 0;
const check = (value, note) => { assert.ok(value, note); checks++; };
try {
  let ready = false;
  for (let i = 0; i < 30; i++) {
    await new Promise(r => setTimeout(r, 100));
    if (anvil.exitCode !== null) throw new Error(`Could not start isolated Anvil: ${startupError}`);
    try { await client.getChainId(); ready = true; break; } catch {}
  }
  if (!ready) throw new Error("Local Anvil did not start");
  const accounts = await wallet.getAddresses();
  const [root, treasury, company, admin, user] = accounts;
  async function receipt(hash) { const r = await client.waitForTransactionReceipt({ hash, pollingInterval: 10 }); assert.equal(r.status, "success"); return r; }
  const multicall = (await receipt(await wallet.deployContract({ abi: [], bytecode: multicall3Bytecode, account: admin }))).contractAddress;
  client = createPublicClient({ chain: { ...foundry, contracts: { multicall3: { address: multicall, blockCreated: 0 } } }, transport, cacheTime: 0 });
  const token = (await receipt(await wallet.deployContract({ abi: tokenArtifact.abi, bytecode: tokenArtifact.bytecode.object, account: admin }))).contractAddress;
  const address = (await receipt(await wallet.deployContract({ abi, bytecode: candidate.bytecode.object, args: [token, root, treasury, company, admin, 86400], account: admin }))).contractAddress;
  const deployment = { chainId: 31337, address, token, runtimeHash: keccak256(await client.getCode({ address })) };
  async function act(account, functionName, args = []) {
    const simulated = await client.simulateContract({ address, abi, functionName, args, account });
    return receipt(await wallet.writeContract(simulated.request));
  }
  async function tokenAct(functionName, args, account = admin) { return receipt(await wallet.writeContract({ address: token, abi: tokenArtifact.abi, functionName, args, account })); }
  const initial = await readV6Snapshot(client, deployment, root);
  check(initial.paused && initial.registered && initial.highestStage === 5, "candidate launches paused with root");
  check(initial.stages.every(s => s.boards === 1n && s.completed === 0n && s.earned === 0n), "six free root boards are not earnings");
  await act(admin, "setPaused", [false]);
  for (const member of accounts.slice(4, 25)) await tokenAct("mint", [member, 20000n * 10n ** 18n]);
  for (const member of accounts.slice(4, 25)) {
    for (let stage = 0; stage < 6; stage++) {
      const before = await readV6Snapshot(client, deployment, member);
      checkV6Purchase(before, member, zeroAddress, stage, before.stages[stage].fee);
      await tokenAct("approve", [address, before.stages[stage].fee], member);
      if (stage === 0) await act(member, "register", [member === user ? zeroAddress : user]);
      else await act(member, "joinStage", [stage]);
      const after = await readV6Snapshot(client, deployment, member);
      check(after.registered && after.highestStage === stage, "correct sequential stage after receipt");
      check(after.allowance === 0n, "exact fee approval consumed");
    }
  }
  let member = await readV6Snapshot(client, deployment, user);
  check(member.stages.reduce((sum, s) => sum + s.earned, 0n) === member.earned, "all stage earnings reconcile");
  check(member.stages.some(s => s.completed > 0n && s.boards > 1n), "funded re-entry reflected in history");
  const history = await readV6History(client, deployment, user, 0, member.stages[0].boards, 0, member.block);
  check(history.length > 1 && history.length <= 10, "real historical boards available");
  const tree = await readV6Tree(client, deployment, history[0].id, history[0].position, 2, member.block);
  check(tree.length === 7, "stage 1 tree bounded to six child positions");
  await tokenAct("setBlocked", [user, true]);
  await tokenAct("approve", [address, 20n * 10n ** 18n], accounts[25]);
  await tokenAct("mint", [accounts[25], 20n * 10n ** 18n]);
  await act(accounts[25], "register", [user]);
  member = await readV6Snapshot(client, deployment, user);
  check(member.claimable > 0n, "blocked payout is claimable, not lost");
  const reserve = await client.readContract({ address, abi, functionName: "totalReserved" });
  check(reserve > 0n, "reserves accumulated");
  await act(admin, "recoverEmergencyReserves", [accounts[29]]);
  const recovery = await readV6Snapshot(client, deployment, user);
  check(recovery.recovery && recovery.paused, "recovery displayed and actions frozen");
  check(recovery.earned === member.earned && recovery.claimable === member.claimable, "custody transfer does not change member earnings");
  const beforeClaim = await client.readContract({ address: token, abi: tokenArtifact.abi, functionName: "balanceOf", args: [accounts[28]] });
  await act(user, "claim", [accounts[28]]);
  const afterClaim = await client.readContract({ address: token, abi: tokenArtifact.abi, functionName: "balanceOf", args: [accounts[28]] });
  check(afterClaim - beforeClaim === member.claimable, "claim works during recovery to another recipient");
  await tokenAct("approve", [address, reserve], accounts[29]);
  await act(accounts[29], "restoreEmergencyReserves", [reserve]);
  await act(admin, "completeEmergencyRecovery");
  const restored = await readV6Snapshot(client, deployment, user);
  check(restored.paused && !restored.recovery && restored.claimable === 0n, "restoration stays paused and claim cleared");
  await act(admin, "setPaused", [false]);
  check(!(await readV6Snapshot(client, deployment, user)).paused, "explicit resumption observed");
  await assert.rejects(readV6Snapshot(client, { ...deployment, runtimeHash: `0x${"11".repeat(32)}` }, user), /identity/); checks++;
  console.log(JSON.stringify({ localOnly: true, paidWalletsAcrossSixStages: 21, paidStageTransactions: 126, checks, result: "PASS", coverage: "Frontend data adapter + ABI-encoded transactions, not browser wallet-provider UI" }, null, 2));
} finally { anvil.kill("SIGTERM"); }
