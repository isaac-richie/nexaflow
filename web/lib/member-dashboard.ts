import type { MemberSummary, StageConfig, StageMembership } from "@/hooks/use-membership";

export type StageView = {
  id: number;
  state: "active" | "available" | "locked" | "unavailable";
  membership?: StageMembership;
  config?: StageConfig;
  currentBoard?: bigint;
  remaining?: bigint;
  nextMilestone?: bigint;
  milestoneReached: boolean;
};

/** Missing multicall results are unknown, never zero or a locked membership. */
export function buildMemberDashboard(
  member: MemberSummary,
  memberships?: Array<StageMembership | undefined>,
  configs?: Array<StageConfig | undefined>,
) {
  const complete = memberships?.length === 6 && memberships.every(Boolean);
  const stages: StageView[] = Array.from({ length: 6 }, (_, id) => {
    const membership = memberships?.[id];
    const config = configs?.[id];
    const known = Boolean(membership && config && config.treeSlots > 0n &&
      (membership.enrolled || id === 0 || memberships?.[id - 1]));
    const previous = id === 0 || memberships?.[id - 1]?.enrolled === true;
    const state = !known ? "unavailable" : membership!.enrolled ? "active" : previous ? "available" : "locked";
    const nextMilestone = membership && config && config.rolloversForAward > 0n
      ? membership.lastAwardedRollover + config.rolloversForAward : undefined;
    return {
      id, state, membership, config,
      currentBoard: membership?.enrolled ? membership.rolloverCount + 1n : undefined,
      remaining: known && membership!.enrolled
        ? (config!.treeSlots > membership!.slotsFilledBelow ? config!.treeSlots - membership!.slotsFilledBelow : 0n) : undefined,
      nextMilestone,
      milestoneReached: nextMilestone !== undefined && Boolean(membership?.enrolled) && membership!.rolloverCount >= nextMilestone,
    };
  });
  const highestKnown = memberships?.reduce((highest, m, i) => m?.enrolled ? i : highest, -1) ?? -1;
  return {
    earned: member.totalEarned,
    stages,
    currentStage: complete ? highestKnown : undefined,
    activeStages: complete ? memberships.filter(m => m!.enrolled).length : undefined,
    completedBoards: complete ? memberships.reduce((sum, m) => sum + (m!.enrolled ? m!.rolloverCount : 0n), 0n) : undefined,
    totalAwarded: complete ? memberships.reduce((sum, m) => sum + m!.totalAwarded, 0n) : undefined,
    partial: stages.some(stage => stage.state === "unavailable"),
  };
}

/** V5 BSC USDT has 18 decimals. Round display only, using integers throughout. */
export function memberAmount(value?: bigint, decimals = 18, precision = 2): string {
  if (value === undefined) return "—";
  const digits = Math.min(precision, decimals);
  const negative = value < 0n;
  const absolute = negative ? -value : value;
  const divisor = 10n ** BigInt(decimals - digits);
  const rounded = (absolute + divisor / 2n) / divisor;
  const scale = 10n ** BigInt(digits);
  const whole = (rounded / scale).toLocaleString("en-US");
  const fraction = digits ? `.${(rounded % scale).toString().padStart(digits, "0")}` : "";
  return `${negative ? "-" : ""}${whole}${fraction}`;
}

export function memberReadState(input: {
  connected: boolean; deployed: boolean; wrongChain: boolean; loading: boolean;
  member?: MemberSummary;
}) {
  if (!input.deployed) return "unconfigured";
  if (!input.connected) return "disconnected";
  if (input.wrongChain) return "wrong-chain";
  if (input.loading && !input.member) return "loading";
  if (!input.member) return "unavailable";
  return input.member.active ? "ready" : "unregistered";
}
