# CertiFiks Protocol v1 — errors, events and API contracts

**Status:** Draft public contracts. API endpoints and on-chain event ABIs are not implemented. Source: protocol/openapi.base.json, generated protocol/openapi.v1.json and packages/shared/src/generated/openapi.d.ts.

## 1. Error response and HTTP semantics
Every API error response has version=1, typed code, safe human-readable message and opaque requestId. Never return a successful payment status based on a queue, unconfirmed wallet transaction, API marker or synthetic demo data.

| Error code | Meaning | Typical HTTP | Financial safety behavior |
|---|---|---|---|
| INVALID_SCHEMA | Invalid field, missing invariant or unknown type | 400 | Reject mutation before funding/reporting |
| UNSUPPORTED_SPEC_VERSION | Protocol version other than committed v1 | 400 | No downgrade/implicit coercion |
| UNAUTHORIZED | No valid wallet/GitHub session | 401 | No private data or mutation |
| FORBIDDEN | Role/tenant/ownership mismatch | 403 | No privilege escalation |
| WRONG_CHAIN | Wallet/provider network or genesis mismatch | 409 | No signing or contract call |
| STALE_COMMIT | GitHub SHA differs from pinned attempt | 409 | Reject/evaluate new immutable attempt only |
| MANIFEST_MISMATCH | Hash differs from original funded policy | 409 | No payout/approval |
| VERIFIER_CONFLICT | Signer economics/identity conflicts with roles | 409 | Exclude from quorum |
| QUORUM_MISSING | Required independent positive attestations absent | 409 | Never pay automatically |
| TEST_INCONCLUSIVE | Runner/CI didn't produce reproducible result | 422/503 | Protected timely work, retry/escalate |
| ESCROW_UNFUNDED | No canonical confirmed funding | 409 | No paid-work claim |
| CHALLENGE_PENDING | Mandatory review window active | 409 | Do not allocate credit yet |
| DISPUTE_IN_PROGRESS | Evidence case unresolved | 409 | No unauthorized settlement |
| RATE_LIMITED | Abuse control/verification compute limit | 429 | Preserve immutable queue and deadlines |
| DEPENDENCY_UNAVAILABLE | GitHub/RPC/DB/runner unavailable | 503 | Fail closed and reconcile rather than forge success |

Schema/client generation errors must fail CI. The generated type API is not a claim that the real server routes exist yet.

## 2. On-chain event names and minimum public intent
Every event envelope MUST bind chain genesis, contract locator digest, tx hash, block height, index and finality indicator; indexer #27 is responsible for canonical finality/reorg handling.

| Event | Required eventual payload intent | Security note |
|---|---|---|
| BountyFunded | sponsor, reward atoms, manifest digest | Must reconcile with escrow liabilities |
| DeveloperAssigned | accepted developer, assignment digest | Never more than one active assignee |
| FixSubmitted | author, attempt digest, immutable head SHA | Must reject force-push substitution |
| VerificationCommitted | verifier org, signature/report digest, verdict | Signature not sufficient for release until quorum |
| ReviewStarted | challenge deadline, approved report digest | Must not imply paid |
| ChallengeOpened | challenger, reason/evidence digest and response cutoff | Holds during bounded case |
| DisputeResolved | decision beneficiary and ruling digest | Strictly bounded/independent authority |
| CreditAllocated | beneficiary, authorized amount | Exactly one credit per escrow |
| WithdrawalCompleted | recipient, amount and transaction | Canonical settlement after finality |
| RefundCompleted | sponsor, amount and transaction | No double payout/refund |

The v1 chain-event schema currently defines these names and authoritative envelope fields. **It intentionally does NOT pretend that contract-specific ABI payloads are finalized while Portaldot V3 VM deployment remains unverified.** Implement type-specific event payload validation in #9/#13/#14/#16/#27, before exposing these as public economic claims.

## 3. API definitions and generated clients
The OpenAPI 3.1 document defines future paths for draft creation, bounty lookups, pinned GitHub submissions, signed report reads, dispute initiation and event listing. They are labelled implementation-status=not-implemented and are not currently mounted in Fastify. Generated TypeScript types at packages/shared/src/generated/openapi.d.ts are checked into git, regenerated from the same versioned JSON Schema sources via npm run protocol:generate, and validated against reproducible generation in CI via npm run protocol:check.

- No newly advertised API should be exposed until #23 (auth), #24 (data), #26 (API), #27 (indexing) and #28 (workflow state) are complete.
- Any API field that cannot be reconciled with contract truth must report unknown/pending rather than an optimistic success.
- Breaking semantic changes require a new schema version and compatibility plan; changing already-funded commitments is forbidden.
- All private report and organization endpoints require actual backend authorization, not frontend hiding.
