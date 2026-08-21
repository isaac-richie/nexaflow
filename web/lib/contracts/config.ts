import { bsc, bscTestnet } from "wagmi/chains";

/**
 * Contract + chain configuration.
 *
 * V2 pays in Rawli Analytics (RWAAN) at
 * 0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a. The membership address remains
 * environment-driven until the replacement deployment is complete.
 *
 * Everything still reads from env rather than being hardcoded, so a redeploy or
 * a testnet build is a config change. The UI must never invent numbers when a
 * value is missing — an unset address produces an explicit "not configured"
 * panel, not a dashboard full of zeroes that look like real balances.
 *
 * Amounts must always be formatted from the token's own `decimals()`.
 */

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const;

/** Set NEXT_PUBLIC_CHAIN=bsc to point at mainnet. Defaults to testnet. */
export const ACTIVE_CHAIN =
  process.env.NEXT_PUBLIC_CHAIN === "bsc" ? bsc : bscTestnet;

export const MEMBERSHIP_ADDRESS = (process.env
  .NEXT_PUBLIC_MEMBERSHIP_ADDRESS ?? ZERO_ADDRESS) as `0x${string}`;

/** The ERC-20 members pay fees in. */
export const PAYMENT_TOKEN_ADDRESS = (process.env
  .NEXT_PUBLIC_PAYMENT_TOKEN_ADDRESS ?? ZERO_ADDRESS) as `0x${string}`;

/**
 * True once a real membership address is configured. Every data hook checks
 * this before enabling a query — an unconfigured build should show an explicit
 * "not deployed" state, never fabricated zeroes.
 */
export const IS_DEPLOYED = MEMBERSHIP_ADDRESS !== ZERO_ADDRESS;

/**
 * Stage presentation data.
 *
 * `stageId` is the on-chain index (0-5); `label` is what members are shown
 * (Stage 1-6). Getting this offset wrong is the easiest way to mislead someone
 * about what they are paying for, so the mapping lives in exactly one place.
 *
 * Fees and rewards here are for DISPLAY BEFORE CONNECTION only. Once a chain
 * is reachable the UI reads `getStageConfig` and shows that instead — the
 * contract is the source of truth, since admin can retune fees at runtime.
 */
export type StagePreset = {
  stageId: number;
  label: string;
  fee: number;
  nodeReward: number;
  slots: number;
  fullBoard: number;
  rolloversForAward: number;
};

export const STAGE_PRESETS: StagePreset[] = [
  { stageId: 0, label: "Stage 1", fee: 20, nodeReward: 5, slots: 6, fullBoard: 30, rolloversForAward: 0 },
  { stageId: 1, label: "Stage 2", fee: 60, nodeReward: 10, slots: 14, fullBoard: 140, rolloversForAward: 10 },
  { stageId: 2, label: "Stage 3", fee: 180, nodeReward: 25, slots: 14, fullBoard: 350, rolloversForAward: 10 },
  { stageId: 3, label: "Stage 4", fee: 540, nodeReward: 80, slots: 14, fullBoard: 1120, rolloversForAward: 10 },
  { stageId: 4, label: "Stage 5", fee: 1620, nodeReward: 250, slots: 14, fullBoard: 3500, rolloversForAward: 10 },
  { stageId: 5, label: "Stage 6", fee: 4860, nodeReward: 800, slots: 14, fullBoard: 11200, rolloversForAward: 8 },
];

export const MAX_STAGES = 6;

/** Display label for an on-chain stage index. */
export function stageLabel(stageId: number): string {
  return STAGE_PRESETS[stageId]?.label ?? `Stage ${stageId + 1}`;
}
