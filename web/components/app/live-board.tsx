"use client";

import { useId, useMemo } from "react";
import type { StageMembership } from "@/hooks/use-membership";
import type { StagePreset } from "@/lib/contracts/config";
import { formatToken } from "@/lib/format";
import { PAYMENT_TOKEN_SYMBOL } from "@/lib/contracts/config";

type Props = {
  preset: StagePreset;
  membership?: StageMembership;
};

type Node = { id: string; x: number; y: number; level: number; index: number };
type Edge = { from: Node; to: Node };

const W = 480;
const H_D2 = 240;
const H_D3 = 320;

export function LiveBoard({ preset, membership }: Props) {
  const depth = preset.slots === 6 ? 2 : 3;
  const H = depth === 2 ? H_D2 : H_D3;
  const filled = Number(membership?.slotsFilledBelow ?? 0);
  const uid = useId().replace(/:/g, "");

  const { nodes, edges } = useMemo(() => {
    const levels: Node[][] = [];
    const rowGap = depth === 2 ? 90 : 80;

    const leafCount = 2 ** depth;
    const span = W - 100;
    const leaves: Node[] = Array.from({ length: leafCount }, (_, i) => ({
      id: `${depth}-${i}`,
      x: 50 + (span / (leafCount - 1)) * i,
      y: 40 + depth * rowGap,
      level: depth,
      index: i + (2 ** depth - 2),
    }));
    levels[depth] = leaves;

    for (let level = depth - 1; level >= 0; level--) {
      levels[level] = Array.from({ length: 2 ** level }, (_, i) => ({
        id: `${level}-${i}`,
        x: (levels[level + 1][i * 2].x + levels[level + 1][i * 2 + 1].x) / 2,
        y: 40 + level * rowGap,
        level,
        index: level === 0 ? -1 : i + (2 ** level - 2),
      }));
    }

    const e: Edge[] = [];
    for (let level = 1; level <= depth; level++) {
      levels[level].forEach((node, i) => {
        e.push({ from: node, to: levels[level - 1][Math.floor(i / 2)] });
      });
    }

    return { nodes: levels.flat(), edges: e };
  }, [depth]);

  const isFilled = (node: Node) => {
    if (node.level === 0) return true;
    return node.index < filled;
  };

  return (
    <div className="relative">
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full max-w-md mx-auto" role="img"
        aria-label={`Board with ${filled} of ${preset.slots} positions filled`}>
        <defs>
          <linearGradient id={`eg-${uid}`} x1="0" y1="1" x2="0" y2="0">
            <stop offset="0%" stopColor="hsl(var(--gold))" stopOpacity="0.25" />
            <stop offset="100%" stopColor="hsl(var(--gold-hi))" stopOpacity="0.6" />
          </linearGradient>
          <linearGradient id={`eo-${uid}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="hsl(var(--gold-hi))" />
            <stop offset="100%" stopColor="hsl(var(--gold))" />
          </linearGradient>
          <filter id={`gl-${uid}`} x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="6" result="b" />
            <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
          <radialGradient id={`fg-${uid}`} cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="hsl(var(--up))" stopOpacity="0.35" />
            <stop offset="100%" stopColor="hsl(var(--up))" stopOpacity="0" />
          </radialGradient>
        </defs>

        {/* Edges */}
        <g strokeLinecap="round" fill="none">
          {edges.map((edge, i) => {
            const active = isFilled(edge.from);
            const midY = (edge.from.y + edge.to.y) / 2;
            const d = `M ${edge.from.x} ${edge.from.y} C ${edge.from.x} ${midY}, ${edge.to.x} ${midY}, ${edge.to.x} ${edge.to.y}`;
            return (
              <g key={i}>
                <path d={d}
                  stroke={active ? `url(#eg-${uid})` : "hsl(var(--line))"}
                  strokeWidth={active ? 1.5 : 1}
                  strokeDasharray={active ? undefined : "4 4"}
                  opacity={active ? 1 : 0.4}
                />
                {active && (
                  <path d={d}
                    stroke="hsl(var(--gold-hi))"
                    strokeWidth={2}
                    strokeDasharray="8 180"
                    className="animate-flowUp motion-reduce:hidden"
                    style={{ animationDelay: `${i * 0.15}s` }}
                  />
                )}
              </g>
            );
          })}
        </g>

        {/* Nodes */}
        {nodes.map((node) => {
          if (node.level === 0) {
            return (
              <g key={node.id} filter={`url(#gl-${uid})`}>
                <circle cx={node.x} cy={node.y} r={22}
                  fill={`url(#eo-${uid})`} />
                <text x={node.x} y={node.y + 4} textAnchor="middle"
                  className="fill-bg font-display text-[11px] font-bold">
                  YOU
                </text>
              </g>
            );
          }

          const active = isFilled(node);
          return (
            <g key={node.id}>
              {active && (
                <circle cx={node.x} cy={node.y} r={20}
                  fill={`url(#fg-${uid})`}
                  className="animate-pulse" />
              )}
              <circle cx={node.x} cy={node.y} r={13}
                fill={active ? "hsl(var(--up) / 0.15)" : "hsl(var(--surface-2))"}
                stroke={active ? "hsl(var(--up) / 0.6)" : "hsl(var(--line))"}
                strokeWidth={active ? 1.5 : 1}
                strokeDasharray={active ? undefined : "3 3"}
              />
              {active ? (
                <text x={node.x} y={node.y + 4} textAnchor="middle"
                  className="fill-up font-mono text-[9px] font-medium">
                  ${preset.nodeReward}
                </text>
              ) : (
                <text x={node.x} y={node.y + 3.5} textAnchor="middle"
                  className="fill-faint text-[9px]">
                  ·
                </text>
              )}
            </g>
          );
        })}
      </svg>

      {/* Summary below tree */}
      <div className="mt-3 flex flex-wrap items-center justify-center gap-x-5 gap-y-1.5 text-[11px] text-muted sm:mt-4 sm:gap-x-6 sm:text-xs">
        <span className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 rounded-full bg-up sm:h-2 sm:w-2" />
          {filled} filled
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 rounded-full border border-dashed border-line bg-surface-2 sm:h-2 sm:w-2" />
          {preset.slots - filled} open
        </span>
        <span className="figure text-ink">
          {formatToken(membership?.stageEarnings)}{" "}
          <span className="text-faint">{PAYMENT_TOKEN_SYMBOL}</span>
        </span>
      </div>
    </div>
  );
}
