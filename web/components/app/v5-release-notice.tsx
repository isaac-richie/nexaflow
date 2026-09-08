"use client";

import { IS_V6, MEMBERSHIP_ADDRESS } from "@/lib/contracts/config";

export function V5ReleaseNotice() {
  if (!IS_V6 && MEMBERSHIP_ADDRESS.toLowerCase() !== "0xef7ede29c63abd3add2c829bdd70625b47e1a245") return null;

  return (
    <aside className="mb-6 rounded-xl border border-gold/25 bg-gold/5 p-4 text-sm text-muted" aria-label="Previous membership notice">
      <p className="font-semibold text-ink">Returning member?</p>
      <p className="mt-1">
        Previous memberships, boards and balances have not been transferred.
        Contact the team before paying again.
      </p>
    </aside>
  );
}
