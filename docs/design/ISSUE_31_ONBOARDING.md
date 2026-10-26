# Issue #31 — Accessible, truthful product shell

The public Next.js app now provides responsive, mobile-first dark and light themes with design tokens, a visible keyboard-focus state, skip navigation, semantic landmarks, reduced-motion preferences and straightforward error/empty/unavailable states. The home page loads public bounty records **only** from the configured real `CERTIFIKS_API_BASE_URL` server-side, with no fallback fixtures. Backend outage is different from a true empty marketplace; both are described accurately.

## Sponsor first visit

1. Read the distinction between immutable acceptance terms and a verified paid repair.
2. Choose **Sponsor / Maintainer** under `/onboarding` to see the real prerequisites: GitHub installation consent, identity/wallet authentication, approved runtime and exact funding manifest.
3. Because registration, chain compatibility and real deposit paths are unverified, the UI does not expose a misleading enabled funding CTA.
4. Once the authenticated sponsor lifecycle is implemented, user testing must demonstrate setup, secure funding, monitoring, dispute/refund and withdrawal receipts without fabricated states.

## Contributor first visit

1. Explore `/#marketplace`. When a real published backend is configured, cards show repository, raw atomic-unit reward and chain-indexed lifecycle **without asserting verification success**.
2. Choose **Developer / Contributor** under `/onboarding` and review immutable commit requirements and independent test/report expectations.
3. No fake application, submission or payout button is shown while the actual authenticated operations are unavailable.
4. Before closing this issue, test real GitHub account linkage, assignment, submission, before/after verification and withdrawal with a genuine contributor.

## Reviewer or arbitrator first visit

1. View the proof pipeline as an explicitly labeled **concept**, never real activity.
2. Read the approved reviewer-identity, private evidence, signed-report and dispute criteria under `/onboarding#reviewer`.
3. Never show a green status from frontend memory or a standalone CI check; final verdicts must be independently backed by stored artifacts and verified on-chain policy.

## Automated checks and limits

`apps/web/tests/design-contract.test.mjs` checks basic semantic landmarks, stated unavailability, no mocked public bounty data, system color-pair contrast and reduced-motion CSS support. Next.js CI performs typecheck and production build. These tests are **not a replacement** for real browser keyboard/VoiceOver/NVDA testing, automated axe audits, screenshot regressions or WCAG 2.2 AA sign-off.

**Outstanding:** live secure GitHub App/wallet onboarding, actual role-based API flows, real chain support and funds; independent user interviews for UX copy; automated screenshot + accessibility audit; complete responsive real-data user journeys. Keep Issue #31 OPEN until those tests pass.
