# Issue #38 — Responsive, accessible, failure-safe product checks

This integration adds **actual production-Chromium** browser checks for the public-facing app. It also adds on-page recovery boundaries, a truthful disconnected/returned-network notice, a non-fabricated dashboard loading state, and accessible 404/error navigation.

## CI acceptance budget

The `browser-quality` GitHub Actions job builds the real Next.js production app (no development server or screenshot mock). It runs Chromium at **375px mobile** and **1280px desktop**, with reduced motion enabled, and checks these eight routes:

- `/` — public homepage
- `/onboarding` — role guide
- `/opportunities` — contributor discovery
- `/sponsor` — sponsor public-state overview
- `/verifier` — reviewer access requirements
- `/disputes` — adjudication safety
- `/wallet` — wallet/transaction safety
- `/dashboard` — real-only public history

Each real page must return HTTP 200, expose exactly one main `h1`, avoid horizontal viewport overflow, and reveal **zero serious or critical axe-core WCAG 2.1 AA issues**. The suite enforces a **≤ 8,500ms navigation TTFB** and **≤ 1,600,000 decoded JS resource bytes** per route (CI-hosted hardware; budgets are conservative ceilings, not target scores). It also checks initial keyboard navigation reaches the skip link, simulated offline state produces an `alert`, restored network offers an explicit refresh, and no unhandled browser JavaScript errors occur.

The action attaches real screenshots of `/`, `/onboarding` and `/dashboard` at both viewport widths, plus machine-readable JSON audit findings. CI deliberately runs **with no live custody or funding credentials**. Empty/unavailable published records are appropriate and cannot be silently replaced with invented data.

Reproduce locally with the same exact dependencies:

```bash
npm ci --ignore-scripts --no-audit --no-fund
npm install --no-save --package-lock=false --ignore-scripts --no-audit --no-fund playwright@1.56.1 axe-core@4.10.3
./node_modules/.bin/playwright install --with-deps chromium
npm run build --workspace=@certifiks/web
./node_modules/.bin/next start apps/web --port 4100
# in another shell:
CERTIFIKS_BROWSER_ORIGIN=http://127.0.0.1:4100 node scripts/quality/browser-a11y.mjs
```

## Recovery and security interpretation

The offline banner represents `navigator.onLine` only. That browser flag **does not prove API health, chain finality, submitted deposits or payout success**; returning online provides an explicit user-driven refresh instead of mutating a money balance. Next.js error boundaries display error messages that reveal **no private wallet addresses, evidence logs or request bodies** and do not claim a transfer was completed. The dashboard loading and error states likewise do not fabricate results.

## Still blocked for full Issue #38 acceptance

- A genuine signed-in sponsor and contributor lifecycle, real GitHub consent, real chain wallet adapter and tested mobile deep-links. These paths cannot be exercised in CI until secure external integrations are configured and verified.
- Private evidence upload/resume flows, long-artifact handling and permission-aware failure recovery on real server and device sessions.
- Manual keyboard/screen-reader checks (VoiceOver, NVDA, TalkBack), tablet/low-memory devices, high contrast preferences and assisted-technology acceptance by real users.
- Realistic production network throttling with deployed API and database, backup/recovery and independently verified transaction state/escrow funds.
- Broader image-based visual regression baselines and review of interface decisions in production.

**Do not close Issue #38** until the full user-path acceptance criteria are met. A green browser check on the available public pages is evidence of those pages only, not a security audit or full product readiness.
