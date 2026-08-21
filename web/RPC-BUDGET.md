# Frontend RPC budget

The browser reads BSC directly, but it does not poll dashboards or prices in
the background. RPC usage is controlled in `lib/rpc-policy.ts` and enforced by
the Wagmi, Viem and React Query configuration.

## What consumes RPC

- Opening a screen after its cached data expires.
- Explicitly refreshing the current quote and placement immediately before a
  paid transaction.
- Wallet simulation/submission.
- One receipt check every configured polling interval while a transaction is
  pending.

Upline payments, treasury allocation, spillover, spillunder and rollover are
internal operations in the same membership transaction. They do not cause one
RPC request per transfer or per tree level.

## Controls

- Nearby `readContract` calls are combined into one Multicall3 `eth_call`.
- Identical in-flight reads are deduplicated by React Query.
- Cached reads survive client-side navigation for 15 minutes and are reused
  until their state-specific stale window expires.
- Token metadata is cached for the browser session.
- Price quotes cache for 45 seconds, but are explicitly refreshed once when a
  user clicks Approve or Join.
- Placement caches for 20 seconds and is explicitly refreshed once when a user
  clicks Join.
- Stage configuration caches for 10 minutes.
- Wallet, member, board and award state caches for 30-45 seconds.
- Protocol totals and open-stage anchors cache for 2 minutes.
- Window focus, reconnect and interval-based background refetches are disabled.
- HTTP transport retries once. React Query does not retry 400 or 429 errors.
- Transaction receipts poll every 8 seconds by default, not every block.

The provider may price Multicall computation differently, so its billing
dashboard remains the final source of request and compute-unit usage. Configure
provider-side rate and spend alerts even with client caching enabled.

## Environment controls

```dotenv
NEXT_PUBLIC_RPC_POLLING_INTERVAL_MS=8000
NEXT_PUBLIC_RPC_MULTICALL_WAIT_MS=40
```

Receipt polling is clamped to 5-30 seconds. The multicall collection window is
clamped to 0-100 milliseconds.
