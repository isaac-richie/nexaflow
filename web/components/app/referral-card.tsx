"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { getAddress } from "viem";
import {
  directReferralPathForAddress,
  referralCodeForAddress,
  referralPathForAddress,
} from "@/lib/referrals";

export function ReferralCard({ address }: { address?: `0x${string}` }) {
  const [origin, setOrigin] = useState("");
  const [copied, setCopied] = useState<"share" | "direct" | null>(null);
  const [sharing, setSharing] = useState(false);
  const [error, setError] = useState("");
  const resetTimer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(resetTimer.current), []);

  useEffect(() => setOrigin(window.location.origin), []);

  const normalized = address ? getAddress(address) : undefined;
  const code = normalized ? referralCodeForAddress(normalized) : "";
  const shareUrl = useMemo(
    () => (origin && normalized ? `${origin}${referralPathForAddress(normalized)}` : ""),
    [origin, normalized],
  );
  const directUrl = useMemo(
    () => (origin && normalized ? `${origin}${directReferralPathForAddress(normalized)}` : ""),
    [origin, normalized],
  );

  if (!normalized) return null;

  async function copyText(value: string) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      return;
    }

    const fallback = document.createElement("textarea");
    fallback.value = value;
    fallback.setAttribute("readonly", "true");
    fallback.style.position = "fixed";
    fallback.style.opacity = "0";
    document.body.appendChild(fallback);
    fallback.select();
    const copied = document.execCommand("copy");
    fallback.remove();
    if (!copied) throw new Error("Clipboard is unavailable");
  }

  async function copy(kind: "share" | "direct", value: string) {
    setError("");
    try {
      await copyText(value);
      setCopied(kind);
      clearTimeout(resetTimer.current);
      resetTimer.current = setTimeout(() => setCopied(null), 1800);
    } catch {
      setError("Copy is unavailable. Select the referral link and copy it manually.");
    }
  }

  async function share() {
    if (!shareUrl) return;
    setSharing(true);
    setError("");
    try {
      if (navigator.share) {
        await navigator.share({
          title: "Join NexaFlow",
          text: "Join me on NexaFlow.",
          url: shareUrl,
        });
      } else {
        await copy("share", shareUrl);
      }
    } catch (shareError) {
      if (!(shareError instanceof Error && shareError.name === "AbortError")) {
        setError("Sharing is unavailable. Use Copy to share your link instead.");
      }
    } finally {
      setSharing(false);
    }
  }

  return (
    <section className="panel panel-sheen p-4 sm:p-6">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 className="font-display text-base font-semibold sm:text-lg">Invite your network</h2>
          <p className="mt-0.5 max-w-xl text-xs leading-relaxed text-muted sm:mt-1 sm:text-sm">
            Share this link. It permanently resolves to your wallet.
          </p>
        </div>
        <span className="shrink-0 rounded-full border border-gold/25 bg-gold/10 px-2.5 py-1 font-mono text-[10px] text-gold sm:px-3 sm:text-xs">
          {code.slice(0, 8)}…
        </span>
      </div>

      <div className="mt-4 flex flex-col gap-2 sm:mt-5 sm:flex-row">
        <input
          value={shareUrl || "Preparing link…"}
          readOnly
          aria-label="Referral link"
          className="min-w-0 flex-1 rounded-xl border border-line bg-surface-2 px-3 py-2.5 font-mono text-[11px] text-muted sm:text-xs"
        />
        <div className="flex gap-2">
          <button onClick={share} disabled={!shareUrl || sharing} className="btn-gold flex-1 px-4 py-2.5 text-sm disabled:opacity-50 sm:flex-initial">
            {sharing ? "Opening…" : "Share"}
          </button>
          <button onClick={() => copy("share", shareUrl)} disabled={!shareUrl} className="btn-ghost flex-1 px-4 py-2.5 text-sm disabled:opacity-50 sm:flex-initial">
            {copied === "share" ? "Copied" : "Copy"}
          </button>
        </div>
      </div>

      <p role="status" className="mt-3 text-xs text-muted">{error || (copied ? "Referral link copied." : "")}</p>
      <details className="mt-4 text-xs text-faint">
        <summary className="cursor-pointer hover:text-muted">Direct wallet fallback</summary>
        <div className="mt-2 flex flex-col gap-2 sm:flex-row">
          <code className="min-w-0 flex-1 break-all rounded-lg border border-line bg-surface-2 px-3 py-2 text-[11px]">
            {directUrl || "Preparing link…"}
          </code>
          <button onClick={() => copy("direct", directUrl)} disabled={!directUrl} className="btn-ghost px-3 py-2 text-xs disabled:opacity-50">
            {copied === "direct" ? "Copied" : "Copy fallback"}
          </button>
        </div>
      </details>
    </section>
  );
}
