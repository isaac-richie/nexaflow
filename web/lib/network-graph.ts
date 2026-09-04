export type RegistrationRecord = {
  member: `0x${string}`;
  sponsor: `0x${string}`;
  memberId: number;
  blockNumber: number;
  transactionHash: `0x${string}`;
  /** Unix seconds. Optional so historical callers and tests still
   *  compile; the server index attaches it whenever available. */
  timestamp?: number;
};

export type NetworkMember = RegistrationRecord & {
  directCount: number;
  teamCount: number;
};

export type NetworkSummary = {
  root: `0x${string}`;
  personalReferrals: number;
  totalTeam: number;
  generations: number;
  protocolMembers: number;
  generationCounts: Array<{ generation: number; count: number }>;
  selectedGeneration: number;
  members: NetworkMember[];
  offset: number;
  limit: number;
  hasMore: boolean;
  /** Rolling 30-day new-registration series for this root's subtree.
   *  One entry per day, oldest first, zero-filled. Empty when the
   *  underlying records carry no timestamps. */
  dailyRegistrations: Array<{ day: string; count: number }>;
};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

function key(address: string): string {
  return address.toLowerCase();
}

/**
 * Build one member's referral-network view from immutable registration events.
 *
 * A referral network is deliberately different from a stage board. Sponsor
 * edges never change, while board parent/child edges can differ by stage and
 * cycle. Keeping this calculation pure makes that distinction testable.
 */

/** Rolling 30-day new-registration histogram over a set of records, ending
 *  at the most-recent timestamp in the set (or "now" if none). Empty when no
 *  record carries a timestamp — the caller shows the number without a chart. */
function dailySeries(records: RegistrationRecord[], days = 30): Array<{ day: string; count: number }> {
  const timestamped = records.filter((r): r is RegistrationRecord & { timestamp: number } => typeof r.timestamp === "number");
  if (timestamped.length === 0) return [];

  const msPerDay = 86_400_000;
  let anchorSec = timestamped[0].timestamp;
  for (let index = 1; index < timestamped.length; index += 1) {
    if (timestamped[index].timestamp > anchorSec) {
      anchorSec = timestamped[index].timestamp;
    }
  }
  const anchor = new Date(anchorSec * 1000);
  // Anchor is inclusive; use midnight-UTC of that day as the last bucket.
  const anchorDay = Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), anchor.getUTCDate());
  const now = Date.now();
  const endDay = Math.min(anchorDay, Date.UTC(new Date(now).getUTCFullYear(), new Date(now).getUTCMonth(), new Date(now).getUTCDate()));

  const buckets = new Map<string, number>();
  for (let i = days - 1; i >= 0; i -= 1) {
    const dayMs = endDay - i * msPerDay;
    buckets.set(new Date(dayMs).toISOString().slice(0, 10), 0);
  }
  for (const record of timestamped) {
    const day = new Date(record.timestamp * 1000).toISOString().slice(0, 10);
    if (buckets.has(day)) buckets.set(day, (buckets.get(day) ?? 0) + 1);
  }
  return [...buckets.entries()].map(([day, count]) => ({ day, count }));
}

export function summarizeNetwork(
  source: RegistrationRecord[],
  root: `0x${string}`,
  selectedGeneration = 1,
  offset = 0,
  limit = 20,
): NetworkSummary {
  const records = [...source].sort((a, b) => a.memberId - b.memberId);
  const byMember = new Map<string, RegistrationRecord>();
  const children = new Map<string, string[]>();

  for (const record of records) {
    const memberKey = key(record.member);
    const sponsorKey = key(record.sponsor);
    byMember.set(memberKey, record);

    if (sponsorKey !== ZERO_ADDRESS && sponsorKey !== memberKey) {
      const list = children.get(sponsorKey) ?? [];
      list.push(memberKey);
      children.set(sponsorKey, list);
    }
  }

  // Every member has one immutable sponsor and sponsors must already exist.
  // Walking newest-to-oldest therefore produces every subtree size in O(n).
  const teamCounts = new Map<string, number>();
  for (let index = records.length - 1; index >= 0; index -= 1) {
    const record = records[index];
    const memberKey = key(record.member);
    const sponsorKey = key(record.sponsor);
    if (sponsorKey === ZERO_ADDRESS || sponsorKey === memberKey) continue;
    teamCounts.set(
      sponsorKey,
      (teamCounts.get(sponsorKey) ?? 0) + 1 + (teamCounts.get(memberKey) ?? 0),
    );
  }

  const rootKey = key(root);
  const visited = new Set<string>([rootKey]);
  let frontier = [...(children.get(rootKey) ?? [])];
  const generations: string[][] = [];

  while (frontier.length > 0) {
    const current: string[] = [];
    const next: string[] = [];

    for (const memberKey of frontier) {
      if (visited.has(memberKey)) continue;
      visited.add(memberKey);
      current.push(memberKey);
      next.push(...(children.get(memberKey) ?? []));
    }

    if (current.length === 0) break;
    generations.push(current);
    frontier = next;
  }

  const safeGeneration = Math.max(1, Math.trunc(selectedGeneration));
  const safeOffset = Math.max(0, Math.trunc(offset));
  const safeLimit = Math.min(50, Math.max(1, Math.trunc(limit)));
  const selected = generations[safeGeneration - 1] ?? [];
  const pageKeys = selected.slice(safeOffset, safeOffset + safeLimit);

  const members = pageKeys.flatMap((memberKey) => {
    const record = byMember.get(memberKey);
    if (!record) return [];
    return [{
      ...record,
      directCount: children.get(memberKey)?.length ?? 0,
      teamCount: teamCounts.get(memberKey) ?? 0,
    }];
  });

  // Only include the root's subtree (personal + descendants) in the
  // series — the top-line chart is about this network's growth, not the
  // whole protocol's.
  const subtreeRecords = records.filter((record) => {
    const memberKey = key(record.member);
    return memberKey !== rootKey && visited.has(memberKey);
  });

  return {
    root,
    personalReferrals: generations[0]?.length ?? 0,
    totalTeam: generations.reduce((sum, generation) => sum + generation.length, 0),
    generations: generations.length,
    protocolMembers: records.length,
    generationCounts: generations.map((generation, index) => ({
      generation: index + 1,
      count: generation.length,
    })),
    selectedGeneration: safeGeneration,
    members,
    offset: safeOffset,
    limit: safeLimit,
    hasMore: safeOffset + safeLimit < selected.length,
    dailyRegistrations: dailySeries(subtreeRecords),
  };
}
