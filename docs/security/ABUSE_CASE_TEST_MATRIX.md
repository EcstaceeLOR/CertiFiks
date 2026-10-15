# CertiFiks abuse-case and security test matrix

**Status:** Test design and release requirements only; tests are NOT yet implemented. Linked threat IDs map to [THREAT_MODEL.md](./THREAT_MODEL.md), invariants map to [SECURITY_INVARIANTS.md](./SECURITY_INVARIANTS.md).

## 1. Required adversarial test cases

| Test ID / threats | Setup and malicious action | Expected fail-closed outcome | Implementation target | Evidence required |
|---|---|---|---|---|
| A01 / T01 T21 | Replay SIWE/OAuth challenge, switch chain, reuse revoked org invitation | 401/403, no other wallet/org access, nonce one-time | #23/#30 | Auth integration traces and session test |
| A02 / T02 T10 | Reuse GitHub delivery ID, forge HMAC or wrong App installation ID | Reject invalid; replay idempotent; no phantom PR/run | #20/#28 | Webhook contract tests |
| A03 / T03 T22 | After sponsor funds, submit different test image, assertion, dependency or hidden criteria | Manifest digest mismatch; rejected; no payout | #9/#19/#25 | Canonicalization vectors, contract revert |
| A04 / T04 | Force-push PR after verification; submit changed head or wrong repo ID | Original evidence stays bound to original commit; changed candidate needs new attempt | #11/#20 | GitHub integration test |
| A05 / T04 T07 | Patch deletes/skips test or converts failing assertion into vacuous success | Trusted baseline/candidate harness integrity rejects or escalates; no positive quorum | #21/#25 | Malicious fixture report |
| A06 / T05 | Two different signatures for same reviewer/key and contradictory verdicts | Case frozen/escalated; double vote not counted | #12/#13 | Signature/vote conformance test |
| A07 / T06 | Untrusted PR reads /proc, host metadata, sibling temp dir or GitHub credentials | Access denied, secrets absent, resource-limited failure; incident logged | #21/#41 | Independent sandbox escape suite |
| A08 / T06 T08 | Fork bomb, infinite loop, GB logs, network exfiltration | Job bounded with explicit timeout/OOM/rejection; no platform-wide outage | #21/#28 | Worker fault-injection |
| A09 / T07 T18 | Guess private evidence URL across organizations; inject secret into log/notification | Authorized download fails; output redacted; no source leak | #22/#23/#29 | IDOR and redaction tests |
| A10 / T09 | Primary arbitrator becomes unreachable after funded dispute | Precommitted fallback activates automatically after deadline | #14 | Timed decision state test |
| A11 / T09 | Every fallback arbitrator disappears | **BLOCK RELEASE** until objective, on-chain terminal policy adopted and simulated | #14/#15 | Liveness model and stateful test |
| A12 / T10 T23 | Register two wallets controlled by same verifier organization | Only one organization counts; still no quorum | #12/#13 | Admission and negative vote test |
| A13 / T11 | Platform operator tries manual DB approval or unauthorized contract withdrawal | No contract credit; permission denied; alert/audit created | #9/#16/#23 | API and contract permission tests |
| A14 / T12 | Signed report reused on different chain, contract, bounty, attempt, repo, base/head, image or expiry | Signature verification/domain binding fails | #13/#19 | Cross-domain signature test vectors |
| A15 / T13 | Indexer receives replaced/reorged payout event after optimistic UX state | UI reverts to pending/unknown and reconciles chain; no credited local money | #27/#36 | Reorg simulation |
| A16 / T14 | Malicious reentrant withdraw contract tries callback + revert | Exactly one withdrawal credit can be spent; other funds remain claimable | #16/#17 | Foundry invariant test |
| A17 / T15 | Sponsor challenges every valid decision or waits until submission cutoff to claim refund | Timely attempt protected; bounded single challenge and escalation; no refund sniping | #14/#15 | Timestamp-boundary fuzz |
| A18 / T16 | Wallet connected to counterfeit RPC with different genesis/chain ID | Block funding and display actionable mismatch; no signature | #2/#18/#36 | Wrong-network E2E |
| A19 / T17 | Delete signed evidence bundle during active dispute, poison backup | Approval suspended; tamper detected; restore from integrity-checked replica | #22/#24/#42 | Restore and hash mismatch reports |
| A20 / T19 | Kill worker, GitHub 429, DB restart, duplicate queue message | Inconclusive/retry then escalation; no duplicate decisions/payout | #28/#40 | End-to-end fault injection |
| A21 / T20 | Admin attempts to change already-funded reviewer/quorum/policy | Forbidden for existing bounty; change audited for future only | #9/#12/#14 | Upgrade/admin controls test |
| A22 / T24 | Deploy Solidity to legacy WASM RPC or pretend local test node is V3 testnet | Deployment gate reports incompatible/blocked; no qualifying claim | #2/#18/#45 | Network probe + real approved tx |
| A23 / T03 T15 | Dishonest sponsor commits acceptance tests designed to never pass | Upfront preflight/warning and contributor review; failed attempts cannot be misrepresented as secure payout | #19/#25/#32 | Test-spec invalidity fixtures and UX |
| A24 / T05 T23 | Arbitrator also controls contributor/sponsor while reviewer hides conflict | Reassignment/recusal; conflicting signatures rejected; documented operator residual risk | #12/#14/#35 | Role-conflict test and audit trace |
| A25 / T13 T14 | Retry settlement twice via chain tx, API request and wallet reload | Single canonical escrow settlement, no duplicate credit or user success claim | #16/#17/#27/#40 | Cross-layer state convergence test |
| A26 / T08 T19 | Network outage starts after successful submission but before quorum | Timely claim remains protected; status INCONCLUSIVE, explicit bounded retry/escalation | #14/#15/#28 | End-to-end timeout fixture |
| A27 / T02 T07 | Fake fork PR embeds SSRF link, encoded token exfil or traversal path | Pre-checkout path validation, no network/secret, safe result | #20/#21/#41 | Sandbox and webhook tests |
| A28 / T18 T20 | Incident alert/email embeds user private repository/source | Redacted, role-bound notice; no unapproved external disclosure | #29/#42/#44 | Notification security snapshot |

## 2. Minimum CI/test evidence by feature class

**Protocol/contract:** Foundry unit tests, stateful invariant fuzzing, clock boundary and adverse caller receiver tests with logged seed and pinned compiler version (#6, #9–#17). If chain uses WASM instead, equivalent native execution/invariant tests plus exact ABI compatibility proof are mandatory; Solidity-only green tests do not suffice.

**Off-chain verification:** Test images pinned by digest, baseline failing for intended defect, candidate passing and unrelated regressions, exact GitHub SHA, signed evidence integrity and independent offline verifier (#19–#25).

**Operations:** Worker crash/restart, replayed GitHub webhook, queue duplicate, reorgs, service timeout, restored database and missing evidence must preserve safety and disclose liveness limitations (#24, #27, #28, #40, #42).

**User access:** Multi-account, cross-tenant negative tests for API, OAuth, GitHub installation, wallet identity switching, role revocation and evidence downloads (#20/#23/#26/#30).

**Independent security:** External penetration/review of runner and custody contracts before accepting mainnet user funds (#41). The authors of these specifications cannot self-certify completion.

## 3. Release stop conditions

| Gate | Must be demonstrably complete | Blocking open issue |
|---|---|---|
| Qualifying network | Actual V3 chain identity and approved contract deployment with receipts | #18 |
| Isolation | Untrusted code cannot access production or other-user secrets | #21/#41 |
| Value conservation | No double payment, reentrancy, unauthorized credit/refund, or stuck funds | #16/#17 |
| Proof validity | Genuine baseline-fails/candidate-passes; bound signed reports; no spoofed verifier quorum | #12/#13/#19/#25 |
| Timeouts and adjudication | Timely submissions protected, challenge honored, all-arbitrators-disappear fallback resolved | #14/#15 |
| Privacy and auth | Cross-tenant deny tests, private repo consent, incident disclosures and retention policy | #22/#23/#44 |
| Product readiness | Real funded→patched→verified→withdrawn and refund paths with external participants | #40/#43 |
| Production release | All known critical/high issues fixed and independently verified; backup/restore and support | #41/#42/#44 |

**No unsolved critical risk may be marked acceptable purely for a demo.** Hackathon-ready testnet demonstration must explicitly disclose incomplete commercial/mainnet security readiness.

## 4. Tracking practice
- Every implementation issue must attach at least the matching attack-case ID(s), artifact URLs, reproducible commands and negative outcome.
- A test is marked implemented only when executable code actually runs. The above rows are specifications, not results.
- A signed report without an independently reproducible bundle does not establish valid acceptance; a passed unit test cannot replace live on-chain evidence.
- Security findings are triaged by severity; regression tests and independent retests are mandatory for critical/high bugs.
