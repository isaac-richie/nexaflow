# NexaFlow — community copy

Paste-ready for WhatsApp and Telegram. `*bold*` renders in both.

---

## ⚠️ ADDRESSES — check this table before you post anything

Every message below carries a `[LINK]`. Fill it from **CANONICAL** only.

Several NexaFlow contracts exist on chain. That is normal during development
and dangerous during marketing: a plausible-looking old address is exactly what
a phishing clone copies. Anyone posting a link is responsible for matching it
against this table first.

### CANONICAL — the one to promote

| | Address |
|---|---|
| **Membership (V3)** | `0x65d4c2AF32c56D9c07c425815B339ba791adA996` |
| **Price oracle (V3)** | `0xd5Ae2003dE1e35986ECA85110654247420b3FEdE` |

V3 is the 1-hour TWAP / 8-hour staleness build. The addresses are deployed and
verified, and the designated root is now registered. The keeper and a first
real UI join must still be completed before any launch message is posted.

### Supporting addresses — same on every version

| | Address |
|---|---|
| RWAAN token | `0xACB921bf2Dac2F7E8E101AAd9CA013d6Af5C648a` |
| RWAAN/WBNB pair | `0xA285059BBc89Fe9B43414D098318675462aaa3e6` |
| Designated root | `0x1Dd8EaAF54a6E9f9e293e758d701142cF73971bB` |
| Treasury | `0xf17F4a489FDf606AD19dbdACA6adD575e5E884b1` |

### DEPRECATED — never post these

| Address | What it is | Why not |
|---|---|---|
| `0x3fAaDAac24A953a623B01e77D5b70Bfdc7E08cE0` | V2, RWAAN, BSC mainnet | Superseded by V3. Oracle window too tight; it went stale and quotes revert. Zero members, no funds at risk. |
| `0xc5dc9b0d753c66c65962370b26b97cc2d53ad318` | V1, USDT, BSC mainnet | Wrong payment token. Zero members. |
| `0xeca3f1c747acfbb5ccedcd464543f0631f42e912` | V1, BSC **testnet** (chain 97) | Test money only. |
| `0x0df789…9955` | partial deploy, BSC testnet | Abandoned mid-deployment during an RPC retry. Never configured. |

If somebody in the community shares a NexaFlow address that is not the
canonical one above, treat it as hostile until proven otherwise and say so in
the group immediately.

### Before any launch post

- [x] V3 deployed, and both addresses written into the CANONICAL table
- [ ] Source verified on BscScan
- [ ] Stages configured and read back on chain
- [x] Root registered, so `findPlacementSlot` resolves
- [ ] Keeper running, oracle fresh
- [ ] One real join completed by the team with their own money
- [ ] `[LINK]` replaced everywhere in this file

---

Every figure here comes from the deployed contract. Nothing is projected,
annualised, or totalled across levels nobody has reached. That is deliberate:
the moment a number cannot be checked on chain, the whole message becomes
deniable, and a burned audience checks.

---

## 1. Main broadcast

🟡 *NEXAFLOW IS LIVE*

Contract deployed on BNB Chain. Verified. Open now.

*What makes this different*

Every other programme asks you to trust a backoffice. A dashboard with your
balance on it. A withdraw button that works right up until it doesn't.

NexaFlow has no backoffice.

When someone fills a position on your board, the live USD-priced amount of
RWAAN moves to your wallet *in the same transaction*. Not credited. Not
pending. Not "processing". Sent.

There is no withdraw button because there is nothing to withdraw. You already
have it.

*THE BOARD*

Stage 1 is priced at $20 and paid in the quoted amount of RWAAN.

Your board is 6 positions. Every single one pays you $5.

Fill it and you have taken *$30 back on a $20 entry.*

Then the board clears and starts again. Same board. Same $30. No cap on how
many times it cycles.

*YOU GET PAID FOR PEOPLE YOU NEVER MET*

When the person above you runs out of space, the next person drops down and
lands on *your* board.

You did not recruit them. You still get paid.

That is spillover, and the contract decides it. Not an admin. Not a favourite.
Not who shouted loudest in the group.

*THE LADDER*

Stage 1 · $20 in · $30 board
Stage 2 · $60 in · $140 board
Stage 3 · $180 in · $350 board
Stage 4 · $540 in · $1,120 board
Stage 5 · $1,620 in · $3,500 board
Stage 6 · $4,860 in · $11,200 board

Each stage is its own board with its own numbers. You climb in order.

*WHY THIS ONE*

✅ Non-custodial. Your money never sits in our account, because we do not have
one.
✅ Paid on chain, same transaction, every time.
✅ The contract is public. Read it yourself before you send a cent.
✅ 192 tests, including 2,000 wallets across all six stages, plus a live-chain fork test.
✅ No proxy or upgrade switch. Authorized fee/threshold controls remain public on chain.

*Straight talk.* Your board fills when people join beneath you. Active network,
you earn. Quiet network, it slows. Nobody can promise you a full board, and
anyone who promises you millions is selling you something.

We built the contract so it can never pay out more than it takes in. That is
exactly why we will still be standing next year.

🟡 *Take your position.*
👉 [LINK]

---

## 2. Short version, for status and quick drops

🟡 *NEXAFLOW. LIVE ON BNB CHAIN.*

$20 in.
6 positions on your board.
$5 from every single one.
*$30 back, then the board resets and pays again.*

No backoffice. No withdraw button. No waiting.
RWAAN hits your wallet in the same transaction the position fills.

The contract is public. Go and read it.

👉 [LINK]

---

## 3. The comparison post

*Ask them these five questions.* 👇

*1. Where is my money sitting right now?*
Ours: in your own wallet. It never touches ours. There is no account for us to
freeze and no balance for us to hold.

*2. Show me the contract.*
Ours is deployed and verified on BscScan. Read every line before you join.
If they cannot show you code, you are trusting a website.

*3. Who decides where new people are placed?*
Ours: the contract, by a fixed rule. Nobody can move somebody into a friend's
leg.

*4. Can the rules change after I join?*
Ours: there is no proxy or upgrade switch. The contract code cannot be replaced;
authorized fee, award-threshold, treasury and stage controls are visible on chain.

*5. What happens when growth slows?*
Ours: your board fills slower and you earn less. We say that out loud.
Any platform still promising you millions when growth slows is lying, and you
already know how that story ends.

🟡 *NexaFlow. Built to be checked, not believed.*
👉 [LINK]

---

## 4. Objection replies

**"How much can I make?"**
> Per board, the numbers are fixed and public: $30 on a $20 Stage 1 board, $140
> on Stage 2. What nobody can tell you is how fast your board fills, because
> that depends on the network. Anyone quoting you a total is guessing.

**"Is it a Ponzi?"**
> It is a matrix programme and the money comes from entry fees, same as every
> other one. The difference is that ours cannot pay out more than it takes in,
> the code enforces it, and you can verify that yourself instead of taking our
> word for it.

**"What if the admin runs?"**
> There is nothing to run with. Your earnings are sent to your wallet in the
> same transaction, and the contract has no function that lets anyone take
> member funds.

**"Why is it cheaper than [rival]?"**
> $20 gets you in. We would rather you start small, see the payment land in
> your wallet, and climb because it worked than because you were talked into it.

---

## Rules for anyone writing more of this

Keep these. They are what makes the message survive contact with a sceptic.

1. **No totals across levels.** "Over $12 million" assumes recruitment that
   never stops. It stops.
2. **No percentage returns.** "294% returns" reads as a yield. This is not a
   yield, it is a payout per filled position.
3. **No "guaranteed", "non-stop", or "endless".** One quiet month makes the
   whole message a lie people can screenshot.
4. **Every number must be checkable on chain.** If a claim cannot be verified
   in BscScan, cut it.
5. **Say the condition out loud.** "Your board fills when people join beneath
   you" costs nothing and buys credibility that hype cannot.
