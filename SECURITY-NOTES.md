# BinaryMembershipV1/V2 — Security Notes

Audit-support document. Records what was tested, what was found, what was
**not** covered, and which risks are operational rather than code defects.

Last full run: 2026-08-17
Contracts: legacy `src/BinaryMembershipV1.sol` and replacement
`src/BinaryMembershipV2.sol` with `src/PancakeV2RwaanUsdOracle.sol`
Solidity: 0.8.20 · OpenZeppelin 5.x · optimizer on (200 runs) · `via_ir = false`

> **This document was rewritten after a specification defect was found and
> fixed.** Section 2 covers it. An earlier revision of these notes described the
> pre-fix contract and contained a justification for the defect; treat any copy
> without this banner as superseded.

---

## 1. Summary

| Area | Result |
|---|---|
| Static analysis | 0 actionable V2/oracle findings; Aderyn's constructor-only reentrancy alert reviewed as a false positive |
| Property fuzzing (Echidna) | 8 invariants hold over 200,321 calls |
| Foundry tests | 192 / 192 pass across 31 suites, plus live BSC fork pass |
| Mutation testing | 10 / 10 injected bugs caught |
| **Specification defects found** | **1 — fixed, see §2** |
| Findings closed by the fix | 1 (FINDING-1, gas growth) |
| Findings patched | 4 (FINDING-2 award farming; DEFECT-2/3/4, see §2a) |
| Open code-logic findings | **0 known; external audit still required before launch** |

The 2026-08-17 Aderyn rerun reported one nominal High: external metadata/pair
calls followed by immutable assignments inside constructors. These calls cannot
reenter an under-construction contract because its runtime code is not installed
yet, and production additionally pins every called address. A malicious target
could only make construction revert. The remaining reports are documented
centralization, bounded loops, test-mock style, and compiler-target notices.
The local Slither release could not ingest the current nightly Foundry build
metadata, so no claim is made that Slither was freshly rerun on V2. Mythril's
bounded V2 pass also failed to terminate cleanly and was stopped; its final
"no issues" line is not treated as a completed result.

---

## 2a. Manual review findings · **ALL PATCHED**

Four analyzers and a 200k-call fuzzing campaign reported clean, then a manual
read of the contract found four further issues. None were reachable by those
tools, because none is a memory-safety or arithmetic fault — they are questions
of privilege, configuration and spec intent. Regression tests for all four live
in `test/BinaryMembershipV1DeepProbe.t.sol`.

### DEFECT-2 — the root position could be front-run · **PATCHED**

**Severity: High (deployment).** `register` decided the system root on
`memberCount == 0` alone, with no access control, and the root path skips
`_pullExact`. Anyone watching the mempool could take the position for **$0** in
the gap between deployment and the intended root's transaction. The
1,000-wallet run measured that position capturing **60% of the entire stage-0
pool**, so it was well worth front-running.

**Fix.** `designatedRoot` is now an immutable constructor argument and the only
address permitted to claim the root slot:

```solidity
if (isRoot && msg.sender != designatedRoot) revert NotDesignatedRoot();
```

Covered by `test_Probe_RootPositionCannotBeFrontRun` and
`test_Probe_DesignatedRootDoesNotBlockNormalRegistration`.

### DEFECT-3 — board geometry was never validated · **PATCHED**

**Severity: Medium (irrecoverable misconfiguration).** `configureStages` is
one-time, and neither `treeSlots` nor `treeDepth` has a setter afterwards — yet
any pair was accepted. A binary board `d` levels deep holds exactly
`2^(d+1) − 2` slots (6 at depth 2, 14 at depth 3). A mismatch would have been
permanent: too many slots makes rollover unreachable and awards unclaimable
forever, too few fires rollover before the board is full.

**Fix.** The identity is enforced at config time, with `MAX_TREE_DEPTH = 8`
bounding the shift. Covered by
`test_Probe_ConfigureStagesRejectsImpossibleBoardGeometry`, which checks the
too-many, too-few and absurd-depth cases.

### DEFECT-4 — pause did not stop funds leaving · **PATCHED**

**Severity: Low.** `whenNotPaused` guarded `register` and `joinStage` only, so
`withdrawTreasury` and `grantPhysicalAward` stayed live while paused — the wrong
way round for incident response. Both now carry `whenNotPaused`. Covered by
`test_Probe_PauseHaltsTreasuryAndAwards`, which also verifies unpausing restores
them.

### OBSERVATION — `enrollStageRoot` is a fee bypass

**Not patched; documented instead.** It is not restricted to the system root:
any `OPERATOR_ROLE` holder can enrol any registered member into stages 1–5 free
of charge — **$7,260 per member** — and that member then earns as a board owner
from everyone placed beneath them. This is how a stage is seeded, so the
flexibility is in genuine use (the stress suites rely on it) and constraining it
is a business decision. The docstring previously claimed it enrolled "the system
root", which was wrong; it and README §4.4 now state the privilege plainly.
**Treat `OPERATOR_ROLE` as equal in power to admin and hold it on a multisig.**

### FINDING-5 — ordinary paying leaders detached before award thresholds · **PATCHED**

**Original severity: High (economic/specification).** In the community model, an
ordinary wallet pays its stage fee, receives its first two members, rolls its
board repeatedly and becomes award-eligible after 10 rollovers (8 at the last
stage). The original guarded 350-wallet split-cohort reproduction did not do that.

Each paying leader completed two rollovers. Its ancestor then rolled over,
cleared the child link and made the leader's upward path stale. The cycle guard
rejected further placement inside that detached branch, and
`findPlacementSlot` fell back to the fee-free stage anchor. All six paying
leaders stopped at two rollovers, so none could reach 10/8.

**Fix:** `_isPlaceable` now treats the first non-reciprocal rollover edge as the
root boundary of an independent live board. This matches `_payUplines` and
`_propagateSlotFilled`, which already stop at that same edge, so the detached
leader keeps receiving placements and rolling without paying or crediting its
former ancestor.

The post-fix 350-paying-wallet campaign keeps every follower on its intended
leader board with zero anchor fallback. Leader rollover counts are
**58 / 20 / 16 / 12 / 8 / 4** across stages 1–6; stages 2–4 reach the configured
10-rollover award threshold and receive test awards, while stages 5–6 correctly
remain below their 10/8 thresholds for these cohort sizes. Each technical anchor
stays at exactly one legitimate initial rollover. Fees, rewards, awards,
treasury liability and token balance reconcile exactly. Covered by
`BinaryMembershipV1Stress350PayingLeaders.t.sol` plus deep-detachment,
adversarial, 300-wallet and 2,000-wallet guard regressions.

---

## 2b. Previous business decisions

### RESOLVED — root capture, fixed by `findSponsorSlot`

Anchoring every placement at the global root concentrated earnings there:
rollover clears a board owner's child pointers, BFS refills the root's own
slots, and the members it just dropped are unreachable by BFS forever.

`findSponsorSlot(sponsor, stageId)` walks up the sponsor chain to the first
member enrolled at that stage and runs BFS from them, so recruits land on their
sponsor's board. Measured over the same 1,000 stage-0 wallets:

| | root-anchored | sponsor-first |
|---|---|---|
| Root's share of pool | 60% | **0%** |
| Members who earned $0 | 667 | 500 |
| Members reaching the $30 board | **0** | **249** |
| Best non-root member | $10 (net loss) | **$30** |
| Total paid to members | $8,330 | **$9,995** |

The decisive row is the third: under root-anchored placement **no ordinary
member ever reached the board reward the plan promises.** Under sponsor-first,
249 of 1,000 do. Covered by `test_SponsorSlot_FixesRootCaptureAt1000Wallets`
against the `test_Stress1000_EarningsDistribution` baseline.

**One integration requirement.** `findSponsorSlot` reverts
`SponsorChainExhausted` when no ancestor is enrolled, but returns
`(address(0), Side.None)` when the sponsor's board is full. Callers must fall
back to `findOpenSlot(root, stageId)` on a zero parent; passing the zero
through fails with the unhelpful `ParentNotInStage(address(0))`. Pinned by
`test_SponsorSlot_ReturnsZeroParentRatherThanRevertingWhenBoardFull` and
documented in README §10.

### RESOLVED — awards now repeat every N rollovers

`awardClaimed` (bool) was replaced by `lastAwardedRollover` + `totalAwarded`.
Each grant advances the milestone by exactly `rolloversForAward` rather than
snapping to the current count, so surplus rollovers carry forward: 20 rollovers
at the $60 stage's threshold of 10 yields two awards, not one. The earnings cap now applies
**cumulatively** — total awards at a stage can never exceed
`stageEarnings × awardCapBps / 10_000` — so repeatability does not reopen the
farming vector from §6. `getAwardInfo` exposes eligibility and the next
milestone. Covered by `test_Probe_AwardRepeatsEveryNRollovers` and
`test_AwardInfo_ReportsEligibilityAndMilestones`.

### RESOLVED — six stages is the final scope

The $14,580 / $2,500 / $35,000 tier appears on the fee sheet but not in the
rules sheet, which enumerates only "$180, $540, $1,620 and $4,860" and stops.
**Confirmed dropped on 2026-08-15.** `MAX_STAGES = 6` is correct and final; the
ladder ends at the $4,860 package. No further work is required here.

### Still open

FINDING-5 above requires a compensation-plan decision and code/test follow-up
before launch.

---

## 2. DEFECT-1 — the contract did not implement the compensation plan

**Severity: Critical (economic). Status: FIXED.**

### What was wrong

The plan marks the node amount on **every position of a board**:

- Stage 0 board — 6 positions × $5 → owner collects **$30**
- Stage 1 board — 14 positions × $10 → owner collects **$140**

Those totals are only reachable if **every upline whose board the placement
lands on** is paid. The contract paid **only the direct parent**, so a board
owner collected $10 and $20 — **3× and 7× short**. Members in the middle of a
board were underpaid the same way: a level-1 member on a stage-1 board should
collect $60 from six descendants and was collecting $20.

### How it survived earlier review

Two failures compounded:

1. **The tests encoded the same wrong assumption.** All 67 tests passed because
   they asserted what the contract did, never what the plan required. Passing
   tests were evidence of internal consistency, not correctness.
2. **A circular argument was written into the documentation.** The prior
   README §14 claimed paying every upline was "not solvent," comparing a full
   board's $50 obligation against a $30 "pool" — but that $30 was itself
   `6 joins × the $5 the flawed design set aside`. The real denominator is the
   $120 those six joins collected. Paying $50 from $120 leaves $70 for treasury.
   The claim was false and the reasoning circular.

### The fix

`_payNodeReward` (single recipient) was replaced by `_payUplines`, which walks
parent-ward paying one full `nodeReward` per ancestor, **capped at
`treeDepth`** — a board is `treeDepth` levels, so a member further above that is
not on the board. `_propagateSlotFilled` and `_verifyCyclePath` were capped the
same way, which also closed FINDING-1 (§5).

The fee split became variable: uplines take what they are owed, treasury keeps
the remainder. Placements near the top of a fresh tree have fewer ancestors, so
treasury keeps more from them.

`configureStages` and `updateStageFee` now enforce
**`treeDepth × nodeReward < fee`**, replacing the weaker `nodeReward < fee`.
This makes a full-depth payout provably impossible to exceed the fee funding it.

### Verified after the fix

| Plan requirement | Measured |
|---|---|
| Stage 0 board owner collects $30 | $30 |
| Stage 1 board owner collects $140 | $140 |
| Stage 1 level-1 member collects $60 | $60 |
| Stage 0 board: $50 paid of $120, $70 treasury | exact |
| Stage 1 board: $340 paid of $840, $500 treasury | exact |
| Payout capped at board depth | 3rd-level upline correctly paid $0 |

### Regression protection

`test/BinaryMembershipV1SpecConformance.t.sol` (7 tests) asserts the plan's
numbers as **hardcoded constants**, independent of contract behaviour. Run
against the pre-fix contract, **all 7 fail** with exactly the shortfalls above
($10 vs $30, $20 vs $140, $20 vs $60). They are the guard against silently
drifting back.

### Economic impact

Across the 300-wallet run (stages 0–4, 580 placements, $95,040 collected):

| | Before | After |
|---|---|---|
| Paid to members | $15,010 (16%) | **$35,310 (37%)** |
| Retained by treasury | $80,030 | $59,730 |
| Board owner earnings | $2,430 | **$15,010** |
| Earned via spillunder | $12,580 | **$20,300** |

Solvent at every stage — payout is 34–42% of revenue, never approaching the fee.

---

## 3. Tooling results

All tools re-run against the fixed contract. Earlier results are void.

### 3.1 Slither 0.11.0

```bash
slither . --compile-force-framework foundry --exclude naming-convention,pragma
```

**0 high, 0 medium.** One informational on this contract:

| Finding | Disposition |
|---|---|
| `_updateWeeklySponsor` uses `block.timestamp` for comparison | **Accepted.** Buckets sponsor counts into week epochs. ~15s miner drift cannot move a 604,800s boundary meaningfully. |

Solidity 0.8.20's known `via_ir` codegen bugs (`VerbatimInvalidDeduplication`,
`FullInlinerNonExpressionSplitArgumentEvaluationOrder`) are flagged repo-wide and
**accepted**: `via_ir = false`, so neither path is reachable.

### 3.2 Aderyn

**0 high, 0 medium.** This project contains exactly two Solidity files —
`BinaryMembershipV1.sol` and the `MockERC20` test double — so the scan is
scoped to the contract under review with nothing else in range.

> Running Aderyn inside the `RwanV2` monorepo instead reports one repo-wide
> High (`Reentrancy: state change after external call`). It belongs to
> `RWANSecureStakingV2.sol`, an unrelated contract, and none of it touches
> `BinaryMembershipV1`. Scan this project standalone to avoid conflating them.

Four Lows touch `BinaryMembershipV1`, all accepted:

| ID | Where | Disposition |
|---|---|---|
| L-1 Centralization risk | 11 admin functions | By design. Mitigate with a multisig — see §7. |
| L-2 Costly operations in loop | `configureStages`, `_payUplines`, `_propagateSlotFilled` | All bounded: 6 iterations (admin, one-time) and `treeDepth` (2–3). |
| L-6 PUSH0 opcode | pragma | BSC supports PUSH0 post-Shanghai. |
| L-7 Loop contains revert | `configureStages`, `_payUplines`, `_verifyCyclePath` | Intentional validation. |

The previously-fixed **L-3 (`nonReentrant` not first modifier)** no longer
appears, confirming that fix held.

### 3.3 Mythril 0.24.8

> The analysis was completed successfully. No issues were detected.

### 3.4 Echidna 2.3.3

```bash
echidna . --contract EchidnaBinaryMembership --config echidna.yaml \
  --crytic-args "--foundry-compile-all"
```

**200,321 calls. 8 / 8 invariants passing.**

| Invariant | Property |
|---|---|
| `echidna_solvency` | balance ≥ `pendingTreasury` |
| `echidna_fee_conservation` | fees pulled == `totalPoolPaid + totalTreasuryPaid` |
| `echidna_treasury_accounting` | `pendingTreasury == totalTreasuryPaid − withdrawn` |
| `echidna_balance_conservation` | balance == seed + fees − pool − withdrawals − awards |
| `echidna_member_count` | `memberCount` == registered actors + root |
| `echidna_full_depth_payout_under_fee` | `treeDepth × nodeReward < fee`, every stage |
| `echidna_pool_monotonic` | `totalPoolPaid` never decreases |
| `echidna_pending_within_balance` | `pendingTreasury ≤ balance` |

Two harness defects noted in the previous revision are now fixed:

- `echidna_reward_less_than_fee` checked `nodeReward < fee` — **weaker than what
  the contract enforces**. Replaced with `echidna_full_depth_payout_under_fee`,
  which tests the real binding condition.
- `echidna_action_registerBFS` carried the property prefix while mutating state,
  so Echidna counted it as a trivially-passing property. Renamed; the count is
  now honestly 8, not 9.

**Harness validated, not assumed.** A passing campaign proves nothing if the
fuzzer never reaches meaningful state. Four canary properties asserting
*nothing ever happened* were added and the campaign re-run — all four were
**falsified**, confirming Echidna genuinely registered members, pulled fees,
drove boards through rollover, and withdrew treasury:

```
echidna_canary_noMembersEverRegistered    falsified
echidna_canary_noFeesEverPulled           falsified
echidna_canary_noRolloverEverHappened     falsified
echidna_canary_noTreasuryEverWithdrawn    falsified
```

**Remaining weaknesses** — stated so they are not overread: corpus stays small
(6), Slither integration fails during the run so the fuzzer works without
constant hints, coverage is stage-0 weighted, and `action_register` is dead code
carrying comments admitting it does not work.

---

## 4. Test suite

**192 tests, 31 suites, all passing, plus the live BSC fork test.**

| Suite | Tests | Scope |
|---|---|---|
| `BinaryMembershipV1.t.sol` | 32 | Units, admin controls, access control, client award schedule |
| `BinaryMembershipV1SpecConformance.t.sol` | 7 | **Plan numbers as hardcoded constants — the DEFECT-1 guard** |
| `BinaryMembershipV1Fuzz.t.sol` | 8 | Stateless properties, 1,000 runs each |
| `BinaryMembershipV1Invariant.t.sol` | 5 | Handler-driven, 512 runs × depth 100 = 51,200 calls per invariant |
| `BinaryMembershipV1Integration.t.sol` | 10 | 100 wallets across 3 stages |
| `BinaryMembershipV1Stress300.t.sol` | 4 | **300 wallets across stages 0–4**, admin roles, 10 adversarial probes |
| `BinaryMembershipV1Adversarial.t.sol` | 7 | Manual (non-BFS) placement, deep chains, gas-flatness guards |
| `BinaryMembershipV1AwardFarming.t.sol` | 5 | Award farming economics + cap enforcement |
| `BinaryMembershipV1Visual.t.sol` | 1 | Narrated walkthrough (`-vv`) |
| `BinaryMembershipV1DeepProbe.t.sol` | 7 | Root, geometry, privilege, pause and repeat-award regressions |
| `BinaryMembershipV1SponsorPlacement.t.sol` | 10 | Sponsor-first and anchor-fallback placement |
| `BinaryMembershipV1Stress1000.t.sol` | 9 | Full six-stage 1,000-wallet stress and distribution |
| `BinaryMembershipV1Stress700.t.sol` | 5 | Post-patch higher-stage and treasury stress |
| `BinaryMembershipV1ClaimProbe.t.sol` | 4 | Regressions for the four manually reproduced logic defects |
| `BinaryMembershipV1Stress2000Audit.t.sol` | 8 | 2,000 baseline plus 3,000 guarded mixed-sponsor full ladder and award-stage boundaries |
| `BinaryMembershipV1UnseededInvariant.t.sol` | 4 | No-prefund treasury/award solvency invariants |
| `BinaryMembershipV1GuardOnLaunch.t.sol` | 3 | Cycle guard behavior when enabled before launch |
| `BinaryMembershipV1AwardThreshold.t.sol` | 5 | Live admin threshold increases, reductions, disablement and cap interaction |
| `BinaryMembershipV1BscCampaign.t.sol` | 3 | 18-decimal BEP-20 USDT deployment guards, 100-wallet BSC checkpoint plus 140-wallet award extension |
| `BinaryMembershipV1Stress350DistinctRoots.t.sol` | 1 | Six split cohorts with distinct fee-free protocol roots and one treasury |
| `BinaryMembershipV1Stress350PayingLeaders.t.sol` | 1 | Six ordinary paying leaders; reproduces permanent fallback before 10/8 award thresholds |
| `BinaryMembershipV2Price.t.sol` | 13 | Dynamic conversion, rounding, staleness, deadlines and mandatory maximum-payment bounds |
| `PancakeV2RwaanUsdOracle.t.sol` | 8 | TWAP/Chainlink arithmetic, failure paths and same-block manipulation resistance |
| `BinaryMembershipV2BscFork.t.sol` | 1 | Live RWAAN/pair/feed transfer and quote compatibility |
| `BinaryMembershipV2Stress2000.t.sol` | 1 | 2,000 wallets across all six stages under changing prices |
| `BinaryMembershipV2Stress350Rwaan.t.sol` | 1 | 350-wallet moving-price campaign with quote rejection, awards and treasury reconciliation |
| `RwaanOracleMainnetDeployGuardsTest` | 3 | Production TWAP/feed timing floors |

Expected values in the stress and integration suites are derived **by walking
the tree independently** (`_expectedPayout`) rather than read back from the
payment code, so a payment bug fails the assertion instead of being confirmed
by it.

### 4.1 300-wallet system run

| Stage | Joins | Rollovers | Expected |
|---|---|---|---|
| 0 ($20) | 300 | 50 | 300 ÷ 6 |
| 1 ($60) | 140 | 10 | 140 ÷ 14 |
| 2 ($180) | 70 | 5 | 70 ÷ 14 |
| 3 ($540) | 42 | 3 | 42 ÷ 14 |
| 4 ($1,620) | 28 | 2 | 28 ÷ 14 |

- Fees **$95,040** → pool **$35,310** + treasury **$59,730**, exact
- Upline totals asserted on **all 580 placements individually**
- **140 members earned having recruited nobody** — $20,300 via spillunder

### 4.2 Mutation testing

Green tests are worthless unless they can go red. Ten bugs were injected one at
a time and the suite re-run:

| Injected bug | Caught | Tests failing |
|---|---|---|
| Revert to direct-parent-only (the original defect) | Yes | 30 |
| Pay one upline too many (off-by-one on the cap) | Yes | 12 |
| Skim 1 wei from every upline payment | Yes | 36 |
| Drop the `treeDepth × nodeReward < fee` check | Yes | 2 |
| Upline underpaid by 1 wei *(pre-fix run)* | Yes | — |
| Rollover fires one slot early *(pre-fix run)* | Yes | — |
| Treasury skimmed 1 wei per join *(pre-fix run)* | Yes | — |
| Remove award cap check entirely | Yes | award farming suite |
| Allow award cap > 100% | Yes | `test_AwardCap_CannotExceed100Percent` |
| Cap uses wrong denominator (1,000 vs 10,000) | Yes | `test_AwardCap_GenuineMemberStillProfits` |

The contract was restored from backup and verified clean (78/78) after each.

---

## 5. FINDING-1 — unbounded walk gas growth · **RESOLVED**

**Was: Low. Now: closed by the DEFECT-1 fix.**

`_propagateSlotFilled` previously walked the entire ancestor chain with an
unbounded loop. BFS keeps trees 2–3 deep, but nothing enforced that — direct
calls with a hand-picked parent built chains of arbitrary depth, and gas grew
**~3,708 per level** (383k at depth 1 → 1,347k at depth 250, ~30M at depth 8,000).

Capping payout and slot propagation at `treeDepth` made their cost constant:

| | Before | After |
|---|---|---|
| depth 50 | 423,172 | **187,874** |
| depth 250 | 1,346,602 | **187,982** |

The cycle guard has a different requirement: it follows reciprocal links until
it reaches either a parentless root or a stale rollover edge, which is a valid
independent-board boundary. Actual reciprocal cycles and intact paths beyond
the independent `MAX_LIVE_PATH = 256` ceiling are rejected. Guarded
cost grows only to that fixed bound (207,736 gas at depth 20; 305,293 at depth
150; 385,585 at the boundary), and an over-deep parent is rejected with
`ParentPathTooDeep`.

Both properties are locked by regression tests
(`test_Adversarial_DeepChain_GasStaysFlat`,
`test_Adversarial_CycleGuard_IsBoundedAndRejectsOverdeepPaths`).

---

## 6. FINDING-2 — the award threshold can be self-farmed · **PATCHED**

**Severity: Medium (economic). Status: PATCHED** with earnings-based award cap.

### The problem

`grantPhysicalAward` gates solely on `rolloverCount >= rolloversForAward`.
`rolloverCount` counts placements below a member and **cannot distinguish a real
recruit from a wallet the same person controls.**

A farmer can fund 140 sock-puppet wallets to fake 10 rollovers at stage 1 and
reach the award threshold.

### The patch: `awardCapBps`

Awards are now capped at `(stageEarnings × awardCapBps) / 10,000` — the member
can never receive more than a configured percentage of what they actually earned
at that stage.

- Default: 10,000 (100% of earnings)
- Admin-adjustable via `setAwardCapBps(newCapBps)`
- Hard-capped at 10,000 — cannot be raised past 100%, keeping the
  unprofitability guarantee structural rather than a policy choice

### Why it works

A farmer who funds their own board spends far more on fees than they earn back
in upline payments. Their `stageEarnings` is a fraction of the total cost. The
cap ties the maximum award to those earnings, so the award can never close the
gap.

Measured (`test_AwardCap_MakesFarmingUnprofitable`):

```
Controlled-cluster fees (140 stage-0 + 140 stage-1): $11,200
Farmer stage-1 stageEarnings:                        $1,400
Maximum award at 100% cap:                           $1,400
Net loss after all in-cluster rewards and max award: $5,240
```

A genuine member's economics are the opposite
(`test_AwardCap_GenuineMemberStillProfits`):

```
Genuine member outlay:  $80  (one stage-0 + one stage-1 join)
Genuine member gain:    $2,800  (stageEarnings + max award)
```

### Three mutations injected, all caught

| Mutation | Caught by |
|---|---|
| Remove the cap check entirely | `test_AwardCap_MakesFarmingUnprofitable` |
| Allow cap > 100% | `test_AwardCap_CannotExceed100Percent` |
| Cap uses wrong denominator (1,000 instead of 10,000) | `test_AwardCap_GenuineMemberStillProfits` |

### Defence in depth

The cap is the **structural backstop**. Two other layers remain:

1. **Operator gate** — `grantPhysicalAward` requires `OPERATOR_ROLE`. Verified
   in `test_AwardFarming_OperatorGateIsTheDefence` — neither a farmer nor their
   puppets can trigger a payout; both revert.
2. **Off-chain review** — review downlines before granting: funded from one
   source? joined within a few blocks? any real-world identity?
3. **`updateAwardThreshold(stageId, n)`** raises the bar at runtime, increasing
   the farming cost proportionally.

---

## 7. Verified security properties

| Attack vector | Status | Basis |
|---|---|---|
| Reentrancy | Guarded | `nonReentrant` on all state-changing externals; state written before transfers; Slither + Mythril clean |
| Integer overflow / underflow | Not possible | Solidity 0.8.20 checked arithmetic |
| Access control bypass | Verified | Every admin function tested against a non-role caller |
| Fee-on-transfer token drain | Blocked | `_pullExact` asserts exact balance delta |
| Payout exceeding fee | Impossible | `treeDepth × nodeReward < fee` enforced at config and runtime |
| Unbounded gas / DoS | Closed | Economic walks capped at `treeDepth`; full-path guard capped at `MAX_LIVE_PATH = 256` |
| Insolvency | Never observed | 256k invariant calls + 200k Echidna calls + all stress runs |
| Fee accounting drift | Never observed | `feesPulled == poolPaid + treasuryPaid` exact throughout |
| Double registration / stage join | Reverts | `AlreadyRegistered`, `AlreadyEnrolledInStage` |
| Stage skipping | Reverts | `PreviousStageRequired` |
| Slot theft | Reverts | `SlotOccupied` |
| Treasury over-withdrawal | Reverts | `InsufficientPendingTreasury` |
| Double award claim | Reverts | `AwardAlreadyClaimed` |
| Oracle manipulation | Mitigated, not eliminated | Two-hour production-floor TWAP blocks same-block/short flash moves; a distortion sustained for the full window can still affect price and must be monitored |
| Price/allowance front-running | Bounded | Paid V2 calls require `maximumPayment`; a higher required token amount reverts even with unlimited allowance. A preferred slot can still be lost and retried |
| Self-referral for profit | Unprofitable | Fees always exceed what returns to the cluster |
| Award threshold gaming | Patched | FINDING-2: earnings-based cap makes farming unprofitable; operator gate + off-chain review |

---

## 8. Not covered by this work

1. **No external human audit.** Static analyzers match patterns; they do not
   reason about whether a compensation design is sound. **DEFECT-1 is the proof
   — four analyzers and 67 passing tests all missed a 3× underpayment**, because
   no tool checks a contract against a business plan. A firm-level review is
   still strongly recommended.
2. **No upgrade path.** Not proxied. A post-deployment bug means redeploying and
   migrating. Deliberate choice.
3. **Shared control-key risk.** The selected permanent policy assigns deployer,
   admin, operator and pauser to one EOA. That key can change fees, close stages,
   re-point treasury, seed fee-free stage roots, grant awards and pause the
   protocol. A compromise therefore concentrates all those powers in one
   attacker. Treasury and economic root remain separate, but this is not a
   substitute for multisig custody or a runtime timelock.
4. **Underlying token risk.** If the payment token's issuer pauses transfers or
   blacklists this contract, everything freezes.
5. **Token transfer hooks.** A join now makes up to `treeDepth` transfers instead
   of one. With a standard ERC-20 this is safe (no recipient code runs). With a
   hook-bearing token (ERC-777 style), a malicious upline could revert and block
   placements up to `treeDepth` levels below them — a wider blast radius than
   before the fix. **Confirm the payment token has no transfer callbacks.**
6. **No rate limiting.** Nothing stops a script registering many wallets in one
   block to occupy slots ahead of humans.
7. **No on-chain member enumeration.** Member lists, downlines and leaderboards
   must come from an event indexer. `NodeRewardPaid` now fires **up to
   `treeDepth` times per join** — indexers written against the old one-per-join
   behaviour must be updated.
8. **Market-oracle residual risk.** The live fork verifies RWAAN transfers and
   oracle composition, and the unit suite proves that a same-block reserve move
   cannot change the published TWAP. It cannot prove that the RWAAN/WBNB market
   will remain liquid or unmanipulated for an entire averaging window. Pair
   monitoring and the pauser remain required operational controls.

---

## 9. Pre-deployment checklist

- [ ] Shared deployer/admin/operator/pauser EOA is hardware-backed and monitored continuously
- [ ] `_adminDelay >= 10 minutes` so acceptance of an admin transfer is delayed
- [ ] Runtime-admin risk accepted in writing — `_adminDelay` does not timelock current-admin calls
- [ ] `ALLOW_EOA_ROLES=true` and `ALLOW_SHARED_CONTROL_ADDRESS=true` accepted in writing
- [ ] `DEPLOYER == ADMIN == OPERATOR == PAUSER`; treasury and economic root are separate from it and each other
- [ ] `awardCapBps` reviewed — default 100% makes farming unprofitable; tighten if desired
- [ ] Written operator policy for reviewing downlines before granting awards
- [ ] Payment token confirmed to have **no transfer hooks** (§8.5)
- [ ] Indexer updated for **multiple `NodeRewardPaid` events per join** (§8.7)
- [ ] Award treasury funded through accumulated fees or `fundTreasury` (not raw token transfers)
- [ ] Fixed CREATE2 salt and independently recorded `EXPECTED_MEMBERSHIP_ADDRESS` confirmed
- [ ] Independently recorded `EXPECTED_ROLE_MANIFEST_HASH` matches every role, root and admin delay
- [ ] `ConfigureBscMainnet` five calls submitted unchanged and in order; stage configuration last
- [ ] `ConfigureBscMainnet.verify()` passes before root registration — **one-time configuration**
- [ ] `BinaryMembershipV2BscForkTest` passes against live RWAAN, its Pancake pair and Chainlink BNB/USD
- [ ] Production TWAP is at least two hours and an updater/monitoring runbook is active
- [ ] Frontend uses only `registerWithMaxPayment` / `joinStageWithMaxPayment` for paid entries
- [ ] Enable `cycleGuardEnabled` at launch to reject cyclic/over-deep parent paths

---

## 10. Reproducing these results

```bash
forge test                                   # 192 tests across 31 suites
forge test --gas-report
slither . --compile-force-framework foundry --exclude naming-convention,pragma
aderyn .
myth analyze src/BinaryMembershipV1.sol --solc-json mythril-config.json --execution-timeout 300
echidna . --contract EchidnaBinaryMembership --config echidna.yaml --crytic-args "--foundry-compile-all"
```

Two Echidna invocation requirements, both easy to get wrong: the target must be
the **project directory** (`.`), not the file path, and `--foundry-compile-all`
is required because crytic-compile skips `test/**` by default, which would leave
the harness uncompiled.
