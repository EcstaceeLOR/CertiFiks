# Issue #12 — Permissioned verifier identity and independence controls

**Status: database-enforced identity, key and review-assignment boundaries. This is not proof of unique humans, an independently audited verifier system, or authority to release funds.**

## Initial trust model

CertiFiks does not claim anonymous trustless verification. For the first controlled pilot, a human operator must privately confirm the real organization controlling each reviewer, verify its appropriate qualifications/conflicts, gather consent, and issue a distinct enrollment approval. That process **does not exist as a working onboarding service yet**.

The database records a salted pseudonymous `control_digest` and an immutable `independent_review_digest` pointing to the operator's off-platform assessment. Do not use wallet keys, usernames or bare email hashes as proof of unique individuals. Do not store identity documents on chain or in public artifacts.

## Implemented controls

The migration `202610270002_verifier_independence.sql` creates three backend-only tables:

- `certifiks_verifier_principals`: reviewer user UUID, one immutable control identity within each organization, independent approval digest and an active **different** operator who approved the enrollment. Duplicate control tags and duplicate user enrollments are rejected. All enrollment identities are private.
- `certifiks_verifier_signing_keys`: one or more signer key IDs bound to a single reviewer principal. Keys may be one-way revoked, but no new key can change the owner's identity.
- `certifiks_verifier_review_assignments`: immutable assignment of a vetted principal and one specific key to an exact tenant-bound verification run/bounty. At most one assignment per **principal per run**, regardless of number of private keys. Its insert trigger locks reviewer/key rows against concurrent revocation and rejects conflicts with sponsor, any bounty applicant/developer, any dispute opener, or an active arbitrator role in that workspace. It also checks the run actually belongs to the bounty and that the verifier membership is still active.

Reviewer or operator status must be active at enrollment; revoked keys and principals cannot receive new assignments. A previously created assignment record survives later revocation for audit purposes but **does not confer irrevocable signing authority**: any actual vote/attestation authorization must re-check current principal, key, trusted session and policy at signing time.

These tables, including key IDs, are not readable from the browser, and they cannot change on-chain escrow. There is **no new public vote, signer, payout, dispute, or funds-moving method**. Existing preflight keeps `canAttest: false` and `payoutAuthorized: false`.

## Synthetic regression evidence

CI applies this schema on PostgreSQL 16 with deterministic role, sponsor, developer, reviewer and independent operator fixtures. Assertions reject:
- Two approvals for the same run under different keys of one reviewer.
- A second reviewer identity claiming the already enrolled control digest.
- Assignment of a developer to verify the bounty they applied to.
- Assignment with a revoked key or reactivating that key.
- Deleting a historical assignment; reading private registry as anonymous browser role.

These tests demonstrate constraints under synthetic inputs only. They do **not** provide independent KYC, guarantors, fraud protection or social-graph disambiguation, and they do not exercise live GitHub review or chain payouts.

## Remaining full acceptance requirements

- Build an audited, operator-authenticated enrollment/revocation API with consent, provenance, rotation, service SLAs and access reviews; validate real reviewer capacity and identities with independent administrators.
- Establish bounded verification timeouts, compensation, replacement rules, challenge/review independence and residual control/financial conflicts on real bounties.
- Connect selected principals and independently signed EIP-712 vote verification to immutable run evidence, while checking key revocation at vote time; reject cross-identity collusion and cross-organization reuse under a reviewed policy.
- Demonstrate two independent real reviewers performing honest/dissenting cases on the qualifying Portaldot testnet and independently reproduce the signing/audit trail.

**Issue #12 remains open** until that evidence and security sign-off exist. An enrolled principal or key does not mean an independent human was verified.
