# CertiFiks historical Solidity escrow — baseline security assessment

**Issue:** #6 · **Date:** 2026-10-15 · **Review type:** Internal preliminary code-path assessment + reproducible Foundry tests. **NOT an external security audit, certification, production authorization or Portaldot V3 deployment.**

## 1. Provenance and build limitations
The Solidity baseline at contracts/src/CertiFiksEscrow.sol is a renamed/adapted copy of the historical ProofPatch escrow starter. The original was a research prototype. This file is marked unsafe in source and README; the independent Python reference model and 14 characterization tests live in research/reference-model.

The Solidity source compiles under **Solidity 0.8.24**, Foundry pinned to **v1.8.5** via GitHub Actions workflow, and Foundry tests exercise both ordinary lifecycle and known defects. To reproduce: cd contracts && forge --version && forge clean && forge build && forge test -vv.

**A passing Foundry test suite proves the existing code's observed behavior, including vulnerabilities. It does NOT mean the behavior is secure or acceptable.**

## 2. Findings prioritized by actual user harm

| ID | Severity | Finding and affected code | Foundry evidence | Blocking remediation issue |
|---|---|---|---|---|
| CF-001 | **CRITICAL** | refundExpired accepts Submitted state after verification timeout. A sponsor can recover locked money even if developer submitted exact work before deadline and the verifiers (outside developer control) went silent. | testKnownCriticalSponsorCanRefundTimelySubmissionWhenReviewersAreSilent | #15 (fair timeout), #14 (escalation), #17 (fuzz/invariants) |
| CF-002 | **HIGH** | _payDeveloper and _refundSponsor use synchronous push native-asset calls with require(ok). A reverting contributor recipient contract can block settled reward forever; credit is not independently withdrawable or safely redirected. | testKnownHighRevertingRecipientTrapsApprovedReward | #16 (pull credits), #17 (reentrancy / accounting tests) |
| CF-003 | **HIGH** | resolveDispute depends only on a single arbitrator EOA without a deadline/fallback. If the arbitrator is lost, conflicted or malicious, a challenged bounty can stay Disputed indefinitely. | testKnownHighDisputeCanRemainLockedIfArbitratorDisappears | #14 (bounded arbitration and fallback), #15 |
| CF-004 | **HIGH** | Verifier uniqueness is checked by wallet address only. One person or organization can control both verifier wallets and approve its own arbitrary reports; economic independence, enrollment/revocation and conflicts are absent. | testKnownHighTwoWalletsFromSameControllerCanApprove | #12 (independent controller registry), #13 (signed governance validation) |
| CF-005 | **HIGH** | recordVerification accepts arbitrary opaque reportHash values; it does not cryptographically bind reports to chain/contract, numeric GitHub repository ID, baseline/head SHA, immutable test image or proof provenance. The two verifiers can approve a fix without reproducible before/after tests. | testTwoVerifiersAndWindowPermitSettlement demonstrates this permissive behavior | #9 (immutable bounty spec), #11 (commit binding), #13 (attestation), #19–#25 (real evidence) |
| CF-006 | **MEDIUM/HIGH** | Sponsor can pick a developer wallet without developer acceptance, leading to squatting, misassignment or a nonresponsive recipient; unassigned wallet and duplicate submission checks exist, but the full assignment lifecycle is incomplete. | testUnauthorizedAndConflictedAssignmentFails, testOnlyAssignedDeveloperCanSubmitAndNoDuplicate | #10 |
| CF-007 | **MEDIUM** | Deadline semantics: submission accepted with timestamp <= deadline, verification with <= submittedAt + window and challenge with < approvedAt + challenge window. The window starts from actor-generated events, not chain finality for the actual target VM. Time arithmetic needs bound/invariant tests across Solidity/EVM vs a future WASM implementation. | testSubmissionDeadlineBoundary, testTwoVerifiersAndWindowPermitSettlement | #15/#17/#18 |
| CF-008 | **HIGH (deployment risk)** | Contract compiled for EVM and pays native currency on msg.value. Current Portaldot V3 testnet EVM endpoint, accepted wallet, gas, token and contract deployment are **not verified**; legacy Portaldot Mainnet RPC differs. Do not deploy or claim qualifying chain support. | Issue #2 read-only mainnet probe; no on-chain deployment | #18 |
| CF-009 | **MEDIUM** | The contract has neither versioned governance/contract migration process nor upgrade policy. Direct upgradability would introduce privileged theft and trust risks; no migration path exists for already funded bounties. | N/A — design omission | #5, #9, #16, #18 and governance review #41 |

**Risk state:** all findings remain OPEN. No test in this PR purports to fix them. #41 must perform independent security assessment after the actual production design is implemented.

## 3. State-transition test inventory
The Foundry characterization test exercises:
1. Bounty creation locks exact native asset and rejects unfunded/zero spec.
2. Authorized assignment and role conflict checks.
3. Assigned contribution, duplicate prevention and deadline exact boundaries.
4. Two verifier reports and no settlement before challenge timeout.
5. Disagreeing reviewers force dispute and arbitrator can issue sponsor refund.
6. Sponsor challenge prevents automatic payout and arbitrator can award contributor.
7. No-submission expiry permits sponsor refund.
8. Timely submission can be unfairly refunded if reviewers remain silent (**known critical exploit**).
9. Reverting developer receiver leaves approved funds blocked (**known high liveness flaw**).
10. Absent sole arbitrator leaves dispute unresolved after prolonged time (**known high liveness flaw**).
11. Two controlled reviewer wallets can pass without organizational independence (**known governance flaw**).

Every regression above is explicitly named `testKnown...` when it characterizes unacceptable historical behavior. When remediating #14–#16, invert the attack tests to assert the desired safe outcome. Don't remove the fixture merely because its historical behavior is insecure.

## 4. Decision record: replace push transfer with checked pull withdrawals
**Decision:** Introduce per-beneficiary claimable credits, transfer only after authenticated withdrawal, use checks-effects-interactions and nonReentrant guard, and account for all outstanding balances. A failed external recipient must leave the credit intact and allow a policy-bounded authorized retry or approved recipient change. Never give an operator an undisclosed wallet or arbitrary transfer permission.

**Acceptance for #16/#17:** invariant `sum(open liabilities + withdrawable credits) <= contract balance`; no double credit, double withdraw, refund-and-payout overlap, wrong recipient, reentrancy, receiver revert or gas griefing across any reachable transition.

## 5. Decision record: safe migration and deployment policy
**Policy for initial launch:** Deploy a versioned immutable custody contract only after verifying qualifying Portaldot VM and external security review. Avoid a general-purpose privileged upgrade proxy on public user escrow. If a bug requires replacement, deploy a separate audited next-version contract, leave old bounty terms immutable, permit fund withdrawal/refund only under precommitted recoverable rights, and require explicit participant consent for any new bounty funding/migration. Publish contract IDs, bytecode, chain identities, compatibility notes, pause/governance scope and migration receipts.

**Important caveat:** Some legacy escrow states currently lack a safe withdrawal/refund route; merely naming a migration process does not solve locked funds. Do NOT accept funds into this baseline. Design a precommitted fallback and test it under #14–#18 before any real contract receives deposits.

## 6. Go/no-go decision
**NO-GO for mainnet or user funds.** This starter is useful only as a reproducible behavior baseline and an attack-test inventory. Actual user-ready escrow requires #9–#18, external verification pipeline #19–#25, independent security review #41 and approved V3 deployment evidence #18. No Testnet 'green build' is a substitute for those conditions.
