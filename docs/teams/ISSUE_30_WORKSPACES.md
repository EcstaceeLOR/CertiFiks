# Issue #30 — Organization workspaces and bounded delegation

**Status:** internal PostgreSQL identity and delegation foundation. Not a complete user-facing organization console or custody delegation system.

Migration `202610260007_workspace_delegation.sql` creates an explicit workspace owner, distinct roles (`owner`, `billing`, `maintainer`, `reviewer`, `viewer`), hashed single-use time-bounded invitations, active/revoked memberships, private repository policy hashes, and an immutable role-change audit stream.

Backend-only RPC functions support workspace creation, issuing invitations, accepting only on behalf of the exact intended authenticated user, revoking members, and controlled ownership transfer to an already active member. Maintainers can invite **viewers only**; only the current workspace owner may approve elevated team roles. Membership removal and transfer do not rewrite funded bounty sponsorship, smart contract signer rights or verification outcomes.

All tables deny direct access to `anon` or `authenticated` browser roles, and state transitions are restricted to the privileged backend. The API must derive actor and target identity from a separately verified wallet/GitHub session (Issue #23); it may NOT accept caller-provided user IDs without signed session verification.

## Evidence

PostgreSQL CI covers wrong-user redemption, invite replay rejection, unauthorized promotion, owner transfer with exactly one active owner, old-owner revocation, append-only role event history, private tenant scoping and unchanged bounty ownership. The database backup/restore job must also pass.

## Outstanding production acceptance

- Authenticated organization creation, invitations and secure email/delivery for the invite redemption flow; UI/role administration with actual user sessions and IDOR tests.
- Repo-specific GitHub installation authorization, contracted signer rights, profile delegation and cross-tenant membership checks.
- Billing, review, private evidence and dispute permissions with explicit role matrix enforced both in backend and, where applicable, on-chain.
- Recovery of organization access after founder wallet loss, owner-transfer multi-signature policy, safe org archiving and contractor session revocation.
- Real two-user end-to-end demonstration with funding and real independent GitHub App permissions.

Keep Issue #30 **OPEN** until every condition is verified. This migration alone does not permit team members to withdraw money.
