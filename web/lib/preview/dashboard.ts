/** Synthetic design fixtures. Never import into live contract hooks or indexers. */
export type PreviewBoard = {
  stage: number;
  fee: number;
  reward: number;
  slots: number;
  filled: number;
  completed: number;
  unlocked: boolean;
};

export const PREVIEW_BOARDS: readonly PreviewBoard[] = [
  { stage: 1, fee: 20, reward: 5, slots: 6, filled: 5, completed: 2, unlocked: true },
  { stage: 2, fee: 60, reward: 10, slots: 14, filled: 8, completed: 1, unlocked: true },
  { stage: 3, fee: 180, reward: 25, slots: 14, filled: 4, completed: 0, unlocked: true },
  { stage: 4, fee: 540, reward: 80, slots: 14, filled: 0, completed: 0, unlocked: false },
  { stage: 5, fee: 1620, reward: 250, slots: 14, filled: 0, completed: 0, unlocked: false },
  { stage: 6, fee: 4860, reward: 800, slots: 14, filled: 0, completed: 0, unlocked: false },
];

export function boardEarnings(board: PreviewBoard) {
  return (board.completed * board.slots + board.filled) * board.reward;
}

export function canUnlock(board: PreviewBoard) {
  return !board.unlocked && (board.stage === 1 || PREVIEW_BOARDS[board.stage - 2].unlocked);
}

export function boardReserve(board: PreviewBoard) {
  const reserveSlots = board.stage === 1 ? 4 : 8;
  const contributors = Math.max(0, board.filled - (board.slots - reserveSlots));
  return contributors * board.fee / reserveSlots;
}

export const PREVIEW_GENERATIONS = [6, 12, 24, 18] as const;
export const PREVIEW_CLAIMABLE = 10;
export const PREVIEW_EARNED = PREVIEW_BOARDS.reduce((sum, board) => sum + boardEarnings(board), 0);
export const PREVIEW_DELIVERED = PREVIEW_EARNED - PREVIEW_CLAIMABLE;
export const PREVIEW_RESERVED = PREVIEW_BOARDS.reduce((sum, board) => sum + boardReserve(board), 0);

export const previewMoney = (value: number) => new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 2, maximumFractionDigits: 2,
}).format(value);
