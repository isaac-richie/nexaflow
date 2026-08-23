"use client";

import { useEffect, useRef } from "react";

const PARTICLE_COUNT = 28;
const PARTICLE_COUNT_MOBILE = 14;

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  alpha: number;
  pulse: number;
  pulseSpeed: number;
}

export function DashboardBg() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const particles = useRef<Particle[]>([]);
  const raf = useRef(0);
  const mouse = useRef({ x: -1, y: -1 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

    let w = 0;
    let h = 0;

    function resize() {
      const dpr = Math.min(window.devicePixelRatio, 2);
      w = canvas!.clientWidth;
      h = canvas!.clientHeight;
      canvas!.width = w * dpr;
      canvas!.height = h * dpr;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function init() {
      resize();
      const count = w < 640 ? PARTICLE_COUNT_MOBILE : PARTICLE_COUNT;
      particles.current = Array.from({ length: count }, () => ({
        x: Math.random() * w,
        y: Math.random() * h,
        vx: (Math.random() - 0.5) * 0.3,
        vy: (Math.random() - 0.5) * 0.3 - 0.15,
        r: Math.random() * 1.8 + 0.6,
        alpha: Math.random() * 0.4 + 0.1,
        pulse: Math.random() * Math.PI * 2,
        pulseSpeed: Math.random() * 0.02 + 0.008,
      }));
    }

    function draw() {
      ctx!.clearRect(0, 0, w, h);
      const mx = mouse.current.x;
      const my = mouse.current.y;

      for (const p of particles.current) {
        p.x += p.vx;
        p.y += p.vy;
        p.pulse += p.pulseSpeed;

        if (p.x < -10) p.x = w + 10;
        if (p.x > w + 10) p.x = -10;
        if (p.y < -10) p.y = h + 10;
        if (p.y > h + 10) p.y = -10;

        const pAlpha = p.alpha * (0.6 + 0.4 * Math.sin(p.pulse));

        if (mx >= 0 && my >= 0) {
          const dx = p.x - mx;
          const dy = p.y - my;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < 160) {
            const force = (1 - dist / 160) * 0.4;
            p.vx += (dx / dist) * force;
            p.vy += (dy / dist) * force;
          }
        }

        p.vx *= 0.995;
        p.vy *= 0.995;

        ctx!.beginPath();
        ctx!.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx!.fillStyle = `hsla(45, 89%, 49%, ${pAlpha})`;
        ctx!.fill();

        if (p.r > 1) {
          ctx!.beginPath();
          ctx!.arc(p.x, p.y, p.r * 3, 0, Math.PI * 2);
          ctx!.fillStyle = `hsla(45, 89%, 49%, ${pAlpha * 0.15})`;
          ctx!.fill();
        }
      }

      const maxDist = 120;
      ctx!.lineWidth = 0.5;
      for (let i = 0; i < particles.current.length; i++) {
        for (let j = i + 1; j < particles.current.length; j++) {
          const a = particles.current[i];
          const b = particles.current[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < maxDist) {
            const opacity = (1 - dist / maxDist) * 0.12;
            ctx!.beginPath();
            ctx!.moveTo(a.x, a.y);
            ctx!.lineTo(b.x, b.y);
            ctx!.strokeStyle = `hsla(45, 89%, 49%, ${opacity})`;
            ctx!.stroke();
          }
        }
      }

      raf.current = requestAnimationFrame(draw);
    }

    function onMove(e: MouseEvent) {
      const rect = canvas!.getBoundingClientRect();
      mouse.current = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    }
    function onLeave() {
      mouse.current = { x: -1, y: -1 };
    }

    init();
    raf.current = requestAnimationFrame(draw);
    window.addEventListener("resize", resize);
    canvas.addEventListener("mousemove", onMove);
    canvas.addEventListener("mouseleave", onLeave);

    return () => {
      cancelAnimationFrame(raf.current);
      window.removeEventListener("resize", resize);
      canvas.removeEventListener("mousemove", onMove);
      canvas.removeEventListener("mouseleave", onLeave);
    };
  }, []);

  return (
    <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
      {/* Gradient orbs */}
      <div className="orb orb-gold" />
      <div className="orb orb-blue" />
      <div className="orb orb-accent" />

      {/* Interactive particle canvas */}
      <canvas
        ref={canvasRef}
        className="pointer-events-auto absolute inset-0 h-full w-full"
        style={{ opacity: 0.7 }}
      />

      {/* Noise texture */}
      <div className="noise pointer-events-none" />
    </div>
  );
}
