"use client";

export function BackgroundEffects() {
  return (
    <div className="bg-fx pointer-events-none fixed inset-0 -z-10 overflow-hidden" aria-hidden>
      {/* Primary gold orb — slow drift */}
      <div className="orb orb-gold" />
      {/* Secondary cool orb — counterbalance */}
      <div className="orb orb-blue" />
      {/* Tertiary accent — smaller, faster */}
      <div className="orb orb-accent" />
      {/* Noise overlay for texture */}
      <div className="noise" />
      {/* Floating particles */}
      <div className="particles">
        {Array.from({ length: 32 }, (_, i) => (
          <span key={i} className="dot" style={dotStyle(i)} />
        ))}
      </div>
    </div>
  );
}

function dotStyle(i: number): React.CSSProperties {
  const col = i % 8;
  const row = Math.floor(i / 8);
  return {
    "--x": `${5 + col * 12}%`,
    "--y": `${5 + row * 24}%`,
    "--d": `${3.5 + (i * 1.3) % 5}s`,
    "--del": `${(i * 0.6) % 7}s`,
    "--s": `${1.5 + (i % 4) * 0.8}px`,
  } as React.CSSProperties;
}
