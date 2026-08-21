# Retired V1 deployment record

The previous Binance-Peg USDT membership deployment is retired and must not be
used by the frontend, campaign scripts, or indexer.

- Network: BNB Smart Chain mainnet (chain 56)
- Contract: `0xC5Dc9b0D753c66c65962370b26b97Cc2d53ad318`
- Deployment transaction: `0x0f0eef089bef73b77f4b764bae5fab91da9be0179d08b12a0b913ff7889b7df8`
- Deployment block: `116390593`
- Final launch state: one fee-free designated root, no paying members, no USDT
  balance and no treasury liability
- Retirement state: paused on chain before replacement work began
- Source record: `https://sourcify.dev/server/v2/verify/8fc33d87-9665-4a00-95a4-d061467a9d0d`

An unused partial duplicate at `0x0df789...9955` was produced by an RPC retry
during the earlier test/deployment process. No campaign wallet used it. It is
not canonical and must never be published as a membership address.

The active `.env` and frontend configuration intentionally contain no V2
membership address until the replacement RWAAN contract is deployed, verified,
configured, and independently audited.
