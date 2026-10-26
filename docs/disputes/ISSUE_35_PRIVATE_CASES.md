# Issue #35 — Immutable, private dispute case timeline

**This milestone does not adjudicate a claim or authorize withdrawal, refund or on-chain release.**

The database migration `202610260010_dispute_timeline.sql` stores only content-addressed reason/evidence digests. Each event is scoped to the original tenant and dispute, immutable after creation and idempotent under webhook/request retries. One case-opening event per dispute is allowed. Only service-role RPCs can record or list event metadata, and their actor user IDs must come from a previously verified session. Opening-party, sponsor and assigned contributor are participants. An arbitrator may read and add arbitration notes only if *explicitly assigned to that dispute*, granted an active arbitrator role, and not personally the sponsor, opener or assigned contributor.

`certifiks_read_dispute_timeline` reveals neither plaintext evidence nor storage credentials. `apps/api/src/disputes/timeline.ts` checks exact tenant/case identity, required digest fields and rejects unexpected remote results. The `/disputes` page describes the process truthfully, with all case submission and settlement controls unavailable until authorization is proven.

### Test evidence

The PostgreSQL CI job checks private RLS, party participation, independent arbitrator case assignment, wrong-tenant access, same-key replay, conflicting-content rejection, immutable update/delete, and **no unearned payment writes**. Node tests validate fixed service origin, no-fallback behavior and no purported authorized settlement.

### Requirements that remain before closing Issue #35

- Real wallet/GitHub user sessions, session-derived access controls, case intake and signed consent, immutable private artifact upload/download with expiry and rate limiting.
- Arbitrator selection through an independently governed registry and assignment policy, deadlines, notice delivery, appeal, conflict checks and blinded independent reviewer votes as applicable.
- On-chain bounded arbitration and recovery linked to escrow custody, verification receipts, real refund/withdrawal txs, chain reorg reconciliation and complete money accounting.
- Actual sponsor/developer/arbitrator operated dispute E2E and accessible UI/screenshot audit across desktop and mobile.

**Issue #35 must remain open.** Digest-only case records are useful backend substrate but not an operational arbitration service.
