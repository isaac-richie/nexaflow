"use client";

import Image from "next/image";
import Link from "next/link";
import { useId, useRef, useState } from "react";
import { motion, MotionConfig } from "framer-motion";
import {
  PREVIEW_BOARDS, PREVIEW_CLAIMABLE, PREVIEW_DELIVERED, PREVIEW_EARNED,
  PREVIEW_GENERATIONS, PREVIEW_RESERVED, boardEarnings, boardReserve, canUnlock,
  previewMoney, type PreviewBoard,
} from "@/lib/preview/dashboard";
import s from "./dashboard-preview.module.css";

type View = "overview" | "boards" | "network" | "benefits";
type IconName = "overview" | "boards" | "network" | "benefits" | "arrow" | "check" | "lock" | "chevron" | "wallet" | "cycle";
const navigation: { id: View; label: string; mobile: string }[] = [
  { id: "overview", label: "Overview", mobile: "Home" },
  { id: "boards", label: "My boards", mobile: "Boards" },
  { id: "network", label: "My network", mobile: "Network" },
  { id: "benefits", label: "Benefits", mobile: "Benefits" },
];

function Icon({ name, className = "" }: { name: IconName; className?: string }) {
  const paths: Record<IconName, React.ReactNode> = {
    overview: <><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></>,
    boards: <><rect x="4" y="3" width="16" height="5" rx="1.5"/><rect x="4" y="11" width="16" height="10" rx="1.5"/><path d="M9 15h6M9 18h4"/></>,
    network: <><circle cx="12" cy="5" r="3"/><circle cx="5" cy="19" r="3"/><circle cx="19" cy="19" r="3"/><path d="M12 8v5M5 16v-3h14v3"/></>,
    benefits: <><path d="M3 9h18v4H3zM5 13v8h14v-8M12 9v12"/><path d="M12 9C2 9 5 0 9 4l3 5Zm0 0c10 0 7-9 3-5l-3 5Z"/></>,
    arrow: <path d="M5 12h14m-5-5 5 5-5 5"/>,
    check: <path d="m5 12 4 4L19 6"/>,
    lock: <><rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/></>,
    chevron: <path d="m8 10 4 4 4-4"/>,
    wallet: <><rect x="3" y="5" width="18" height="15" rx="3"/><path d="M17 10h4v5h-4a2.5 2.5 0 0 1 0-5ZM4 5l12-3v3"/></>,
    cycle: <><path d="M20 10a8 8 0 0 0-14-4L3 9m0-5v5h5M4 14a8 8 0 0 0 14 4l3-3m0 5v-5h-5"/></>,
  };
  return <svg className={className} width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

function BoardTree({ board, filled, cycle }: { board: PreviewBoard; filled: number; cycle: number }) {
  const titleId = useId();
  const depth = board.slots === 6 ? 2 : 3;
  const nodes = Array.from({ length: board.slots + 1 }, (_, index) => {
    const level = Math.floor(Math.log2(index + 1));
    const position = index - (2 ** level - 1);
    return { x: (position + 0.5) * 560 / 2 ** level, y: 30 + level * 58, active: index <= filled };
  });
  return (
    <figure className={s.tree}>
      <svg viewBox={`0 0 560 ${depth * 58 + 60}`} role="img" aria-labelledby={titleId}>
        <title id={titleId}>{`Stage ${board.stage}, board ${cycle}: ${filled} of ${board.slots} positions filled. Sample data.`}</title>
        {nodes.slice(1).map((node, i) => {
          const parent = nodes[Math.floor(i / 2)];
          return <path key={`edge-${i}`} d={`M${parent.x} ${parent.y + 14} V${node.y - 26} H${node.x} V${node.y - 14}`} className={node.active ? s.edgeFilled : s.edgeEmpty} fill="none"/>;
        })}
        {nodes.map((node, i) => <g key={i}>
          <circle cx={node.x} cy={node.y} r={i === 0 ? 19 : 14} className={i === 0 ? s.nodeRoot : node.active ? s.nodeFilled : s.nodeEmpty}/>
          <text x={node.x} y={node.y + 4} textAnchor="middle" className={i === 0 ? s.rootText : s.nodeText}>{i === 0 ? "YOU" : node.active ? String(i).padStart(2, "0") : "·"}</text>
        </g>)}
      </svg>
      <figcaption><span><i className={s.legendFilled}/>Filled</span><span><i className={s.legendEmpty}/>Open</span><span>{board.slots - filled} positions remaining</span></figcaption>
    </figure>
  );
}

function StageDetail({ board }: { board: PreviewBoard }) {
  const [cycle, setCycle] = useState(board.completed + 1);
  const historical = cycle <= board.completed;
  const filled = historical ? board.slots : board.filled;
  if (!board.unlocked) return <div className={s.lockedDetail}>
    <span className={s.lockIcon}><Icon name="lock"/></span>
    <div><h3>{canUnlock(board) ? `Stage ${board.stage} is ready to unlock` : `Stage ${board.stage} is locked`}</h3><p>{canUnlock(board) ? `Your previous stage is unlocked. You can activate this stage for ${previewMoney(board.fee)} USDT.` : `Join Stage ${board.stage - 1} first, then activate this stage for ${previewMoney(board.fee)} USDT.`} Board completion is not required to buy the next stage.</p><span className={s.previewHint}>Preview only — stage purchases are disabled.</span></div>
  </div>;
  return <div className={s.stageDetail}>
    <div className={s.boardToolbar}>
      <div><span className={s.eyebrow}>YOUR BOARD</span><h3>Board {String(cycle).padStart(2, "0")} <span className={historical ? s.neutralBadge : s.greenBadge}>{historical ? "Completed" : "Active"}</span></h3></div>
      <label className={s.historyLabel}>Board history<select value={cycle} onChange={event => setCycle(Number(event.target.value))} aria-label={`Stage ${board.stage} board history`}>
        {Array.from({ length: board.completed + 1 }, (_, index) => index + 1).reverse().map(id => <option key={id} value={id}>Board {id}{id > board.completed ? " · Current" : " · Completed"}</option>)}
      </select></label>
    </div>
    <div className={s.boardContent}>
      <BoardTree board={board} filled={filled} cycle={cycle}/>
      <div className={s.boardNumbers}>
        <div><span>Board progress</span><strong>{filled}<small> / {board.slots}</small></strong></div>
        <div><span>This board earned</span><strong>{previewMoney(filled * board.reward)}<small> USDT</small></strong></div>
        <div><span>{historical ? "Re-entry fee used" : "Reserved for re-entry"}</span><strong>{previewMoney(historical ? board.fee : boardReserve(board))}<small> USDT</small></strong></div>
        <p>{historical ? "This board is closed. Its reserve funded the next position." : "The reserve funds your next position at this stage. It is not a withdrawable bonus."}</p>
      </div>
    </div>
    <div className={s.boardFoot}><span><Icon name="cycle"/>{board.completed} completed {board.completed === 1 ? "board" : "boards"}</span><span>{previewMoney(boardEarnings(board))} USDT earned across this stage</span></div>
  </div>;
}

function Stages({ initialStage = 1 }: { initialStage?: number }) {
  const [expanded, setExpanded] = useState<number | null>(initialStage);
  return <section className={s.panel} aria-labelledby="stages-heading">
    <div className={s.sectionHead}><div><span className={s.eyebrow}>SIX STAGES. YOUR PACE.</span><h2 id="stages-heading">Your board journey</h2></div><span className={s.neutralBadge}>3 of 6 unlocked</span></div>
    <div className={s.stageList}>{PREVIEW_BOARDS.map(board => <div className={s.stageItem} key={board.stage}>
      <h3><button className={`${s.stageButton} ${expanded === board.stage ? s.stageSelected : ""}`} aria-expanded={expanded === board.stage} aria-controls={`stage-detail-${board.stage}`} id={`stage-trigger-${board.stage}`} onClick={() => setExpanded(expanded === board.stage ? null : board.stage)}>
        <span className={`${s.stageNumber} ${!board.unlocked ? s.stageNumberLocked : ""}`}>{String(board.stage).padStart(2, "0")}</span>
        <span className={s.stageName}><strong>Stage {board.stage}</strong><span>{board.unlocked ? `Board ${board.completed + 1} · ${board.filled}/${board.slots} filled` : `${previewMoney(board.fee)} USDT to unlock`}</span></span>
        <span className={s.stageTrack} aria-hidden="true"><i style={{ width: `${board.filled / board.slots * 100}%` }}/></span>
        <span className={s.stageValue}>{board.unlocked ? <><strong>{previewMoney(boardEarnings(board))}</strong><span>USDT earned</span></> : <><Icon name="lock"/><span>{canUnlock(board) ? "Available" : "Locked"}</span></>}</span>
        <Icon name="chevron" className={`${s.chevron} ${expanded === board.stage ? s.chevronOpen : ""}`}/>
      </button></h3>
      <div id={`stage-detail-${board.stage}`} role="region" aria-labelledby={`stage-trigger-${board.stage}`} hidden={expanded !== board.stage}><StageDetail board={board}/></div>
    </div>)}</div>
  </section>;
}

function Network({ compact = false, onExplore }: { compact?: boolean; onExplore?: () => void }) {
  const total = PREVIEW_GENERATIONS.reduce((sum, n) => sum + n, 0);
  return <section className={s.panel} aria-labelledby="network-heading">
    <div className={s.sectionHead}><div><span className={s.eyebrow}>PEOPLE, NOT POSITIONS</span><h2 id="network-heading">Your network</h2></div><Icon name="network"/></div>
    <div className={s.networkCounts}><div><strong>{PREVIEW_GENERATIONS[0]}</strong><span>Direct referrals</span></div><div><strong>{total}</strong><span>Total team members</span></div></div>
    {!compact && <div className={s.generations}>{PREVIEW_GENERATIONS.map((count, i) => <div key={i}><span>Generation {i + 1}</span><div className={s.generationTrack}><i style={{ width: `${count / 24 * 100}%` }}/></div><strong>{count}</strong></div>)}</div>}
    <p className={s.panelCopy}>Your team includes your direct referrals and the people below them. Rollovers do not add new members.</p>
    {onExplore && <button className={s.textButton} onClick={onExplore}>Explore your network<Icon name="arrow"/></button>}
    {!compact && <p className={s.previewHint}>Sample network. Live branch exploration will be connected in the integration phase.</p>}
  </section>;
}

function Benefits() {
  return <section className={s.panel}>
    <div className={s.sectionHead}><div><span className={s.eyebrow}>BEYOND YOUR BOARDS</span><h2>Membership benefits</h2></div><Icon name="benefits"/></div>
    <p className={s.panelCopy}>A preview of the benefits area. Availability, eligibility and fulfilment have not been verified here.</p>
    <div className={s.benefits}>{["Royalty bonus", "Gaming", "Solar power", "Prediction market"].map((name, i) => <article key={name}><span className={s.benefitIndex}>0{i + 1}</span><h3>{name}</h3><span className={s.neutralBadge}>Details pending</span></article>)}</div>
  </section>;
}

export function DashboardPreview() {
  const [view, setView] = useState<View>("overview");
  const [notice, setNotice] = useState("");
  const headingRef = useRef<HTMLHeadingElement>(null);
  function navigate(next: View) {
    setView(next);
    setNotice("");
    requestAnimationFrame(() => {
      headingRef.current?.focus({ preventScroll: true });
      window.scrollTo({ top: 0, behavior: "auto" });
    });
  }
  const title = { overview: "A clear view of your progress.", boards: "Every stage. Every board.", network: "See how your team connects.", benefits: "More to your membership." }[view];
  return <MotionConfig reducedMotion="user"><div className={s.shell}>
    <a href="#preview-main" className={s.skip}>Skip to dashboard</a>
    <aside className={s.sidebar}>
      <div className={s.brand}><Image src="/logo-mark.svg" alt="" width={34} height={34}/><span>Nexa<span>Flow</span></span></div>
      <div className={s.workspaceLabel}>MEMBER SPACE</div>
      <nav aria-label="Desktop preview navigation">{navigation.map(item => <button key={item.id} className={`${s.navButton} ${view === item.id ? s.navActive : ""}`} aria-current={view === item.id ? "page" : undefined} onClick={() => navigate(item.id)}><Icon name={item.id}/>{item.label}{view === item.id && <span className={s.activeDot}/>}</button>)}</nav>
      <div className={s.sidebarFoot}><span className={s.previewBadge}>DESIGN PREVIEW</span><p>A new perspective.<br/>The same NexaFlow.</p><Link href="/app">Go to live dashboard<Icon name="arrow"/></Link></div>
    </aside>
    <div className={s.workspace}>
      <header className={s.topbar}><div className={s.mobileBrand}><Image src="/logo-mark.svg" alt="" width={28} height={28}/><strong>NexaFlow</strong></div><span className={s.breadcrumb}>Member space <span>/</span> {navigation.find(item => item.id === view)?.label}</span><span className={s.account}><span className={s.avatar}>N</span> Demo member <Icon name="wallet"/></span></header>
      <div className={s.previewBanner}><span className={s.bannerDot}/><strong>Preview mode</strong><span>Sample data only. No wallet connected. No transactions.</span></div>
      <main id="preview-main" className={s.main} tabIndex={-1}>
        <div className={s.pageHeading}><div><span className={s.eyebrow}>{view === "overview" ? "YOUR OVERVIEW" : navigation.find(item => item.id === view)?.label.toUpperCase()}</span><h1 ref={headingRef} tabIndex={-1}>{title}</h1></div><span className={s.sampleLabel}>V6 design study · 01</span></div>
        <motion.div key={view} initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.18 }}>
          {view === "overview" && <>
            <div className={s.summaryGrid}>
              <section className={s.earningsCard} aria-label="Sample earnings summary"><div className={s.earningsTop}><span>Total earned</span><Icon name="wallet"/></div><div className={s.balance}>{previewMoney(PREVIEW_EARNED)} <span>USDT</span></div><p>Across your three active stages</p><div className={s.balanceBreakdown}><div><span><Icon name="check"/>Delivered to wallet</span><strong>{previewMoney(PREVIEW_DELIVERED)} <small>USDT</small></strong></div><div><span>Available to claim</span><strong>{previewMoney(PREVIEW_CLAIMABLE)} <small>USDT</small></strong></div></div></section>
              <section className={s.nextCard}><span className={s.eyebrow}>YOUR NEXT STEP</span><span className={s.nextStage}>04<span>STAGE</span></span><h2>Ready when you are.</h2><p>Your next stage is available to unlock for <strong>540 USDT</strong>.</p><button className={s.primaryButton} onClick={() => { navigate("boards"); setNotice("Stage purchases are disabled in this design preview. No wallet request has been made."); }}>Explore stages<Icon name="arrow"/></button></section>
            </div>
            <div className={s.quickStats}><div><Icon name="boards"/><span>Stages unlocked<strong>3 <small>/ 6</small></strong></span></div><div><Icon name="cycle"/><span>Completed boards<strong>3</strong></span></div><div><Icon name="wallet"/><span>Re-entry reserves<strong>{previewMoney(PREVIEW_RESERVED)} <small>USDT</small></strong></span></div></div>
            <div className={s.contentGrid}><Stages/><div className={s.rightColumn}><Network compact onExplore={() => navigate("network")}/><section className={s.panel}><div className={s.sectionHead}><div><span className={s.eyebrow}>SAMPLE ACTIVITY</span><h2>Small steps. Real clarity.</h2></div></div><ol className={s.activity}><li><span className={s.activityIcon}><Icon name="check"/></span><div><strong>Position reward delivered</strong><span>Stage 1 · Current board</span></div><b>+5 USDT</b></li><li><span className={s.activityIcon}><Icon name="cycle"/></span><div><strong>New board opened</strong><span>Stage 1 · Board 3</span></div></li><li><span className={s.activityIcon}><Icon name="network"/></span><div><strong>A new direct referral</strong><span>Your team now has 60 members</span></div></li></ol><p className={s.previewHint}>Illustrative entries, not a live transaction feed.</p></section></div></div>
          </>}
          {view === "boards" && <><div className={s.inlineNotice}><Icon name="cycle"/><p>Completed boards stay in your history. Re-entry reserves fund a new position at the same stage—not an extra cash bonus.</p></div><Stages initialStage={3}/></>}
          {view === "network" && <Network/>}
          {view === "benefits" && <Benefits/>}
        </motion.div>
        <div className={s.statusMessage} role="status">{notice}</div>
        <footer className={s.footer}><span>NexaFlow · Member experience</span><span>Sample figures are not earnings promises.</span></footer>
      </main>
    </div>
    <nav className={s.bottomNav} aria-label="Mobile preview navigation">{navigation.map(item => <button key={item.id} aria-current={view === item.id ? "page" : undefined} className={view === item.id ? s.bottomActive : ""} onClick={() => navigate(item.id)}><Icon name={item.id}/><span>{item.mobile}</span></button>)}</nav>
  </div></MotionConfig>;
}
