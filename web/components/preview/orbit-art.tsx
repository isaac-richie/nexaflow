"use client";

import dynamic from "next/dynamic";
import Image from "next/image";
import { Component, useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { mayAutoplay, mayRenderAnimation, type AnimationPreferences } from "@/lib/preview/animation-policy";
import s from "./landing-preview.module.css";

// Three and its renderer never enter the initial landing content bundle.
const OrbitScene = dynamic(() => import("./orbit-scene"), { ssr: false, loading: () => null });

class ArtBoundary extends Component<{ children: ReactNode; onFailure: () => void }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch() { this.props.onFailure(); }
  render() { return this.state.failed ? null : this.props.children; }
}

export function OrbitArt() {
  const container = useRef<HTMLDivElement>(null);
  const [preferences, setPreferences] = useState<AnimationPreferences | null>(null);
  const [inView, setInView] = useState(false);
  const [documentVisible, setDocumentVisible] = useState(true);
  const [requested, setRequested] = useState(false);
  const [started, setStarted] = useState(false);
  const [paused, setPaused] = useState(false);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const onReady = useCallback(() => setReady(true), []);
  const onFailure = useCallback(() => { setFailed(true); setReady(false); }, []);

  useEffect(() => {
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    const compact = matchMedia("(max-width: 767px)");
    const browser = navigator as Navigator & { deviceMemory?: number; connection?: { saveData?: boolean; addEventListener?: (type: string, listener: () => void) => void; removeEventListener?: (type: string, listener: () => void) => void } };
    function update() {
      setPreferences({ reducedMotion: reduced.matches, compact: compact.matches,
        saveData: browser.connection?.saveData ?? false,
        limitedDevice: (browser.deviceMemory !== undefined && browser.deviceMemory <= 4) || (browser.hardwareConcurrency > 0 && browser.hardwareConcurrency <= 4),
      });
    }
    function visibility() { setDocumentVisible(document.visibilityState === "visible"); }
    update(); visibility();
    reduced.addEventListener("change", update); compact.addEventListener("change", update);
    browser.connection?.addEventListener?.("change", update);
    document.addEventListener("visibilitychange", visibility);
    const observer = typeof IntersectionObserver !== "undefined" ? new IntersectionObserver(entries => setInView(entries[0].isIntersecting), { threshold: 0.08 }) : null;
    if (container.current) observer?.observe(container.current);
    if (!observer) setInView(true);
    return () => {
      reduced.removeEventListener("change", update); compact.removeEventListener("change", update);
      browser.connection?.removeEventListener?.("change", update);
      document.removeEventListener("visibilitychange", visibility); observer?.disconnect();
    };
  }, []);

  const enabled = Boolean(preferences && !preferences.reducedMotion && !failed && (requested || mayAutoplay(preferences)));
  useEffect(() => { if (enabled && inView && documentVisible) setStarted(true); }, [enabled, inView, documentVisible]);
  const mounted = enabled && started;
  const running = mayRenderAnimation({ enabled: mounted, paused, inView, documentVisible, reducedMotion: preferences?.reducedMotion ?? true });
  return <div ref={container} className={s.orbitArt}>
    <div className={s.artSurface} role="img" aria-label="Sculpted NexaFlow gold emblem with six orbital markers">
      <div className={`${s.staticMark} ${mounted && ready ? s.fallbackHidden : ""}`} aria-hidden="true"><Image src="/logo-mark.svg" alt="" width={290} height={290} priority/></div>
      {mounted && <div className={s.canvasLayer} aria-hidden="true"><ArtBoundary onFailure={onFailure}><OrbitScene running={running} compact={preferences?.compact ?? true} onReady={onReady} onFailure={onFailure}/></ArtBoundary></div>}
    </div>
    <div className={s.artControls}>
      {failed ? <span>Static artwork · 3D unavailable</span> : preferences?.reducedMotion ? <span>Static artwork · reduced motion</span> : mounted ? <button type="button" aria-pressed={paused} onClick={() => setPaused(value => !value)}>{paused ? "▶ Resume animation" : "Ⅱ Pause animation"}</button> : <button type="button" onClick={() => setRequested(true)} disabled={!preferences}>▷ Play 3D animation</button>}
      <span>THE NEXAFLOW EMBLEM</span>
    </div>
  </div>;
}
