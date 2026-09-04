import assert from "node:assert/strict";
import { test } from "node:test";
import {
  summarizeNetwork,
  type RegistrationRecord,
} from "../lib/network-graph.ts";

const ZERO = "0x0000000000000000000000000000000000000000" as const;

function address(id: number): `0x${string}` {
  return `0x${id.toString(16).padStart(40, "0")}`;
}

function record(memberId: number, sponsorId: number): RegistrationRecord {
  return {
    member: address(memberId),
    sponsor: sponsorId === 0 ? ZERO : address(sponsorId),
    memberId,
    blockNumber: 118_526_708 + memberId,
    transactionHash: `0x${memberId.toString(16).padStart(64, "0")}`,
  };
}

test("counts direct referrals and every generation without mixing board placement", () => {
  const records = [
    record(1, 0),
    record(2, 1),
    record(3, 1),
    record(4, 2),
    record(5, 2),
    record(6, 3),
    record(7, 4),
  ];

  const levelOne = summarizeNetwork(records, address(1), 1, 0, 20);
  assert.equal(levelOne.personalReferrals, 2);
  assert.equal(levelOne.totalTeam, 6);
  assert.equal(levelOne.generations, 3);
  assert.deepEqual(levelOne.generationCounts, [
    { generation: 1, count: 2 },
    { generation: 2, count: 3 },
    { generation: 3, count: 1 },
  ]);
  assert.deepEqual(levelOne.members.map((member) => member.memberId), [2, 3]);
  assert.deepEqual(levelOne.members.map((member) => member.teamCount), [3, 1]);
});

test("supports branch drill-down and stable generation pagination", () => {
  const records = [record(1, 0)];
  for (let id = 2; id <= 56; id += 1) records.push(record(id, 1));

  const first = summarizeNetwork(records, address(1), 1, 0, 20);
  const second = summarizeNetwork(records, address(1), 1, 20, 20);
  const last = summarizeNetwork(records, address(1), 1, 40, 20);
  assert.equal(first.personalReferrals, 55);
  assert.equal(first.members.length, 20);
  assert.equal(first.hasMore, true);
  assert.equal(second.members[0].memberId, 22);
  assert.equal(last.members.length, 15);
  assert.equal(last.hasMore, false);

  const leaf = summarizeNetwork(records, address(2), 1, 0, 20);
  assert.equal(leaf.personalReferrals, 0);
  assert.equal(leaf.totalTeam, 0);
  assert.equal(leaf.generations, 0);
});

test("handles an aggressive 600-wallet, multi-generation tree", () => {
  const records = [record(1, 0)];
  for (let id = 2; id <= 600; id += 1) {
    const sponsor = Math.floor((id - 2) / 3) + 1;
    records.push(record(id, sponsor));
  }

  const root = summarizeNetwork(records, address(1), 1, 0, 50);
  assert.equal(root.personalReferrals, 3);
  assert.equal(root.totalTeam, 599);
  assert.equal(root.protocolMembers, 600);
  assert.ok(root.generations >= 5);
  assert.equal(
    root.generationCounts.reduce((sum, item) => sum + item.count, 0),
    599,
  );

  const branch = summarizeNetwork(records, address(2), 2, 0, 50);
  assert.equal(branch.personalReferrals, 3);
  assert.ok(branch.totalTeam > branch.personalReferrals);
  assert.ok(branch.members.every((member) => member.memberId > 2));
});

test("does not recurse or overflow on a 10,000-wallet referral chain", () => {
  const records = [record(1, 0)];
  for (let id = 2; id <= 10_000; id += 1) records.push(record(id, id - 1));

  const root = summarizeNetwork(records, address(1), 9_999, 0, 20);
  assert.equal(root.totalTeam, 9_999);
  assert.equal(root.generations, 9_999);
  assert.equal(root.members.length, 1);
  assert.equal(root.members[0].memberId, 10_000);
});

test("returns a safe empty network for an unrelated wallet", () => {
  const records = [record(1, 0), record(2, 1)];
  const result = summarizeNetwork(records, address(999), 1, 0, 20);
  assert.equal(result.personalReferrals, 0);
  assert.equal(result.totalTeam, 0);
  assert.equal(result.generations, 0);
  assert.deepEqual(result.members, []);
});

test("builds a zero-filled 30-day registration series for the selected subtree", () => {
  const day = Math.floor(Date.UTC(2026, 7, 1) / 1000);
  const records = [
    { ...record(1, 0), timestamp: day },
    { ...record(2, 1), timestamp: day },
    { ...record(3, 2), timestamp: day + 86_400 },
  ];

  const result = summarizeNetwork(records, address(1));
  assert.equal(result.dailyRegistrations.length, 30);
  assert.equal(
    result.dailyRegistrations.reduce((sum, item) => sum + item.count, 0),
    2,
  );
  assert.equal(result.dailyRegistrations.at(-2)?.count, 1);
  assert.equal(result.dailyRegistrations.at(-1)?.count, 1);
});
