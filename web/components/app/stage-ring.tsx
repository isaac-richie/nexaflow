"use client";

type Props = {
  filled: number;
  total: number;
  size?: number;
  strokeWidth?: number;
  label: string;
};

export function StageRing({ filled, total, size = 52, strokeWidth = 3.5, label }: Props) {
  const r = (size - strokeWidth) / 2;
  const circ = 2 * Math.PI * r;
  const pct = total > 0 ? Math.min(1, filled / total) : 0;
  const offset = circ * (1 - pct);

  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}
        className="-rotate-90">
        {/* Track */}
        <circle
          cx={size / 2} cy={size / 2} r={r}
          fill="none"
          stroke="hsl(var(--surface-3))"
          strokeWidth={strokeWidth}
        />
        {/* Progress */}
        {pct > 0 && (
          <circle
            cx={size / 2} cy={size / 2} r={r}
            fill="none"
            stroke="url(#ring-grad)"
            strokeWidth={strokeWidth}
            strokeLinecap="round"
            strokeDasharray={circ}
            strokeDashoffset={offset}
            className="transition-[stroke-dashoffset] duration-700 ease-out"
          />
        )}
        <defs>
          <linearGradient id="ring-grad" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="hsl(var(--gold-hi))" />
            <stop offset="100%" stopColor="hsl(var(--gold))" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className="figure text-[10px] text-muted">{label}</span>
      </div>
    </div>
  );
}
