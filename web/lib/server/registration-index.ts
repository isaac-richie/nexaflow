import "server-only";

import { unstable_cache } from "next/cache";
import {
  createPublicClient,
  fallback,
  getAddress,
  http,
  isAddress,
  keccak256,
  parseAbiItem,
  type PublicClient,
} from "viem";
import { bsc, bscTestnet } from "viem/chains";
import type { RegistrationRecord } from "@/lib/network-graph";

const VERSION = process.env.NEXT_PUBLIC_MEMBERSHIP_VERSION ?? "v5";
const REGISTRATION_EVENT = VERSION === "v6" ? parseAbiItem("event Registered(address indexed member, address indexed sponsor)") : parseAbiItem(
  "event MemberRegistered(address indexed member, address indexed sponsor, uint256 memberId)",
);

const FINALITY_BLOCKS = 20n;
const DEFAULT_CHUNK_SIZE = 250_000n;
const MIN_SPLIT_RANGE = 1_000n;

// Vercel data caches can survive releases. Never reuse another chain's logs
// or another deployment's complete snapshot when production switches versions.
const CHAIN_CACHE_KEY = process.env.NEXT_PUBLIC_CHAIN === "bsc" ? "56" : "97";
const SNAPSHOT_CACHE_SCOPE = [
  CHAIN_CACHE_KEY,
  VERSION,
  process.env.NEXT_PUBLIC_V6_RUNTIME_HASH ?? "legacy",
  (process.env.NEXT_PUBLIC_MEMBERSHIP_ADDRESS ?? "unconfigured").toLowerCase(),
  process.env.MEMBERSHIP_DEPLOYMENT_BLOCK ??
    process.env.NEXT_PUBLIC_MEMBERSHIP_DEPLOYMENT_BLOCK ?? "known-deployment",
  process.env.NETWORK_INDEX_CHUNK_SIZE ?? DEFAULT_CHUNK_SIZE.toString(),
];

// Production deployments already used by the frontend. Keeping their creation
// blocks here makes the network panel work immediately on Vercel even before a
// deployment-block environment variable is added. Future contracts should set
// MEMBERSHIP_DEPLOYMENT_BLOCK explicitly instead of scanning from genesis.
const KNOWN_DEPLOYMENT_BLOCKS = new Map<string, bigint>([
  ["0xc1624d739b446f9986d51d2d83822d2b393419ae", 117_789_702n], // V4
  ["0xef7ede29c63abd3add2c829bd70625b47e1a245", 118_526_709n], // V5
]);

function boundedBigInt(
  raw: string | undefined,
  fallbackValue: bigint,
  minimum: bigint,
  maximum: bigint,
): bigint {
  if (!raw || !/^\d+$/.test(raw)) return fallbackValue;
  const value = BigInt(raw);
  return value < minimum ? minimum : value > maximum ? maximum : value;
}

function membershipAddress(): `0x${string}` {
  const address = process.env.NEXT_PUBLIC_MEMBERSHIP_ADDRESS;
  if (!address || !isAddress(address)) {
    throw new Error("Network index is not configured: membership address is missing");
  }
  return getAddress(address);
}

function deploymentBlock(address: `0x${string}`): bigint {
  const raw =
    process.env.MEMBERSHIP_DEPLOYMENT_BLOCK ??
    process.env.NEXT_PUBLIC_MEMBERSHIP_DEPLOYMENT_BLOCK;
  if (raw && /^\d+$/.test(raw)) return BigInt(raw);

  const known = KNOWN_DEPLOYMENT_BLOCKS.get(address.toLowerCase());
  if (known !== undefined) return known;

  throw new Error("Network index is not configured: deployment block is missing");
}

function rpcUrls(): string[] {
  const urls = [
    process.env.BSC_RPC_URL,
    process.env.NEXT_PUBLIC_BSC_RPC_URL_ALCHEMY,
    process.env.NEXT_PUBLIC_BSC_RPC_URL,
  ].filter((value): value is string => Boolean(value));
  return [...new Set(urls)];
}

let publicClient: PublicClient | undefined;

function client(): PublicClient {
  if (publicClient) return publicClient;
  const chain = process.env.NEXT_PUBLIC_CHAIN === "bsc" ? bsc : bscTestnet;
  const urls = rpcUrls();
  const transports = urls.length > 0
    ? urls.map((url) => http(url, { retryCount: 1, timeout: 15_000 }))
    : [http(undefined, { retryCount: 1, timeout: 15_000 })];
  publicClient = createPublicClient({
    chain,
    transport: transports.length === 1 ? transports[0] : fallback(transports, { rank: false }),
  });
  return publicClient;
}

async function readRange(
  address: `0x${string}`,
  fromBlock: bigint,
  toBlock: bigint,
): Promise<RegistrationRecord[]> {
  if (toBlock < fromBlock) return [];

  try {
    const logs = await client().getLogs({
      address,
      event: REGISTRATION_EVENT,
      fromBlock,
      toBlock,
      strict: true,
    });

    const records = logs.flatMap((log) => {
      const { member, sponsor } = log.args;
      const memberId = "memberId" in log.args ? log.args.memberId : 0n;
      if (!member || !sponsor || memberId == null || !log.transactionHash || log.blockNumber == null) {
        return [];
      }
      return [{
        member: getAddress(member),
        sponsor: getAddress(sponsor),
        memberId: Number(memberId),
        logIndex: log.logIndex,
        blockNumber: Number(log.blockNumber),
        transactionHash: log.transactionHash,
      }];
    });
    // V6 creates root positions in the constructor, without a Registered event.
    // Include the first uncharged root position once, using its real receipt.
    const start = deploymentBlock(address);
    if (VERSION === "v6" && fromBlock <= start && start <= toBlock) {
      const opened = await client().getLogs({ address, fromBlock: start, toBlock: start,
        event: parseAbiItem("event PositionOpened(uint256 indexed id, address indexed member, uint8 indexed stage, uint256 parent, uint64 cycle, bool funded)"), strict: true });
      if (!opened.some(log => log.args.id === 1n && log.args.stage === 0 && log.args.funded === false)) {
        throw new Error("V6 deployment block does not contain the initial root position");
      }
      for (const log of opened) {
        if (log.args.id === 1n && log.args.stage === 0 && log.args.funded === false) records.unshift({ member: getAddress(log.args.member), sponsor: "0x0000000000000000000000000000000000000000", memberId: 0, logIndex: log.logIndex, blockNumber: Number(log.blockNumber), transactionHash: log.transactionHash });
      }
    }
    return records;
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("V6 deployment block")) throw error;
    const span = toBlock - fromBlock + 1n;
    if (span <= MIN_SPLIT_RANGE) throw error;

    // Providers enforce different eth_getLogs limits. Split only after an
    // actual rejection, and do it sequentially to avoid request bursts.
    const midpoint = fromBlock + (span / 2n) - 1n;
    const left = await readRange(address, fromBlock, midpoint);
    const right = await readRange(address, midpoint + 1n, toBlock);
    return [...left, ...right];
  }
}

async function fetchRegistrationChunk(
  address: string,
  fromBlock: string,
  toBlock: string,
): Promise<RegistrationRecord[]> {
  return readRange(getAddress(address), BigInt(fromBlock), BigInt(toBlock));
}

// Completed block buckets never need to hit RPC again. Next/Vercel's data
// cache persists these results across users and serverless invocations.
const cachedClosedChunk = unstable_cache(
  fetchRegistrationChunk,
  ["nexaflow-registration-closed-chunk-v3", CHAIN_CACHE_KEY, VERSION],
  { revalidate: false },
);

// Only the current bucket refreshes. A one-minute cache keeps the dashboard
// useful without turning every page view into an RPC log scan.
const cachedLiveChunk = unstable_cache(
  fetchRegistrationChunk,
  ["nexaflow-registration-live-chunk-v3", CHAIN_CACHE_KEY, VERSION],
  { revalidate: 60 },
);

// Block timestamps are immutable once a block is final, so a permanent
// per-block cache costs one RPC call per block for the lifetime of the
// deployment. Alchemy returns a whole block for ~1 credit; this covers the
// sparkline series without materially growing the RPC budget.
const fetchBlockTimestamp = unstable_cache(
  async (block: string): Promise<number> => {
    const value = await client().getBlock({ blockNumber: BigInt(block) });
    return Number(value.timestamp);
  },
  ["nexaflow-block-timestamp-v2", CHAIN_CACHE_KEY],
  { revalidate: false },
);

// Bounded concurrency keeps big first-load bursts inside provider rate limits.
async function attachTimestamps(
  records: RegistrationRecord[],
): Promise<RegistrationRecord[]> {
  const uniqueBlocks = [...new Set(records.map((r) => r.blockNumber))];
  const concurrency = 10;
  const timestamps = new Map<number, number>();
  for (let index = 0; index < uniqueBlocks.length; index += concurrency) {
    const slice = uniqueBlocks.slice(index, index + concurrency);
    const results = await Promise.all(
      slice.map(async (block) => {
        try {
          const ts = await fetchBlockTimestamp(String(block));
          return [block, ts] as const;
        } catch (error) {
          console.warn("Timestamp lookup failed for block", block, error);
          return [block, undefined] as const;
        }
      }),
    );
    for (const [block, ts] of results) {
      if (ts !== undefined) timestamps.set(block, ts);
    }
  }
  return records.map((record) => {
    const ts = timestamps.get(record.blockNumber);
    return ts === undefined ? record : { ...record, timestamp: ts };
  });
}

async function buildRegistrationSnapshot(): Promise<{
  records: RegistrationRecord[];
  syncedBlock: number;
}> {
  const address = membershipAddress();
  if (!["v5", "v6"].includes(VERSION)) throw new Error("Unsupported network index version");
  if (VERSION === "v6") {
    if (await client().getChainId() !== Number(CHAIN_CACHE_KEY)) throw new Error("Network index chain mismatch");
    const expected = process.env.NEXT_PUBLIC_V6_RUNTIME_HASH;
    const code = await client().getCode({ address });
    if (!expected || !code || code === "0x" || keccak256(code).toLowerCase() !== expected.toLowerCase()) throw new Error("V6 network index contract identity mismatch");
  }
  const start = deploymentBlock(address);
  const latest = await client().getBlockNumber();
  const safeHead = latest > FINALITY_BLOCKS ? latest - FINALITY_BLOCKS : latest;
  if (safeHead < start) return { records: [], syncedBlock: Number(safeHead) };

  const chunkSize = boundedBigInt(
    process.env.NETWORK_INDEX_CHUNK_SIZE,
    DEFAULT_CHUNK_SIZE,
    10_000n,
    500_000n,
  );
  const records: RegistrationRecord[] = [];
  let cursor = start;

  while (cursor <= safeHead) {
    const end = cursor + chunkSize - 1n > safeHead
      ? safeHead
      : cursor + chunkSize - 1n;
    const isLive = end === safeHead;
    const chunk = await (isLive ? cachedLiveChunk : cachedClosedChunk)(
      address,
      cursor.toString(),
      end.toString(),
    );
    records.push(...chunk);
    cursor = end + 1n;
  }

  // MemberRegistered is emitted once per address. The defensive map also
  // protects the UI from duplicated provider results around chunk boundaries.
  const unique = new Map<string, RegistrationRecord>();
  for (const record of records) unique.set(record.member.toLowerCase(), record);

  const sorted = [...unique.values()].sort((a, b) => VERSION === "v6" ? a.blockNumber - b.blockNumber || (a.logIndex ?? 0) - (b.logIndex ?? 0) : a.memberId - b.memberId);
  if (VERSION === "v6") sorted.forEach((record, index) => { record.memberId = index + 1; });
  const withTimestamps = await attachTimestamps(sorted);
  return {
    records: withTimestamps,
    syncedBlock: Number(safeHead),
  };
}

export const getRegistrationSnapshot = unstable_cache(
  buildRegistrationSnapshot,
  ["nexaflow-registration-snapshot-v3", ...SNAPSHOT_CACHE_SCOPE],
  { revalidate: 60 },
);
