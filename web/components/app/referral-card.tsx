"use client";

import { useEffect, useMemo, useState } from "react";
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
    await copyText(value);
    setCopied(kind);
    window.setTimeout(() => setCopied(null), 1800);
  }

  async function share() {
    if (!shareUrl) return;
    setSharing(true);
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
    } finally {
      setSharing(false);
    }
  }

  return (
    <section className="panel panel-sheen p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="font-display text-lg font-semibold">Invite your network</h2>
          <p className="mt-1 max-w-xl text-sm leading-relaxed text-muted">
            Share this link. It permanently resolves to your wallet, so a browser
            refresh or a copied message cannot silently change your sponsor.
          </p>
        </div>
        <span className="rounded-full border border-gold/25 bg-gold/10 px-3 py-1 font-mono text-xs text-gold">
          {code}
        </span>
      </div>

      <div className="mt-5 flex flex-col gap-2 sm:flex-row">
        <input
          value={shareUrl || "Preparing link…"}
          readOnly
          aria-label="Referral link"
          className="min-w-0 flex-1 rounded-xl border border-line bg-surface-2 px-3 py-2.5 font-mono text-xs text-muted"
        />
        <button onClick={share} disabled={!shareUrl || sharing} className="btn-gold px-4 py-2.5 text-sm disabled:opacity-50">
          {sharing ? "Opening…" : "Share link"}
        </button>
        <button onClick={() => copy("share", shareUrl)} disabled={!shareUrl} className="btn-ghost px-4 py-2.5 text-sm disabled:opacity-50">
          {copied === "share" ? "Copied" : "Copy"}
        </button>
      </div>

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
