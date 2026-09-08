// A V5 acknowledgement must not silently cover V6's new custody authority.
export const CONSENT_VERSION = process.env.NEXT_PUBLIC_MEMBERSHIP_VERSION === "v6"
  ? "2026-09-08-v6" : "2026-09-01-v2";
