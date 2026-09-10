# Serverless re-entry keeper (existing V6)

<!-- Deployment marker: dry-run environment verification build. -->

## Status

Implemented locally, disabled by default. No wallet generated/funded, no live key loaded, no Redis account provisioned, no scheduled job enabled, and no contract transaction submitted by this implementation task. The production contract and ABI are unchanged. Deployment and a controlled live canary are still required.

The existing frontend's explicit Prepare Stage action remains a fallback. This worker reduces queue delays; it cannot change the deployed algorithm or guarantee that every purchase succeeds between scheduled runs.

## Architecture

An authenticated scheduler calls `GET /api/keeper`. The Next.js serverless function verifies the configured V6 runtime and chain, inspects the six queues, and may submit one permissionless `processReentries` transaction. It never calls register, joinStage, claim, recovery, transfer, approval or administrative setters.

- Dedicated, unprivileged BNB gas wallet; not the deployer/admin, root, treasury or company.
- Persistent Upstash-compatible Redis REST storage, shared by all deployments using that signer on chain 56. Never use a per-instance memory lock or an evicting cache for this state.
- 120-second lease with owner checks on atomic reservation/settlement. The route has a 60-second execution limit. An expired worker cannot create a new reserved intent.
- Persist signed bytes, hash and nonce atomically with the gas reservation BEFORE broadcasting. On ambiguity/crash, retry only identical signed bytes, not a new nonce or replacement transaction.
- Pending records do not expire. A receipt needs two additional blocks and reactivation evidence to report confirmed progress. Reverted/no-progress receipts raise an alert status. Gas reservations are not refunded.
- A transaction pending for over 15 minutes is retained and flagged for operator review; it is never silently discarded or replaced.
- Emergency recovery blocks new submissions. Already broadcast transactions cannot be recalled by the worker.
- Rotating stage cursor is persisted so the scheduler interval cannot starve higher stages.
- Simulation must show progress. Try work limits 16, 4 and 1 to fit the gas cap; reject a no-progress or over-budget transaction.
- Batch read calls using multicall. No historical event scan, browser polling or unbounded loop. At most one new transaction per invocation; settling an existing intent consumes that invocation.

## Required configuration

Set these only as server-side production variables. No signing/storage/scheduler secret may use a `NEXT_PUBLIC_` prefix or be committed to git.

| Variable | Initial setting / purpose |
|---|---|
| `KEEPER_ENABLED` | `false` until storage and scheduler are ready |
| `KEEPER_DRY_RUN` | `true` initially; only exact `false` allows broadcasting |
| `CRON_SECRET` | Random secret of at least 32 characters; scheduler sends `Authorization: Bearer <secret>` |
| `KEEPER_WALLET_ADDRESS` | Dedicated new operational wallet; do not share its nonce with any other tool |
| `KEEPER_PRIVATE_KEY` | Dedicated wallet key, stored securely; unnecessary for dry run |
| `BSC_RPC_URL` | Private HTTPS endpoint; no browser RPC fallback |
| `UPSTASH_REDIS_REST_URL` | Durable Redis HTTPS endpoint |
| `UPSTASH_REDIS_REST_TOKEN` | Private Redis authorization token |
| `KEEPER_MAX_GAS_PRICE_GWEI` | Default `0.1`; higher network prices stop the worker, not auto-increase the cap |
| `KEEPER_MAX_GAS` | Default `2000000`; includes 25% estimate headroom |
| `KEEPER_BUDGET_BNB_24H` | Default `0.001`; rolling reservation budget, not a prediction of cost |
| `KEEPER_MIN_BALANCE_BNB` | Default `0.0001`, retained in addition to the proposed maximum gas charge |

Existing frontend chain/version/address/runtime-hash variables must identify the intended V6 deployment. Live mode additionally requires `VERCEL_ENV=production`. A preview deployment cannot sign. The endpoint still requires authorization when disabled.

The budget counts worst-case gas commitments made within the last 24 hours, rounded UP to gwei. It conservatively counts failed and uncertain submissions. A delayed older transaction can mine later; this is a commitment budget, not a guarantee about gas mined within an exact calendar day. One pending intent blocks creation of another. Changing caps or disabling the worker does not revoke an already signed/broadcast transaction.

## Persistent state initialization

For a fresh dedicated signer only, use the Redis provider console to initialize:

```text
SET nexaflow:keeper:56:<lowercase-keeper-address>:state {"costs":[],"cursor":0} NX
```

The value must be a JSON string, with no expiration. `NX` prevents overwriting existing state. Keep Redis persistence/backups and disable eviction for these keys. Missing state causes a fail-closed error; it is not automatically recreated.

Never delete/reinitialize production keeper state to clear a pending transaction or budget. Restore its saved state, inspect the on-chain nonce and receipt, and review before resuming. Initialization must not run at every cold start/deployment. Do not use this signer for manual transactions or another service.

## Scheduling without a dedicated server

Start with a two-minute interval. Options:

1. Vercel cron on a plan supporting frequent schedules. Merge the following into the active `vercel.json` only after confirming plan support:

```json
{"crons":[{"path":"/api/keeper","schedule":"*/2 * * * *"}]}
```

2. An external managed scheduler calling the same authenticated HTTPS endpoint. Keep its credential private. Configure failure alerts and avoid aggressive automatic retries.

No cron entry was added to the existing project configuration: Vercel Hobby permits only daily cron runs, unsuitable for this use. Do not claim this functionality is free or currently scheduled. Scheduler, serverless runtime, storage, RPC and BNB gas may incur charges.

Sources: [Vercel cron limits](https://vercel.com/docs/cron-jobs/usage-and-pricing), [cron authentication and management](https://vercel.com/docs/cron-jobs/manage-cron-jobs), [Redis REST API](https://upstash.com/docs/redis/features/restapi), [atomic Lua EVAL](https://upstash.com/docs/redis/sdks/ts/commands/scripts/eval).

## Enablement checklist

1. Review/deploy the frontend + keeper endpoint, leaving enabled=false and dry-run=true.
2. Provision persistent Redis and the dedicated gas wallet; initialize state once. Configure private RPC and scheduler authentication.
3. Set enabled=true, keep dry-run=true. Observe authenticated dry-run/idle responses. Dry run checks identity/recovery/queues; it does NOT sign, estimate execution gas, validate a private key or prove funding sufficiency.
4. Fund only a small operator-approved BNB amount. Confirm wallet address/key match, gas/budget limits and alert delivery. Do not use any existing reserve or member wallet to pay for this without separate authorization.
5. After approval, set dry-run=false in production. Observe one transaction, its stored hash, confirmed receipt, reserve backing and queue progress. Then enable regular scheduling.
6. Keep Prepare Stage available as a fallback. Monitor both HTTP failures AND missing scheduler invocations. Vercel logs alone do not deliver alerts; connect scheduler failure notifications/uptime monitoring explicitly.

## Responses / operations

- `idle`, `dry_run`, `disabled`, `busy`: no new blockchain transaction.
- `submitted`, `pending`: retain/track the returned transaction hash.
- `confirmed`: receipt confirms re-entry progress; not necessarily an empty queue.
- `no_progress`, `reverted`, `pending_stalled`, `budget_or_lease_blocked`, `pending_deployment_mismatch`, `recovery_pending`: HTTP 503 for configured monitoring. Investigate; do not repeatedly reset keys or top up blindly.
- `check_failed`: safe redacted error. Check private configuration, storage, RPC, gas funding and pending intent. No raw RPC exception, key or signed bytes are returned/logged.
- To stop: set `KEEPER_ENABLED=false` and disable scheduling. Preserve Redis state. Previously broadcast transactions may still confirm.

## Local verification

`npm run test:keeper` exercises coordinator/adapter/authentication and actual Redis Lua atomicity (requires redis-server/redis-cli). It uses a public deterministic unit-test signer ONLY; never fund it. Run `npm run test:v6`, typecheck, lint and build as well.

The earlier Foundry reproduction and 3,000-wallet/six-stage campaign demonstrate that separate permissionless processing unblocks the known failure. These are local tests; no live worker canary has run yet.
