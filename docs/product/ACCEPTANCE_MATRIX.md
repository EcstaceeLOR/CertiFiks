# CertiFiks — requirement/acceptance traceability matrix

Status: planned (not delivered). Refer to [product requirements](./PRD.md), [lifecycle](./STATE_MACHINE.md), [risk register](./RISK_REGISTER.md) and [canonical issue index](https://github.com/EcstaceeLOR/CertiFiks/issues/1).

This document explicitly maps each promised capability to one or more existing, individually checkbox-tested GitHub issues and defines proof required for claiming that capability is complete.

| Requirement and persona | Linked implementation/issues | Acceptance and evidence |
|---|---|---|
| Honest eligible release environment | #1, #2, #4, #8, #18 | Reproducible local build; qualifying RPC/chain and deployed tx with explorer evidence |
| Explicit trust and threat model | #3, #5, #12 | Threat inventory, independent verifier policy, signed role-conflict deny cases |
| Real funded immutable bounty | #6, #9, #19, #32 | User signs authentic funding transaction; full spec hash and reward on chain; no after-funding edits |
| Safe applications and assignment | #10, #23, #33 | Two real users, signed assignment and negative impersonation tests |
| Exact commit-bound work submission | #11, #20 | Real GitHub App, PR and fixed base/head SHAs, webhook HMAC/replay/force-push tests |
| Trusted isolated execution | #21, #25 | Safe clean-room runner; baseline expected failing, patch expected passing, regressions, malicious test alteration denial |
| Signed independently checkable reports | #12, #13, #19, #22, #34 | Two eligible unconflicted reviewers, signed digest, independent hash/report checker |
| Protected fair contest/refund | #14, #15, #35 | Timely submission cannot be seized due to CI outage; valid dispute gets bounded decision; real refund tx |
| Safe developer withdrawal | #16, #17, #36 | Authorized transfer confirmed on chain, reentrancy and double-withdraw rejection |
| Secure identity and permissions | #23, #24, #30 | GitHub+wallet sessions, organization scoping, migration and cross-tenant attack tests |
| Complete typed APIs | #26, #39 | Working API, independent CLI, versioned schema, idempotency and authorization checks |
| Accurate event-driven chain UX | #27, #28, #29 | Event reconciliation, reorg/crash recoveries and delivered real notifications |
| Complete user interfaces | #31, #32, #33, #34, #35, #36, #37, #38 | No placeholder action; real sponsor/developer/verifier/arbitrator journey with accessible responsive UX |
| Trustworthy live E2E | #18, #40 | Browser->GitHub->isolated run->signed evidence->chain settlement, plus failure/refund cases |
| Security and on-call operations | #3, #17, #41, #42, #44 | No unresolved known critical/high findings, restore drills, support/privacy and public current risk statement |
| Actual user adoption | #7, #43 | Independent maintainers/developers complete real opt-in pilot cases with genuine issues and evidence |
| Feasible business | #7, #43, #46 | Measured compute, reviewer and storage costs; interviews; sustainable fee hypothesis |
| Accurate hackathon package | #8, #45 | Primary-source eligibility, original repo history, working live URL, real on-chain receipts and technical demo |

## Test fixtures and release checks
1. **Happy path:** A maintainer funds a defined reproducible GitHub bug; independent developer submits a pinned actual patch; baseline fails and candidate passes in an isolated environment; independent reviewers sign; challenge period completes; wallet withdrawal settles on Portaldot.
2. **Invalid patch:** Candidate still fails or suppresses tests; signed report rejects and prevents payout.
3. **Fraud, conflict and replay:** Same-signing-operator aliases, wrong bounty/chain/SHAs, forged webhook, unauthorized contributor and malicious runner code fail safely.
4. **Timeout & dispute:** Timely submitted fix is preserved on verifier timeout; challenge resolves without indefinite escrow lock; sponsor gets objective legitimate refund only.
5. **Distributed recovery:** Worker interrupted mid-run, repeated webhook delivery, RPC timeout/reorg and database recovery preserve funds and truth.
6. **Usability & privacy:** A fresh sponsor and developer with distinct sessions/wallets complete journeys on desktop and mobile with no manual DB patching. Access to other teams' private evidence is denied.
7. **No invented metrics:** Every funded count, transaction, verifier result and screenshot is tied to actual local/testnet service evidence; clearly separate illustrative fixtures from production records.

## Common definition of done for every issue
- Narrow feature branch; reviewed PR describing outcome, architecture/trust effect, dependencies and rollback considerations.
- Verified each issue checkbox in its own description; attach compiler/CI/unit/integration/negative test outputs appropriate to scope.
- A working action must be backed by real persisted data, authenticated authorization and appropriate on-chain transaction—not only frontend rendering.
- Correct error/empty/unauthorized/reverted cases; no green mocks or fake success metrics.
- Financial changes include invariants, deadline edge cases and external security review before mainnet.
- Retain evidence (commit SHA, test output, actual explorer receipt or immutable report link if applicable); document unverified work truthfully.
- Merge only after acceptance review; then close that issue explicitly and move to the next. Never close work because a follow-on issue is planned.

## Stage gates
- **G0:** #1–#8: product clarity, security baseline, compatible network and initial code quality.
- **G1:** #19–#22 and #25: independently reproducible fix evidence.
- **G2:** #9–#18: real custody and final settlement, including exceptions.
- **G3:** #23–#39: founder-grade operating app, not demo pages.
- **G4:** #40–#46: E2E, independent security, restored operations, pilots and submission.

No single stage can bypass G0 chain-eligibility requirements. Hackathon-ready does not automatically mean safe for commercial mainnet funds.
