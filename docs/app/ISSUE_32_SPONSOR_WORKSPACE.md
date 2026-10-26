# Issue #32 — Sponsor read-only workspace and funding gate

This slice adds `/sponsor`, a responsive, accessible sponsor overview that reads only actual server-redacted records from `GET /v1/bounties`. Network failure and genuine zero published records are distinguished; neither fallback bounties nor invented wallet balances are rendered. A sponsor can review the necessary GitHub, manifest, runtime, chain, consent and finality prerequisites; **no transaction or fake funding CTA exists**.

The page currently displays *public* records, **not an authorized sponsor's private bounties**. It never claims sponsorship ownership, true account balances, verified fixes or release rights from read-only metadata. The /onboarding page links to it so that it can be discovered by prospective maintainers. The frontend honors no-store requests and an HTTPS-only API origin (local dev is limited to loopback HTTP), validates returned public fields and fails closed.

## Remaining production Issue #32 acceptance

A real maintainer must be able to authorize installation of the genuine CertiFiks GitHub App, authenticate wallet identity and repo consent, persist a private funding intent with immutable manifest, select a verified organizer-approved Portaldot runtime, sign a transaction in their own wallet, confirm a real deployable audited escrow exists, index a finalized receipt, and then manage real applications, assignments, refund/dispute and payout operations through session-bound audited APIs.

**None of these on-chain and private mutation paths are enabled.** The existing Solidity module CI is not proof of approved Portaldot deployment. Leave Issue #32 OPEN until actual user, browser and chain E2E evidence passes.
