/** Pure, testable rules; animation never shares a clock with blockchain reads. */
export type AnimationPreferences = { reducedMotion: boolean; compact: boolean; saveData: boolean; limitedDevice: boolean };

export function mayAutoplay(prefs: AnimationPreferences) {
  return !prefs.reducedMotion && !prefs.compact && !prefs.saveData && !prefs.limitedDevice;
}

export function mayRenderAnimation(input: {
  enabled: boolean; paused: boolean; inView: boolean; documentVisible: boolean; reducedMotion: boolean;
}) {
  return input.enabled && !input.paused && input.inView && input.documentVisible && !input.reducedMotion;
}

export const HERO_FRAME_INTERVAL_MS = 1000 / 30;
