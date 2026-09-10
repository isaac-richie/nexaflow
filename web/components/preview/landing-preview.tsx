import Image from "next/image";
import Link from "next/link";
import { STAGES } from "@/lib/stages";
import { OrbitArt } from "./orbit-art";
import s from "./landing-preview.module.css";

function Arrow() {
  return <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6"/></svg>;
}

export function LandingPreview() {
  return <NexaFlowLanding preview />;
}

/** Shared presentation; only the explicit preview variant links to sample-data routes. */
export function NexaFlowLanding({ preview = false }: { preview?: boolean }) {
  const appHref = preview ? "/preview" : "/app";
  const joinHref = preview ? "/preview" : "/app/join";
  return <div className={s.page}>
    <a className={s.skip} href="#landing-main">Skip to content</a>
    {preview && <div className={s.previewNotice}>DESIGN PREVIEW <span>Explore the next NexaFlow experience. No live V6 transactions.</span><Link href="/preview">Dashboard preview ↗</Link></div>}
    <header className={s.header}>
      <Link className={s.brand} href={preview ? "/preview/landing" : "/"} aria-label={preview ? "NexaFlow landing preview" : "NexaFlow home"}><Image src="/logo-mark.svg" width={36} height={36} alt=""/><span>Nexa<span>Flow</span></span></Link>
      <nav aria-label="Landing navigation"><a href="#journey">The journey</a><a href="#stages">Six stages</a><a href="#possibilities">Beyond the board</a></nav>
      <Link className={s.headerAction} href={appHref}>Explore the app<Arrow/></Link>
    </header>
    <main id="landing-main">
      <section className={s.hero} aria-labelledby="hero-heading">
        <div className={s.heroCopy}><div className={s.eyebrow}><i/>CONNECTED BY COMMUNITY</div><h1 id="hero-heading">Move forward.<br/><em>Together.</em></h1><p>Six stages. Your own pace.<br/>A connected membership experience, with a clear view of every step.</p><div className={s.heroActions}><Link href={joinHref} className={s.primary}>{preview ? "Discover NexaFlow" : "Begin at Stage 1"}<Arrow/></Link><a href="#journey" className={s.secondary}>See how it works <span>↓</span></a></div><span className={s.heroNote}>Start at Stage 1 · Progress sequentially</span></div>
        <div className={s.heroVisual}><OrbitArt/><div className={s.artCaption}><span>01 — 06</span><span>ONE CONNECTED JOURNEY</span></div></div>
        <div className={s.heroFoot}><span>NEXAFLOW / MEMBERSHIP REIMAGINED</span><a href="#journey">A closer look <span>↓</span></a></div>
      </section>
      <section id="journey" className={s.journey} aria-labelledby="journey-heading"><div className={s.sectionIntro}><span className={s.eyebrow}>THE JOURNEY</span><h2 id="journey-heading">Your next step.<br/><em>Always in view.</em></h2><p>From your first registration to your next board, understand where you are—and what comes next.</p></div><div className={s.steps}>
        <article><span>01</span><div><h3>Begin with a connection.</h3><p>Start at Stage 1 with a referral, or join under the protocol when you don’t have a sponsor.</p></div></article>
        <article><span>02</span><div><h3>See your community grow.</h3><p>Follow your board positions and your referral network separately. Know who you introduced and how your wider team connects.</p></div></article>
        <article><span>03</span><div><h3>Keep your progress in perspective.</h3><p>{preview ? "View completed boards, your current cycle and re-entry reserves. A funded re-entry opens a new position—not an extra cash bonus." : "See your completed-board counts, current cycle and recorded earnings. Track board progress separately from your permanent referral network."}</p></div></article>
      </div></section>
      <section id="stages" className={s.stages} aria-labelledby="stages-heading"><div className={s.sectionTitle}><div><span className={s.eyebrow}>A CLEAR PATH FORWARD</span><h2 id="stages-heading">Six stages.<br className={s.mobileBreak}/> <em>One journey.</em></h2></div><p>Begin at Stage 1. Unlock each next stage when you choose, after joining the previous one.</p></div><div className={s.stageGrid}>{STAGES.map(({ fee, id, label }) => <article key={id}><span className={s.stageIndex}>0{id + 1}</span><h3>{label}</h3><div className={s.stageFee}>{fee.toLocaleString("en-US")}<span>USDT</span></div><p>{id === 0 ? "Your starting point" : "Continue your journey"}</p></article>)}</div><div className={s.stageDisclaimer}><span>{preview ? "Stage entry amounts shown for the proposed experience." : "Indicative stage fees. Confirm the current amount in the app before approving payment."}</span><span>Participation involves risk. Earnings and board completion are not guaranteed.</span></div></section>
      <section id="possibilities" className={s.possibilities} aria-labelledby="possibilities-heading"><div><span className={s.eyebrow}>BEYOND THE BOARD</span><h2 id="possibilities-heading">More possibilities.<br/><em>One community.</em></h2><p>An introduction to the wider NexaFlow vision. Features, eligibility and availability remain subject to confirmation.</p><Link href={appHref} className={s.secondary}>Explore the member experience <Arrow/></Link></div><div className={s.benefitList}>{["Royalty bonus", "Gaming", "Solar power", "Prediction market"].map((benefit, i) => <div key={benefit}><span>0{i + 1}</span><h3>{benefit}</h3><span className={s.planned}>Details pending</span></div>)}</div></section>
      <section className={s.closing}><span className={s.eyebrow}>YOUR JOURNEY, WITH CLARITY</span><h2>A new perspective.<br/><em>A shared direction.</em></h2><Link href={joinHref} className={s.primary}>{preview ? "Step inside the preview" : "Start your journey"}<Arrow/></Link><p>{preview ? "Explore the experience. No wallet connection required." : "Joining requires a connected wallet, USDT on BNB Smart Chain and BNB for network fees."}</p></section>
    </main>
    <footer className={s.footer}><div className={s.brand}><Image src="/logo-mark.svg" width={26} height={26} alt=""/><span>Nexa<span>Flow</span></span></div><p>Move forward. Together.</p><Link href="/legal">Terms & disclosures ↗</Link><span>{preview ? "Design preview · Not a live V6 launch" : "Earnings depend on subsequent qualifying participation and are not guaranteed. Entry fees are non-refundable except where required by law. No independent third-party audit has been completed."}</span></footer>
  </div>;
}
