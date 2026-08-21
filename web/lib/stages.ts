/**
 * The six stages, mirroring `configureStages` in BinaryMembershipV1.sol.
 *
 * These are display values. The contract is the source of truth at runtime —
 * `getStageConfig(stageId)` returns the live figures, and admin can retune fees
 * and node rewards after deployment. Anything user-facing that drives a
 * transaction must read the chain, not this file.
 *
 * Stage indices are 0-based in the contract and presented as 1-based to users.
 * `label` is what a member sees; `id` is what you pass to the contract.
 */

export type Stage = {
  id: number;
  label: string;
  /** Entry fee in whole dollars. */
  fee: number;
  /** Paid to each upline whose board the placement lands on. */
  nodeReward: number;
  /** Positions on a board: 6 at stage 0, 14 above it. */
  slots: number;
  /** Levels beneath a member that make up their board. */
  depth: number;
  /** What a board owner collects from a full board: slots x nodeReward. */
  boardYield: number;
  /** Rollovers needed before an award unlocks. 0 = no award at this stage. */
  rolloversForAward: number;
};

export const STAGES: Stage[] = [
  { id: 0, label: "Stage 1", fee: 20, nodeReward: 5, slots: 6, depth: 2, boardYield: 30, rolloversForAward: 0 },
  { id: 1, label: "Stage 2", fee: 60, nodeReward: 10, slots: 14, depth: 3, boardYield: 140, rolloversForAward: 10 },
  { id: 2, label: "Stage 3", fee: 180, nodeReward: 25, slots: 14, depth: 3, boardYield: 350, rolloversForAward: 10 },
  { id: 3, label: "Stage 4", fee: 540, nodeReward: 80, slots: 14, depth: 3, boardYield: 1_120, rolloversForAward: 10 },
  { id: 4, label: "Stage 5", fee: 1_620, nodeReward: 250, slots: 14, depth: 3, boardYield: 3_500, rolloversForAward: 10 },
  { id: 5, label: "Stage 6", fee: 4_860, nodeReward: 800, slots: 14, depth: 3, boardYield: 11_200, rolloversForAward: 8 },
];

/** Multiple of the entry fee returned by one completed board. */
export function boardMultiple(stage: Stage): number {
  return stage.boardYield / stage.fee;
}

export const usd = (n: number) =>
  n >= 1000 ? `$${n.toLocaleString("en-US")}` : `$${n}`;
