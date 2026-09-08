# NexaFlow revamp — dashboard and landing previews

This is an isolated, synthetic-data design preview at `/preview`, not a V6 contract integration.

The landing preview is at `/preview/landing`. It adds an editorial black/gold layout, a responsive six-stage overview, explicitly unverified benefit descriptions, and a Three.js hero. Application calls to action lead to the dashboard preview, not a live transaction flow.

## Landing animation

- `orbit-art.tsx` loads `orbit-scene.tsx` only on the client when eligible. All essential landing content is server-rendered independently.
- React Three Fiber 8.18.0 pairs with existing React 18; Three 0.170.0 and matching types are pinned. The dependency lockfile is updated; no React/Next major upgrade was made.
- The gold geometry is an extrusion of existing `/logo-mark.svg` paths, with six orbital markers and a procedural studio environment. No external HDR/model/image service or RPC call is used by the animation.
- Manual rendering targets 30 FPS, caps device-pixel ratio at 1.5 (1 on compact displays), and stops its animation loop when paused, out of view or in a hidden document.
- Reduced-motion mode stays static. Compact screens, limited hardware and data-saving mode default to a static logo with an explicit play option. Shader/renderer errors and context loss return to static artwork. WebGL hardware behaviour still requires actual browser validation.
- The static logo remains visible until the animated scene signals readiness. Pause/resume is a native keyboard-accessible button outside the decorative canvas.
- Tests cover autoplay/render eligibility, initial static server rendering, non-transactional links and production gating. They do not prove a particular GPU frame rate or replace mobile/visual testing.

Landing validation (7 September 2026): production build, lint/type checks, all 14 preview tests, RPC-policy checks and all 10 network graph/cache tests passed. Next reports 107 kB first-load JS for the landing route; the deferred 3D chunk is additional, so this is not the complete animated experience's download size. The npm production-dependency audit reports 30 findings (23 moderate, seven high, zero critical) across the app tree. No findings were listed for Three, React Three Fiber, its-fine, react-reconciler, react-use-measure or suspend-react in that check. The remaining findings have not been triaged or fixed in this design task; no security-clearance claim is made.

## Included

- Charcoal/gold member workspace with desktop side navigation and mobile bottom navigation.
- Earned, delivered, claimable and re-entry reserve amounts presented separately.
- All six stages, one expanded at a time; completed-board selection and SVG position diagrams.
- Sequential stage availability: Stage 4 is available in the fixture, while 5/6 require their preceding stages.
- Direct-referral/team counts and sample generation breakdown, separate from board positions.
- Benefit placeholders explicitly labelled as unverified/details pending; no fulfilment promises.
- Reduced-motion policy, keyboard focus, labelled stage regions, native history selectors and a skip link.
- Existing brand SVG, Motion and scoped CSS for the dashboard. The landing adds the renderer dependencies described above.

## Isolation

The server page rejects production access by default. `NEXAFLOW_DESIGN_PREVIEW=true` is a server-only opt-in for an explicitly authorised preview deployment, **not authentication**; do not enable it expecting a private page. No environment file is modified by this work.

`SiteRuntime` preserves the existing provider/background/consent structure on other routes. Only exact `/preview` and `/preview/landing` bypass mounting those components. The previews contain no wallet reads/writes or live index calls. The fixture module is separate from contract hooks and should remain preview-only. All account figures are synthetic and clearly labelled.

Development: `npm run dev`, then open `/preview`.

Validation: `npm run test:preview`, `npm run lint`, `npm run typecheck`, `npm run test:rpc`, `npm run test:network`. The network test script needs a Node runtime supporting TypeScript stripping. `NEXAFLOW_ISOLATED_BUILD=true npm run build` uses `.next-design-build` to avoid interfering with an active development cache. Normal builds and Vercel retain `.next`.

Tests cover fixture accounting, stage configuration and availability, server rendering, exact-route provider isolation and production gating. They do not constitute browser interaction testing, a visual audit, or live-wallet end-to-end validation.

## Next slices

1. Review this working mobile/desktop design with the client, then add the shared UI primitives needed for transaction dialogs and sheets. No component-library migration was performed in this slice.
2. Review the implemented landing hero in actual desktop/mobile browsers, verify WebGL fallback and controls, and measure its performance. Keep all essential content available without WebGL.
3. Finalise V6 production interfaces, roles and award handling; implement a version-aware data layer. Do not connect this fixture view by changing only the live contract address/ABI.
4. Add real board history, branch navigation, deferred-claim actions and transaction states against a local test deployment; label and retain pending/re-entry states.
5. Run browser/mobile accessibility and wallet-flow tests plus performance/RPC-budget checks before any production cutover.

No contract changes, deployment, Git push or Vercel changes are part of this slice.
