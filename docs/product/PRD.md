# CertiFiks — Product Requirements Document

Version: 0.1.0 · Status: specification only (not implemented) · Date: 2026-10-15 · Tracking: #1

## 1. Product promise and boundaries
**Prove the Fix. Release the Reward.**

CertiFiks is intended to let maintainers escrow rewards for a clearly defined software repair, contributors submit the exact GitHub commit fixing it, independent and accountable verifiers inspect reproducible test evidence, and contributors withdraw approved funds after a fair challenge process. It is a working-name, in-development protocol, not a launched platform.

A failing baseline and passing patched revision demonstrate compliance with agreed tests—not a proof that all bugs or vulnerabilities are absent. Two wallets are not automatically two independent verifiers. Initially adopt a disclosed permissioned trust model; never claim a trustless arbitrator unless one has actually been implemented and audited.

## 2. Personas and roles
| Persona | Wants | Authorized actions | Forbidden actions |
|---|---|---|---|
| Sponsor / repo maintainer | A real repair, reproducible tests and funds protection | Connect GitHub repo, fund immutable terms, assign a developer, challenge within policy | Edit test spec post-funding or veto a qualified timely fix |
| Contributor | Clear scope and enforceable payout | Discover funded issue, apply, accept assignment, submit exact SHA, inspect evidence, withdraw | Submit as an unassigned identity or silently alter trusted tests |
| Verifier | Evidence integrity and independent decisions | Reproduce before/after run, inspect bundle, attest verdict | Verify own bounty/fix, forge or rewrite artifact |
| Arbitrator | Fair and time-bounded resolution | Review parties' evidence, issue signed reason and settlement authorization | Hold funds indefinitely or decide a conflicted case |
| Org admin | Delegation without shared keys | Invite and revoke team users, manage repos within policy | Override on-chain custody |
| Service operator | Reliable API/jobs/indexing | Recover services and audit failures | Secretly seize escrow or fabricate successful test outcome |

## 3. Detailed user stories
### Sponsor
- As a maintainer, I sign in, connect a real repository with a GitHub App, select its immutable numeric ID and baseline SHA, and define the exact reproducible acceptance test, pinned execution image and reward.
- I see actual chain, network, token precision, fees and deadlines before authorizing funding through my wallet.
- Once funded, I can select and assign one applicant without retroactively editing the bounty terms.
- I can inspect exactly what source revision, harness and verifiers generated the result and challenge it before deadline.
- I can claim a legitimate refund on predetermined conditions, never by abusing CI downtime against timely submitted work.

### Contributor
- I can browse only clearly labeled funded/unfunded bounties with real on-chain receipts, understand the acceptance tests, apply and accept the assignment.
- I submit a GitHub PR pinned to base/head commit SHAs, inspect failing-before/passing-after logs, respond to disputes and withdraw earned credit.
- A sponsor cannot change specifications mid-work, and an unavailable reviewer cannot arbitrarily erase a timely claim.

### Verifier, arbitrator and operator
- Verifiers inspect independently reproducible evidence, attest or reject a specific manifest/commit/report combination, and cannot bypass conflict checks.
- An independent arbitrator reviews frozen evidence, hears both parties and resolves within a fixed policy deadline with signed reasoning and a liveness fallback.
- Operators can find stuck jobs, safely retry idempotent work, reconcile block events, rotate secrets and restore backups without modifying chain truth.

## 4. End-to-end successful user journey
1. Sponsor authenticates GitHub and wallet; connects authorized repository.
2. Sponsor creates a versioned acceptance manifest: numeric repo ID, fixed base SHA, intended baseline failure, candidate pass criteria, regression suite, runner image digest, payout amount, signer/verifier policy, challenge period and all deadlines.
3. Sponsor confirms real qualifying-network transaction; escrow event is finalized and reconciled before listing displays funded.
4. Contributor applies, is explicitly assigned, signs acceptance, submits PR with exact head SHA and attempt ID.
5. Ephemeral sandbox checks identical trusted test spec against baseline (expected defect) then submitted revision (expected fix). It records environment, exit codes, results, logs and digest. Failure, flake, timeout and CI outage never count as success.
6. Eligible separately accountable verifiers inspect evidence and sign reports bound to chain/contract/bounty, immutable manifest and exact commits.
7. Sufficient matching attestations start a transparent challenge period, not automatic payment.
8. No valid challenge occurs or adjudication favors developer; contract books withdrawal credit exactly once.
9. Developer signs withdrawal, payment settles on chain; canonical events, UI amount, evidence bundle and receipt match.

## 5. Failure/refund/dispute user journeys
- **No assignment:** funding/assignment window expires; sponsor obtains policy-authorized refund; no contributor is protected by a timely submission.
- **Developer misses submission:** objective assignment expiry with safe reassignment or refund; cannot assign two active contributors.
- **Invalid fix:** trusted baseline test fails as expected but candidate also fails or breaks regressions; show specific signed rejection, enable only pre-agreed resubmission windows, then expire/refund.
- **Verifier/runner outage after timely submission:** mark inconclusive, bounded retries and fair escalation. Never infer success and never grant immediate unilateral sponsor refund simply because review timed out.
- **Verifier disagreement / fraud allegation:** record immutable challenge, parties' responses, independent arbitration, bounded fallback to prevent trapped escrow, and final signed reason.
- **Malicious PR force-push / repo permission loss:** fixed head SHA cannot change a previously verified attempt. Missing access is explicitly inconclusive.
- **Wallet rejection / reorg / RPC outage:** transaction remains pending/failed until canonical confirmation; frontend must never optimistically show funds paid.

## 6. Product release requirements
- **Custody:** immutable funded bounty; exact on-chain liabilities; fair cancel/timeout/refund; bounded dispute resolution; safe pull withdrawals.
- **Provenance:** real GitHub App, HMAC-protected webhooks, exact immutable SHAs and contributor identity.
- **Verification:** isolated untrusted code, pinned test image, failing-before/passing-after, regression tests, attributable signed reports and offline verification.
- **Backend:** secure GitHub+wallet authentication, organizational tenancy, durable DB, versioned APIs, indexer/reorg handling, retries, proof storage and alerts.
- **Frontend:** complete working workflows for sponsor, contributor, verifier and arbitrator; honest balances/history, real wallet TX, clear errors and responsive accessibility.
- **Operations:** backups/restore, incident response, test coverage, independent security review before mainnet, privacy/help policy and external pilot cases.
- **Network:** actual Portaldot deployment only if network compatibility and organizer qualification are proved by receipts. Until then chain specifics are blocked, not assumed.

## 7. Out of scope / non-goals
- Autonomous code-writing, generalized AI code correctness, decentralized arbitration without credible implementation, custodial wallet-key storage, fake growth stats, free-floating off-chain promises of payment and any prototype marketed as a finished product.
- Initially prioritize reproducible, safe open-source issues; private repositories require stronger permissions, storage/privacy reviews and opt-in.
- A hackathon testnet deliverable is not equivalent to secure mainnet operations.

## 8. Authoritative data model and trust assumptions
- **Chain is authoritative** for escrow, bound policy hashes, permitted settlement, withdrawal credits, refunds and transfer receipt.
- **GitHub is authoritative** for repo identity and code SHAs; branch head is mutable, so cannot serve as proof.
- **Signed verifier evidence** reports only concrete tests/evaluation under a disclosed eligibility/governance policy.
- **API/DB/indexer** store user identities, app permissions, attempts, job statuses and presentation state, but cannot override chain custody.
- **Artifact store** retains integrity-checked, optionally redacted reports with access control and independent hash verification.

## 9. Measurable completion criteria
| Objective | Release threshold | Evidence / issues |
|---|---|---|
| Complete real payout | At least two genuine funded GitHub fixes with chain withdrawal receipts and signed evidence | #18, #25, #40, #43 |
| Non-success path | At least one rejected/retried case and one dispute or valid refund on chain | #14, #15, #40 |
| Money invariants | Zero unexplained balance difference and zero double credit/withdraw in stateful tests | #16, #17, #27 |
| Immutable proof | Every settled fix bound to numeric repo ID, base/head SHAs, manifest and signed report | #11, #19, #22 |
| Auth and isolation | No unresolved known critical/high risks at release; negative tests enforce permissions and process isolation | #21, #23, #41 |
| Reliability | Recovery from worker kill, RPC outage and DB restore without lost/duplicate decision | #24, #28, #42 |
| Actual adoption | Two documented, consented outside-user pilot cases as target | #7, #43 |
| Honest usable UI | Every advertised public action maps to functioning API/contract path; accessible role workflows | #31–#40 |

Metrics above are targets, NOT present achievements.

## 10. Lifecycle gates and scheduling
**G0 feasibility/spec** (#1–#8): Portaldot RPC, VM, faucet and contract eligibility must be verified. Existing ProofPatch starter is not yet compiled or deployed. Security architecture and immutable terms defined.
**G1 executable proof** (#19–#22, #25): real GitHub SHA, isolated before/after test and signed evidence.
**G2 real funds flow** (#9–#18): funded escrow through documented disputes, refunds and withdrawal; invariants proven.
**G3 real product** (#23–#39): resilient backend, role-complete UI, authorization, evidence browser and wallet UX.
**G4 founder release** (#40–#46): real E2E, independent review, pilots, operating recovery and economics.
**Competition gate:** #8/#45 validates exact organizer conditions separately. Do not claim all founder-grade gates complete just because an entry is submitted.

## 11. Open decisions, initial risks and business hypothesis
Hard blockers: official qualifying Portaldot chain/VM/RPC and token; verifier identity independence; arbitration timeout and conflicts; funding precision/fees; independent user availability; production compliance and trademark clearance for the provisional CertiFiks brand.

Initial risks: malicious code sandbox escape; false or changed acceptance tests; collusion; contract double settlement or stuck funds; data exfiltration; indexer reorg; misleading claims; ignored GitHub permissions; missed hackathon eligibility. See [risk register](./RISK_REGISTER.md) and issue #3.

Sponsors might pay a fixed verification fee, usage fee or subscription, but pricing must be based on measured verifier/compute/storage/gas/dispute costs and willingness-to-pay interviews (#7/#46), not invented traction.

## 12. Definition of done and change control
Every issue must link a scoped PR; reviewer must be able to reproduce checks for the issue's acceptance criteria; tests and negative paths pass before merge; expected on-chain evidence must be authentic. PR merged and issue closed only when issue criteria are satisfied. Never close a dependent issue prematurely. Funded policy specifications remain immutable despite updates to future code. See [state machine](./STATE_MACHINE.md), [acceptance matrix](./ACCEPTANCE_MATRIX.md) and [risk register](./RISK_REGISTER.md).
