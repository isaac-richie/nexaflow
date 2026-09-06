import "server-only";

import { unstable_cache } from "next/cache";
import {
  createPublicClient,
  fallback,
  getAddress,
  http,
  isAddress,
  parseAbiItem,
  type PublicClient,
} from "viem";
import { bsc, bscTestnet } from "viem/chains";
import type { RegistrationRecord } from "@/lib/network-graph";

const REGISTRATION_EVENT = parseAbiItem(
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

    return logs.flatMap((log) => {
      const { member, sponsor, memberId } = log.args;
      if (!member || !sponsor || memberId == null || !log.transactionHash || log.blockNumber == null) {
        return [];
      }
      return [{
        member: getAddress(member),
        sponsor: getAddress(sponsor),
        memberId: Number(memberId),
        blockNumber: Number(log.blockNumber),
        transactionHash: log.transactionHash,
      }];
    });
  } catch (error) {
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
  ["nexaflow-registration-closed-chunk-v2", CHAIN_CACHE_KEY],
  { revalidate: false },
);

// Only the current bucket refreshes. A one-minute cache keeps the dashboard
// useful without turning every page view into an RPC log scan.
const cachedLiveChunk = unstable_cache(
  fetchRegistrationChunk,
  ["nexaflow-registration-live-chunk-v2", CHAIN_CACHE_KEY],
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

  const sorted = [...unique.values()].sort((a, b) => a.memberId - b.memberId);
  const withTimestamps = await attachTimestamps(sorted);
  return {
    records: withTimestamps,
    syncedBlock: Number(safeHead),
  };
}

export const getRegistrationSnapshot = unstable_cache(
  buildRegistrationSnapshot,
  ["nexaflow-registration-snapshot-v2", ...SNAPSHOT_CACHE_SCOPE],
  { revalidate: 60 },
);
