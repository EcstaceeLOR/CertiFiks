# CertiFiks security invariants, access controls and authority boundaries

**Status:** Normative design requirements; NOT implemented · **Tracking:** #3 (future enforcement #5/#9–#17/#23/#41)

## 1. Definitions
- **Bounty:** uniquely identified funded agreement committed to chain with a fixed manifest digest, participants, reward and review/expiry policy.
- **Attempt:** (bounty, developer, numeric GitHub repo ID, immutable baseline SHA, submitted head SHA, manifest hash, attempt sequence, chain and contract), cryptographically hashed using documented canonicalization and domain separation.
- **Verifier identity:** an approved *organization and signer binding*, not merely an EOA. Different keys under the same enrolled organization do not count as different reviewers.
- **Review/decision:** explicit bounded positive, negative or inconclusive attestation for the exact same immutable attempt and signed evidence.
- **Escrow balance:** the total funds held by on-chain contract. UI balance and worker state are non-authoritative.
- **Terminal claim:** a contract-created, payable credit to exactly one authorized recipient as determined by the committed escrow conditions.

## 2. Control invariants (proposed formal properties)

**S01: Conservation and exclusivity (P0).** For all reachable contract states, the aggregate of unsettled bounty liabilities, outstanding developer withdrawal credits, and outstanding sponsor refunds is never more than available custody; each funded unit can be allocated **at most once** to one terminal beneficiary. Track fees separately, never by silently reducing contributor credit.

**S02: Authorized payer and recipient (P0).** The only party who can create reward custody is the sponsor signing actual chain transaction; only contract-validated participants can obtain credits. Withdrawal requires beneficiary authorization and cannot be redirected by untrusted API metadata.

**S03: Immutable post-funding terms (P0).** Every bounty's reward, manifest digest, numeric repository identity, baseline commit, expiry, verifier policy, challenge window, arbitration authority and fees are immutable once funded. Updating spec requires terminating through its permitted path and funding a *new* bounty.

**S04: Single valid assignment (P0).** At most one active contributor may earn under an active bounty attempt; sponsor choice alone does not impersonate contributor acceptance. Attempts from non-assigned or expired contributor identities are rejected.

**S05: Exact proof binding (P0).** A positive vote proves only: accepted signer organization, chain ID/genesis and contract address, bounty ID, attempt sequence, repo ID, baseline/head SHAs, manifest digest, trusted image digest, result digest, verdict and expiry. Any changed field invalidates authorization.

**S06: Distinct reviewer controllers (P0).** Quorum counts **separately enrolled and conflict-checked beneficial controllers**, not distinct keys alone. Sponsor/developer, maintainer, arbitrator or platform operator with financial interest cannot fill the verifier quorum.

**S07: No result fabrication (P0).** An inconclusive, failed, flaky, skipped, tampered or unreachable test never becomes positive due to a queue retry, manual DB write, UI toast or single reviewer vote. Trusted tests must fail on baseline for the agreed defect and pass on candidate without unapproved harness modifications.

**S08: Contention safety (P0).** Reentrant call, callback, duplicate webhook, duplicate report, multiple concurrent wallets, transaction reorg, invalid nonce or double withdrawal cannot allocate a second liability or settle the same bounty twice.

**S09: Challenge fairness (P0).** A positive quorum enters a bounded review window before claimability. A timely valid challenge freezes relevant settlement only for the committed case. Challenges and arbitration cannot extend indefinitely.

**S10: Timely developer protection (P0).** Once an eligible contributor submitted a valid SHA before deadline, external verifier/runner outage alone cannot authorize immediate unilateral sponsor refund. A contract-enforceable escalation policy must determine a fair terminal result.

**S11: Dispute liveness (P0; currently unresolved release gate).** Every funded dispute must have a declared deadline, fallback independent authority and a bounded terminal outcome that does not depend indefinitely on a disappeared privileged signer. This remains a **blocking, not-yet-solved design requirement** pending #14/#15.

**S12: Finality and chain selection (P0).** Each view and signed payload is bound to an explicit chain. Off-chain payouts are never displayed as final until the canonical on-chain contract state and receipt satisfy specified finality. Correctness cannot rely only on an RPC's unconfirmed response.

**S13: Tenant and secret isolation (P0).** Org/user with no permission cannot fetch private evidence, repo source, signer secrets or workflow logs; untrusted contributor code cannot see GitHub App token, signing key, metadata service or a different customer's job.

**S14: Auditability (P0).** Every privileged role change, signed report, dispute ruling and payment decision creates a durable, time-stamped, hash-linked event. The operator cannot silently replace historical evidence or change funded terms.

**S15: Operational recovery (P0).** Queue/DB restart, retry, replayed webhook or benign RPC outage must not manufacture a positive verdict or release funds. Failed workers must transition to explicit retryable/inconclusive state.

**S16: Release gate integrity (P0).** A testnet proof is not mainnet audit approval, and an old Portaldot mainnet RPC is not proof of a V3 testnet contract. Until issue #18 has genuine compatible deployment receipts, claims of Portaldot integration remain prohibited.

## 3. Role and capability matrix
Permissions are **independent on-chain and server-side checks**. Roles can overlap globally, but conflict policy excludes same-controller economic parties from a given bounty's independent decisions.

| Action | Sponsor | Assigned contributor | Eligible verifier | Independent arbitrator | Platform operator |
|---|---|---|---|---|---|
| Create draft/manifest | Yes, for owned repo | No | No | No | No |
| Fund escrow | Yes, authenticated wallet | No | No | No | **Never** using platform-owned escrow signer |
| Edit funded manifest/reward | **No** | No | No | No | No |
| Apply for reward | No (self-award blocked) | Yes, before assignment | No when conflicted | No when conflicted | No when conflicted |
| Assign contributor | Yes per immutable bounty rules | Must separately accept | No | No | No |
| Submit fix SHA | No | Yes with exact authenticated assignment | No | No | No |
| Start protected runner | API queues validated job | Request authorized submission | View/trigger scoped job only | Review case only | Safe retry only, no result override |
| Produce signed positive verdict | No | No | Yes if enrolled, eligible and explicit | No for disputed bounty | No, unless independent eligible org in separate disclosure-reviewed design |
| Challenge outcome | Yes within policy | Yes where policy grants response/procedural appeal | Report a conflict, not personal payout override | No after being appointed | Report incident, never economic veto |
| Open/resolution of dispute | File challenge | File rebuttal/procedural claim | Can submit evidence | Resolve if preselected and unconflicted | Escalate to declared fallback only |
| Allocate developer reward | Contract after quorum/window or ruling | Cannot mint own credit | Cannot release funds directly | May produce authorized ruling only | No unilateral mint/credit |
| Authorize sponsor refund | Contract on objective policy / ruling | No | No | May rule within bounded case authority | No unilateral redirect |
| Withdraw authorized credit | Only sponsor refund to authorized recipient | Only developer reward to authorized recipient | No | No | **Never** |
| Change verifier enrollment | No per-bounty override | No | Enrollment request/revocation | Conflict declaration | Admin-controlled, multi-person logged, no retroactive funded term change |
| Read private repo/evidence | Only owned/authorized | Scoped to assigned case | Scoped to specifically assigned case | Scoped to assigned disputed case | Limited break-glass audited support access only |

## 4. Secrets, signer and privileged operation design
1. **Funding/withdrawal:** Wallet signatures submitted to on-chain contract; backend never stores sponsor/developer withdrawal private keys.
2. **Platform backend:** GitHub App private key resides in audited secret manager; mint installation tokens with minimum necessary scope, short TTL. No full repo access unless specific maintainer grants it.
3. **Untrusted test runner:** No inherited backend cloud credentials, wallet keys, GitHub tokens, shared writable storage, Docker host socket or unrestricted outbound network. The input includes fixed SHA + harmless read-only code checkout via a scoped prefetch stage and immutable image.
4. **Verifier:** Each enrolled legal/organizational reviewer controls separate signing key(s) with revocation and rotation. Registry tracks beneficial-controller identity and conflict declarations. Verifier must explicitly sign the exact immutable evidence digest.
5. **Arbitration:** Named precommitted authority with case-level recusal and a precommitted independent substitute panel. No one admin can silently change review windows after funding. All privileged adjudication must be transparent.
6. **Chain admin controls:** Any upgradability, pause or signer-registry authority must be explicitly disclosed and governed. 'Emergency pause' MUST NOT become a hidden arbitrary withdrawal power. A permanent paused system or missing arbiter is a serious liveness risk.
7. **Logging:** Redact tokens, user wallet signatures not intended to be public, private source and personal identifiers. Publish only public hashes/receipts and scoped content-addressed evidence.
8. **Data protection:** Restricted evidence retained through appeals; delete/export policies only after review. Private repo source is never displayed in public verification pages.

## 5. Negative test obligations before any financial launch
| Invariant | Tests / attacks required | Future issue(s) |
|---|---|---|
| S01, S02, S08 | Fuzz handler with arbitrary operation orders, double withdraw, reentrancy and reverting recipient | #16/#17/#41 |
| S03, S05 | Manifest/hash tampering, replay across bounty/chain/contract, changed GitHub head | #11/#13/#19 |
| S04 | Unassigned/expired developer submission, assignment race and reassignment | #10/#11 |
| S06, S07 | Two wallets in same enrolled organization, conflicting signed reports, skipped tests and malicious harness | #12/#13/#21/#25 |
| S09–S11 | Boundary time-warp, early payout, late challenge, sponsor timeout sniping, silent primary and fallback arbiters | #14/#15/#17/#40 |
| S12, S15, S16 | Malicious RPC chain identity, reorg, worker kill, duplicate job/chain event, genuine V3 deploy | #2/#18/#27/#28/#40 |
| S13, S14 | Secrets/metadata exfiltration, IDOR, evidence tamper, role changes and audit chain verification | #20–#24/#41 |

See [full scenario-by-scenario matrix](./ABUSE_CASE_TEST_MATRIX.md) for exact fail-closed expectations and evidence requirements.

## 6. Unresolved issues cannot be papered over
- Genuine V3 testnet endpoint, VM/ABI and deployability: #18 hard gate.
- Objective fraud/test policy and sufficient evidence to authorize reward: #5/#12/#13/#25.
- Independence proof of reviewers: current v1 model is permissioned/attested, never cryptographically guaranteed.
- Terminal dispute fallback when *all* adjudicators disappear: #14/#15 release blocker until on-chain enforceable solution and signed risk acceptance.
- Confidential code handling, record retention and jurisdictional compliance: #21/#22/#44 before sensitive/private usage.
- Contract or service security review is not complete merely from these docs: #17/#41.

**This is a normative specification, not a test report or production guarantee.**
