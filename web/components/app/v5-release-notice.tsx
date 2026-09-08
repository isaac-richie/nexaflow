"use client";

import { IS_V6, MEMBERSHIP_ADDRESS } from "@/lib/contracts/config";

export function V5ReleaseNotice() {
  if (IS_V6) return <aside className="mb-6 rounded-xl border border-gold/25 bg-gold/5 p-4 text-sm text-muted" aria-label="V6 membership notice"><p className="font-semibold text-ink">You’re using NexaFlow V6</p><p className="mt-1">This is a separate deployment. Previous memberships, boards and balances have not been transferred. Already a member of an earlier version? Contact the team before paying again.</p></aside>;
  if (MEMBERSHIP_ADDRESS.toLowerCase() !== "0xef7ede29c63abd3add2c829bd70625b47e1a245") return null;

  return (
    <aside className="mb-6 rounded-xl border border-gold/25 bg-gold/5 p-4 text-sm text-muted" aria-label="V5 membership notice">
      <p className="font-semibold text-ink">You’re using NexaFlow V5</p>
      <p className="mt-1">
        This dashboard shows V5 activity only. V4 memberships and boards have not
        been transferred. Already a V4 member? Contact the team before paying again.
      </p>
    </aside>
  );
}
