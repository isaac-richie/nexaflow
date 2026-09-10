import "server-only";
import { randomUUID } from "node:crypto";
import type { Intent, KeeperStore } from "./queue-keeper-core";

// One atomic record contains both the pending signed transaction and rolling
// gas reservations. Never expire it or fall back to in-memory persistence.
export const RESERVE_SCRIPT = `
if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
local raw = redis.call('GET', KEYS[2]); if not raw then return 0 end
local state = cjson.decode(raw)
if state.pending then return 0 end
local now = tonumber(redis.call('TIME')[1]) * 1000
local kept = {}; local total = 0
for _,cost in ipairs(state.costs) do
  if cost.at > now - 86400000 then table.insert(kept, cost); total = total + cost.amount end
end
local amount = tonumber(ARGV[3]); local budget = tonumber(ARGV[4])
if amount <= 0 or amount > budget or total + amount > budget then return 0 end
table.insert(kept, {at=now, amount=amount})
state.costs = kept; state.pending = cjson.decode(ARGV[2]); state.cursor = (state.pending.stage + 1) % 6
redis.call('SET', KEYS[2], cjson.encode(state))
return 1`;
export const COMPLETE_SCRIPT = `
if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
local raw = redis.call('GET', KEYS[2]); if not raw then return 0 end
local state = cjson.decode(raw)
if not state.pending or state.pending.hash ~= ARGV[2] then return 0 end
state.pending = nil
redis.call('SET', KEYS[2], cjson.encode(state))
return 1`;
const RELEASE_SCRIPT = `if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end return 0`;

export function redisKeeperStore(url: string, token: string, scope: string): KeeperStore {
  if (!url.startsWith("https://") || !token) throw new Error("Keeper storage not configured");
  const owner = randomUUID();
  const lock = `${scope}:lock`, state = `${scope}:state`;
  async function command(args: (string | number)[]) {
    const response = await fetch(url, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(args), cache: "no-store", signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error("Keeper storage unavailable");
    const result = await response.json();
    if (result.error) throw new Error("Keeper storage command failed");
    return result.result;
  }
  let cursor = 0;
  return {
    acquire: async () => await command(["SET", lock, owner, "NX", "PX", 120000]) === "OK",
    release: async () => { await command(["EVAL", RELEASE_SCRIPT, 1, lock, owner]); },
    pending: async () => {
      const raw = await command(["GET", state]);
      if (!raw) throw new Error("Keeper state missing; initialize or restore storage before enabling");
      const value = JSON.parse(raw);
      if (!value.costs || typeof value.costs !== "object") throw new Error("Keeper state invalid");
      cursor = value.cursor ?? 0;
      return value.pending ?? null;
    },
    cursor: async () => cursor,
    reserve: async (intent, cost, budget) => {
      if (![cost, budget].every(Number.isSafeInteger) || cost <= 0 || budget <= 0) throw new Error("Invalid keeper budget");
      return await command(["EVAL", RESERVE_SCRIPT, 2, lock, state, owner, JSON.stringify(intent), cost, budget]) === 1;
    },
    complete: async hash => await command(["EVAL", COMPLETE_SCRIPT, 2, lock, state, owner, hash]) === 1,
  };
}
