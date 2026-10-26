# Issue #34 — Conflict-filtered verifier review preflight

**Status: read-only reviewer eligibility and public-safe onboarding, not a live verifier app or on-chain attestation service.**

Migration `supabase/migrations/202610260009_verifier_preflight.sql` exposes a service-only `certifiks_verifier_review_preflight(organization_id, verified_actor_id, limit)` RPC. It checks active verifier role membership and prevents the same sponsoring or contributing user from reviewing their own run. It joins stored bounty, attempt, immutable commit IDs and verification-run metadata. Only digests and the **number** of retained artifacts are returned, never private bytes, storage keys, evidence downloads, billing secrets or review votes. It always marks `can_attest=false` and `payout_authorized=false` regardless of the runner's claimed result.

`apps/api/src/reviews/verifier-preflight.ts` is a typed privileged adapter for this RPC that validates IDs, hex commitments, outcome allowlists, tenant filtering and the explicit unsigned state. It must be invoked **only after** the backend authenticates the user via a production session and derives the user's identity; user IDs passed by browsers are not authoritative. It is deliberately not registered as an unauthenticated HTTP endpoint. `apps/web/app/verifier` explains the reviewer journey and never renders a synthetic queue or active signing button.

The SQL integration tests create synthetic reviewer, sponsor and developer identities and prove that ordinary independent reviewers see review metadata, while sponsors, contributors and unrelated organizations cannot. They assert no verifier votes or payments are created as a side effect. The Node tests cover bogus server results and cross-tenant cases. **Synthetic tests do not prove live enrollment or safe signing.**

## Remaining blockers before closing #34

- Authenticate actual verifier users with secure wallet+GitHub sessions, assign independent verifier organizations from a trusted registry, and issue strict tenant-scoped short-lived evidence access.
- Complete immutable private artifact decryption/download/redaction and limits, blind reviewer commitments and human-readable approval/rejection/inconclusive reasons; test wrong-job, stale-commit, replay, conflict and expiry.
- Implement explicit wallet signature, independent quorum checks, real on-chain attestation transactions and receipts, and production chain compatibility. Never derive authority from a runner's self-reported success.
- Run a real two-verifier end-to-end review and retain accepted redacted chain/runner evidence with permission logs. If the chain, verifier keys or custody aren't deployed, do not enable approvals.

Keep **Issue #34 OPEN** until its complete definition of done and independent external evidence are met.
