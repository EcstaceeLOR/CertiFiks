# Issue #33 — Real-data-only contributor discovery

This integration adds an actual filtered discovery path without pretending that wallet payouts, developer applications or commit submissions exist.

## Available now (code-tested)

The read-only `GET /v1/bounties` API now accepts exact `state` and `repo` filters alongside bounded pagination. The backend validates the supported public state and canonical `owner/name` repository format before passing exact predicates to the redacted PostgreSQL public view. The filters are applied **before** pagination. It rejects attempted PostgREST query injections and unsupported states with an explicit 400; absent database credentials, upstream failures, or malformed records yield an explicit 503. Rewards remain exact **atomic-unit decimal strings**, not misleading USD conversions, and every item has `verificationProven:false`.

The public `/opportunities` Next.js route retrieves only actual API data (no fixtures, fallback mock profiles or invented rewards), offers a keyboard-accessible exact repo/status filter and pagination, shows a meaningful invalid/empty/unavailable state, and accurately labels all currently blocked application and payout functions. It can be reached from the homepage and onboarding navigation.

## Reproduce

```sh
npm ci
npm run test --workspace=@certifiks/api
npm run test --workspace=@certifiks/web
npm run build
```

These unit tests are not live GitHub App, wallet, blockchain or browser-to-chain proofs.

## Remaining Issue #33 requirements

Secure contributor identity, protected private applications, sponsor assignment, immutable GitHub PR/commit submission, real verifier sandbox jobs/reviewer outcomes, appeal/dispute rights, developer notifications, supported chain/wallet compatibility, truly claimable on-chain earnings, actual withdrawal receipts and multi-wallet end-to-end tests remain incomplete. User-facing application/withdraw buttons must not be enabled until all relevant preceding issues meet production release criteria.

**Keep Issue #33 OPEN**. A public list is not evidence of a funded claimable bounty or guaranteed assignment, and a merged PR is not product completion.
