import Link from "next/link";
import { BoardDiagram } from "@/components/board-diagram";
import { SiteNav, Mark } from "@/components/site-nav";
import { Reveal, Stagger, StaggerItem } from "@/components/motion";
import { STAGES, usd } from "@/lib/stages";

/**
 * Landing page.
 *
 * Two rules held throughout:
 *
 *  - No section captions. "Mechanics", "Stages", "Security" told the reader
 *    what they could already see. A page that labels its own parts reads as a
 *    template.
 *  - Gold means money. It is used for figures and the primary action, nowhere
 *    else. When labels, headings and numbers were all gold the colour carried
 *    no information.
 */
export default function Home() {
  return (
    <>
      <SiteNav />
      <main id="top">
        <Hero />
        <Mechanics />
        <Stages />
        <Proof />
      </main>
      <Footer />
    </>
  );
}

/* ------------------------------------------------------------------ */

function Hero() {
  return (
    <section className="relative overflow-hidden px-5 pb-24 pt-32 sm:px-6 sm:pt-40">
      <div className="grid-field pointer-events-none absolute inset-0 -z-10" />
      <div
        className="pointer-events-none absolute left-1/2 top-[-20%] -z-10 h-[520px]
                   w-[min(900px,120vw)] -translate-x-1/2 rounded-full opacity-[0.13] blur-[140px]"
        style={{ background: "radial-gradient(circle, hsl(var(--gold)) 0%, transparent 70%)" }}
      />

      <div className="mx-auto max-w-3xl text-center">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full border border-line
                           bg-surface-1/80 px-3.5 py-1.5 text-xs text-muted backdrop-blur">
            <span className="relative flex h-1.5 w-1.5">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-up opacity-60" />
              <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-up" />
            </span>
            Live on BNB Chain
          </span>
        </Reveal>

        <Reveal delay={0.06}>
          <h1 className="mt-7 font-display text-[3rem] font-extrabold leading-[0.98]
                         tracking-[-0.035em] sm:text-7xl lg:text-[5.25rem]">
            Every position
            <br />
            <span className="gold-text">pays you back</span>
          </h1>
        </Reveal>

        <Reveal delay={0.12}>
          <p className="mx-auto mt-6 max-w-sm text-base leading-relaxed text-muted sm:text-lg">
            Someone fills a slot on your board, you are paid in the same
            transaction.
          </p>
        </Reveal>

        <Reveal delay={0.18}>
          <div className="mt-9 flex flex-col gap-3 sm:flex-row sm:justify-center">
            <Link href="/app" className="btn-gold w-full py-3.5 sm:w-auto">
              Launch App
            </Link>
            <a href="#how" className="btn-ghost w-full py-3.5 sm:w-auto">
              How it works
            </a>
          </div>
        </Reveal>
      </div>

      {/* The single lifted element on the page. The board explains the product
          faster than any paragraph, so it gets the weight. */}
      <Reveal delay={0.26} y={30}>
        <div className="panel-raised mx-auto mt-16 max-w-5xl p-5 sm:mt-24 sm:p-10">
          <div className="sm:hidden">
            <BoardDiagram depth={2} nodeReward={5} />
            <p className="mt-6 text-center text-xs text-faint">
              Stage 1 &middot; six positions &middot; {usd(5)} each
            </p>
          </div>
          <div className="hidden sm:block">
            <BoardDiagram depth={3} nodeReward={10} />
            <p className="mt-8 text-center text-xs text-faint">
              Stage 2 &middot; fourteen positions &middot; {usd(10)} each
            </p>
          </div>
        </div>
      </Reveal>
    </section>
  );
}

/* ------------------------------------------------------------------ */

const MECHANICS = [
  {
    t: "Every position pays you",
    b: "Your board is the levels beneath you. Each filled slot sends one reward, not just your two direct ones.",
  },
  {
    t: "People land under you",
    b: "When the slots above are taken, the next arrival drops to the board below. You are paid for them either way.",
  },
  {
    t: "A full board starts again",
    b: "The slots reopen and the board pays you a second time. There is no cap on how often it cycles.",
  },
];

function Mechanics() {
  return (
    <section id="how" className="scroll-mt-20 px-5 py-20 sm:px-6 sm:py-28">
      <div className="mx-auto max-w-5xl">
        {/* Numerals as the visual anchor rather than boxes. Three identical
            cards make three ideas look like a list of features; numbered rows
            make them read as a sequence. */}
        <Stagger className="divide-y divide-line">
          {MECHANICS.map((m, i) => (
            <StaggerItem key={m.t}>
              <div className="grid gap-3 py-9 sm:grid-cols-[auto_1fr_1.2fr] sm:gap-10 sm:py-12">
                <span className="figure text-sm text-faint sm:pt-1.5">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <h3 className="font-display text-xl font-semibold leading-snug tracking-[-0.01em] sm:text-2xl">
                  {m.t}
                </h3>
                <p className="max-w-md text-[15px] leading-relaxed text-muted">
                  {m.b}
                </p>
              </div>
            </StaggerItem>
          ))}
        </Stagger>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */

/**
 * Stages as a ledger, not as six cards.
 *
 * Six identical cards is the default template shape and reads as marketing.
 * A table reads as a financial instrument, scans down a single column, and
 * lets the payout figures line up so they can actually be compared.
 */
function Stages() {
  return (
    <section id="stages" className="scroll-mt-20 px-5 py-20 sm:px-6 sm:py-28">
      <div className="mx-auto max-w-5xl">
        <Reveal className="mb-10 sm:mb-14">
          <h2 className="font-display text-3xl font-bold tracking-[-0.025em] sm:text-[2.75rem]">
            Six stages
          </h2>
        </Reveal>

        <Reveal>
          <div className="panel overflow-hidden">
            {/* Header row, desktop only: on mobile each row carries its own
                labels, since a header far above the data is unreadable there. */}
            <div className="hidden grid-cols-[1fr_repeat(4,minmax(0,0.7fr))] gap-4 px-7 pb-4 pt-6 sm:grid">
              <span className="label">Stage</span>
              <span className="label text-right">Entry</span>
              <span className="label text-right">Per slot</span>
              <span className="label text-right">Board</span>
              <span className="label text-right">Full board</span>
            </div>

            <div className="divide-y divide-line sm:border-t sm:border-line">
              {STAGES.map((s) => (
                <div
                  key={s.id}
                  className="group grid grid-cols-2 gap-3 px-5 py-5 transition-colors
                             duration-200 hover:bg-surface-2/40 sm:grid-cols-[1fr_repeat(4,minmax(0,0.7fr))]
                             sm:gap-4 sm:px-7 sm:py-5"
                >
                  <div className="col-span-2 flex items-baseline justify-between sm:col-span-1 sm:block">
                    <span className="font-display text-base font-semibold">{s.label}</span>
                    <span className="figure text-base sm:hidden">{usd(s.fee)}</span>
                  </div>

                  <Cell label="Entry" value={usd(s.fee)} hideOnMobile />
                  <Cell label="Per slot" value={usd(s.nodeReward)} />
                  <Cell label="Board" value={`${s.slots}`} />
                  <Cell label="Full board" value={usd(s.boardYield)} accent />
                </div>
              ))}
            </div>
          </div>
        </Reveal>

        <p className="mt-6 text-center text-sm text-faint">
          Figures are a full board. A partly filled board pays for the slots
          that are filled.
        </p>
      </div>
    </section>
  );
}

function Cell({
  label,
  value,
  accent,
  hideOnMobile,
}: {
  label: string;
  value: string;
  accent?: boolean;
  hideOnMobile?: boolean;
}) {
  return (
    <div className={hideOnMobile ? "hidden sm:block sm:text-right" : "sm:text-right"}>
      <span className="label block sm:hidden">{label}</span>
      <span
        className={`figure mt-1 block text-[15px] sm:mt-0 ${
          accent ? "gold-text font-semibold" : "text-ink"
        }`}
      >
        {value}
      </span>
    </div>
  );
}

/* ------------------------------------------------------------------ */

const PROOF = [
  ["192", "tests"],
  ["200k+", "fuzzed calls"],
  ["4", "analysis tools"],
  ["10/10", "injected bugs caught"],
];

function Proof() {
  return (
    <section id="security" className="scroll-mt-20 px-5 py-20 sm:px-6 sm:py-28">
      <div className="mx-auto max-w-5xl">
        <Reveal className="mb-10 max-w-xl sm:mb-14">
          <h2 className="font-display text-3xl font-bold tracking-[-0.025em] sm:text-[2.75rem]">
            Checked, not claimed
          </h2>
        </Reveal>

        {/* Figures on the page itself rather than boxed into a stat card. The
            box was doing nothing except making four numbers look like an ad. */}
        <Stagger className="grid grid-cols-2 gap-x-6 gap-y-12 sm:grid-cols-4 sm:gap-x-8 sm:gap-y-0">
          {PROOF.map(([n, l]) => (
            <StaggerItem key={l}>
              <p className="figure text-4xl font-bold tracking-[-0.02em] sm:text-5xl">{n}</p>
              <p className="mt-2 text-sm text-muted">{l}</p>
            </StaggerItem>
          ))}
        </Stagger>

        <div className="hairline my-12 sm:my-16" />

        <Stagger className="grid gap-10 sm:grid-cols-2 sm:gap-14">
          <StaggerItem>
            <h3 className="font-display text-lg font-semibold">Solvency is enforced</h3>
            <p className="mt-3 max-w-sm text-[15px] leading-relaxed text-muted">
              A payout can never exceed the fee that funded it. The contract
              refuses any configuration where it could.
            </p>
          </StaggerItem>
          <StaggerItem>
            <h3 className="font-display text-lg font-semibold">No upgrade switch</h3>
            <p className="mt-3 max-w-sm text-[15px] leading-relaxed text-muted">
              There is no proxy. What was deployed is what runs, and the logic
              cannot be swapped underneath you.
            </p>
          </StaggerItem>
        </Stagger>

        <p className="mt-12 text-sm text-faint sm:mt-16">
          No third party audit has been carried out.
        </p>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */

function Footer() {
  return (
    <footer className="safe-x border-t border-line px-5 py-12 sm:px-6 sm:py-16">
      <div className="mx-auto flex max-w-5xl flex-col items-center gap-8 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-center gap-2.5">
          <Mark size={22} />
          <span className="font-display font-bold">
            Nexa<span className="gold-text">Flow</span>
          </span>
        </div>

        <p className="max-w-sm text-center text-xs leading-relaxed text-faint sm:text-right">
          What you earn depends on people joining after you. Entry fees are not
          refundable and a full board is not guaranteed. Not financial advice.
        </p>
      </div>
    </footer>
  );
}
