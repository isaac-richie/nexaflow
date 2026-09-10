# Member frontend — V5 integration

The approved visual direction is now applied to `/app`, `/app/board`, and
`/app/network`. These are real membership screens, not the `/preview` fixtures.
The existing `/app/join` transaction flow uses the new shell without being rewritten.

## Presentation and data

- Desktop sidebar; four-destination mobile bottom navigation with safe-area spacing.
- Six vertical, expandable stage rows. No hidden horizontal stage carousel.
- Member earnings, completed-board totals, current progress, and separate award totals.
- Stage fees, rewards, board sizes, and milestones come from the configured contract.
- Missing multicall results remain unavailable. They never become zero balances or a
  confident “not registered” message. Cached data is labelled if a refresh fails.
- Board diagram is a progress illustration, not an exact placement map or historical
  occupant list. V5 exposes the rollover count, not previous-board snapshots.
- Referral lineage and board placements remain distinct. Account changes remount
  wallet-local UI state; aborted network responses cannot replace newer generations.
- Royalty bonus, gaming, solar power, and prediction market are labelled Details pending.
  No benefit eligibility or delivery is inferred from stage activation.
- No public treasury/company balance cards; no V6 reserve, claim, or re-entry figures.

## Cost and accessibility

Existing RPC stale windows and disabled background polling are preserved. Stage reads
are batched across six stages and pinned to the configured chain. User refresh controls
have a 15-second cooldown. Opening an accordion sends no new contract read.

Transaction screens mount no decorative canvas or hidden animated background. The
Three.js landing is now the public `/` homepage, with live `/app` and `/app/join`
links and V5-compatible copy. The artwork is opt-in on mobile and constrained devices;
reduced motion retains the static logo. The existing consent gate remains in place.
Preview routes remain separate, non-transactional, and production-gated by default.
Member screens use scoped responsive
CSS, reduced-motion rules, visible keyboard focus, semantic stage buttons, and a skip link.

## Verification

- `npm run test:member`: 17 tests, including 1,000 synthetic six-stage snapshots,
  precise bigint formatting, partial reads, chain guards, stage eligibility, SSR controls,
  and asynchronous network-response races. These are not 1,000 on-chain transactions.
- `npm run test:preview`: 16 homepage, preview, isolation, and animation-policy tests.
- `npm run test:network`: 6 graph tests plus 4 deployment/chain cache-isolation tests.
- `npm run test:rpc`: RPC policy checks.
- `npm run lint`, `npm run typecheck`, and an isolated Next.js production build.
- Production HTTP checks: `/`, `/app`, `/app/board`, `/app/network`, and `/app/join`
  returned 200; both preview routes returned 404 with the default production gate.
  The final local development overview, boards, and network routes also returned 200.
- A read-only BSC check returned all six stage configurations (6/14/14/14/14/14
  positions) and an active root membership through the configured frontend ABI.

Browser/device wallet testing, approval/registration end-to-end testing, and dependency
security triage remain release gates. The read-only check does not validate transfer
execution or establish contract safety. No live transactions, environment changes,
ABI/address switches, Git push, or deployment were performed for this frontend slice.

V6 integration requires its own adapter and transaction-flow tests before enabling
funded re-entry, reserve accounting, deferred claims, or position history. Do not switch
the current membership address to a V6 prototype as a configuration-only upgrade.
