"use client";

import { useId, useMemo } from "react";

/**
 * The board, drawn as it actually behaves.
 *
 * A member's board is the `depth` levels beneath them. Every position on it
 * pays them one node reward, so the honest way to draw it is value travelling
 * *up* every edge toward the owner — not a static org chart. Each edge carries
 * a pulse whose delay is proportional to its depth, so lower positions take
 * longer to arrive, which is what the eye expects from a network.
 *
 * Pure SVG + CSS. No layout thrash, no canvas, and it degrades to a clean
 * static diagram under `prefers-reduced-motion`.
 */

type Props = {
  /** 2 → a 6-position board (stage 1). 3 → 14 positions (stages 2-6). */
  depth?: 2 | 3;
  /** Dollar figure each position pays the owner. */
  nodeReward?: number;
  className?: string;
};

type Node = { id: string; x: number; y: number; level: number };
type Edge = { from: Node; to: Node; level: number };

const W = 860;

export function BoardDiagram({ depth = 3, nodeReward = 10, className }: Props) {
  const H = depth === 3 ? 440 : 320;

  // SVG defs live in a global id namespace. The page renders more than one
  // board (responsive variants, plus the stage 1 example), and a duplicate id
  // makes every `url(#...)` resolve to the FIRST match in document order. When
  // that first match sits inside a `display:none` responsive wrapper, the
  // referenced paint silently renders nothing, so the connecting lines vanish
  // while literal-coloured strokes still draw. Scope every id per instance.
  const uid = useId().replace(/:/g, "");
  const ids = {
    edge: `edge-${uid}`,
    owner: `owner-${uid}`,
    soft: `soft-${uid}`,
  };

  const { nodes, edges } = useMemo(() => {
    const levels: Node[][] = [];
    const rowGap = depth === 3 ? 120 : 130;

    // Lay out the deepest row evenly, then place every parent at the midpoint
    // of its two children. Spreading each level independently across the full
    // width would fling level 1 to the canvas edges and the tree would read as
    // a fan rather than a hierarchy.
    const leafCount = 2 ** depth;
    const span = W - 120;
    const leaves: Node[] = Array.from({ length: leafCount }, (_, i) => ({
      id: `${depth}-${i}`,
      x: 60 + (span / (leafCount - 1)) * i,
      y: 40 + depth * rowGap,
      level: depth,
    }));
    levels[depth] = leaves;

    for (let level = depth - 1; level >= 0; level--) {
      levels[level] = Array.from({ length: 2 ** level }, (_, i) => ({
        id: `${level}-${i}`,
        x: (levels[level + 1][i * 2].x + levels[level + 1][i * 2 + 1].x) / 2,
        y: 40 + level * rowGap,
        level,
      }));
    }

    const e: Edge[] = [];
    for (let level = 1; level <= depth; level++) {
      levels[level].forEach((node, i) => {
        e.push({ from: node, to: levels[level - 1][Math.floor(i / 2)], level });
      });
    }

    return { nodes: levels.flat(), edges: e };
  }, [depth]);

  const positions = 2 ** (depth + 1) - 2;
  const total = positions * nodeReward;

  return (
    <div className={className}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="w-full"
        role="img"
        aria-label={`A ${positions}-position board. Every position pays the owner $${nodeReward}, totalling $${total} when full.`}
      >
        <defs>
          <linearGradient id={ids.edge} x1="0" y1="1" x2="0" y2="0">
            <stop offset="0%" stopColor="hsl(var(--gold))" stopOpacity="0.35" />
            <stop offset="100%" stopColor="hsl(var(--gold-hi))" stopOpacity="0.85" />
          </linearGradient>
          <linearGradient id={ids.owner} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="hsl(var(--gold-hi))" />
            <stop offset="100%" stopColor="hsl(var(--gold))" />
          </linearGradient>
          <filter id={ids.soft} x="-60%" y="-60%" width="220%" height="220%">
            <feGaussianBlur stdDeviation="10" result="b" />
            <feMerge>
              <feMergeNode in="b" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* Edges, drawn first so nodes sit above them. */}
        <g strokeLinecap="round" fill="none">
          {edges.map((edge, i) => (
            <g key={`e-${i}`}>
              <path
                d={curve(edge)}
                stroke={`url(#${ids.edge})`}
                strokeWidth={1.75}
              />
              {/* The pulse: value arriving at the owner. */}
              <path
                d={curve(edge)}
                stroke="hsl(var(--gold-hi))"
                strokeWidth={2.5}
                strokeDasharray="10 200"
                className="animate-flowUp motion-reduce:hidden"
                style={{ animationDelay: `${edge.level * 0.28 + (i % 4) * 0.12}s` }}
              />
            </g>
          ))}
        </g>

        {/* Positions */}
        {nodes.map((node) =>
          node.level === 0 ? (
            <g key={node.id} filter={`url(#${ids.soft})`}>
              <circle cx={node.x} cy={node.y} r={26} fill={`url(#${ids.owner})`} />
              <text
                x={node.x}
                y={node.y + 4}
                textAnchor="middle"
                className="fill-bg font-display text-[13px] font-bold"
              >
                YOU
              </text>
            </g>
          ) : (
            <g key={node.id} className="animate-float motion-reduce:animate-none"
               style={{ animationDelay: `${node.level * 0.5 + node.x * 0.002}s` }}>
              <circle
                cx={node.x}
                cy={node.y}
                r={15}
                fill="hsl(var(--surface-2))"
                stroke="hsl(var(--gold) / 0.3)"
                strokeWidth={1}
              />
              <text
                x={node.x}
                y={node.y + 4}
                textAnchor="middle"
                className="fill-muted font-mono text-[10px]"
              >
                ${nodeReward}
              </text>
            </g>
          )
        )}
      </svg>

      <div className="mt-6 flex flex-wrap items-center justify-center gap-x-8 gap-y-3 text-sm">
        <Legend swatch="bg-gradient-to-r from-goldHi to-gold" label="You, the board owner" />
        <Legend swatch="bg-surface-2 ring-1 ring-gold/30" label={`${positions} positions, $${nodeReward} each`} />
        <span className="figure text-ink">
          Full board ={" "}
          <span className="gold-text font-semibold">${total.toLocaleString()}</span>
        </span>
      </div>
    </div>
  );
}

function Legend({ swatch, label }: { swatch: string; label: string }) {
  return (
    <span className="flex items-center gap-2 text-muted">
      <span className={`h-3 w-3 shrink-0 rounded-full ${swatch}`} />
      {label}
    </span>
  );
}

/** A gentle S-curve reads as a connection; a straight line reads as a chart. */
function curve({ from, to }: Edge): string {
  const midY = (from.y + to.y) / 2;
  return `M ${from.x} ${from.y} C ${from.x} ${midY}, ${to.x} ${midY}, ${to.x} ${to.y}`;
}
