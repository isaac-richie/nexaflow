# BSC Testnet campaign runbook

This runbook deploys an 18-decimal mock RWAAN, a $1 test oracle and
`BinaryMembershipV2` to BNB
Smart Chain Testnet (chain ID 97), runs 100 disposable wallets through all six
stages, audits the four-stage and six-stage checkpoints, then optionally extends
to 140 wallets to exercise the physical-award thresholds.

The mock token is not real RWAAN. Every key and mnemonic used here must be
disposable and must never be reused on mainnet.

Production uses Rawli Analytics (`RWAAN`) at
`0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a`. Production pricing comes from
the RWAAN/WBNB TWAP plus Chainlink BNB/USD; testnet fixes the mock price at $1
so the existing campaign totals remain easy to audit.

## 1. Prepare the environment

```bash
cp .env.bsc-testnet.example .env.bsc-testnet
```

Populate `DEPLOYER_PRIVATE_KEY` with a disposable funded BSC Testnet key and
`TESTNET_MNEMONIC` with a new test-only mnemonic. Do not commit the populated
file. Obtain tBNB from the official BNB Chain faucet, then load the variables:

```bash
set -a
source .env.bsc-testnet
set +a

cast chain-id --rpc-url "$BSC_TESTNET_RPC_URL"  # must print 97
cast balance "$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")" \
  --rpc-url "$BSC_TESTNET_RPC_URL"
```

At the currently observed 0.1 gwei testnet gas price, 0.15 tBNB covers the
default 140-wallet campaign with margin. Recheck the gas price immediately
before broadcasting.

## 2. Deploy and configure

`FOUNDRY_OFFLINE=true` prevents Foundry's trace decoder from making unnecessary
Sourcify lookups while it prepares hundreds of transactions. It does not block
the explicitly supplied RPC.

```bash
FOUNDRY_OFFLINE=true forge script \
  script/DeployBscTestnet.s.sol:DeployBscTestnet \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v
```

Copy the emitted mock-token and membership addresses into
`MOCK_RWAAN_ADDRESS` and `MEMBERSHIP_ADDRESS`, then confirm:

- 18-decimal mock RWAAN and $1 mock oracle deployed;
- membership is `BinaryMembershipV2` and `quoteStagePayment(0)` returns 20
  mRWAAN fee / 5 mRWAAN reward at the test price;
- award thresholds are `[0, 10, 10, 10, 10, 8]`;
- cycle guard is enabled;
- root is registered and enrolled at all six stages;
- operator, treasury and pauser roles use separate derived test accounts.

## 3. Provision the first 100 wallets

```bash
WALLET_START=0 WALLET_END=100 FOUNDRY_OFFLINE=true forge script \
  script/ProvisionBscWallets.s.sol:ProvisionBscWallets \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v
```

Each wallet receives 10,000 mRWAAN and a 0.001 tBNB gas target. Provisioning is
idempotent: rerunning only tops balances up to their targets.

## 4. Four-stage checkpoint

```bash
WALLET_START=0 WALLET_END=100 STAGE_START=0 STAGE_END=3 \
SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true forge script \
  script/RunBscCampaign.s.sol:RunBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

WALLET_END=100 STAGE_END=3 SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true \
forge script script/AuditBscCampaign.s.sol:AuditBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --disable-labels -v
```

Expected checkpoint: 101 total members including root, 80,000 mRWAAN in fees,
and an `AUDIT PASS` result.

## 5. Complete all six stages

```bash
WALLET_START=0 WALLET_END=100 STAGE_START=4 STAGE_END=5 \
SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true forge script \
  script/RunBscCampaign.s.sol:RunBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

WALLET_END=100 STAGE_END=5 SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true \
forge script script/AuditBscCampaign.s.sol:AuditBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --disable-labels -v
```

Expected checkpoint: 728,000 mRWAAN in fees. Stages 1–5 each have seven root
rollovers and two positions on the next board, so every paid-stage award must
still be ineligible.

## 6. Award-boundary extension

First move from 100 to 112 wallets. This reaches exactly eight rollovers on the
14-slot boards:

```bash
WALLET_START=100 WALLET_END=112 FOUNDRY_OFFLINE=true forge script \
  script/ProvisionBscWallets.s.sol:ProvisionBscWallets \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

WALLET_START=100 WALLET_END=112 STAGE_START=0 STAGE_END=5 \
SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true forge script \
  script/RunBscCampaign.s.sol:RunBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

FOUNDRY_OFFLINE=true forge script \
  script/ExerciseBscAwards.s.sol:ExerciseBscAwards \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v
```

Expected: stages $60–$1,620 are skipped as ineligible; only the $4,860 stage
receives its one-mRWAAN test award and advances its next milestone to 16.

Then move from 112 to 140 wallets:

```bash
WALLET_START=112 WALLET_END=140 FOUNDRY_OFFLINE=true forge script \
  script/ProvisionBscWallets.s.sol:ProvisionBscWallets \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

WALLET_START=112 WALLET_END=140 STAGE_START=0 STAGE_END=5 \
SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true forge script \
  script/RunBscCampaign.s.sol:RunBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

FOUNDRY_OFFLINE=true forge script \
  script/ExerciseBscAwards.s.sol:ExerciseBscAwards \
  --rpc-url "$BSC_TESTNET_RPC_URL" --broadcast --disable-labels -v

WALLET_END=140 STAGE_END=5 SPONSOR_FIRST_MASK=1 FOUNDRY_OFFLINE=true \
forge script script/AuditBscCampaign.s.sol:AuditBscCampaign \
  --rpc-url "$BSC_TESTNET_RPC_URL" --disable-labels -v
```

Expected: stages $60–$1,620 receive their first awards at ten rollovers; the
$4,860 stage remains ineligible until rollover 16. Total campaign fees are
1,019,200 mRWAAN, and every ledger must still reconcile after the five awards.

## 7. Evidence and verification

Preserve the non-secret `broadcast/**/97/run-latest.json` transaction hashes in
the final report, link both contracts and representative wallet transactions on
BscScan Testnet, and verify the contracts separately after broadcasting. Never
publish `cache/**`, the mnemonic, or any private key.

---

## 8. Do not reuse this runbook for mainnet

Everything above is deliberately unsafe for production, and the values that make
it convenient here are the ones that cause the most damage there. Mainnet has
its own script, `script/DeployBscMainnet.s.sol`, which **cannot** be run against
a test setup — and this script cannot be run against mainnet.

| | This runbook (testnet) | Mainnet |
|---|---|---|
| Payment token | mock RWAAN deployed by the script | pinned RWAAN, `0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a` |
| Price | fixed mock oracle at $1 | RWAAN/WBNB TWAP + Chainlink BNB/USD |
| admin transfer delay | `0` | **`>= 10 minutes`, enforced** |
| Roles | derived from one mnemonic | deployer/admin/operator/pauser share one EOA by explicit policy; treasury and root separate |
| Deployment | plain `new` | fixed-salt **CREATE2** + locked address and role manifest |
| Keys | disposable | multisig or hardware, never reused from here |

### The three that bite

**1. `adminDelay = 0`.** Section 2 hardcodes it. On testnet that is right: you
want to iterate without waiting for a default-admin transfer. On mainnet the
script enforces a 10-minute floor, and `test_Guard_RejectsZeroAdminDelay` proves
the refusal fires.

That delay has a deliberately narrow meaning: it delays acceptance of a
**transfer of `DEFAULT_ADMIN_ROLE`**. It does not delay calls made by the current
admin. The current admin can still grant non-admin roles, change fees, change
award thresholds, change treasury and toggle stages immediately. Runtime delay
must therefore be enforced by the admin Safe policy/Delay Module; do not rely on
`adminDelay` as an incident-response window.

**2. Duplicate deployments from RPC retries.** The testnet campaign produced one
(`0x0df789…9955`) when an RPC call was retried. It was harmless because no
wallet used it and the canonical address was known. On mainnet a stray,
half-configured contract at a plausible address is something members, an
indexer, or a phishing site can find and use. The mainnet script deploys with
CREATE2 from a source-controlled salt. The independently generated prediction
must also equal `EXPECTED_MEMBERSHIP_ADDRESS`, so changing a constructor input
cannot silently produce a second plausible address. An identical retry lands
on the occupied canonical address and stops.

Operator and pauser are assigned after construction, so they do not affect the
CREATE2 address. `EXPECTED_ROLE_MANIFEST_HASH` independently commits those two
addresses together with admin, treasury, root and admin-transfer delay. Both the
deployment and configuration scripts refuse a manifest mismatch.

**3. Oracle readiness and freshness.** The production oracle has no usable
price until one full TWAP period has elapsed and `update()` succeeds. It must
then be updated inside `MAX_PRICE_AGE_SECONDS`. A zero, future, stale or
uninitialized price blocks paid enrollment instead of silently mispricing it.

### Mainnet sequence

1. Copy `.env.bsc-mainnet.example` to the ignored `.env`, fill only public role
   addresses first, and `chmod 600` the file. The selected permanent policy
   requires deployer, admin, operator and pauser to be the same address through
   explicit `ALLOW_EOA_ROLES=true` and `ALLOW_SHARED_CONTROL_ADDRESS=true`
   switches. Treasury and economic root must each be separate from that control
   address and from one another.
2. Run the live BSC fork compatibility test. It exercises the actual RWAAN buy,
   wallet-to-membership and membership-to-upline transfer paths:

   ```bash
   forge test --match-contract BinaryMembershipV2BscForkTest \
     --fork-url "$BSC_MAINNET_RPC_URL" -vv
   ```

3. Predict and deploy `DeployRwaanOracle`, wait `TWAP_PERIOD_SECONDS`, call
   `updateFromEnv()`, and run `verifyFromEnv()`. Set the verified address as
   `PRICE_ORACLE_ADDRESS`.
4. Independently predict the canonical membership address without a deployer key:

   ```bash
   set -a; source .env; set +a
   forge script script/DeployBscMainnet.s.sol:DeployBscMainnet \
     --sig "predictFromEnv()" --rpc-url "$BSC_MAINNET_RPC_URL"
   ```

   Record the printed address and role-manifest hash through a second reviewer,
   then set them exactly as `EXPECTED_MEMBERSHIP_ADDRESS` and
   `EXPECTED_ROLE_MANIFEST_HASH`. The salt is source-controlled; there is no
   `DEPLOY_SALT` environment override. Any later role-address edit requires a
   fresh prediction and review rather than silently changing the admin calls.
5. Add the shared control/deployer key, dry-run `run()`, then broadcast. The
   script refuses chain IDs other than 56, any control-address mismatch,
   treasury/root overlap, missing explicit EOA/shared-control opt-outs,
   constructor drift, role-manifest drift and predicted-address drift. It only
   deploys:

   ```bash
   forge script script/DeployBscMainnet.s.sol:DeployBscMainnet \
     --sig "run()" --rpc-url "$BSC_MAINNET_RPC_URL" --broadcast
   ```

6. Verify source on BscScan and independently confirm the payment token,
   treasury, default admin, admin-transfer delay and designated root. Set
   `MEMBERSHIP_ADDRESS` to the verified address; it must equal
   `EXPECTED_MEMBERSHIP_ADDRESS`. Keep the independently recorded role-manifest
   hash unchanged.
7. Generate the exact admin calls:

   ```bash
   forge script script/ConfigureBscMainnet.s.sol:ConfigureBscMainnet \
     --sig "printCalldata()" --rpc-url "$BSC_MAINNET_RPC_URL"
   ```

   Submit all five from the dedicated admin EOA, unchanged and in order: grant
   operator, treasury and pauser roles; enable the cycle guard; configure all
   six stages last. Do not hand-enter the stage arrays. Because configuration
   is last, no member can join during the sequential setup window.
8. Run the post-configuration verifier before any member joins:

   ```bash
   forge script script/ConfigureBscMainnet.s.sol:ConfigureBscMainnet \
     --sig "verify()" --rpc-url "$BSC_MAINNET_RPC_URL"
   ```

   It checks the constructor state, all roles, every fee/reward/slot/depth/award
   threshold, cycle guard, pause state, empty membership, empty anchors and zero
   pre-launch accounting. Any mismatch is a stop condition.
9. Register the designated root, then seed each stage root. **The cycle guard
   must already be enabled.**
10. Rehearse pause, unpause, a treasury withdrawal and a small award before
    opening registration. Confirm the frontend refuses to enable joining unless
   chain ID is 56, the address is canonical, `configured()` and
   `cycleGuardEnabled()` are true, `paused()` is false, the payment token is the
   pinned RWAAN and oracle addresses, and every stage value matches the verified manifest.
   For the withdrawal, confirm half reaches `TREASURY_ADDRESS`, half reaches
   `COMPANY_WALLET_ADDRESS`, and the two transfers sum exactly to the decrease
   in `pendingTreasury`.

Fund awards with `fundTreasury()`. A raw token transfer raises the balance
without raising the tracked liability, leaving funds the accounting cannot see
or spend.
