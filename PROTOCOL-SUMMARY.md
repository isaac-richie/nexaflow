# BinaryMembershipV2 Protocol Summary

Last updated: 18 August 2026

## 1. Current status

BinaryMembershipV2 is the replacement membership contract. It uses Rawli
Analytics (`RWAAN`) on BNB Smart Chain instead of USDT and calculates the RWAAN
quantity for each paid registration from the current on-chain USD price.

- Solidity tests: **202 passed, 0 failed**
- Frontend TypeScript check: passed
- Frontend production build: passed
- Live BSC-fork RWAAN transfer test: passed
- 350-, 500- and 2,000-wallet stress campaigns: passed
- Mainnet deployment performed: **no**

The previously deployed contract is not modified. A new V2 deployment is
required.

## 2. BSC contracts and price sources

| Component | Address |
|---|---|
| RWAAN token | `0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a` |
| RWAAN/WBNB PancakeSwap V2 pair | `0xA285059BBc89Fe9B43414D098318675462aaa3e6` |
| WBNB | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` |
| Chainlink BNB/USD feed | `0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE` |

RWAAN uses 18 decimals.

`PancakeV2RwaanUsdOracle` combines:

1. A time-weighted RWAAN/WBNB price from PancakeSwap V2.
2. The Chainlink BNB/USD price.
3. The two values into an 18-decimal RWAAN/USD price.

Production uses a minimum two-hour TWAP. The oracle must be initialized and
updated by keeper automation. Paid registration safely reverts when the price
is zero, stale, future-dated or otherwise invalid.

## 3. Stage economics

Stage configuration remains USD-denominated. The contract converts the fee and
per-upline reward into RWAAN during each paid entry using the same validated
price snapshot.

| Display stage | On-chain stage | USD fee | USD reward per upline | Slots | Depth | Award rollovers |
|---|---:|---:|---:|---:|---:|---:|
| Stage 1 | 0 | $20 | $5 | 6 | 2 | Disabled |
| Stage 2 | 1 | $60 | $10 | 14 | 3 | 10 |
| Stage 3 | 2 | $180 | $25 | 14 | 3 | 10 |
| Stage 4 | 3 | $540 | $80 | 14 | 3 | 10 |
| Stage 5 | 4 | $1,620 | $250 | 14 | 3 | 10 |
| Stage 6 | 5 | $4,860 | $800 | 14 | 3 | 8 |

The required RWAAN quantity is not fixed. For example, a $20 stage costs more
RWAAN when RWAAN's USD price falls and less RWAAN when its price rises.

The fee conversion rounds up and the reward conversion rounds down. This
prevents conversion rounding from making a registration insolvent.

## 4. Registration protection

Paid users use bounded entrypoints:

```solidity
registerWithMaxPayment(sponsor, parent, side, maximumPayment, deadline);
joinStageWithMaxPayment(stageId, parent, side, maximumPayment, deadline);
```

Recommended frontend flow:

1. Read `quoteStagePayment(stageId)`.
2. Read `findPlacementSlot(sponsor, stageId)`.
3. Approve the exact quoted RWAAN fee.
4. Refresh the quote and placement once immediately before signing.
5. Submit the bounded registration with a short deadline.

If the RWAAN price falls and the required quantity exceeds `maximumPayment`,
the transaction reverts with `PaymentExceedsMaximum`. A transaction submitted
after its deadline reverts with `TransactionExpired`.

The designated root is the only wallet that can take the initial fee-free root
position. Paid users cannot use the legacy unbounded V1 entrypoints.

## 5. Uplines, spillover, spillunder and rollover

Each paid stage entry is one blockchain transaction. Inside that transaction:

1. The contract pulls the exact RWAAN fee.
2. The member is placed in the selected binary-tree position.
3. Eligible uplines receive their RWAAN rewards immediately.
4. The unpaid remainder is recorded in `pendingTreasury`.
5. Board position counters are updated.
6. Full boards roll over and reopen.

`findPlacementSlot` performs sponsor-first placement and falls back to the
permanent stage anchor when the sponsor lineage is unavailable or full.

- **Spillover:** a member is placed below someone other than their direct
  sponsor because the sponsor's immediate positions are unavailable.
- **Spillunder:** a member can earn from members placed below them even when
  those members were introduced by someone else.
- **Rollover:** after all configured positions fill, the board counter
  increments and the board opens for another cycle.

Upline rewards, treasury allocation, spillover, spillunder and rollover are
internal operations in one transaction. They add transaction gas but do not
create separate frontend RPC requests.

## 6. Treasury and company profit split

`pendingTreasury` is the undistributed RWAAN liability remaining after upline
rewards and awards.

When an address with `TREASURY_ROLE` calls:

```solidity
withdrawTreasury(amount);
```

V2 divides that requested total amount as follows:

- 50% to the `treasury` address.
- 50% to `companyWallet`.
- For an odd token base-unit amount, treasury receives the one indivisible
  remainder, so company profit never exceeds 50%.

The amount is selected by the caller; **100 RWAAN is not hardcoded**.

Examples:

| Call | Treasury receives | Company receives |
|---|---:|---:|
| `withdrawTreasury(10 ether)` | 5 RWAAN | 5 RWAAN |
| `withdrawTreasury(100 ether)` | 50 RWAAN | 50 RWAAN |
| `withdrawTreasury(1_000 ether)` | 500 RWAAN | 500 RWAAN |
| `withdrawTreasury(pendingTreasury)` | Half of all available funds | Half of all available funds |

The full requested amount is deducted from `pendingTreasury`. Both transfers
are atomic: if either transfer fails, the entire withdrawal reverts.

Physical awards are paid from `pendingTreasury` before withdrawal. Therefore,
the implemented model is a **withdrawal-time 50/50 split**, not two protected
accrual ledgers. Whatever remains available for withdrawal is divided 50/50.

Events emitted for reconciliation:

```solidity
TreasuryWithdrawn(treasury, treasuryAmount);
CompanyProfitWithdrawn(companyWallet, companyAmount);
TreasuryWithdrawalSplit(totalAmount, treasuryAmount, companyAmount);
```

## 7. Wallets and post-deployment administration

| Address or role | Changeable after deployment? | Method |
|---|---|---|
| Operator role holders | Yes | `grantRole` and `revokeRole` with `OPERATOR_ROLE` |
| Treasury role holders | Yes | `grantRole` and `revokeRole` with `TREASURY_ROLE` |
| Pauser role holders | Yes | `grantRole` and `revokeRole` with `PAUSER_ROLE` |
| Treasury recipient | Yes | `setTreasury(newTreasury)` |
| Company recipient | Yes | `setCompanyWallet(newCompanyWallet)` |
| Default admin | Yes, delayed two-step transfer | `beginDefaultAdminTransfer` and `acceptDefaultAdminTransfer` |
| Designated root | No | Immutable constructor value |
| RWAAN token | No | Immutable constructor value |
| Price oracle | No | Immutable constructor value |
| Maximum accepted price age | No | Immutable constructor value |
| Existing sponsor and tree positions | No | No administrative editing function |
| Existing stage anchors | No | First anchor remains permanent |

The treasury recipient and company recipient can never be zero or equal to
each other.

The wallet holding `TREASURY_ROLE` authorizes a withdrawal. It does not have to
be the wallet that receives the treasury half. The `treasury` address receives
the treasury half, while `companyWallet` receives the company half.

Recommended role rotation:

```solidity
grantRole(OPERATOR_ROLE, newOperator);
revokeRole(OPERATOR_ROLE, oldOperator);

grantRole(TREASURY_ROLE, newTreasuryController);
revokeRole(TREASURY_ROLE, oldTreasuryController);

setTreasury(newTreasuryRecipient);
setCompanyWallet(newCompanyRecipient);
```

Grant the replacement role first, verify it, and only then revoke the previous
holder. AccessControl permits multiple holders until the old role is revoked.

### Administrative risk

The default-admin transfer delay protects changing the default admin. It does
not automatically delay ordinary admin actions such as wallet rotation or
granting roles. A compromised admin could redirect economic destinations and
grant itself `TREASURY_ROLE`.

Production admin should therefore be a multisig or Safe with an appropriate
delay module rather than a single hot wallet.

## 8. RPC budget controls

The frontend reads BSC directly but avoids continuous paid-provider usage.

- No background dashboard or price polling.
- Nearby reads are combined through Multicall3.
- Identical in-flight reads are deduplicated.
- Placement cache: 20 seconds.
- Price quote cache: 45 seconds.
- Wallet cache: 30 seconds.
- Member, board and award cache: 45 seconds.
- Protocol totals and open-stage anchor cache: 2 minutes.
- Stage configuration cache: 10 minutes.
- Token metadata is long-lived in the browser cache.
- Quote and placement refresh exactly once at transaction intent.
- Transaction receipts poll every 8 seconds only while pending.
- HTTP transport retries once.
- HTTP 400 and 429 responses are not retried.
- Cached reads remain available for 15 minutes across client navigation.

Environment controls:

```dotenv
NEXT_PUBLIC_RPC_POLLING_INTERVAL_MS=8000
NEXT_PUBLIC_RPC_MULTICALL_WAIT_MS=40
```

Provider-side rate limits, usage alerts and spending caps should still be
enabled. Providers may price Multicall computation differently.

## 9. Test evidence

The current repository contains 202 passing Solidity tests across 32 suites.

Important V2 coverage includes:

- Dynamic RWAAN fee and reward conversion.
- Maximum-payment and deadline protection.
- Zero, stale and future-price rejection.
- TWAP manipulation resistance.
- Real RWAAN behavior on a BSC fork.
- Exact fee, payout and treasury conservation.
- 350 wallets across five stages.
- 500 wallets across five stages.
- 2,000 wallets across all six stages.
- Spillover, spillunder and rollover at every tested stage.
- Exact 50/50 treasury/company withdrawals.
- Odd base-unit rounding.
- Paused and unauthorized withdrawal rejection.
- Treasury/company address collision prevention.
- Company address inclusion in CREATE2 prediction and the deployment manifest.

V2 runtime bytecode is 20,571 bytes, leaving 4,005 bytes below the 24,576-byte
EIP-170 runtime limit.

Useful commands:

```bash
forge test
forge test --match-contract BinaryMembershipV2TreasurySplitTest -vv
forge test --match-contract BinaryMembershipV2Stress350RwaanTest -vv
npm --prefix web run test:rpc
npm --prefix web run typecheck
npm --prefix web run build
```

## 10. Deployment requirements

Required mainnet environment values include:

```dotenv
PRICE_ORACLE_ADDRESS=
MAX_PRICE_AGE_SECONDS=10800

ADMIN_ADDRESS=
OPERATOR_ADDRESS=
TREASURY_ADDRESS=
COMPANY_WALLET_ADDRESS=
PAUSER_ADDRESS=
ROOT_ADDRESS=

EXPECTED_MEMBERSHIP_ADDRESS=
EXPECTED_ROLE_MANIFEST_HASH=
```

The company wallet is constructor-bound and included in the role-manifest
hash. Because the constructor changed for the split, the source-controlled
CREATE2 salt is now:

```text
BinaryMembershipV2:BSC_MAINNET:RWAAN:V2
```

Old predicted addresses and old manifest hashes are invalid.

Launch sequence:

1. Select and independently verify every control and economic wallet.
2. Deploy the RWAAN TWAP oracle.
3. Wait one complete TWAP period.
4. Call the oracle update and verify its price/freshness.
5. Run `DeployBscMainnet.predictFromEnv()`.
6. Independently record the expected membership address and manifest hash.
7. Deploy BinaryMembershipV2 using the reviewed environment.
8. Execute the generated configuration actions.
9. Run the post-configuration verifier.
10. Register the designated root and seed higher-stage roots.
11. Perform a small-value registration test.
12. Perform a small treasury withdrawal and confirm the exact 50/50 split.
13. Confirm keeper automation, RPC limits, alerts and pause procedures.
14. Open registration.

## 11. Key source files

- `src/BinaryMembershipV2.sol`
- `src/PancakeV2RwaanUsdOracle.sol`
- `script/DeployRwaanOracle.s.sol`
- `script/DeployBscMainnet.s.sol`
- `script/ConfigureBscMainnet.s.sol`
- `test/BinaryMembershipV2Price.t.sol`
- `test/BinaryMembershipV2TreasurySplit.t.sol`
- `test/BinaryMembershipV2Stress350Rwaan.t.sol`
- `test/BinaryMembershipV2Stress2000.t.sol`
- `test/BinaryMembershipV2BscFork.t.sol`
- `web/RPC-BUDGET.md`

## 12. Final operational position

The implementation and automated verification are green. No mainnet
deployment has been performed. Before launch, the remaining work is operational:
choosing final wallets, initializing the oracle, producing the new CREATE2
prediction and role manifest, deploying, configuring, verifying and executing
small-value mainnet smoke tests.
