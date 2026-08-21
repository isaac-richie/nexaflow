# BinaryMembershipV2 RWAAN release candidate

Prepared on 2026-08-17 for BNB Smart Chain mainnet. This is a pre-deployment
record, not evidence that the replacement contracts are live.

## Pinned production inputs

- RWAAN: `0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a`
- WBNB: `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`
- Pancake V2 RWAAN/WBNB pair: `0xA285059BBc89Fe9B43414D098318675462aaa3e6`
- Chainlink BNB/USD: `0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE`
- RWAAN decimals: 18
- TWAP period: 7,200 seconds (two-hour production floor)
- BNB-feed maximum age: 10,800 seconds
- Membership maximum price age: 10,800 seconds

## Deterministic oracle candidate

- CREATE2 salt hash:
  `0xbf2ab4b265df0df33d56e72201d262d4c57e65abf10a61626a29dc841290f4ec`
- Predicted oracle:
  `0x4d10C6c35bb449BE9FBF4FBec02C9D1C26b2e67F`
- Code at prediction when checked: empty
- Non-broadcast deployment simulation: passed
- Simulated gas: 1,070,004 at the sampled 0.05 gwei gas price
- Simulated cost: 0.0000535002 BNB

The predicted address must be independently recomputed before broadcast. After
deployment, wait a full two hours, call permissionless `update()`, and run
`DeployRwaanOracle.verifyFromEnv()` before predicting the membership address.

## Verification evidence

- `forge test -q`: passed; `forge test --list --json` enumerates 192 tests in
  31 suites.
- Dedicated dynamic-price test: 2,000 wallets across all six stages.
- Detailed moving-price campaign: 350 wallets, 1,745 paid entries, 20 rejected
  moved-price quotes, spillover, spillunder, rollovers, awards and treasury
  withdrawal; exact balance/accounting reconciliation passed.
- Live BSC fork: production two-hour TWAP composition and real
  RWAAN wallet-to-membership-to-upline transfers passed without transfer tax.
- Frontend: ABI regeneration, TypeScript check and production build passed.
- Aderyn: no actionable issue after review; constructor-only reentrancy report
  is a false positive. Slither/Foundry integration and Mythril completion are
  documented tooling limitations, not clean reruns.

## Stop conditions

Do not broadcast membership deployment if the oracle address/hash differs,
oracle price is uninitialized or stale, live pair/feed addresses differ, the
role manifest changes, any test/fork/build check fails, or an independent
security reviewer has not approved the release candidate.
