"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useAccount } from "wagmi";
import { ACTIVE_CHAIN, IS_DEPLOYED } from "@/lib/contracts/config";
import { useAllStageMemberships, useMember, useStageConfigs } from "@/hooks/use-membership";
import { buildMemberDashboard, memberAmount, memberReadState } from "@/lib/member-dashboard";
import { ConnectPrompt, LoadingPanel, NotDeployedNotice, NotRegisteredNotice } from "./states";
import { ConnectButton } from "./connect-button";
import { MemberStages } from "./member-stages";
import { ReferralCard } from "./referral-card";
import { NetworkOverview } from "./network-overview";
import styles from "./member-ui.module.css";

export function MemberDashboard({ view = "overview" }: { view?: "overview" | "boards" | "network" }) {
  const account = useAccount();
  // Remount local UI state when the wallet changes. Query keys remain address-scoped.
  return <WalletDashboard key={`${account.address ?? "none"}:${account.chainId}`} view={view} />;
}

function WalletDashboard({ view }: { view: "overview" | "boards" | "network" }) {
  const { address, isConnected, chainId } = useAccount();
  const memberQuery = useMember();
  const stageQuery = useAllStageMemberships();
  const configQuery = useStageConfigs();
  const [cooldown, setCooldown] = useState(false);
  const refreshing = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(timer.current), []);
  const wrongChain = chainId !== ACTIVE_CHAIN.id;
  const state = memberReadState({ connected: isConnected, deployed: IS_DEPLOYED, wrongChain, loading: memberQuery.isLoading, member: memberQuery.isError && !memberQuery.member?.active ? undefined : memberQuery.member });
  const fetching = memberQuery.isFetching || stageQuery.isFetching || configQuery.isFetching;
  const failed = memberQuery.isError || stageQuery.isError || configQuery.isError;
  const model = memberQuery.member ? buildMemberDashboard(memberQuery.member, stageQuery.stages, configQuery.configs) : undefined;

  async function refresh() {
    if (refreshing.current || cooldown || fetching || !isConnected || wrongChain || !IS_DEPLOYED) return;
    refreshing.current = true;
    setCooldown(true);
    try { await Promise.all([memberQuery.refetch(), stageQuery.refetch(), configQuery.refetch()]); }
    finally {
      refreshing.current = false;
      timer.current = setTimeout(() => setCooldown(false), 15_000);
    }
  }

  return (
    <div>
      <header className={styles.heading}>
        <div><p className={styles.eyebrow}>Your member space</p><h1>{view === "boards" ? "Every board. Your progress." : view === "network" ? "The people you bring together." : "Welcome to your next chapter."}</h1><p className={styles.muted}>{view === "boards" ? "All six stages, without the clutter." : view === "network" ? "Your referrals and the community growing beneath them." : "Your earnings, your boards, your community."}</p></div>
        {IS_DEPLOYED && isConnected && !wrongChain && <button type="button" onClick={refresh} disabled={fetching || cooldown} className={styles.button} aria-label="Refresh membership and board data">{fetching ? "Updating…" : cooldown ? "Please wait" : "Refresh ↻"}</button>}
      </header>
      {state === "unconfigured" ? <NotDeployedNotice /> : state === "disconnected" ? <ConnectPrompt /> : state === "wrong-chain" ? (
        <section className={styles.notice}><h2>Switch to {ACTIVE_CHAIN.name}</h2><p>Your membership is on {ACTIVE_CHAIN.name}. Switch networks to see the correct boards.</p><ConnectButton className="mt-4" /></section>
      ) : state === "loading" ? <LoadingPanel label="Loading your membership…" /> : state === "unavailable" ? (
        <section className={styles.notice} role="alert"><h2>We couldn’t load your membership</h2><p>Please use Refresh to try again. No payment is needed to reload this page.</p></section>
      ) : state === "unregistered" ? <NotRegisteredNotice /> : model && (
        <div className={styles.stack}>
          {(failed || (model.partial && !fetching)) && <p role="status" className={styles.notice}>{failed ? "Some reads could not refresh. Any available figures are the last successful readings." : "Some stage details are unavailable."} Unknown values are shown as a dash, not zero. Use Refresh to retry.</p>}
          {view !== "network" && <><dl className={styles.stats}>
            <Stat label="Board earnings" value={memberAmount(model.earned)} note="USDT · total recorded" />
            <Stat label="Active stages" value={model.activeStages === undefined ? "—" : `${model.activeStages} / 6`} note="Stages you have unlocked" />
            <Stat label="Completed boards" value={model.completedBoards?.toLocaleString("en-US") ?? "—"} note="Across all stages" />
            <Stat label="Awards recorded" value={memberAmount(model.totalAwarded)} note="USDT · separate from board earnings" />
          </dl>
          {stageQuery.isLoading || configQuery.isLoading ? <LoadingPanel label="Reading all six boards…" /> : <MemberStages key={`${address}:${model.currentStage ?? "partial"}`} stages={model.stages} currentStage={model.currentStage} />}</>}
          {view !== "boards" && <>
            <ReferralCard key={address} address={address} />
            <div id="network" className="scroll-mt-6"><NetworkOverview key={address} address={address} /></div>
          </>}
          {view === "overview" && <>
            <section className={styles.section} aria-labelledby="benefits-title">
              <div className={styles.sectionTitle}><div><h2 id="benefits-title">Beyond the boards</h2><p className={styles.muted}>The community program. Availability and eligibility are subject to published terms.</p></div></div>
              <div className={styles.benefits}>{["Royalty bonus", "Gaming", "Solar power", "Prediction market"].map((title, i) => <article key={title} className={styles.benefit}><span className={styles.eyebrow}>0{i + 1}</span><h3>{title}</h3><span className={styles.badge}>Details pending</span></article>)}</div>
              <p className={`${styles.muted} mt-4`}>This dashboard does not confirm benefit eligibility, product delivery or availability. <Link href="/legal" className="underline underline-offset-4">Read the program disclosures.</Link></p>
            </section>
          </>}
          <p className={styles.muted}>Balances are cached briefly to limit network requests. Refresh for a new reading. Earnings and board completion are not guaranteed.</p>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, note }: { label: string; value: string; note: string }) {
  return <div className={styles.stat}><dt>{label}</dt><dd>{value}</dd><small>{note}</small></div>;
}
