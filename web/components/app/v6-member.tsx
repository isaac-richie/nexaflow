"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useAccount } from "wagmi";
import { getAddress, isAddress, zeroAddress, type Address, type PublicClient } from "viem";
import { ACTIVE_CHAIN, IS_DEPLOYED, MEMBERSHIP_ADDRESS } from "@/lib/contracts/config";
import { memberAmount } from "@/lib/member-dashboard";
import { purchaseStage, readV6History, readV6Tree, type V6Snapshot, type V6Stage } from "@/lib/v6";
import { useV6Snapshot, useV6Transaction, v6Deployment, v6Error, v6Scope } from "@/hooks/use-v6";
import { NO_BACKGROUND_RPC, RPC_CACHE_MS } from "@/lib/rpc-policy";
import { ConnectPrompt, LoadingPanel, NotDeployedNotice, NotRegisteredNotice } from "./states";
import { ConnectButton } from "./connect-button";
import { ReferralCard } from "./referral-card";
import { NetworkOverview } from "./network-overview";
import styles from "./member-ui.module.css";

type View = "overview" | "boards" | "network" | "join";
export function V6Member({ view = "overview" }: { view?: View }) {
  const { address, chainId } = useAccount();
  return <Member key={`${address}:${chainId}:${MEMBERSHIP_ADDRESS}`} view={view} />;
}

function Member({ view }: { view: View }) {
  const query = useV6Snapshot();
  const { address, chainId, isConnected } = query.account;
  const [cooldown, setCooldown] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(timer.current), []);
  function refresh() {
    if (cooldown || query.isFetching) return;
    setCooldown(true); void query.refetch();
    timer.current = setTimeout(() => setCooldown(false), 15_000);
  }
  const s = query.data;
  return <div className={styles.stack}>
    <header className={styles.heading}><div><p className={styles.eyebrow}>NexaFlow V6</p><h1>{view === "join" ? "Your next stage starts here." : view === "boards" ? "Every board. Every cycle." : view === "network" ? "Your community, connected." : "Your progress, in view."}</h1></div>
      {isConnected && chainId === ACTIVE_CHAIN.id && IS_DEPLOYED && <button className={styles.button} disabled={query.isFetching || cooldown} onClick={refresh}>{query.isFetching ? "Updating…" : cooldown ? "Please wait" : "Refresh ↻"}</button>}
    </header>
    {!IS_DEPLOYED ? <NotDeployedNotice /> : !isConnected ? <ConnectPrompt /> : chainId !== ACTIVE_CHAIN.id ? <section className={styles.notice}><h2>Switch to {ACTIVE_CHAIN.name}</h2><p>Your membership and payments must use the correct network.</p><ConnectButton /></section>
      : query.isPending ? <LoadingPanel label="Checking V6 and reading your boards…" />
      : query.isError || !s ? <section className={styles.notice} role="alert"><h2>Membership unavailable</h2><p>{query.error ? v6Error(query.error) : "Please refresh to try again."}</p><p>No payment is needed to reload your membership.</p></section>
      : <>
        {(s.paused || s.recovery) && <section className={styles.notice} role="status"><h2>{s.recovery ? "Emergency recovery in progress" : "Registration is paused"}</h2><p>{s.recovery ? "New entries and re-entries are frozen while reserve backing is restored. Your recorded boards remain visible. Unpaid payouts can still be claimed." : "You can review existing boards and claim unpaid payouts. New stage entries are temporarily disabled."} Do not send tokens manually.</p></section>}
        <ClaimPayout amount={s.claimable} />
        {view === "join" ? <V6Join snapshot={s} member={address!} /> : !s.registered ? <NotRegisteredNotice /> : <>
          {view !== "network" && <>
            <dl className={styles.stats}>
              <Stat label="Board rewards allocated" value={memberAmount(s.earned)} note="USDT · includes unpaid board rewards" />
              <Stat label="Stages unlocked" value={`${s.highestStage + 1} / 6`} note="Each stage is a separate activation" />
              <Stat label="Completed boards" value={s.stages.reduce((sum, stage) => sum + stage.completed, 0n).toString()} note="All six stages" />
              <Stat label="Unpaid payouts" value={memberAmount(s.claimable)} note="USDT · available to claim" />
            </dl>
            <V6Stages key={`${address}:${s.block}`} snapshot={s} member={address!} client={query.client!} />
          </>}
          {view !== "boards" && <><ReferralCard address={address} /><NetworkOverview address={address} /></>}
          {view === "overview" && <section className={styles.section}><h2>Beyond the boards</h2><p className={`${styles.muted} mb-4`}>Program availability and eligibility are subject to published terms.</p><div className={styles.benefits}>{["Royalty bonus", "Gaming", "Solar power", "Prediction market"].map(title => <article className={styles.benefit} key={title}><h3>{title}</h3><span className={styles.badge}>Details pending</span></article>)}</div><p className={`${styles.muted} mt-4`}>These are not contract-confirmed awards or delivery promises. <Link href="/legal" className="underline">Read the disclosures.</Link></p></section>}
        </>}
        <p className={styles.muted}>On-chain snapshot at block {s.block.toString()}. Reads are briefly cached; use Refresh for an update. Earnings and board completion are not guaranteed.</p>
      </>}
  </div>;
}

function Stat({ label, value, note }: { label: string; value: string; note: string }) {
  return <div className={styles.stat}><dt>{label}</dt><dd>{value}</dd><small>{note}</small></div>;
}

function TransactionStatus({ tx }: { tx: ReturnType<typeof useV6Transaction> }) {
  return <div aria-live="polite" className="space-y-3 text-sm">
    {tx.message && <p role="status" className={styles.notice}>{tx.message}</p>}
    {tx.error && <p role="alert" className={styles.notice}>{tx.error}</p>}
    {tx.hash && <a className="block break-all text-gold underline" href={`${ACTIVE_CHAIN.blockExplorers.default.url}/tx/${tx.hash}`} target="_blank" rel="noopener noreferrer">View transaction ↗</a>}
  </div>;
}

function ClaimPayout({ amount }: { amount: bigint }) {
  const [recipient, setRecipient] = useState("");
  const tx = useV6Transaction();
  const valid = !recipient.trim() || isAddress(recipient.trim()) && recipient.trim() !== zeroAddress;
  if (amount === 0n) return <TransactionStatus tx={tx} />;
  return <section className={styles.section}><h2>Claim an unpaid payout</h2><p className={styles.muted}>If a direct transfer failed, its payout remains available here. This is not a withdrawal of re-entry reserves. Leave the recipient blank to use your connected wallet.</p>
    <label htmlFor="claim-recipient" className="mt-4 block text-sm">Recipient wallet (optional)</label><input id="claim-recipient" className="my-3 w-full rounded-xl border border-line bg-surface-2 p-3 text-sm" value={recipient} onChange={e => setRecipient(e.target.value)} disabled={tx.busy} spellCheck={false} autoComplete="off" />
    <button className={`${styles.button} ${styles.primary}`} disabled={tx.busy || !valid} onClick={() => void tx.execute("claim", { recipient: recipient.trim() ? getAddress(recipient.trim()) : undefined })}>Claim unpaid payout</button><TransactionStatus tx={tx} />
  </section>;
}

function V6Join({ snapshot: s, member }: { snapshot: V6Snapshot; member: Address }) {
  const tx = useV6Transaction();
  const [sponsor, setSponsor] = useState("");
  const storageKey = `nexaflow:v6:sponsor:${ACTIVE_CHAIN.id}:${MEMBERSHIP_ADDRESS.toLowerCase()}`;
  useEffect(() => {
    const ref = new URLSearchParams(window.location.search).get("ref");
    if (ref && isAddress(ref)) { setSponsor(getAddress(ref)); try { localStorage.setItem(storageKey, getAddress(ref)); } catch {} return; }
    try { const saved = localStorage.getItem(storageKey); if (saved && isAddress(saved)) setSponsor(getAddress(saved)); } catch { /* Storage is optional. */ }
  }, [storageKey]);
  function changeSponsor(value: string) {
    setSponsor(value);
    try { if (!value) localStorage.removeItem(storageKey); else if (isAddress(value)) localStorage.setItem(storageKey, getAddress(value)); } catch {}
  }
  const stage = purchaseStage(s);
  const config = s.stages[stage];
  const sponsorValid = !sponsor.trim() || isAddress(sponsor.trim()) && sponsor.trim().toLowerCase() !== member.toLowerCase();
  const approved = config && s.allowance >= config.fee;
  const ready = config && !s.paused && !s.recovery && (s.registered || sponsorValid) && s.balance >= config.fee && !tx.busy;
  return <div className={styles.stack}>
    <section className={styles.section}>
      <h2>{config ? `Join Stage ${stage + 1}` : "All six stages unlocked"}</h2><p className={styles.muted}>Start at Stage 1 and unlock each next stage in order. You do not need to complete a board before buying the next stage.</p>
      <div className="my-5 grid grid-cols-2 gap-2 sm:grid-cols-3">{s.stages.map(item => <div key={item.id} className="rounded-xl border border-line p-3 text-sm"><strong>Stage {item.id + 1}</strong><p className="mt-1 text-muted">{item.enrolled ? "Joined" : item.id === stage ? "Available" : "Locked"}</p></div>)}</div>
      {!s.registered && <div className="mb-5"><label htmlFor="v6-sponsor" className="block text-sm">Sponsor address (optional)</label><input id="v6-sponsor" className="my-3 w-full rounded-xl border border-line bg-surface-2 p-3 text-sm" value={sponsor} onChange={e => changeSponsor(e.target.value.trim())} disabled={tx.busy} placeholder="Leave blank to start under the protocol" autoComplete="off" spellCheck={false} />
        <p className={styles.muted}>Without a sponsor, you start under the protocol. After joining, use your own referral link to grow your network. A sponsor must already be registered in V6.</p>
        {!sponsorValid && <p role="alert" className="mt-2 text-sm text-down">Enter a valid wallet other than your own, or leave it blank.</p>}
        {sponsor && <button className={styles.button} disabled={tx.busy} onClick={() => changeSponsor("")}>Clear sponsor</button>}
      </div>}
      {config && <div className={styles.stack}>
        <dl className={styles.boardFacts}><Fact label="Entry fee" value={`${memberAmount(config.fee)} USDT`} /><Fact label="Your USDT balance" value={memberAmount(s.balance)} /><Fact label="Qualifying positions" value={String(config.slots)} /><Fact label="Reward per qualifying position" value={`${memberAmount(config.reward)} USDT`} /></dl>
        <p className={styles.muted}>Re-entry reserves accrue from the final {config.reserveSlots} qualifying positions. On completion, the reserve funds a new position; it is not an extra cash bonus. Actual placement is decided by the contract when your transaction executes.</p>
        <button className={`${styles.button} ${styles.primary}`} disabled={!ready} onClick={() => void tx.execute(approved ? "purchase" : "approve", { stage, fee: config.fee, sponsor: sponsor.trim() && isAddress(sponsor.trim()) ? getAddress(sponsor.trim()) : zeroAddress })}>{tx.busy ? "Transaction in progress…" : approved ? `Join Stage ${stage + 1}` : `Approve ${memberAmount(config.fee)} USDT`}</button>
        <p className={styles.muted}>{approved ? "Approval is ready. Joining requires a separate wallet confirmation." : "Approve only this stage’s fee, then select Join. Keep some BNB for network fees."} {s.balance < config.fee ? "Your USDT balance is too low for this stage." : ""}</p>
      </div>}
      {!config && <Link href="/app/board" className={`${styles.button} mt-4`}>View your boards ↗</Link>}
    </section><TransactionStatus tx={tx} />
  </div>;
}

function V6Stages({ snapshot, member, client }: { snapshot: V6Snapshot; member: Address; client: PublicClient }) {
  const [expanded, setExpanded] = useState<number | null>(snapshot.highestStage);
  return <section className={styles.section}><div className={styles.sectionTitle}><h2>Your six stages</h2><span className={styles.badge}>Boards and re-entry history</span></div><div className={styles.stages}>
    {snapshot.stages.map(stage => <article key={stage.id} className={styles.stage}>
      <h3><button className={styles.stageToggle} aria-expanded={expanded === stage.id} aria-controls={`v6-stage-${stage.id}`} onClick={() => setExpanded(expanded === stage.id ? null : stage.id)}><span className={styles.stageNumber}>{stage.id + 1}</span><span className={styles.stageHeading}><strong>Stage {stage.id + 1}</strong><span className="mt-1 block text-sm text-muted">{stage.enrolled ? `${stage.completed} completed · ${stage.latest?.queued ? "Re-entry pending" : `Board #${stage.boards}`}` : stage.id === purchaseStage(snapshot) ? "Ready to unlock" : "Locked"}</span></span><span className={styles.stageValue}>{memberAmount(stage.enrolled ? stage.earned : stage.fee)}<small>{stage.enrolled ? "USDT allocated" : "USDT entry"}</small></span></button></h3>
      <div id={`v6-stage-${stage.id}`} hidden={expanded !== stage.id}>{expanded === stage.id && <div className={styles.stageDetail}>{stage.enrolled ? <BoardDetails stage={stage} snapshot={snapshot} member={member} client={client} /> : <><p className={styles.muted}>{stage.id === purchaseStage(snapshot) ? "This stage is available to join." : `Unlock Stage ${stage.id} first.`}</p><Link className={`${styles.button} mt-4`} href="/app/join">Review stages ↗</Link></>}</div>}</div>
    </article>)}
  </div></section>;
}

function BoardDetails({ stage, snapshot, member, client }: { stage: V6Stage; snapshot: V6Snapshot; member: Address; client: PublicClient }) {
  const [historyOpen, setHistoryOpen] = useState(false);
  const [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState({ id: stage.latestId, position: stage.latest! });
  const tx = useV6Transaction();
  const history = useQuery({ queryKey: [...v6Scope, "history", member, stage.id, snapshot.block.toString(), offset], queryFn: () => readV6History(client, v6Deployment, member, stage.id, stage.boards, offset, snapshot.block), enabled: historyOpen, staleTime: RPC_CACHE_MS.board, retry: 1, ...NO_BACKGROUND_RPC });
  const tree = useQuery({ queryKey: [...v6Scope, "tree", selected.id.toString(), snapshot.block.toString()], queryFn: () => readV6Tree(client, v6Deployment, selected.id, selected.position, stage.depth, snapshot.block), staleTime: RPC_CACHE_MS.board, retry: 1, ...NO_BACKGROUND_RPC });
  const p = selected.position;
  return <div className={styles.stack}>
    <div className={styles.boardLayout}><div><span className={styles.badge}>Board #{p.cycle.toString()} · {p.queued ? "Re-entry queued" : p.closed ? "Completed" : "Open"}</span>
      {tree.isPending ? <LoadingPanel label="Reading placement tree…" /> : tree.isError ? <p role="status" className={styles.notice}>Tree unavailable. Refresh to retry; your positions have not disappeared.</p> : <svg viewBox={`0 0 400 ${80 + stage.depth * 65}`} className="my-4 w-full" role="img" aria-label={`Board ${p.cycle} placement tree; ${p.filled} credited positions out of ${stage.slots}`}>
        {tree.data?.map((node, index) => {
          const level = Math.floor(Math.log2(index + 1)); const first = 2 ** level - 1; const x = (index - first + .5) * 400 / 2 ** level; const y = 30 + level * 65;
          const parent = Math.floor((index - 1) / 2); const parentLevel = level - 1; const parentX = (parent - (2 ** parentLevel - 1) + .5) * 400 / 2 ** parentLevel;
          return <g key={index}><title>{node.position ? `Position ${node.id}: ${node.position.owner}${node.position.closed ? " (closed)" : ""}` : "Open slot"}</title>{index > 0 && <line x1={parentX} y1={y - 65} x2={x} y2={y} stroke="#66583e" />}<circle cx={x} cy={y} r={level === 0 ? 16 : 12} fill={node.position ? node.position.closed ? "#66583e" : "#2c7154" : "#171a20"} stroke={node.position ? "#dab778" : "#62666f"} strokeDasharray={node.position ? undefined : "3 3"} /><text x={x} y={y + 4} textAnchor="middle" fill="#fff" fontSize="11">{index === 0 ? "YOU" : node.position ? String(index) : "–"}</text></g>;
        })}
      </svg>}
      <p className={styles.muted}>Actual placement links for this board. Green positions are open; brown positions are closed. Placement links and qualifying reward credits are different from your permanent referral network.</p>
    </div><dl className={styles.boardFacts}><Fact label="Qualifying positions credited" value={`${p.filled} / ${stage.slots}`} /><Fact label="Positions remaining" value={String(stage.slots - p.filled)} /><Fact label="This board’s allocated rewards" value={`${memberAmount(BigInt(p.filled) * stage.reward)} USDT`} /><Fact label="Re-entry reserve recorded" value={`${memberAmount(p.reserve)} / ${memberAmount(stage.fee)} USDT`} /><Fact label="Completed boards in this stage" value={stage.completed.toString()} /><Fact label="Re-entry positions opened" value={(stage.boards - 1n).toString()} /><Fact label="Placement parent ID" value={p.parent === 0n ? "None (root position)" : p.parent.toString()} /></dl></div>
    <p className={styles.muted}>{snapshot.recovery ? "Reserve amounts are records, not confirmation of funds currently held by the contract during recovery." : "A completed board’s reserve is spent once to fund re-entry. Earlier boards remain in your history; re-entry is not a second cash payout to you."}</p>
    {stage.latest?.queued && <section className={styles.notice}><p>Your completed board is waiting for re-entry placement. Normal purchases process a limited queue automatically. You can also submit a processing transaction; it costs BNB and does not guarantee immediate placement.</p><button className={styles.button} disabled={tx.busy || snapshot.recovery} onClick={() => void tx.execute("process", { stage: stage.id })}>Process pending re-entries</button><TransactionStatus tx={tx} /></section>}
    <button className={styles.button} aria-expanded={historyOpen} onClick={() => setHistoryOpen(!historyOpen)}>{historyOpen ? "Hide" : "Show"} board history ({stage.boards.toString()})</button>
    {historyOpen && <div className={styles.stack}>{history.isPending ? <LoadingPanel label="Reading board history…" /> : history.isError ? <p className={styles.notice}>History could not load. Refresh to retry.</p> : <ul className="space-y-2">{history.data?.map(item => <li key={item.id.toString()}><button className={`${styles.button} w-full justify-between`} aria-pressed={selected.id === item.id} onClick={() => setSelected(item)}><span>Board #{item.position.cycle.toString()}</span><span>{item.position.queued ? "Queued" : item.position.closed ? "Completed" : "Open"} · {item.position.filled}/{stage.slots}</span></button></li>)}</ul>}<div className="flex gap-3"><button className={styles.button} disabled={offset === 0 || history.isFetching} onClick={() => setOffset(Math.max(0, offset - 10))}>Newer</button><button className={styles.button} disabled={BigInt(offset + 10) >= stage.boards || history.isFetching} onClick={() => setOffset(offset + 10)}>Older</button></div></div>}
  </div>;
}

function Fact({ label, value }: { label: string; value: string }) { return <div className={styles.fact}><dt>{label}</dt><dd>{value}</dd></div>; }
