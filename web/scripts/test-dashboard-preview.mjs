import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import vm from "node:vm";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";

const require = createRequire(import.meta.url);
function load(relative, mocks = {}, env = {}) {
  const source = readFileSync(new URL(relative, import.meta.url), "utf8");
  const js = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, jsx: ts.JsxEmit.ReactJSX,
    esModuleInterop: true,
  } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(js, {
    exports: module.exports, module,
    require: name => Object.hasOwn(mocks, name) ? mocks[name] : require(name),
    process: { env }, console, Intl,
  });
  return module.exports;
}

const data = load("../lib/preview/dashboard.ts");
test("preview earnings, delivered funds and claims reconcile without counting reserves as earnings", () => {
  assert.equal(data.PREVIEW_EARNED, 405);
  assert.equal(data.PREVIEW_DELIVERED, 395);
  assert.equal(data.PREVIEW_CLAIMABLE, 10);
  assert.equal(data.PREVIEW_DELIVERED + data.PREVIEW_CLAIMABLE, data.PREVIEW_EARNED);
  assert.equal(data.PREVIEW_RESERVED, 30);
});
test("six fixture stages have the approved fees, slots and exact terminal reserve", () => {
  assert.deepEqual(Array.from(data.PREVIEW_BOARDS, x => x.fee), [20, 60, 180, 540, 1620, 4860]);
  for (const board of data.PREVIEW_BOARDS) {
    assert.equal(board.slots, board.stage === 1 ? 6 : 14);
    assert.ok(board.filled <= board.slots);
    assert.equal(data.boardReserve({ ...board, filled: board.slots }), board.fee);
    assert.equal(data.boardReserve({ ...board, filled: 0 }), 0);
  }
});
test("only the next sequential locked stage is available", () => {
  assert.deepEqual(Array.from(data.PREVIEW_BOARDS, data.canUnlock), [false, false, false, true, false, false]);
});
test("network figures count people separately from board history", () => {
  assert.equal(data.PREVIEW_GENERATIONS[0], 6);
  assert.equal(data.PREVIEW_GENERATIONS.reduce((a, b) => a + b, 0), 60);
});

function runtimeAt(pathname) {
  const marker = name => ({ children }) => React.createElement("div", { "data-test": name }, children);
  const { SiteRuntime } = load("../components/site-runtime.tsx", {
    "next/navigation": { usePathname: () => pathname },
    "@/app/providers": { Providers: marker("wallet-providers") },
    "@/components/background-effects": { BackgroundEffects: marker("background") },
    "@/components/consent-gate": { ConsentGate: marker("consent") },
  });
  return renderToStaticMarkup(React.createElement(SiteRuntime, null, "route content"));
}
test("exact preview route mounts no wallet provider, consent gate or background", () => {
  assert.equal(runtimeAt("/preview"), "route content");
  assert.equal(runtimeAt("/preview/landing"), "route content");
});
test("all existing live routes retain wallet providers and consent gate", () => {
  for (const route of ["/", "/app", "/app/join", "/app/board", "/r/example", "/legal", "/preview-other", "/preview/nested", "/preview/landing-other", "/preview/landing/nested"]) {
    const html = runtimeAt(route);
    assert.match(html, /data-test="wallet-providers"/);
    assert.match(html, /data-test="consent"/);
    assert.match(html, /id="site-content"/);
  }
});

const animationPolicy = load("../lib/preview/animation-policy.ts");
test("3D autoplay is off for reduced motion, compact screens, data saving or limited hardware", () => {
  const normal = { reducedMotion: false, compact: false, saveData: false, limitedDevice: false };
  assert.equal(animationPolicy.mayAutoplay(normal), true);
  for (const key of Object.keys(normal)) assert.equal(animationPolicy.mayAutoplay({ ...normal, [key]: true }), false);
});
test("animation requires visibility and stops when paused or reduced motion is enabled", () => {
  const enabled = { enabled: true, paused: false, inView: true, documentVisible: true, reducedMotion: false };
  assert.equal(animationPolicy.mayRenderAnimation(enabled), true);
  for (const key of ["enabled", "inView", "documentVisible"]) assert.equal(animationPolicy.mayRenderAnimation({ ...enabled, [key]: false }), false);
  for (const key of ["paused", "reducedMotion"]) assert.equal(animationPolicy.mayRenderAnimation({ ...enabled, [key]: true }), false);
  assert.equal(animationPolicy.HERO_FRAME_INTERVAL_MS, 1000 / 30);
});
test("landing route is gated in production and excluded from search indexing", () => {
  const landingAt = env => load("../app/preview/landing/page.tsx", {
    "next/navigation": { notFound: () => { throw new Error("NOT_FOUND"); } },
    "@/components/preview/landing-preview": { LandingPreview: () => null },
  }, env);
  assert.throws(() => landingAt({ NODE_ENV: "production" }).default(), /NOT_FOUND/);
  assert.doesNotThrow(() => landingAt({ NODE_ENV: "development" }).default());
  assert.doesNotThrow(() => landingAt({ NODE_ENV: "production", NEXAFLOW_DESIGN_PREVIEW: "true" }).default());
  assert.equal(landingAt({ NODE_ENV: "development" }).metadata.robots.index, false);
});
test("landing contains six stages, risk wording and preview-only application calls to action", () => {
  const { LandingPreview } = load("../components/preview/landing-preview.tsx", {
    "@/lib/stages": load("../lib/stages.ts"),
    "./orbit-art": { OrbitArt: () => React.createElement("div", { "data-test": "orbit-art" }) },
    "./landing-preview.module.css": new Proxy({}, { get: (_target, key) => key === "__esModule" ? false : String(key) }),
    "next/image": ({ src, alt, width, height }) => React.createElement("img", { src, alt, width, height }),
    "next/link": ({ href, children }) => React.createElement("a", { href }, children),
  });
  const html = renderToStaticMarkup(React.createElement(LandingPreview));
  for (let i = 1; i <= 6; i++) assert.match(html, new RegExp(`Stage ${i}`));
  assert.match(html, /not guaranteed/);
  assert.match(html, /No live V6 transactions/);
  assert.match(html, /Details pending/);
  assert.match(html, /data-test="orbit-art"/);
  assert.doesNotMatch(html, /href="\/app/);
  assert.match(html, /href="\/preview"/);
});
test("homepage uses the live landing with app links, six fees, disclosures and no V6 claims", () => {
  const landing = load("../components/preview/landing-preview.tsx", {
    "@/lib/stages": load("../lib/stages.ts"),
    "./orbit-art": { OrbitArt: () => React.createElement("div", { "data-test": "orbit-art" }) },
    "./landing-preview.module.css": new Proxy({}, { get: (_target, key) => key === "__esModule" ? false : String(key) }),
    "next/image": ({ src, alt, width, height }) => React.createElement("img", { src, alt, width, height }),
    "next/link": ({ href, children }) => React.createElement("a", { href }, children),
  });
  const { default: Home } = load("../app/page.tsx", {
    "@/components/preview/landing-preview": landing,
  });
  const html = renderToStaticMarkup(React.createElement(Home));
  assert.match(html, /Move forward/);
  assert.match(html, /href="\/app\/join"/);
  assert.match(html, /href="\/app"/);
  assert.match(html, /href="\/legal"/);
  assert.match(html, /data-test="orbit-art"/);
  assert.match(html, /not guaranteed/);
  assert.match(html, /No independent third-party audit/);
  assert.match(html, /Confirm the current amount/);
  assert.match(html, /Details pending/);
  assert.doesNotMatch(html, /href="\/preview|DESIGN PREVIEW|V6|re-entry reserves|funded re-entry|sample data/i);
  for (const stage of load("../lib/stages.ts").STAGES) {
    assert.match(html, new RegExp(`<h3>${stage.label}</h3>`));
    assert.ok(html.includes(`${stage.fee.toLocaleString("en-US")}<span>USDT</span>`));
  }
  for (const id of ["landing-main", "journey", "stages", "possibilities"]) {
    assert.ok(html.includes(`href="#${id}"`));
    assert.ok(html.includes(`id="${id}"`));
  }
});
test("homepage keeps consent but does not mount a second animated background behind its artwork", () => {
  const html = runtimeAt("/");
  assert.match(html, /data-test="consent"/);
  assert.match(html, /data-test="wallet-providers"/);
  assert.doesNotMatch(html, /data-test="background"/);
});
test("initial artwork renders a static logo without loading Three, and 3D modules contain no RPC hooks", () => {
  const { OrbitArt } = load("../components/preview/orbit-art.tsx", {
    "next/dynamic": (_loader, options) => { assert.equal(options.ssr, false); return () => null; },
    "next/image": ({ src, alt, width, height }) => React.createElement("img", { src, alt, width, height }),
    "@/lib/preview/animation-policy": animationPolicy,
    "./landing-preview.module.css": new Proxy({}, { get: (_target, key) => key === "__esModule" ? false : String(key) }),
  });
  const html = renderToStaticMarkup(React.createElement(OrbitArt));
  assert.match(html, /src="\/logo-mark.svg"/);
  assert.match(html, /Play 3D animation/);
  assert.doesNotMatch(html, /<canvas/);
  for (const filename of ["orbit-art.tsx", "orbit-scene.tsx"]) {
    const source = readFileSync(new URL(`../components/preview/${filename}`, import.meta.url), "utf8");
    assert.doesNotMatch(source, /from ["'](?:wagmi|viem|@\/hooks|@\/lib\/contracts)/);
  }
});

function pageAt(env) {
  return load("../app/preview/page.tsx", {
    "next/navigation": { notFound: () => { throw new Error("NOT_FOUND"); } },
    "@/components/preview/dashboard-preview": { DashboardPreview: () => null },
  }, env);
}
test("production preview is unavailable by default, including with a public opt-in flag", () => {
  assert.throws(() => pageAt({ NODE_ENV: "production" }).default(), /NOT_FOUND/);
  assert.throws(() => pageAt({ NODE_ENV: "production", NEXT_PUBLIC_NEXAFLOW_DESIGN_PREVIEW: "true" }).default(), /NOT_FOUND/);
  assert.doesNotThrow(() => pageAt({ NODE_ENV: "development" }).default());
  assert.doesNotThrow(() => pageAt({ NODE_ENV: "production", NEXAFLOW_DESIGN_PREVIEW: "true" }).default());
});
test("preview metadata is non-indexable and does not advertise live earnings", () => {
  const { metadata } = pageAt({ NODE_ENV: "development" });
  assert.equal(metadata.robots.index, false);
  assert.equal(metadata.robots.follow, false);
  assert.equal(metadata.openGraph.images.length, 0);
  assert.match(metadata.description, /sample data/);
});
test("preview renders six accessible stage controls and consistent, explicitly labelled sample figures", () => {
  const { DashboardPreview } = load("../components/preview/dashboard-preview.tsx", {
    "@/lib/preview/dashboard": data,
    "./dashboard-preview.module.css": new Proxy({}, { get: (_target, key) => key === "__esModule" ? false : String(key) }),
    "next/image": ({ src, alt, width, height }) => React.createElement("img", { src, alt, width, height }),
    "next/link": ({ href, children }) => React.createElement("a", { href }, children),
  });
  const html = renderToStaticMarkup(React.createElement(DashboardPreview));
  assert.match(html, /Sample data only/);
  assert.match(html, /No wallet connected/);
  assert.match(html, /405\.00/);
  for (let i = 1; i <= 6; i++) {
    assert.match(html, new RegExp(`aria-controls="stage-detail-${i}"`));
    assert.match(html, new RegExp(`id="stage-detail-${i}"`));
  }
  assert.match(html, /Stage 4 is ready to unlock/);
  assert.match(html, /Stage 5 is locked/);
  assert.match(html, /Mobile preview navigation/);
});
