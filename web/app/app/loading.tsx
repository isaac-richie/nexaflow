/**
 * Route-level loading state for /app.
 *
 * Without this file the App Router renders nothing at all during navigation,
 * so clicking "Launch App" looks broken: the page sits still, the user clicks
 * again, and concludes the button is dead. In dev the wait is worst because
 * the route compiles on demand (17s+ cold), but it matters in production too
 * while Privy initialises and the first chain reads resolve.
 *
 * This renders instantly and mirrors the real dashboard's shape, so the
 * transition reads as loading rather than as a broken link.
 */
export default function Loading() {
  return (
    <div className="space-y-6" aria-busy="true" aria-live="polite">
      <div>
        <div className="h-9 w-44 animate-pulse rounded-lg bg-surface-2" />
        <div className="mt-2.5 h-4 w-72 max-w-full animate-pulse rounded bg-surface-2/70" />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="panel p-4 sm:p-5">
            <div className="h-3 w-20 animate-pulse rounded bg-surface-2" />
            <div className="mt-3 h-7 w-24 animate-pulse rounded bg-surface-2/80" />
          </div>
        ))}
      </div>

      <div className="panel p-5 sm:p-6">
        <div className="h-5 w-32 animate-pulse rounded bg-surface-2" />
        <div className="mt-5 space-y-2">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="h-16 animate-pulse rounded-xl bg-surface-2/60"
              // Staggered so it reads as a list settling in rather than one
              // block flashing.
              style={{ animationDelay: `${i * 70}ms` }}
            />
          ))}
        </div>
      </div>

      <span className="sr-only">Loading your dashboard</span>
    </div>
  );
}
