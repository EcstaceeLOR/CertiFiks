# Issue #31 — CertiFiks product interface and truthful onboarding

The new homepage and `/onboarding` journey are built on a consistent design system (dark/light color tokens, responsive layouts, visible focus rings, reduced-motion preference, semantic landmarks, keyboard skip links and no fake activity).

## Distinct journeys

**Sponsor/maintainer:** review GitHub App installation permissions, supported chain/custody prerequisites, frozen acceptance manifest, independent reviews and test evidence before posting or funding. Funding is explicitly unavailable until the real network and secure escrow exist.

**Contributor:** prepare GitHub account identity, discover real published bounties, confirm baseline/pinned head requirements, and submit immutable revisions for independent testing only once backed by genuine services. Application and payout buttons are intentionally absent.

**Verifier/arbitrator:** independently approve enrolled keys, reproduce artifact commitments, and review the difference between a claimed passing test and actual authorized settlement. Reviewer enrollment and private evidence remain unavailable.

## Real-data rules

The homepage calls `GET /v1/bounties?limit=3&offset=0` only from a configured server-side `CERTIFIKS_API_BASE_URL`. In production this must be HTTPS with no URL-embedded credentials; localhost HTTP is development-only. When the API is missing, offline, untrusted, or returns invalid data, the UI shows a clear *unavailable* state. A genuine empty response displays a distinct *no bounties* state. Bounty cards use the backend's precise reward strings **without implying verified repair or funding eligibility**. The public API currently remains incomplete (Issue #26). No synthetic funds, transaction counts, testimonials, or user activities are rendered.

## Local verification

```sh
npm ci
npm run test --workspace=@certifiks/web
npm run typecheck --workspace=@certifiks/web
npm run build --workspace=@certifiks/web
```

`apps/web/tests/design-system.test.mjs` confirms keyboard landmarks, reduced-motion and responsive CSS, distinct role paths and mandatory unavailable states. This is a regression smoke suite, **not** a WCAG 2.2 AA certification, screenshot regression or real-user usability test.

## Open release gates

- Complete **real** wallet and GitHub sign-in with scoped permissions, wallet chain checks and authenticated role assignment (Issues #20 and #23).
- Wire every workflow to authenticated, durable APIs and independent on-chain attestations before enabling customer transactions (Issues #18, #26 and #27).
- Run Playwright keyboard, axe/WCAG contrast, screen reader and screenshot regression on supported desktop/mobile browsers; address issues found.
- Validate sponsor and contributor onboarding with real people, fix comprehension blockers, then enable only independently verified supported chain workflows.
- Obtain brand/name and legal review before marketing or collecting funds.

**Do not close Issue #31 until live onboarding and real accessibility/UX acceptance evidence exist.** This implementation is product-facing progress, not a live service.
