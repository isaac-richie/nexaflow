import "server-only";
import { createHash, timingSafeEqual } from "node:crypto";
import { createPublicClient, decodeEventLog, encodeFunctionData, http, isAddress, keccak256, parseEther, parseGwei, parseTransaction, recoverTransactionAddress, stringToHex, zeroAddress, type Address, type Hex, type TransactionSerialized } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bsc } from "viem/chains";
import { BINARY_MEMBERSHIP_V6_ABI as abi } from "../contracts/binaryMembershipV6Abi";
import { runQueueKeeper, type Intent, type KeeperChain } from "./queue-keeper-core";
import { redisKeeperStore } from "./queue-keeper-store";

export function keeperAuthorized(header: string | null, secret: string | undefined) {
  if (!secret || secret.length < 32 || !header) return false;
  const hash = (s: string) => createHash("sha256").update(s).digest();
  return timingSafeEqual(hash(header), hash(`Bearer ${secret}`));
}
function required(env: NodeJS.ProcessEnv, name: string) {
  const value = env[name]; if (!value) throw new Error("Missing keeper configuration"); return value;
}
export async function queueKeeper(env: NodeJS.ProcessEnv = process.env) {
  // Disabled by default. Preview deployments must never sign.
  if (env.KEEPER_ENABLED !== "true") return { status: "disabled" };
  const dryRun = env.KEEPER_DRY_RUN !== "false";
  if (!dryRun && env.VERCEL_ENV !== "production") throw new Error("Live keeper requires production");
  if (env.NEXT_PUBLIC_CHAIN !== "bsc" || env.NEXT_PUBLIC_MEMBERSHIP_VERSION !== "v6") throw new Error("Keeper deployment mismatch");
  const address = required(env, "NEXT_PUBLIC_MEMBERSHIP_ADDRESS") as Address;
  const runtimeHash = required(env, "NEXT_PUBLIC_V6_RUNTIME_HASH");
  const keeper = required(env, "KEEPER_WALLET_ADDRESS") as Address;
  if (![address, keeper].every(a => isAddress(a) && a !== zeroAddress) || !/^0x[0-9a-fA-F]{64}$/.test(runtimeHash)) throw new Error("Invalid keeper identity");
  const rpc = required(env, "BSC_RPC_URL");
  if (!rpc.startsWith("https://")) throw new Error("Private HTTPS RPC required");
  const client = createPublicClient({ chain: bsc, transport: http(rpc, { retryCount: 0, timeout: 8000 }) });
  const maxGasPrice = parseGwei(env.KEEPER_MAX_GAS_PRICE_GWEI ?? "0.1");
  const maxGas = BigInt(env.KEEPER_MAX_GAS ?? "2000000");
  const budget = parseEther(env.KEEPER_BUDGET_BNB_24H ?? "0.001");
  const floor = parseEther(env.KEEPER_MIN_BALANCE_BNB ?? "0.0001");
  if (maxGasPrice <= 0n || maxGasPrice > parseGwei("5") || maxGas < 21000n || maxGas > 5000000n || budget <= 0n || budget > parseEther("0.1") || floor < 0n) throw new Error("Invalid keeper limits");
  const read = <N extends "emergencyRecovery" | "root" | "treasury" | "company">(functionName: N) => client.readContract({ address, abi, functionName });
  const scope = `nexaflow:keeper:56:${keeper.toLowerCase()}`; // shared across deployments using this signer
  const store = redisKeeperStore(required(env, "UPSTASH_REDIS_REST_URL"), required(env, "UPSTASH_REDIS_REST_TOKEN"), scope);
  const chain: KeeperChain = {
    verify: async () => {
      const [chainId, code] = await Promise.all([client.getChainId(), client.getCode({ address })]);
      if (chainId !== 56 || !code || keccak256(code).toLowerCase() !== runtimeHash.toLowerCase()) throw new Error("Keeper runtime mismatch");
      const [root, treasury, company, admin, pauser] = await client.multicall({ allowFailure: false, contracts: [
        { address, abi, functionName: "root" }, { address, abi, functionName: "treasury" }, { address, abi, functionName: "company" },
        { address, abi, functionName: "hasRole", args: [`0x${"00".repeat(32)}`, keeper] },
        { address, abi, functionName: "hasRole", args: [keccak256(stringToHex("PAUSER_ROLE")), keeper] },
      ] as const });
      if ([address, root, treasury, company].some(a => a.toLowerCase() === keeper.toLowerCase()) || admin || pauser) throw new Error("Use a dedicated unprivileged keeper wallet");
    },
    recovery: () => read("emergencyRecovery"),
    queues: () => client.multicall({ allowFailure: false, contracts: Array.from({ length: 6 }, (_, i) => ({ address, abi, functionName: "queueLength", args: [BigInt(i)] } as const)) }),
    receipt: async hash => {
      try {
        const receipt = await client.getTransactionReceipt({ hash });
        if ((await client.getBlockNumber({ cacheTime: 0 })) < receipt.blockNumber + 2n) return "pending";
        if (receipt.status === "reverted") return "reverted";
        const progress = receipt.logs.some(log => {
          if (log.address.toLowerCase() !== address.toLowerCase()) return false;
          try { return decodeEventLog({ abi, data: log.data, topics: log.topics }).eventName === "Reactivated"; } catch { return false; }
        });
        return progress ? "success" : "no_progress";
      } catch (error) {
        if (error instanceof Error && error.name === "TransactionReceiptNotFoundError") return "pending";
        throw error;
      }
    },
    prepare: async stage => {
      const gasPrice = await client.getGasPrice();
      if (gasPrice > maxGasPrice || gasPrice === 0n) throw new Error("Gas price cap reached");
      let gas = 0n, work = 0n;
      for (const limit of [16n, 4n, 1n]) {
        const simulation = await client.simulateContract({ address, abi, functionName: "processReentries", args: [stage, limit], account: keeper });
        if (simulation.result === 0n) { if (limit === 16n) return null; continue; }
        const estimated = await client.estimateContractGas({ address, abi, functionName: "processReentries", args: [stage, limit], account: keeper });
        const buffered = (estimated * 125n + 99n) / 100n;
        if (buffered <= maxGas) { gas = buffered; work = limit; break; }
      }
      if (work === 0n) throw new Error("Transaction gas cap reached");
      const [latest, pending, balance] = await Promise.all([client.getTransactionCount({ address: keeper, blockTag: "latest" }), client.getTransactionCount({ address: keeper, blockTag: "pending" }), client.getBalance({ address: keeper })]);
      if (latest !== pending) throw new Error("Unexpected pending keeper nonce");
      if (balance < gas * gasPrice + floor) throw new Error("Keeper needs gas funding");
      const key = required(env, "KEEPER_PRIVATE_KEY") as Hex;
      if (!/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error("Invalid keeper signing configuration");
      const signer = privateKeyToAccount(key);
      if (signer.address.toLowerCase() !== keeper.toLowerCase()) throw new Error("Keeper signer mismatch");
      const raw = await signer.signTransaction({ chainId: 56, type: "legacy", to: address, nonce: latest, gas, gasPrice, value: 0n, data: encodeFunctionData({ abi, functionName: "processReentries", args: [stage, work] }) });
      return { intent: { raw, hash: keccak256(raw), nonce: latest, stage, work: Number(work), contract: address, createdAt: Date.now() }, costGwei: Number((gas * gasPrice + 999999999n) / 1000000000n) };
    },
    broadcast: async (intent: Intent) => {
      // Persisted bytes are usable after a timeout. Validate before rebroadcast.
      const tx = parseTransaction(intent.raw);
      if (keccak256(intent.raw) !== intent.hash || tx.chainId !== 56 || tx.to?.toLowerCase() !== address.toLowerCase() || (tx.value ?? 0n) !== 0n || tx.nonce !== intent.nonce || !Number.isInteger(intent.stage) || intent.stage < 0 || intent.stage > 5 || ![1,4,16].includes(intent.work) || tx.data !== encodeFunctionData({ abi, functionName: "processReentries", args: [intent.stage, BigInt(intent.work)] }) || (await recoverTransactionAddress({ serializedTransaction: intent.raw as TransactionSerialized })).toLowerCase() !== keeper.toLowerCase()) throw new Error("Pending keeper intent mismatch");
      if (await read("emergencyRecovery")) throw new Error("Recovery started; submission stopped");
      try { await client.sendRawTransaction({ serializedTransaction: intent.raw }); }
      catch (error) {
        // A provider may reject an identical rebroadcast as already imported.
        // Keep tracking its existing hash; never treat nonce-too-low as success.
        if (!(error instanceof Error && /already known|already imported/i.test(error.message))) throw error;
      }
    },
  };
  return runQueueKeeper(store, chain, { dryRun, contract: address, budgetGwei: Number(budget / 1000000000n), now: Date.now() });
}
