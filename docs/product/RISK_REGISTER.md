# CertiFiks — risk register

Date: 2026-10-15. All risks open unless explicitly reassessed; these are **not** resolved by writing this document. Threat-model refinement belongs to #3.

| ID | Failure mode | Severity | Mitigation / empirical validation | Issue |
|---|---|---|---|---|
| R01 | Qualifying Portaldot RPC/VM or hackathon eligibility unverified | Critical | Verify network, chain ID, VM, faucet, qualifying deployment and organizer rules before on-chain promises | #2, #8 |
| R02 | Sponsor changes tests or hidden acceptance rules after funding | Critical | Freeze hashed manifest and environments; show exact policy before wallet confirmation; test hash tampering | #5, #9, #19 |
| R03 | Malicious PR escapes code execution sandbox, steals API/GitHub secrets | Critical | Ephemeral workers, no secrets/network by default, limits, independent sandbox/escape tests | #21, #41 |
| R04 | Sponsor refunds after developer submits on time because verifier stalls | Critical | Protected timely submission + bounded review/arbitration; targeted adversarial test | #14, #15, #17 |
| R05 | Unresponsive/conflicted arbitrator freezes dispute funds indefinitely | High | Independent selection, timeout fallback and bounded terminal settlement | #14 |
| R06 | One operator pretends to be two independent verifiers | High | Identity enrollment, conflict checks, disclosed trust limitations, signer revocation | #12, #13 |
| R07 | Patch only deletes or skips tests instead of fixing a bug | High | Trusted harness and pinned image, baseline failure, candidate pass, regressions, human review | #19, #25 |
| R08 | Replay of signed result to wrong chain, bounty or head commit | Critical | Domain-separated attestations, nonce/expiry and signature replay negative tests | #13, #17, #19 |
| R09 | Payout reentrancy, double payment, revert traps developer funds | Critical | Pull withdrawals, accounting invariants, adversarial recipient tests | #16, #17 |
| R10 | GitHub tokens stolen or webhooks forged/replayed | High | Minimal App scope, HMAC signature verification, idempotency, no fork secrets | #20, #23 |
| R11 | Org/private evidence leaks across accounts | High | RBAC, tenant scoping, encrypted secrets, redaction and access tests | #22, #23, #24 |
| R12 | Reorg, lagging indexer, replaced wallet tx yields fake settlement UI | High | Chain finality rules, ledger reconciliation, pending and reverted states | #27, #36 |
| R13 | Worker restart, webhook retry or queue replay causes duplicated approvals | High | Durable jobs, unique attempt keys, leases, bounded retries | #24, #28 |
| R14 | DB/evidence artifact loss leaves no possible dispute audit | High | Content-addressed bundles, retention, backup/restore drill | #22, #24, #42 |
| R15 | UI shows fake funded bounties, payouts, metrics or demo-only functionality | High | Live API/contract integration, no demo success fallbacks, full route audit | #31–#40 |
| R16 | Hackathon check-in missed or ineligible chain/source | High | Primary-source rules, exact check-in evidence and qualifying deployment proof | #8, #45 |
| R17 | No maintainer demand, poor economics or expensive verification | High | External user interviews, two independent pilot cases, cost data and pricing experiments | #7, #43, #46 |
| R18 | Brand name conflicts with registered CERTIFIX marks | Medium / Unknown | Formal trademark clearance, potential rebrand before permanent commercial launch | #44 |
| R19 | Public real-funds launch before independent security/legal review | Critical | Testnet-only until reviewed contracts, incident runbook, privacy/compliance and launch checklists | #41, #42, #44 |
| R20 | Cryptographic success conflated with universal code correctness | High | Document test limits, honest reports, human-review path and qualified claims | #1, #22, #44 |

## Ownership and escalation
- Founder: R01, R15–R20, and the release decision.
- Protocol/security engineers: R02–R09, R19–R20.
- Backend/infrastructure engineers: R03, R10–R14.
- UX/product: R04, R15, R16, R17.
- A risk is only marked mitigated after linking a test, PR and relevant external proof. Recording mitigations above is not completion.
- **Stop conditions:** No proven Portaldot network -> no qualifying-chain claim; no isolated sandbox -> no public untrusted-code execution; no dispute liveness -> no claimed protected escrow; unresolved critical/high security findings -> no mainnet user money.
