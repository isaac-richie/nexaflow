"use client";

import { useState } from "react";
import Link from "next/link";
import { type StageView, memberAmount } from "@/lib/member-dashboard";
import { STAGE_PRESETS, ZERO_ADDRESS } from "@/lib/contracts/config";
import { LiveBoard } from "./live-board";
import styles from "./member-ui.module.css";

export function MemberStages({ stages, currentStage }: { stages: StageView[]; currentStage?: number }) {
  const [expanded, setExpanded] = useState<number | null>(currentStage ?? null);
  return (
    <section className={styles.section} aria-labelledby="member-stages-title">
      <div className={styles.sectionTitle}>
        <div><h2 id="member-stages-title">Your six stages</h2><p className={styles.muted}>One clear view. Open a stage to explore its board.</p></div>
        <span className={styles.badge}>Sequential progression</span>
      </div>
      <div className={styles.stages}>
        {stages.map(stage => {
          const { id, state, membership, config } = stage;
          const open = id === expanded;
          const active = state === "active";
          const label = `Stage ${id + 1}`;
          return (
            <article key={id} className={styles.stage}>
              <h3>
                <button type="button" className={styles.stageToggle} aria-expanded={open} aria-controls={`member-stage-${id}`} onClick={() => setExpanded(open ? null : id)}>
                  <span className={styles.stageNumber}>{String(id + 1).padStart(2, "0")}</span>
                  <span className={styles.stageHeading}>
                    <strong>{label}</strong>
                    <span className="mt-1 block text-xs text-muted">{active ? `${membership!.slotsFilledBelow}/${config!.treeSlots} filled · Board #${stage.currentBoard}` : state === "available" ? "Ready to unlock" : state === "locked" ? `Unlock Stage ${id} first` : "Details unavailable"}</span>
                  </span>
                  <span className={styles.stageValue}>{active ? memberAmount(membership!.stageEarnings) : config ? memberAmount(config.fee) : "—"}<small>{active ? "USDT earned" : "USDT entry"}</small></span>
                  <svg className={styles.chevron} width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
                </button>
              </h3>
              <div id={`member-stage-${id}`} hidden={!open}>
                {open && <div className={styles.stageDetail}>
                  {state === "unavailable" ? <p className={styles.muted}>We couldn’t read this stage. Refresh to try again; this does not mean your board or earnings are empty.</p> : !active ? (
                    <div className={styles.stack}>
                      <p className={styles.muted}>{state === "available" ? `${label} is available. Review the current fee and approve it on the Join page.` : `Complete activation of Stage ${id} before joining this stage. Each stage is a separate paid activation.`} This board has {config!.treeSlots.toString()} positions.</p>
                      {state === "available" && <div><Link href="/app/join" className={`${styles.button} ${styles.primary}`}>Review {label} entry ↗</Link></div>}
                    </div>
                  ) : (
                    <div className={styles.boardLayout}>
                      <div>
                        <span className={`${styles.badge} ${styles.active}`}>Current board #{stage.currentBoard!.toString()}</span>
                        {[6n, 14n].includes(config!.treeSlots) ? <LiveBoard preset={{ ...STAGE_PRESETS[id], slots: Number(config!.treeSlots) }} membership={membership} /> : <p className={styles.muted}>Diagram unavailable for this board size.</p>}
                        <p className={styles.muted}>Progress illustration, not an exact map of member positions. Explore your referral lineage in Network.</p>
                      </div>
                      <div className={styles.boardFacts}>
                        <dl className={styles.boardFacts}>
                          <Fact label="Completed boards" value={membership!.rolloverCount.toLocaleString("en-US")} />
                          <Fact label="Positions remaining" value={stage.remaining!.toString()} />
                          <Fact label="Current reward per position" value={`${memberAmount(config!.nodeReward)} USDT`} />
                          <Fact label="Awards recorded" value={`${memberAmount(membership!.totalAwarded)} USDT`} />
                          <Fact label="Award milestone" value={stage.nextMilestone === undefined ? "Not applicable" : stage.milestoneReached ? "Milestone reached" : `${stage.nextMilestone} completed boards`} />
                          <Fact label="Left placement" value={<PositionAddress address={membership!.left} />} />
                          <Fact label="Right placement" value={<PositionAddress address={membership!.right} />} />
                        </dl>
                        <p className={styles.muted}>Completed boards are recorded as a count. Previous board occupants are not available here. Award fulfilment requires the program’s checks; reaching a milestone is not a delivery confirmation.</p>
                      </div>
                    </div>
                  )}
                </div>}
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}

function Fact({ label, value }: { label: string; value: React.ReactNode }) {
  return <div className={styles.fact}><dt>{label}</dt><dd>{value}</dd></div>;
}

function PositionAddress({ address }: { address: string }) {
  return address === ZERO_ADDRESS ? <>Open</> : <abbr title={address}>{address.slice(0, 6)}…{address.slice(-4)}</abbr>;
}
