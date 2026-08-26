import { STAGE_PRESETS } from "@/lib/contracts/config";
import type { StageMembership } from "@/hooks/use-membership";

type Props = {
  stages?: Array<StageMembership | undefined>;
};

const BENEFITS = [
  {
    key: "fuel-saver",
    label: "Registration package",
    title: "Fuel Saver",
    stageId: 0,
    description:
      "The practical product benefit connected to your NexaFlow registration package.",
    icon: "fuel" as const,
  },
  {
    key: "solar-five",
    label: "Stage 5 benefit",
    title: "Solar Power",
    stageId: 4,
    description:
      "Solar Power benefit associated with activating Stage 5, subject to verification.",
    icon: "solar" as const,
  },
  {
    key: "solar-six",
    label: "Stage 6 benefit",
    title: "Solar Power",
    stageId: 5,
    description:
      "Solar Power benefit associated with activating Stage 6, subject to verification.",
    icon: "solar" as const,
  },
];

export function ProductBenefits({ stages }: Props) {
  return (
    <section className="panel panel-sheen p-4 sm:p-6">
      <div>
        <h2 className="font-display text-base font-semibold sm:text-lg">
          Your product benefits
        </h2>
        <p className="mt-0.5 text-xs text-muted sm:text-sm">
          Products connected to your registration and stage progress.
        </p>
      </div>

      <div className="mt-4 grid gap-3 sm:grid-cols-3">
        {BENEFITS.map((benefit) => {
          const activated = Boolean(stages?.[benefit.stageId]?.enrolled);
          const stage = STAGE_PRESETS[benefit.stageId];

          return (
            <article
              key={benefit.key}
              className={`relative overflow-hidden rounded-xl border p-4 transition-colors ${
                activated
                  ? "panel-sheen border-gold/35 bg-gradient-to-br from-gold/10 via-gold/[0.04] to-transparent shadow-[0_1px_0_0_hsl(0_0%_100%/0.04)_inset,0_10px_30px_-20px_hsl(var(--gold)/0.35)]"
                  : "border-line bg-surface-2/60"
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                <ProductIcon kind={benefit.icon} active={activated} />
                <span
                  className={`rounded-full border px-2 py-0.5 text-[10px] font-medium ${
                    activated
                      ? "border-up/25 bg-up/10 text-up"
                      : "border-line bg-surface-3 text-faint"
                  }`}
                >
                  {activated ? "Stage activated" : `${stage.label} required`}
                </span>
              </div>

              <div className="mt-4 text-[10px] font-medium uppercase tracking-[0.16em] text-gold">
                {benefit.label}
              </div>
              <h3 className="mt-1 font-display text-lg font-semibold text-ink">
                {benefit.title}
              </h3>
              <p className="mt-2 text-xs leading-relaxed text-muted">
                {benefit.description}
              </p>
              {activated && (
                <div className="mt-3 flex items-center gap-2 border-t border-line pt-3 text-[11px] text-faint">
                  <span className="h-1.5 w-1.5 rounded-full bg-gold" />
                  Verification required for fulfilment
                </div>
              )}
            </article>
          );
        })}
      </div>

      <p className="mt-3 text-[11px] leading-relaxed text-faint">
        Product eligibility, availability and fulfilment follow the official
        NexaFlow program terms and community verification process.
      </p>
    </section>
  );
}

function ProductIcon({
  kind,
  active,
}: {
  kind: "fuel" | "solar";
  active: boolean;
}) {
  const className = active
    ? "bg-gold/15 text-gold"
    : "bg-surface-3 text-faint";

  return (
    <div className={`flex h-10 w-10 items-center justify-center rounded-xl ${className}`}>
      {kind === "fuel" ? (
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <path d="M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16" />
          <path d="M4 10h12" />
          <path d="M8 7h4" />
          <path d="M16 7h2l2 3v7a2 2 0 0 1-4 0v-3" />
        </svg>
      ) : (
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <circle cx="12" cy="7" r="3" />
          <path d="M12 1v2M12 11v2M6 7H4M20 7h-2M7.8 2.8 6.4 1.4M17.6 12.6l-1.4-1.4M16.2 2.8l1.4-1.4M6.4 12.6l1.4-1.4" />
          <path d="M4 16h16l-2 7H6l-2-7Z" />
          <path d="m8 16-1 7M16 16l1 7M4.5 19.5h15" />
        </svg>
      )}
    </div>
  );
}
