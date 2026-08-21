#!/usr/bin/env node
/**
 * NexaFlow oracle keeper.
 *
 * The membership contract prices every stage from a PancakeSwap V2 TWAP. That
 * TWAP only advances when somebody calls `update()` on it. If the last update
 * is older than the contract's `maxPriceAge`, every quote and every paid action
 * reverts with `StalePrice` and registration stops dead.
 *
 * So this exists to call one function on a schedule. That is the whole job.
 *
 * The window is the thing to understand:
 *
 *   oracle.period       minimum seconds between updates   (update() reverts before this)
 *   contract.maxPriceAge  maximum age the contract accepts  (quotes revert after this)
 *
 * The keeper must fire inside that band. Production is configured for a 1-hour
 * period and an 8-hour max age, so this runs on a tighter cadence than strictly
 * required and treats "too early" as a normal no-op rather than an error.
 *
 * SECURITY: `update()` is permissionless and this wallet holds no role on the
 * contract. It needs BNB for gas and nothing else. Fund it with a small float
 * and never reuse an admin, operator, treasury or root key here.
 *
 *   node keeper/update-oracle.mjs            run once, then exit  (for cron)
 *   node keeper/update-oracle.mjs --watch    stay running         (for pm2/systemd)
 *   node keeper/update-oracle.mjs --dry-run  report only, send nothing
 */

import {
  createPublicClient,
  createWalletClient,
  fallback,
  http,
  formatEther,
  parseAbi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bsc } from "viem/chains";

const ORACLE_ABI = parseAbi([
  "function update() returns (uint256)",
  "function period() view returns (uint256)",
  "function blockTimestampLast() view returns (uint32)",
  "function latestPriceUsd() view returns (uint256, uint256)",
]);

const MEMBERSHIP_ABI = parseAbi([
  "function maxPriceAge() view returns (uint256)",
  "function priceOracle() view returns (address)",
]);

const RPC_URL = process.env.BSC_RPC_URL ?? "https://bsc-dataseed1.defibit.io";
const RPC_URL_ALCHEMY = process.env.BSC_RPC_URL_ALCHEMY ?? "";
const MEMBERSHIP = process.env.MEMBERSHIP_ADDRESS;
const KEY = process.env.KEEPER_PRIVATE_KEY;

const WATCH = process.argv.includes("--watch");
const DRY_RUN = process.argv.includes("--dry-run");

/** Warn when the gas float would not cover roughly a week of updates. */
const LOW_BALANCE_BNB = 0.02;

const log = (...a) => console.log(new Date().toISOString(), ...a);

function requireEnv() {
  const missing = [];
  if (!MEMBERSHIP) missing.push("MEMBERSHIP_ADDRESS");
  if (!KEY && !DRY_RUN) missing.push("KEEPER_PRIVATE_KEY");
  if (missing.length) {
    console.error(`Missing env: ${missing.join(", ")}`);
    console.error("Copy keeper/.env.example to keeper/.env and fill it in.");
    process.exit(1);
  }
}

/**
 * Fixed-order fallback transport. Primary always tried first; Alchemy only
 * serves traffic the primary drops. No health checks, no ranking — a keeper
 * that stops updating because its RPC blipped is worse than one that pays
 * the fallback provider for the retry.
 */
function bscTransport() {
  const primary = http(RPC_URL);
  if (!RPC_URL_ALCHEMY) return primary;
  return fallback([primary, http(RPC_URL_ALCHEMY)], { rank: false });
}

const publicClient = createPublicClient({ chain: bsc, transport: bscTransport() });

/**
 * Read everything needed to decide, in one place.
 *
 * The oracle address is read FROM the membership contract rather than taken
 * from env. Pointing a keeper at the wrong oracle would look like it was
 * working while the contract went stale anyway.
 */
async function readState() {
  const oracle = await publicClient.readContract({
    address: MEMBERSHIP,
    abi: MEMBERSHIP_ABI,
    functionName: "priceOracle",
  });

  const [period, lastUpdate, maxPriceAge, block] = await Promise.all([
    publicClient.readContract({ address: oracle, abi: ORACLE_ABI, functionName: "period" }),
    publicClient.readContract({ address: oracle, abi: ORACLE_ABI, functionName: "blockTimestampLast" }),
    publicClient.readContract({ address: MEMBERSHIP, abi: MEMBERSHIP_ABI, functionName: "maxPriceAge" }),
    publicClient.getBlock(),
  ]);

  const now = Number(block.timestamp);
  const age = now - Number(lastUpdate);

  return {
    oracle,
    period: Number(period),
    maxPriceAge: Number(maxPriceAge),
    age,
    // Too early: update() would revert PeriodNotElapsed. Not a failure.
    tooEarly: age < Number(period),
    // Already past the point where the contract refuses to quote.
    stale: age > Number(maxPriceAge),
  };
}

async function tick() {
  const s = await readState();

  const mins = (n) => `${Math.floor(n / 60)}m`;
  log(
    `oracle=${s.oracle} age=${mins(s.age)} period=${mins(s.period)} ` +
      `maxAge=${mins(s.maxPriceAge)}${s.stale ? " STALE" : ""}`,
  );

  if (s.tooEarly) {
    log(`too early, ${mins(s.period - s.age)} until update() is callable`);
    return { updated: false, ...s };
  }

  if (DRY_RUN) {
    log("dry run, would call update()");
    return { updated: false, ...s };
  }

  const account = privateKeyToAccount(KEY.startsWith("0x") ? KEY : `0x${KEY}`);
  const wallet = createWalletClient({ account, chain: bsc, transport: bscTransport() });

  const balance = await publicClient.getBalance({ address: account.address });
  if (balance === 0n) {
    log(`ERROR keeper ${account.address} has no BNB, cannot send`);
    return { updated: false, ...s };
  }
  if (Number(formatEther(balance)) < LOW_BALANCE_BNB) {
    log(`WARN keeper balance low: ${formatEther(balance)} BNB — top up ${account.address}`);
  }

  // Simulate first. A revert here is information, not an outage, and it keeps
  // the keeper from burning gas on a call that was never going to land.
  try {
    await publicClient.simulateContract({
      address: s.oracle,
      abi: ORACLE_ABI,
      functionName: "update",
      account,
    });
  } catch (err) {
    log(`simulate failed, skipping: ${String(err.shortMessage ?? err.message).split("\n")[0]}`);
    return { updated: false, ...s };
  }

  const hash = await wallet.writeContract({
    address: s.oracle,
    abi: ORACLE_ABI,
    functionName: "update",
  });
  log(`sent ${hash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") {
    log(`ERROR tx reverted ${hash}`);
    return { updated: false, ...s };
  }

  const [price] = await publicClient.readContract({
    address: s.oracle,
    abi: ORACLE_ABI,
    functionName: "latestPriceUsd",
  });
  const usd = Number(price) / 1e18;
  log(`updated. RWAAN = $${usd.toPrecision(4)} · gas ${receipt.gasUsed}`);

  return { updated: true, ...s };
}

async function main() {
  requireEnv();

  if (!WATCH) {
    await tick();
    return;
  }

  // Poll well inside the period so a single failed run is recoverable long
  // before the contract's maxPriceAge is breached.
  const intervalMs = 10 * 60 * 1000;
  log(`watch mode, checking every ${intervalMs / 60000}m`);

  for (;;) {
    try {
      await tick();
    } catch (err) {
      // Never exit on a transient RPC failure. Public BSC endpoints drop
      // connections and resolve DNS badly; the next tick usually succeeds.
      log(`tick failed: ${String(err.shortMessage ?? err.message).split("\n")[0]}`);
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

main().catch((err) => {
  log("fatal:", err.shortMessage ?? err.message);
  process.exit(1);
});
