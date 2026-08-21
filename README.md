# BinaryMembershipV2 — RWAAN-priced membership

A 6-stage binary-tree membership contract paid in Rawli Analytics (`RWAAN`),
with market-priced registration, real-time upline payouts,
rollover cycling, BFS spillover placement, and admin-triggered physical awards.

V2 preserves the complete V1 tree and award behavior. Stage economics remain
USD-denominated, while the RWAAN fee and reward quantities are calculated at
registration time from a PancakeSwap V2 RWAAN/WBNB TWAP combined with the
Chainlink BNB/USD feed. Stale, future, zero and uninitialized prices revert.
The retired V1 source and regression suites remain in the repository as legacy
evidence; new deployments use `BinaryMembershipV2`.

Every upline whose board a placement lands on is paid, so a board owner collects
the node amount from **every position on their board** — 6 × nodeReward at
stage 0, 14 × at stages 1–5.

Built with Foundry. Analysed with Slither, Aderyn, Mythril and
Echidna — see [`SECURITY-NOTES.md`](./SECURITY-NOTES.md) for findings and audit
support material, including a **critical specification defect that was found and
fixed** (§2 there).

The split-cohort campaign also verifies the FINDING-5 repair: an ordinary
paying leader's board remains live after its ancestor rolls over, while rewards
and slot credit still stop at the detached edge. See `SECURITY-NOTES.md`.

---

## Table of contents

1. [What this is](#1-what-this-is)
2. [The six stages](#2-the-six-stages)
3. [How money moves](#3-how-money-moves)
4. [Tree mechanics](#4-tree-mechanics)
5. [Physical awards](#5-physical-awards)
6. [Admin controls](#6-admin-controls)
7. [Roles](#7-roles)
8. [Function reference](#8-function-reference)
9. [Gas profile](#9-gas-profile)
10. [Frontend integration](#10-frontend-integration)
11. [Indexer requirements](#11-indexer-requirements)
12. [Deployment](#12-deployment)
13. [Testing](#13-testing)
14. [Design decisions](#14-design-decisions)

---

## 1. What this is

Members pay a registration fee to join a stage. They are placed into a binary
tree beneath an existing member. When someone lands anywhere on your board, you
are paid instantly — the tokens arrive in your wallet in the same transaction,
with nothing to claim.

Your board is the `treeDepth` levels beneath you: 6 positions at stage 0,
14 at stages 1–5. You collect one `nodeReward` for each. When it fills it
**rolls over**: the counter increments, your child slots clear, and a fresh
board begins. Accumulate enough rollovers at a stage and you
qualify for a physical award, which an operator grants.

Six stages exist, each with a higher fee and a higher per-placement payout.
Advancing requires completing the previous stage.

**Key properties**

- Every upline on the board is paid one full `nodeReward`; treasury keeps
  whatever they do not consume. Verified exact across 580 placements in the
  300-wallet run.
- `treeDepth * nodeReward < fee` is enforced at config time and on every runtime
  fee change, so a full-depth payout can never exceed the fee funding it.
- `treeSlots == 2^(treeDepth+1) − 2` is enforced at config time, so a stage's
  board geometry cannot be self-contradictory. Both fields are written once and
  have no setter, so a mismatch would have been permanent: too many slots makes
  rollover unreachable, too few fires it before the board is full.
- Payouts are push, not pull. No claim step, no accrual bookkeeping for users.
- `fee` and `nodeReward` are stored as 18-decimal USD values. V2 converts both
  from one validated oracle snapshot for each paid enrollment; the fee rounds
  up and the reward rounds down to preserve solvency.
- The contract is never a custodian of unpaid rewards — the split happens inside
  the join transaction.
- Not upgradeable. Deliberate. Admin can retune economics at runtime instead.

---

## 2. The six stages

Stages are indexed `0..5` in code. They are typically presented to users as
"Stage 1..6" — mind the offset.

Values below are the configured 18-decimal USD amounts. They are **not**
hardcoded; they are passed to `configureStages` at deployment. The actual
RWAAN quantity changes with the oracle price.

| stageId | Fee | nodeReward | Board slots | Levels | Rollovers for award |
|---|---|---|---|---|---|
| 0 | $20 | $5 | 6 | 2 | — (no award) |
| 1 | $60 | $10 | 14 | 3 | 10 |
| 2 | $180 | $25 | 14 | 3 | 10 |
| 3 | $540 | $80 | 14 | 3 | 10 |
| 4 | $1,620 | $250 | 14 | 3 | 10 |
| 5 | $4,860 | $800 | 14 | 3 | 8 |

Fees triple at each step. Because every upline on a board is paid, the payout
per completed board is `payments x nodeReward`, where a stage-0 board makes
10 payments (1+1+2+2+2+2) and a stage-1..5 board makes 34 (2x1 + 4x2 + 8x3):

| stageId | Board revenue | Board pays out | To treasury | Treasury keeps |
|---|---|---|---|---|
| 0 | $120 | $50 | $70 | 58% |
| 1 | $840 | $340 | $500 | 60% |
| 2 | $2,520 | $850 | $1,670 | 66% |
| 3 | $7,560 | $2,720 | $4,840 | 64% |
| 4 | $22,680 | $8,500 | $14,180 | 63% |
| 5 | $68,040 | $27,200 | $40,840 | 60% |

Treasury retains 58–66% of every completed board. `treeDepth * nodeReward < fee`
is enforced, so this can never invert.

### Member economics

You earn from **every position on your board**, not just your two direct slots.
After rollover the board clears and you earn again.

| stageId | Earned per full board | Join cost | Boards to break even | At award threshold |
|---|---|---|---|---|
| 0 | $30 (6 × $5) | $20 | 1 | — (no award) |
| 1 | $140 (14 × $10) | $60 | 1 | $1,400 after 10 (+2,233%) |
| 2 | $350 (14 × $25) | $180 | 1 | $3,500 after 10 (+1,844%) |
| 3 | $1,120 (14 × $80) | $540 | 1 | $11,200 after 10 (+1,974%) |
| 4 | $3,500 (14 × $250) | $1,620 | 1 | $35,000 after 10 (+2,060%) |
| 5 | $11,200 (14 × $800) | $4,860 | 1 | $89,600 after 8 (+1,744%) |

A board owner clears their join cost inside a single completed board. Those
figures assume a **full** board; a partially filled one pays proportionally.

Mid-board members earn too — on a stage-1 board a level-1 member collects from
their six descendants ($60), and a level-2 member from their two ($20).

---

## 3. How money moves

Every join is a single transaction:

```
            USD stage value + live RWAAN/USD price
                           │
                           ▼
                  fee and reward in RWAAN
                           │
                           ▼
                  ┌────────────────┐
                  │   _pullExact   │  exact-balance check
                  └────────┬───────┘  (rejects fee-on-transfer tokens)
                           │
            ┌──────────────┴──────────────┐
            ▼                             ▼
   up to treeDepth uplines        fee − (uplines paid)
   x one nodeReward each                  │
            │                             ▼
            ▼                     pendingTreasury
   every upline whose board       (held until withdrawn)
   this lands on (paid NOW)
```

The upline walk is capped at `treeDepth` — a board is `treeDepth` levels, so a
member further above is not on it. Placements near the top of a fresh tree have
fewer ancestors and cost less than the maximum; the remainder goes to treasury.

Then `_propagateSlotFilled` credits the placement to each of those same boards,
firing rollovers where thresholds are met. Both walks are capped identically, so
gas per join is constant regardless of tree shape.

### Price source

`PancakeV2RwaanUsdOracle` averages the RWAAN/WBNB pair at
`0xA285059BBc89Fe9B43414D098318675462aaa3e6` and converts WBNB to USD through
Chainlink BNB/USD. `update()` is permissionless and must run at least once per
configured freshness window. A spot-reserve quote is deliberately not used:
it could be manipulated inside the same transaction that registers a member.

Production enforces a minimum two-hour TWAP. This blocks same-block and short
flash-loan price changes, but it does not make a thin DEX market unmanipulable:
an actor able to hold the RWAAN/WBNB price away from the wider market for the
entire averaging window can still influence the quote. Monitor the pair,
pause membership during abnormal liquidity/price events, and do not describe
the USD conversion as guaranteed. The user's `maximumPayment` limits their
token debit; it does not remove this market-wide oracle risk.

**Treasury** accumulates in `pendingTreasury` and is moved out only when an
address holding `TREASURY_ROLE` calls `withdrawTreasury(totalAmount)`. V2 sends
50% to `treasury` and 50% to `companyWallet`; for an odd token base-unit amount,
treasury receives the indivisible remainder. Admin may rotate either address,
but the contract prevents the two destinations from ever being identical.

**Accounting invariant** enforced throughout:

```
totalPoolPaid + totalTreasuryPaid == every fee ever pulled
pendingTreasury == totalTreasuryPaid − everything withdrawn
```

---

## 4. Tree mechanics

### 4.1 Placement, spillover and spillunder

Each member has two slots, Left and Right. When both are taken, new arrivals
**spill over** to the next free slot found by breadth-first search from the stage
root — filling level by level, left before right.

`findOpenSlot(anchor, stageId)` performs that search from whatever anchor you
give it. **The frontend should call `findPlacementSlot(sponsor, stageId)`
instead** — see §10.

```
Cycle 1 at stage 0 (6 slots, 2 levels):

              Root
             /    \
           M1      M2          ← level 1, direct
          /  \    /  \
        M3   M4  M5   M6       ← level 2, spillover

  6 placements → Root rolls over
```

**Spillover** and **spillunder** are the same event seen from two sides:

- From above: Root's slots were full, so M3–M6 *spilled over* down the tree.
- From below: M1 received M3 and M4 without recruiting them — *spillunder* — and
  was paid $5 for each. Root was paid for those two as well, since they landed on
  Root's board too.

This is measured, not asserted. In the 300-wallet run every member was sponsored
by the root, so nobody but the root recruited anyone. **140 members still earned,
and $20,300 of the $35,310 pool — 57% — went to people who recruited nobody.**

### 4.2 Rollover

`_propagateSlotFilled` increments `slotsFilledBelow` for each board a placement
lands on — the same `treeDepth` ancestors that were just paid. When a node
reaches `treeSlots`:

```solidity
mem.rolloverCount++;
mem.slotsFilledBelow = 0;
mem.left  = address(0);
mem.right = address(0);
emit Rollover(current, stageId, mem.rolloverCount);
```

The node starts a fresh tree and can earn again. Because BFS always finds the
root's newly cleared slots first, placement stays shallow indefinitely.

Rollover counts are exactly `placements ÷ treeSlots`, verified at every stage:

| Stage | Placements | Rollovers |
|---|---|---|
| 0 | 300 | 50 |
| 1 | 140 | 10 |
| 2 | 70 | 5 |
| 3 | 42 | 3 |
| 4 | 28 | 2 |

### 4.3 Detached boards and the cycle guard

After a rollover the board owner's child pointers are cleared, but the children
keep their historical upward `parent` link. That one-way edge is a **board
boundary**: the detached subtree remains a valid independent board, while the
former ancestor is no longer part of it.

`cycleGuardEnabled` (default **off**) makes `_verifyCyclePath` walk upward from
the proposed parent. It accepts either a parentless root or the first stale
rollover edge as a valid endpoint. An intact path that does not reach either
endpoint within `MAX_LIVE_PATH` (256 links) is rejected with
`ParentPathTooDeep` rather than assumed safe:

```solidity
if (parMem.left != current && parMem.right != current) {
    return (true, address(0), false); // independent board boundary
}
```

Reward and slot propagation stop at that same stale link. Members inside the
detached board can therefore keep earning and rolling, but cannot pay, credit or
roll the former ancestor. The guard adds bounded path-validation gas and still
rejects actual reciprocal cycles and over-deep intact paths.

### 4.4 Stage progression

To join stage N you must already be enrolled at stage N−1. Enforced by
`PreviousStageRequired`.

Each stage needs a tree root, established by an operator calling
`enrollStageRoot(member, stageId)` — no fee, no parent. Everyone else pays and
places normally.

> **`enrollStageRoot` is a real operator privilege, not a formality.** It is not
> restricted to the system root: any registered member who has completed the
> previous stage can be enrolled by it, and a stage may have several roots each
> owning an independent board. The enrolled member **skips that stage's fee
> entirely** — $7,260 across stages 1–5 — and still earns from everyone placed
> beneath them. This is how a stage gets seeded, so it is deliberate, but it
> means `OPERATOR_ROLE` can mint fee-free positions. Hold it on a key you trust
> as much as admin, and prefer a multisig.

---

## 5. Physical awards

`grantPhysicalAward(member, stageId, amount)` pays a bonus to a member who has
reached `rolloversForAward` at that stage. It requires `OPERATOR_ROLE`, is
repeatable at each completed milestone, and records every grant in
`awardRecords`. The configured schedule is `[0, 10, 10, 10, 10, 8]`: no award
for the $20 stage, every 10 rollovers from $60 through $1,620, and every 8
rollovers at $4,860.

Stage 0 has `rolloversForAward = 0`, which disables awards there entirely —
attempting one reverts `InvalidStage`.

**Award cap.** Every award is capped at `(stageEarnings × awardCapBps) / 10,000`
— the member can never receive more than a configured percentage of what they
actually earned at that stage. The default is 100% (10,000 bps). Admin can
tighten this with `setAwardCapBps(newCapBps)`, hard-capped at 10,000 (100%).

This makes self-farming **structurally unprofitable**: a farmer who funds their
own board earns back a fraction of what they spent, so their max award (100% of
earnings) is always less than the cost of faking the board. At the new $60-stage
threshold, the controlled cluster pays $11,200 in fees and remains down
**$5,240** after all in-cluster rewards and the maximum $1,400 award.

A genuine member's economics are the opposite: they pay one join fee and their
downline funds itself, so even with the cap they end far ahead ($80 cost →
$2,800 gain).

> The operator gate remains the primary defence — neither a farmer nor their
> puppets can trigger their own payout. The cap is a structural backstop that
> makes the economics unfavourable even if the operator errs.

---

## 6. Admin controls

Everything below is runtime-adjustable. Because the contract is not upgradeable,
these are how you retune the system after launch.

| Control | Function | Effect |
|---|---|---|
| Fee & upline split | `updateStageFee(stageId, newFee, newNodeReward)` | Applies to the next join. Requires `treeDepth × nodeReward < fee`. |
| Award threshold | `updateAwardThreshold(stageId, n)` | Rollovers required for an award at that stage. |
| Award cap | `setAwardCapBps(newCapBps)` | Max award = `stageEarnings × capBps / 10,000`. Hard-capped at 10,000 (100%). |
| Open / close a stage | `setStageOpen(stageId, open)` | Closed stages reject joins with `StageClosed`. |
| Cycle guard | `setCycleGuardEnabled(bool)` | Section 4.3. |
| Treasury address | `setTreasury(address)` | Receives 50% of each V2 withdrawal. |
| Company wallet | `setCompanyWallet(address)` | Receives the other 50%; cannot equal treasury. |
| Emergency stop | `pause()` / `unpause()` | `PAUSER_ROLE`. Blocks `register`, `joinStage`, `withdrawTreasury` and `grantPhysicalAward` — money stops moving in **and** out. |

Changing the stage-1 pool share from $10 to $15, for example:

```solidity
membership.updateStageFee(1, 60 ether, 15 ether);
// now $15 to the upline, $45 to treasury
```

Existing members are unaffected — they already paid at the old rate.

---

## 7. Roles

Built on OpenZeppelin `AccessControlDefaultAdminRules`, so admin transfer is
two-step and time-delayed by the `_adminDelay` constructor argument.

That delay applies only to transferring `DEFAULT_ADMIN_ROLE`; it does **not**
timelock calls made by the current admin. While admin remains an EOA there is no
runtime timelock, so use a dedicated hardware wallet and active monitoring.

| Role | Powers |
|---|---|
| `DEFAULT_ADMIN_ROLE` | `configureStages`, all six admin controls, role grants |
| `OPERATOR_ROLE` | `enrollStageRoot`, `grantPhysicalAward` |
| `TREASURY_ROLE` | `withdrawTreasury` |
| `PAUSER_ROLE` | `pause`, `unpause` |

The selected launch policy permanently uses one shared EOA for deployment,
admin, operator and pauser, with a 10-minute admin-transfer acceptance delay.
Treasury and the immutable economic root remain separate. This concentrates
control and makes compromise of that one key sufficient to administer, seed and
pause the protocol; see [SECURITY-NOTES §8](./SECURITY-NOTES.md#8-not-covered-by-this-work).

---

## 8. Function reference

### User-facing

| Function | Description |
|---|---|
| `register(address(0), address(0), Side.None)` | Free registration for the immutable designated root only. Paid V2 callers are rejected by this legacy ABI. |
| `registerWithMaxPayment(sponsor, parent, side, maximumPayment, deadline)` | Join stage 0 with an on-chain cap on the RWAAN debit and expiry time. |
| `joinStageWithMaxPayment(stageId, parent, side, maximumPayment, deadline)` | Join stage 1–5 with an on-chain cap and expiry time. Requires enrollment in the previous stage. |

### Views (no indexer needed)

| Function | Returns |
|---|---|
| `findPlacementSlot(sponsor, stageId)` | `(parent, side)` — **use this for placement.** Sponsor-first with automatic fallback to the stage anchor. Never returns a zero parent. |
| `findSponsorSlot(sponsor, stageId)` | `(parent, side)` — raw sponsor-chain lookup. Reverts `SponsorChainExhausted` if no ancestor is enrolled; returns a zero parent if the board is full. Low-level. |
| `findOpenSlot(anchor, stageId)` | `(parent, side)` — raw BFS from a given anchor. Low-level. |
| `stageAnchor(stageId)` | The stage's permanent fallback board (first root seeded there) |
| `isSlotAvailable(parent, stageId, side)` | Whether one specific slot is free |
| `getMember(address)` | `active`, `sponsor`, `joinedAt`, `totalEarned` |
| `getStageMembership(address, stageId)` | Full per-stage struct |
| `getTreeInfo(address, stageId)` | `left`, `right`, `slotsFilledBelow`, `rolloverCount`, `awardClaimed`, `stageEarnings` |
| `getStageConfig(stageId)` | Fee, nodeReward, treeSlots, treeDepth, rolloversForAward |
| `getCurrentWeekSponsorCount(address)` | This week's sponsor count |
| `getAwardRecordCount()` | Number of awards granted |
| `memberCount()`, `pendingTreasury()`, `totalPoolPaid()`, `totalTreasuryPaid()` | Global counters |

### Admin

`configureStages` (one-time), `enrollStageRoot`, `grantPhysicalAward`,
`withdrawTreasury`, `setTreasury`, `setCompanyWallet`, `updateStageFee`, `updateAwardThreshold`,
`setAwardCapBps`, `setStageOpen`, `setCycleGuardEnabled`, `pause`, `unpause`.

### Events

| Event | Emitted when |
|---|---|
| `MemberRegistered(member, sponsor, memberId)` | New member joins |
| `StageJoined(member, stageId, parent, side, fee)` | Any stage enrollment |
| `NodeRewardPaid(recipient, fromMember, stageId, amount)` | Upline paid |
| `Rollover(member, stageId, rolloverCount)` | A tree completes |
| `PhysicalAwardGranted(member, stageId, amount, recordIndex)` | Award granted |
| `TreasuryWithdrawn(to, amount)` | Treasury half of a V2 withdrawal |
| `CompanyProfitWithdrawn(companyWallet, amount)` | Company half of a V2 withdrawal |
| `TreasuryWithdrawalSplit(totalAmount, treasuryAmount, companyAmount)` | Full V2 50/50 split reconciliation |
| `AwardCapUpdated(oldCapBps, newCapBps)` | Award cap changed |
| `StageFeeUpdated`, `AwardThresholdUpdated`, `StageToggled`, `CycleGuardToggled`, `TreasuryAddressUpdated`, `StagesConfigured` | Admin changes |

---

## 9. Gas profile

Measured on the integration suite. Comfortable on BSC.

| Operation | Min | Avg | Max |
|---|---|---|---|
| `register` | 29,352 | 257,612 | 375,309 |
| `joinStage` | 29,343 | 234,643 | 283,680 |
| `findOpenSlot` (view) | 8,033 | 16,467 | 41,842 |
| `enrollStageRoot` | — | 67,862 | — |
| `grantPhysicalAward` | 36,208 | 110,375 | 184,543 |
| `configureStages` (once) | — | 701,770 | — |

**Legacy V1 deployment measurement:** 4,150,137 gas. Current V2 runtime is
20,571 bytes, leaving 4,005 bytes below the 24,576-byte EIP-170 limit.

Paying the whole board costs roughly 7% more on `register` and 19% on
`joinStage` than paying one upline did.

**Payout and slot-propagation gas per join is constant.** Those two walks are
capped at `treeDepth`: 192,976 gas at chain depth 50 versus 193,188 at depth
250 in the adversarial run. The optional cycle guard checks the reciprocal path
until a root or independent board boundary, so its cost grows with depth but is
hard-capped at 256 links; the
measured guarded boundary join used 385,585 gas and the next over-deep parent
was rejected. Regression-tested; see
[FINDING-1 (resolved)](./SECURITY-NOTES.md#5-finding-1--unbounded-walk-gas-growth--resolved).

---

## 10. Frontend integration

A user dashboard needs **no backend**. Everything below reads straight from chain:

- Earnings, stage status, rollover counts → `getMember`, `getStageMembership`
- Tree view → walk `getTreeInfo` left/right
- Where to place a new member → `findPlacementSlot`
- Award eligibility and milestones → `getAwardInfo`
- USD stage config → `getStageConfig`
- Current RWAAN fee/reward/price → `quoteStagePayment`
- Treasury and totals → `pendingTreasury`, `totalPoolPaid`, `memberCount`

### RPC budget and caching

The included frontend does not poll contract state in the background. Nearby
reads are combined through Multicall3, identical reads are deduplicated, and
member/board/price/configuration data uses moderate, volatility-specific cache
windows.
Price and placement are refreshed exactly once immediately before a paid action;
transaction receipts poll every eight seconds only while a transaction is
pending.

Upline transfers, treasury allocation, spillover, spillunder and rollover all
execute inside the single registration transaction—they do not generate one
frontend RPC call per payment or tree position. The full policy and provider
operating guidance are in [`web/RPC-BUDGET.md`](./web/RPC-BUDGET.md).

### Placement: use `findPlacementSlot`

**This is the single most consequential integration decision in the system.**

Anchoring every placement at the global root looks harmless and is not. Rollover
clears a board owner's child pointers, and BFS from the root then refills the
root's own slots, permanently detaching the members it just dropped. Measured
over 1,000 stage-0 wallets:

| | `findOpenSlot(root, 0)` | `findSponsorSlot(sponsor, 0)` |
|---|---|---|
| Root's share of the pool | **60%** | **0%** |
| Members who earned $0 | **667 of 1,000** | 500 of 1,000 |
| Members reaching the $30 board | **0** | **249** |
| Best non-root member | **$10** (net loss on a $20 join) | **$30** (the plan's figure) |
| Total paid to members | $8,330 | **$9,995** |

Under root-anchored placement the compensation plan does not pay as designed:
no ordinary member ever reaches the $30 the plan promises. Under sponsor-first
placement they do. Both rows are reproduced by
`test_Stress1000_EarningsDistribution` and
`test_SponsorSlot_FixesRootCaptureAt1000Wallets`.

Registration flow:

```
1. quoteStagePayment(stage)                     → (RWAAN fee, reward, price, updatedAt)
2. approve(membershipAddress, RWAAN fee)         on RWAAN
3. findPlacementSlot(sponsorAddress, stage)      → (parent, side)
4. registerWithMaxPayment(sponsor, parent, side, quotedFee, deadline)
   // use joinStageWithMaxPayment for stage > 0
```

Approve and pass the exact quoted fee as `maximumPayment`, together with a short
deadline. If the RWAAN price falls before execution and more tokens would be
required, the contract reverts with `PaymentExceedsMaximum`; an unlimited
allowance cannot bypass this cap. A transaction pending beyond its deadline
reverts with `TransactionExpired` instead of executing unexpectedly later.

**Use `findPlacementSlot`. It is the whole integration.** It never returns a
zero parent and needs no fallback logic, no try/catch, and no off-chain
knowledge of which member was seeded as a stage root.

It exists because the lower-level `findSponsorSlot` has two failure modes that
are routine rather than exceptional, and handling either one wrongly breaks
placement:

| Condition | `findSponsorSlot` | `findPlacementSlot` |
|---|---|---|
| Nobody in the sponsor chain has reached this stage | **reverts** `SponsorChainExhausted` — **the common case at stages 2+**, since members routinely climb before their upline | falls back to the stage anchor |
| The board it lands on is full | **returns** `(address(0), Side.None)`; passing that to `register` fails with the unhelpful `ParentNotInStage(address(0))` | continues up the lineage, then the anchor |

`findPlacementSlot` walks the sponsor chain and takes the first enrolled
ancestor **with room**, so a recruit stays inside their own upline wherever
possible, and only falls back to the stage's anchor board when the whole chain
is exhausted or full.

**Anchors are on-chain.** `stageAnchor(stageId)` records the first root seeded
at each stage and never moves, so the fallback target is not something the
frontend has to track. Stage 0's anchor is the system root.

Its only reverts are genuinely exceptional: `StageAnchorNotSet` (the stage was
never seeded — an operator step was missed) and `NoPlacementAvailable`.

`findSponsorSlot` and `findOpenSlot` remain available for custom placement
logic, but a normal integration should not need them.

The 700-wallet run in `test/BinaryMembershipV1Stress700.t.sol` places all 1,299
members across four stages through `findPlacementSlot` alone — 929 of them
landing somewhere other than the sponsor's own two slots — and produces figures
identical to the hand-rolled fallback it replaced.

Between the placement query and execution another transaction may take the slot, reverting with
`SlotOccupied`. Re-query and retry — this is expected under load, not a bug.

---

## 11. Indexer requirements

**No indexer needed for:** user dashboards, tree views, placement, earnings
totals, stage config, treasury balances.

**An indexer is required for:** listing all members, "my referrals", activity
feeds, earnings history over time, all-time leaderboards, member search,
analytics. There is no on-chain array of members, so these cannot be derived
without replaying events.

Four events are sufficient: `MemberRegistered`, `StageJoined`, `NodeRewardPaid`,
`Rollover`.

> **`NodeRewardPaid` fires up to `treeDepth` times per join** — once per upline
> paid, not once per join. An indexer that assumes one event per placement will
> undercount earnings.

Run it as a long-lived process — a serverless function will drop the connection
and miss blocks. If the database is lost it must replay from the deployment
block.

---

## 12. Deployment

Deploy `script/DeployRwaanOracle.s.sol` first, wait one full TWAP period, and
call `updateFromEnv()`. Then use `script/DeployBscMainnet.s.sol` on chain 56.
It pins RWAAN, the initialized oracle, a maximum price age, the CREATE2 salt,
the independently predicted address, the company wallet, and the reviewed role manifest.
The selected policy uses the
same deployer/admin/operator/pauser EOA through the explicit
`ALLOW_EOA_ROLES=true` and `ALLOW_SHARED_CONTROL_ADDRESS=true` opt-outs;
treasury, company and root remain separate economic destinations. The manifest
prevents the company wallet, post-deploy operator or pauser from drifting
between prediction and the Safe batch. Do not
adapt the testnet deploy script.

`BinaryMembershipV2BscFork.t.sol` runs against the live RWAAN token, Pancake
pair and Chainlink feed and proves the real wallet → membership → upline
transfer path is not taxed.

```solidity
new BinaryMembershipV2(
    IERC20Metadata(rwaan),
    priceOracle,
    10800,              // maximum accepted oracle age
    treasuryAddress,
    companyWallet,      // receives 50% of each treasury withdrawal
    controlWallet,     // also deployer, operator and pauser under selected policy
    600,               // 10-minute admin-transfer acceptance delay
    rootWallet         // the ONLY address that may take the root position
);
```

`rootWallet` is immutable and cannot be changed after deployment. It exists
because the root position pays no fee and sits above every board — the
1,000-wallet run measured it capturing 60% of the stage-0 pool. Without the
pin, `register` would award it to whoever transacted first, and the gap
between deployment and your root's transaction would be open to front-running.
Get this argument right; there is no setter.

After the deploy-only transaction, use `script/ConfigureBscMainnet.s.sol` to
generate the exact five admin calls. While admin is an EOA, submit them from
that wallet in the printed order and do not permit member registration until
verification passes:

1. `grantRole(OPERATOR_ROLE, operator)`
2. `grantRole(TREASURY_ROLE, treasuryOps)`
3. `grantRole(PAUSER_ROLE, pauser)`
4. `setCycleGuardEnabled(true)`
5. `configureStages(fees, nodeRewards, treeSlots, treeDepths, rolloversForAward)`
   — **one-time and irreversible**

Run `ConfigureBscMainnet.verify()` before any member joins. Then the root member
calls `register(address(0), address(0), Side.None)` and the operator seeds stage
roots. Do not raw-transfer award funds into the contract; use accumulated fees
or `fundTreasury()` so the accounting liability is updated.

Full pre-launch checklist: [SECURITY-NOTES §7](./SECURITY-NOTES.md#7-pre-deployment-checklist).

The public BNB Smart Chain Testnet rehearsal is documented in
[`BSC-TESTNET-RUNBOOK.md`](./BSC-TESTNET-RUNBOOK.md).

---

## 13. Testing

```bash
forge test                  # 202 tests across 32 suites
forge test -vv              # with narrated output
forge test --gas-report
```

| Suite | Tests | Covers |
|---|---|---|
| `BinaryMembershipV1.t.sol` | 32 | Units, admin controls, access control, client award schedule |
| `BinaryMembershipV1SpecConformance.t.sol` | 7 | **Plan numbers as hardcoded constants** — fails if payouts drift from the compensation plan |
| `BinaryMembershipV1Fuzz.t.sol` | 8 | Properties, 1,000 runs each |
| `BinaryMembershipV1Invariant.t.sol` | 5 | 256,000 calls per invariant |
| `BinaryMembershipV1Integration.t.sol` | 10 | 100 wallets, 3 stages |
| `BinaryMembershipV1Visual.t.sol` | 1 | Narrated walkthrough — run with `-vv` |
| `BinaryMembershipV1Stress300.t.sol` | 4 | 300 wallets, stages 0–4, adversarial probes |
| `BinaryMembershipV1Adversarial.t.sol` | 7 | Manual placement, deep chains, gas-flatness guards |
| `BinaryMembershipV1AwardFarming.t.sol` | 5 | Award farming economics + cap enforcement |
| `BinaryMembershipV1ClaimProbe.t.sol` | 4 | Reproductions/regressions for the four logic defects |
| `BinaryMembershipV1Stress2000Audit.t.sol` | 8 | 2,000-wallet baseline + 3,000-wallet guarded mixed-sponsor full ladder + award-stage boundaries |
| `BinaryMembershipV1GuardOnLaunch.t.sol` | 3 | Cycle guard behavior when enabled before launch |
| `BinaryMembershipV1AwardThreshold.t.sol` | 5 | Live admin threshold increases, reductions, disablement and cap interaction |
| `BinaryMembershipV1BscCampaign.t.sol` | 3 | 18-decimal BEP-20 campaign guards, 100-wallet checkpoint + 140-wallet award extension |
| `BinaryMembershipV2Price.t.sol` | 13 | Live-price conversion, bounded/deadline-limited payments, rounding, accounting and stale/future/zero-price rejection |
| `BinaryMembershipV2Stress2000.t.sol` | 1 | 2,000 wallets across all six stages while the RWAAN/USD price changes on every entry |
| `BinaryMembershipV2Stress350Rwaan.t.sol` | 2 | 350- and 500-wallet campaigns across stages 0-4 with moving RWAAN prices, rejected moved-price quotes, treasury, rollovers, spillover and spillunder |
| `BinaryMembershipV2TreasurySplit.t.sol` | 8 | Exact 50/50 distribution, odd-unit rounding, access control, pause/solvency checks and collision-safe wallet rotation |
| `PancakeV2RwaanUsdOracle.t.sol` | 8 | TWAP arithmetic, same-block manipulation resistance, Chainlink conversion and oracle failure paths |
| `BinaryMembershipV2BscFork.t.sol` | 1 | Live BSC RWAAN/pair/feed compatibility and untaxed registration transfer |
| `BinaryMembershipV1UnseededInvariant.t.sol` | 4 | No-prefund award/treasury solvency invariants |
| `BinaryMembershipV1MainnetDeployGuards.t.sol` | 19 | Chain, company-wallet separation, 10-minute delay, exact shared-control/Safe policies, fixed salt, expected address and role-manifest guards |
| `RwaanOracleMainnetDeployGuardsTest` | 3 | Two-hour TWAP production floor and timing-window configuration guards |
| `BinaryMembershipV1MainnetConfiguration.t.sol` | 4 | Atomic Safe batch generation and exact post-configuration verification |
| `BinaryMembershipV1LastInCohort.t.sol` | 3 | Last-position payment paths, join-order earnings and system-wide fee split |
| `BinaryMembershipV1Stress350Treasury.t.sol` | 1 | 350 wallets across all stages, spillover/spillunder, rollovers, awards and treasury reconciliation |
| `BinaryMembershipV1Stress350DistinctRoots.t.sol` | 1 | Six split cohorts, distinct fee-free protocol roots and one global treasury |
| `BinaryMembershipV1Stress350PayingLeaders.t.sol` | 1 | Six paying community leaders; proves detached boards keep cycling to award eligibility |

Static analysis and fuzzing commands are in
[SECURITY-NOTES §8](./SECURITY-NOTES.md#8-reproducing-these-results).

---

## 14. Design decisions

**Every upline on the board is paid, capped at `treeDepth`.** This is what the
compensation plan specifies: the plan marks the node amount on all 6 stage-0
positions and all 14 stage-1 positions, totals only reachable if each placement
pays every upline whose board it lands on.

An earlier revision of this contract paid **only the direct parent**, and this
section previously defended that by claiming paying every upline was "not
solvent — a full 6-slot tree would owe $50 from $30 of collected pool." **That
argument was wrong and circular.** The $30 was `6 joins x the $5 the flawed
design set aside`, not the money collected. Six joins collect **$120**; paying
$50 leaves $70 for treasury. Paying every upline is comfortably solvent — 34–42%
of revenue at every stage — and the old model underpaid board owners 3x at
stage 0 and 7x at stage 1. See
[SECURITY-NOTES §2](./SECURITY-NOTES.md#2-defect-1--the-contract-did-not-implement-the-compensation-plan).

The cap at `treeDepth` is what keeps it solvent and bounded: a member more than
`treeDepth` levels above a placement is not on its board and is not paid, so a
single join can never owe more than `treeDepth * nodeReward` — enforced below
the fee at config time and on every runtime change.

**Push payments, not claims.** Rewards transfer inside the join transaction.
Users never claim, and the contract never holds unpaid member balances.

**Not upgradeable.** A deliberate trade. The six admin controls cover the
adjustments a live system realistically needs — fees, splits, award thresholds,
stage availability — without a proxy's added risk. The cost is that a genuine bug
means redeploying and migrating.

**Cycle guard off by default.** Accounting holds regardless of tree shape, so
the guard is an optional integrity constraint rather than a safety requirement.
It costs gas on every join; enable it to reject cyclic or over-deep intact
parent paths. A stale rollover edge is intentionally accepted as an independent
board boundary.

**`treeDepth` defines the economic board.** It caps who gets paid and whose slot
counters advance. The cycle guard uses the separate `MAX_LIVE_PATH` bound to
detect reciprocal cycles and gas-hostile paths. A stale parent link is not
traversed: it terminates both economics and liveness at the new board boundary.

**Fee-on-transfer tokens are rejected.** `_pullExact` compares balances before
and after and reverts `TransferAmountMismatch` on any shortfall, rather than
silently under-collecting.

---

## Licence

MIT
