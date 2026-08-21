# Oracle keeper

Calls `update()` on the price oracle so the membership contract can keep
quoting stage prices. That is the entire job.

## Why it is needed

Stage entry is priced in USD and charged in RWAAN, converted through a
PancakeSwap V2 TWAP. A TWAP does not advance by itself: somebody has to call
`update()` on it.

Two numbers define the window:

| | value | meaning |
|---|---|---|
| `oracle.period` | **2 hours** | `update()` reverts before this has elapsed |
| `contract.maxPriceAge` | **3 hours** | quotes revert after this |

The keeper has to fire inside that band. **The usable margin is one hour.**
Miss it and `quoteStagePayment`, `registerWithMaxPayment` and
`joinStageWithMaxPayment` all revert `StalePrice`, and nobody can join.

> **Worth widening.** Raising `maxPriceAge` to 6–8 hours turns a single missed
> run from an outage into a non-event. The tradeoff is accepting a slightly
> older price, which for a TWAP is a small price for not going dark.

## Cost

Roughly **$1.30 a month** at 0.05 gwei and twelve updates a day. A 0.05 BNB
float lasts about two years.

## The keeper key

`update()` is **permissionless**. This wallet has no role on the contract and
no power over member funds. It needs BNB for gas and nothing else.

Use a **dedicated wallet**. Never the admin, operator, treasury or root key.
If this key leaks, the loss is the gas float.

## Setup

```bash
cd keeper
npm install
cp .env.example .env      # add KEEPER_PRIVATE_KEY, fund the address with BNB
npm run dry               # reads chain, sends nothing
```

## Running it

Three options, in the order I would pick them.

### 1. Cron on a small VPS (recommended)

Simplest thing that is reliable. Every 30 minutes; the script no-ops when the
period has not elapsed, so over-calling is free.

```
*/30 * * * * cd /srv/nexaflow/keeper && /usr/bin/node update-oracle.mjs >> keeper.log 2>&1
```

### 2. Long-running process

If you would rather not use cron. Checks every 10 minutes and survives RPC
failures rather than exiting.

```bash
pm2 start update-oracle.mjs --name nexaflow-keeper -- --watch
pm2 save && pm2 startup
```

### 3. A keeper network (Gelato, Chainlink Automation)

No server and no key to manage: you fund a task and the network calls
`update()`. The most robust option and worth it once real money is flowing.

### Not GitHub Actions

Scheduled workflows routinely drift ten to thirty minutes and are dropped
under load. With only an hour of margin that is a real risk of going dark, and
it means putting a spending key in repo secrets. If you do use it, widen
`maxPriceAge` first.

## Monitoring

The one alert worth having: **quotes are failing**. Anything that calls
`latestAssetPriceUsd()` and pages you on revert will catch a dead keeper, a
drained gas wallet and a broken RPC all at once.

The frontend already degrades honestly here: `useOraclePriceHealth()` detects
`StalePrice` and shows a "Pricing is refreshing" panel instead of a form that
cannot work.
