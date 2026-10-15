# CertiFiks security threat model and trust architecture

**Version:** 0.1 · **Date:** 2026-10-15 · **Review status:** Initial security design, NOT a code audit, NOT deployed · **Issue:** #3

This document defines adversaries, assets, boundaries, security controls and release blockers for the product specified in [product requirements](../product/PRD.md) and [lifecycle](../product/STATE_MACHINE.md). The implementation issues own operational proof. Nothing herein is a claim that controls already exist.

## 1. Security objectives and non-objectives

**Primary:** Preserve user escrow, authorized payouts and refunds; bind any award to the precise versioned, committed acceptance policy and authentic GitHub revision; prevent forgery, replay, secret leakage, tampering, unfair timeout settlement and indefinitely stuck funds; provide independent audit evidence and recoverability.

**Security non-objective:** A verifier's test result does not prove general semantic correctness. Named reviewers with separate organizational identities are an accountable, **permissioned trust model**, not mathematically trustless consensus. A smart contract cannot determine by itself whether an arbitrary software bug is truly fixed. CertiFiks must not promise decentralization, censorship resistance or certified correctness it cannot enforce.

**Release stages:** Only read-only analysis and safe testnet development until a real qualifying Portaldot V3 environment (#2/#18), isolated runner (#21), complete refund/challenge policy (#14/#15), audited contract invariants (#17/#41), incident recovery (#42), and privacy/compliance review (#44) exist. Unmitigated critical/high security findings block mainnet with user funds.

## 2. Assets and trust boundaries

| Asset | Security goal | Authority / boundary |
|---|---|---|
| Sponsor escrow and payout/refund claims | No theft, loss, double settlement or indefinite freeze | Custody contract is authoritative; never trust UI/DB as ledger |
| Immutable acceptance spec | No after-funding test/policy edit, ambiguity or policy downgrade | Hash committed on chain; canonical signed manifest off chain |
| Repo/commit identity | Exact code provenance, not mutable branch labels | Authenticated GitHub installation/API for numeric repo ID, pinned base and head SHA |
| Trusted test harness and artifacts | Confidentiality where needed; executable integrity | Pinned image, restricted immutable test source, isolated runner, content hashes |
| Verification attestations | Attributable, nonreplayable, conflict-screened decision | Enrolled key registry, signer verification, chain/contract/bounty/attempt domain |
| Private GitHub installation tokens & CI secrets | No extraction by fork/runner, least privilege | Backend secret store only; never inside untrusted source runner |
| User sessions, wallet binding and team memberships | Prevent takeover, impersonation, privilege escalation | Signed wallet challenge + OAuth binding + server-side authorization |
| Audit history and case evidence | Preserve integrity, availability and restricted access | Content-addressed store, append-only logs, encrypted backups |
| RPC/indexer and event processing | Reflect canonical chain state under reorg and outage | Confirmed chain truth, chain ID/genesis pinning and idempotent log consumer |
| Verifier and arbitrator authority | Accountable independent decisions with timed removal | Public role registry, admission/conflict process, replacement and emergency policy |

### Data flow and trust boundary diagram (textual)
1. Browser/WALLET -> API authenticates sponsor/developer: untrusted user input; session+signature validation boundary.
2. GitHub installation -> Webhook ingress: untrusted internet delivery; HMAC, delivery IDs and GitHub API consistency boundary.
3. API/DB -> Job queue -> Isolated runner: untrusted third-party source code; no production tokens, controlled filesystem/net access; output not inherently trustworthy.
4. Runner -> Human reviewers: untrusted result bytes; pinned container image, reproducible content digest and explicit human signature boundary.
5. Reviewers -> Contract: external cryptographic claims; replay, role, quorum, expiry and exact manifest/SHA verification boundary.
6. Sponsor/developer/arbitrator -> Contract: all money-moving calls independently authenticated and state-checked; API statuses irrelevant to custody.
7. Contract -> Indexer -> DB/UI: chain events may be delayed or reorganized; finality, reconciliation and duplicate suppression boundary.
8. Artifacts -> UI/external verification CLI: hashes/public attestation can be public; full logs and private source strictly tenant-scoped.

## 3. Threat actors and capabilities

- **Dishonest sponsor/maintainer:** authors unfair acceptance tests, changes issue/PR permissions, withholds access, recruits verifier aliases, times out review, challenges to delay payout, funds via malicious recipient.
- **Dishonest contributor:** submits fake PR/force-push, self-verifies, patches trusted harness, disables tests, writes malicious code to run on infrastructure, forges wallet/account linking or tries duplicate claims.
- **Compromised verifier/arbitrator:** signs deliberately wrong or contradictory reports, leaks restricted code, colludes across organizational roles, goes silent or loses/reuses signing keys.
- **External attacker:** steals installation secrets, sends forged GitHub webhook, spoofs RPC/indexer, initiates reentrancy or gas-griefing, exploits SSRF/IDOR, triggers replay, floods workers or exploits CI sandbox.
- **Malicious/compromised infrastructure provider:** withholds RPC finality, reorders webhook/event delivery, serves stale data, loses evidence files, leaks secrets or changes image tags.
- **Platform operator with admin privileges:** modifies DB state, signer registry or alerts; must NOT be able to drain sponsor escrow unilaterally. Administrative recovery is explicit, auditable and bounded.

## 4. STRIDE attack inventory

Rating: C = critical, H = high, M = medium. Likelihood is provisional. 'Control' refers to a REQUIRED future mitigation, not work already implemented.

| ID | STRIDE | Concrete attack and harm | Level | Required control, residual risk and test issue | Owner |
|---|---|---|---|---|---|
| T01 | Spoofing | Stolen wallet session/OAuth callback impersonates funded sponsor | C | Domain/chain-bound nonce, PKCE, secure sessions, account separation; remaining wallet-device compromise; #23/#41 | Auth |
| T02 | Spoofing | Forged webhook claims PR verified, replayed delivery mutates state | H | GitHub HMAC, installation IDs, dedupe and API refetch; remaining compromised GitHub App; #20/#28 | GitHub |
| T03 | Tampering | Sponsor swaps acceptance tests, dependencies or hidden criteria after locking funds | C | Immutable canonical manifest/env hashes, allowlist revisions and hard contract digest match; remaining dishonest originally agreed tests; #5/#9/#19 | Protocol |
| T04 | Tampering | Contributor force-pushes PR or alters harness to pass vacuous test | H | SHA pin, trusted harness outside PR, fail-before/pass-after + regression tests; remaining weak test design; #11/#25 | Verification |
| T05 | Repudiation | Reviewer denies attestation, arbitrator rewrites or hides ruling | H | Domain-separated signed report/reason, audit trail and immutable evidence; compromised signer remains attributable not necessarily honest; #13/#14/#22 | Governance |
| T06 | Information Disclosure | Fork PR code reads GitHub installation token, cloud metadata or neighboring tenant | C | Dedicated ephemeral sandbox, deny outbound network and metadata, no production secrets, escape tests; virtualized-host residual risk; #21/#41 | Infra |
| T07 | Information Disclosure | Unauthorized user downloads private source/test logs or cross-org dispute bundle | H | Per-tenant RBAC, signed temporary downloads, encryption/redaction/retention; operator misuse residual; #22/#23/#24 | Backend |
| T08 | Denial of Service | Fork bomb, huge logs, malicious dependencies exhaust worker and stall paid bounty | H | Resource limits, isolated queue, bounded retries, backpressure/quotas and timeout escalations; high cost still possible; #21/#28 | Infra |
| T09 | Denial of Service | Verifier or arbitrator vanishes, indefinitely freezes escrow | C | Enforced deadlines, precommitted fallback, transparent notice, eligible replacement quorum and explicit terminal policy; unresolved liveness tradeoff blocks release; #14/#15 | Governance |
| T10 | Elevation of Privilege | One person registers several verifier wallets and self-approves payout | C | Named organization enrollment, distinct beneficial controllers and role conflict restrictions; sybil/collusion cannot be cryptographically eliminated; #12/#13 | Governance |
| T11 | Elevation of Privilege | Operator/API bypasses contract to transfer reward or change settlement | C | No platform spend key, on-chain capability permissions, protected upgrades, invariant tests; chain admin key risks remain; #9/#16/#17 | Contract |
| T12 | Tampering | Forged result attaches genuine signature to wrong repo/head/bounty/chain | C | Canonical hash includes chainId+contract+bounty+attempt+repoId+base/head+image+manifest+expiry; malformed/replay deny tests; #13/#19 | Protocol |
| T13 | Tampering | Indexer presents pending or reorged transfer as final payout | H | Finality threshold, genesis/chain pinning, durable event replay and reconciliation; RPC majority risk; #27/#36 | Indexer |
| T14 | Elevation of Privilege | Reentrancy, reverting receiver or math error double-credit / traps funds | C | Pull withdrawals, checks-effects-interactions, uint bound and conservation invariants; unknown compiler/runtime risk; #16/#17 | Contract |
| T15 | Denial of Service | Sponsor challenges every valid fix or snipes expiry to force refund | H | Immutable deadline and challenge rights, bounded one-case process, fair timely submission protection; discretionary judgment risk; #14/#15 | Contract |
| T16 | Spoofing | Fake eligible blockchain RPC or chain-switch tricks wallet into other network | H | Genesis/chain ID checks, explicit wallet display, verified RPC URLs, confirmation; wallet UI can still be compromised; #2/#18/#36 | Chain |
| T17 | Tampering | Storage outage/deletion corrupts signed evidence needed for dispute | H | Content hashes, independent download, encrypted replicas and restore drill; network/storage correlated failure; #22/#24/#42 | Ops |
| T18 | Information Disclosure | Error reports or notifications leak private repo paths, email, access tokens | H | Structured redaction, restricted telemetry, secrets scanner, retention and safe notices; user-uploaded PII risk; #29/#41/#44 | Backend |
| T19 | Denial of Service | External dependencies (GitHub/RPC/database) fail during timeouts | H | Inconclusive, bounded retries, persisted work queue, fair escalation and no false payouts; fail-close may degrade user UX; #14/#15/#27/#28 | Ops |
| T20 | Repudiation | A platform operator silently changes verifier admissions, removal or dispute policies | H | Public registry logs, pre-funded-policy immutability, multi-person admin control and incident notice; admin governance risk remains; #12/#14/#42 | Governance |
| T21 | Spoofing | Org invitation/role reuse exposes wallet or private GitHub repos to old teammate | H | Invite expiry, revocation, organization RBAC with repo-scoped bindings; compromised owner residual; #23/#30 | Auth |
| T22 | Tampering | Malicious source dependencies fetched over network alter acceptance behavior | H | Pinned image, vendored/locked dependencies and network-denied runner, reproducible artifact digest; supply chain poisoning of original pinned image; #19/#21/#25 | Verification |
| T23 | Elevation of Privilege | Arbitrator/verifier/sponsor secretly control same organization | H | Documented beneficial-controller review, declarations, recusal, signed challenge trail; determined collusion remains possible; #12/#14 | Governance |
| T24 | Denial of Service | Bounty reward locked on unsupported VM or no qualifying V3 network | C | Issue #2 NO-GO; block deployment until actual matching V3 RPC/VM, genesis and receipts exist; organizer dependencies remain; #18 | Founder |

## 5. Concrete v1 governance decision (permissioned and accountable)

- **Initial policy:** One operator must register a verifier organization and its authorized wallet(s). For one bounty, success requires **two positive attestations from two separately enrolled organizations with different declared beneficial controllers**, for the *same immutable attempt/report context*. Wallet-key separation alone is insufficient.
- A sponsor, contributor, maintainership controller, arbitrator or CertiFiks platform owner with an economic interest in that bounty may not be counted as an independent verifier for it. Registry enrollment, suspension and conflicts are auditable and reviewed by people; cryptographic signatures bind their exact report, but identity claims remain socially enforced.
- A rejected, inconclusive, missing, expired or disagreeing report **never counts as a positive quorum**. Any deterministic single-verifier bypass is forbidden.
- Reviewers may examine signed sandbox evidence but cannot unilaterally settle on chain. Funds move only under contract state transitions and role-checked signed/chain-submitted actions.
- Disputes must have one conflict-checked primary adjudicator and a separately governed substitute/escalation panel. A sponsor does not hand-pick an arbiter *after* a dispute starts. All decision authorities, timeouts, appeals and fallback behavior must be visible and committed **before funding**.
- A compromised enrolled signer must be revoked for future attempts; an already committed decision or escrow cannot be retroactively rewritten. Pending cases require independent escalation and key-rotation response, not a hidden 'admin override'.
- **Residual trust warning:** Organizational independence and fair judgments cannot be cryptographically assured. The service must disclose the enrollment authority and role conflicts, and avoid marketing as fully decentralized or trustless.

## 6. Explicit liveness/timeout policy (product requirement, not yet deployed)

This is a **proposed design** requiring on-chain specification and adversarial tests in #14/#15. Timeouts are measured from immutable contract events using chain time/block parameters, not server clocks or editable timestamps.

| Failure / timeout | Safe default system action | Must never happen |
|---|---|---|
| No eligible applicant within funded application window | Bounty expires into predetermined, claimable sponsor refund | Unannounced sponsor fee extraction |
| Assigned developer deadline passes with no submission | Precommitted safe reassignment or refund, preserving submitted-at boundary | Two active beneficiaries |
| Contributor submits before deadline; runner fails or GitHub inaccessible | Mark INCONCLUSIVE; preserve timely claim; bounded retries then independent review/escalation | Sponsor immediately refunds due only to infrastructure failure |
| Quorum never reached, reports disagree or signer compromised | No approval; independent second review/appeal route; notify all participants | One actor fabricates second vote |
| Two authentic positive reports, challenge pending | Funds remain held through contract-enforced fixed challenge window | Instant payout before challenge ends |
| Timely valid sponsor/developer challenge | Freeze current settlement; preserve parties' evidence/response window | Sponsor may postpone indefinitely with repeated challenges |
| Primary arbitrator silent or conflicted | Escalate automatically to pre-funded named alternate/quorum; notify parties and preserve records | Funds locked to one disappeared wallet forever |
| Fallback reviewer/panel also silent | **RELEASE BLOCKER** until exact contract-safe terminal policy and fair risk allocation are formally specified in #14/#15 | Secret unilateral refund or payout based on admin preference |
| RPC/indexer outage/reorg | Mark pending or unknown, retry/reconcile canonical chain state | Treat unfinalized/reverted tx as successful |
| Artifact storage disappears | Suspend approval and escalate to recovery/case review | Generate new signed 'successful' evidence from cached UI |

Before a bounty may accept user funds, the system must commit **explicit calendar/chain time bounds** (submission, verification, challenge, arbitration and fallback), allowed retries and an agreed bounded terminal resolution. The unsolved all-adjudicators-missing case above is a deliberate **critical release blocker**, not a design success.

## 7. Evidence privacy and retention principles

- Public proof: on-chain commitment hashes, summary outcome, reviewer public enrollment keys, redacted report metadata and settlement receipts.
- Restricted proof: private repo source, proprietary test data, raw logs, organization accounts, identities, dispute attachments and encrypted failure traces. Access scoped to sponsor, assigned contributor (when authorized), eligible independent reviewer and adjudicator.
- Store report body in content-addressed artifact storage with server-side encryption, integrity check and auditable limited-time access. Retention duration is an **open legal/product decision** in #22/#44, but retention must at least cover active challenges plus appeals.
- GitHub OAuth/install credentials, signing keys, wallet session challenge nonces and signing seeds **never enter untrusted runners, browser telemetry, PR logs or public artifacts**.
- Provide privacy rights and legal/compliance review before allowing sensitive private repositories or production transactions.

## 8. Review/risk ownership and release stop conditions

1. Chain-specific security assumptions cannot be finalized until V3 VM/runtime is verified (#2/#18).
2. **Untrusted public PRs are disabled** until sandbox isolation and secret-exfiltration tests pass (#21/#41).
3. **No actual bounty funds** until immutable hash invariants, withdrawal conservation and fair terminal dispute paths are implemented and tested (#5/#9/#14–#17).
4. **No mainnet funds** without external security audit, vulnerability retests, incident/rollback and legal-policy review (#41/#42/#44).
5. No security claims such as 'independent', 'trustless' or 'guaranteed fix' beyond documented admission process and observed test evidence (#12/#22/#44).
6. Register vulnerabilities in [product risk register](../product/RISK_REGISTER.md) and the [abuse-case verification matrix](./ABUSE_CASE_TEST_MATRIX.md); highest unresolved severity governs release decision.

**Review status:** This is an engineering threat assessment for design and backlog sequencing. It does not constitute an independent audit or certification. The contract code and runtime are not yet deployed or tested in this issue.
