# CertiFiks — Fair timeout, refund and entitlement policy (v1)

**Issue #15 · 2026-10-15 · Stage: abstract Solidity state/accounting model, NOT a deployed funds service.**

## Trust and money boundaries

The existing starter's critical flaw allowed a sponsor refund **after a developer submitted on time** if external verifiers stayed silent. The new implementation explicitly prohibits that shortcut.

- `FairEntitlementModuleV1.sol` inherits the bounded arbitration and signed-verification modules, and is **abstract**. It has **no externally payable production funding**, credit, transfer, refund withdrawal, or emergency admin sweep.
- A terminal entitlement is an on-chain decision allocating **native-asset atomic units**, not actual payment; no funds move, and `totalReservedAtoms` stays unchanged until #16 implements audited pull-withdrawal accounting.
- `recordNoSubmissionRefund` is allowed only after an already valid, explicitly marked `CancelledPendingRefund` (no accepted developer) or `ExpiredPendingRefund` (no submission after the immutable deadline), **and no attempt has ever been pinned**.
- `recordResolvedEntitlement` is allowed only for the currently pinned submitted attempt, with a case in `Resolved`, matching exact attempt digest, and a final award from #14's reviewed/timeout state machine.
- The sponsor cannot force a refund after a timely submission, a negative reviewer vote, a stalled verifier, or a pending arbitration/appeal, without going through the already committed bounded arbitration and response rights.
- Exactly **one immutable entitlement** is recordable per bounty; repeat calls are rejected. A different attempt cannot consume an earlier attempt's final award.
- The total nominal sponsor/developer allocations must equal the **exact reward** committed at funding. Any native ETH arriving directly or force-sent outside funding is **unreserved surplus**, not an increase in bounty liabilities. No unaudited surplus rescue/sweep is provided.
- Each entitlement emits beneficiary wallets, amounts, source attempt/reason digests and reason category for later finalized event reconciliation.

## Refund and award decision table

| Original on-chain state / condition | Permitted outcome | Sponsor atoms | Developer atoms | Who can finalize |
|---|---|---:|---:|---|
| Funded, unassigned, sponsor cancelled before acceptance | UnassignedSponsorCancellation | 100% | 0 | Any account, *only after sponsor's authorized cancellation state* |
| Accepted developer, **no submission**, original submission deadline passed strictly | NoSubmissionAtDeadline | 100% | 0 | Any account after permissionless expiry flag |
| Timely submitted, before signed quorum / expiry / arbitration | **Not eligible for funds decision** | 0 allocated | 0 allocated | Nobody |
| Two independent signed approvals, completed challenge window, **not challenged** | ApprovedFix | 0 | 100% | Any account after unchallenged approval finalized |
| Independently adjudicated sponsor decision, no appeal outstanding | IndependentlyAdjudicatedSponsorRefund | 100% | 0 | Any account after terminal case |
| Independently adjudicated developer decision, no appeal outstanding | ApprovedFix | 0 | 100% | Any account after terminal case |
| Positive signed quorum, sponsor challenge, **both primary & backup arbitrators silent** | ApprovedFix (unchallenged proof stands) | 0 | 100% | Any account after both timeouts and terminal case |
| **Insufficient, dissenting or failed verification**, both primary & backup arbitrators silent | SharedSilenceFallback | 50% (round up odd atoms) | 50% (round down odd atoms) | Any account after two timeouts and terminal case |
| Previous superseded attempt, wrong chain, incomplete dispute, same entitlement replay | **Reject** | — | — | Nobody |
| Unexpected/native direct-surplus ETH without funding event | Quarantined unreserved surplus | 0 | 0 | No sweep/credit action in this module |

**Why a 50/50 fallback?** If a contributor submits on time but reviewers and *both* precommitted arbitrators fail, neither a full developer payout as “verified” nor an automatic full sponsor refund is justified by the available evidence. A bounded, **pre-disclosed neutral economic allocation** avoids granting the sponsor a perverse incentive to suppress the verifier. This is a **governance and fairness design choice, not a proof of correctness** and may be rejected by future user research, counsel or security audit. It is fixed in this pre-deployment v1 Solidity rule and must be consented to before anyone deposits/accepts. Any different fallback requires new immutable funding terms and a new vetted contract version; it is never a silent operator override.

**Important remaining risk:** Sponsor and contributor can dispute whether the precommitted tests are adequate, reviewer identities are genuinely independent, and the split is enforceable in their jurisdiction. A smart contract cannot determine truth when all human evidence channels fail.

## Deadline boundary and liveness rules

1. Cancelled unassigned bounties: sponsor may cancel while assignment remains `Open` or `Offered`, but never after an accepted developer or submitted fix.
2. Missed submissions: `expireUnsubmittedBounty` can only mark expiry at timestamp **strictly greater than** the original funded `submissionDeadline`; contributions at exactly the cutoff remain eligible under existing #10 rules.
3. Submitted fixes: reviewer window, challenge deadline, primary arbitration deadline, backup arbitration deadline and appeal response rights are precomputed under #13/#14; sponsor challenges **cannot extend them**.
4. Verifier silence: the case may be opened permissionlessly after the funded verifier deadline. Primary and fallback timeouts advance permissionlessly to an enforceable terminal *decision*, even when neither arbitrator acts. **Actual withdrawal** still depends on #16.
5. Pending dissent or rejected reports: no immediate refund or developer credit; response and appeal windows remain active until terminal judgment.
6. Uncontested signed quorum: challenge window must pass before the authorized unchallenged developer award can be finalized.
7. No user or governance role can call an equivalent of the historical `refundExpired` after timely submission.

**Remaining liveness limitation:** Chain transitions require gas and someone to send a transaction; an off-chain keeper/indexer with a monitored service-level objective is required for a finished product. Some cases opened after all deadlines have elapsed provide little practical response time, a known Issue #14 notice dependency. Neither “green tests” nor a bounded timestamp guarantees a real user saw their evidence in time. Issue #22/#24/#26 must provide signed notices, durable accessible records and a procedural remedy.

## Gas/fee and unexpected-asset policy

- **No reviewer fees, challenger bond, appeal bond, rescue fee, or undisclosed fee deduction** is implemented. Funds in `rewardAtoms` are fully assigned only under terminal conditions. On-chain EVM gas costs, if applicable, are paid by whichever account sends the transaction and are *not* silently deducted from the reward.
- `totalReservedAtoms` continues to represent original liabilities while actual funds remain in the contract. Entitlements do not free this reserve. Any future withdrawal must reduce the correct liability once, satisfy `sum(unpaid bounty liabilities + unclaimed credits) <= balance`, and prohibit double allocation (Issues #16/#17).
- `unreservedNativeSurplus` reports `max(balance - totalReservedAtoms, 0)`, but has **no sweep**. An attacker cannot increase their payout by force-sending native currency to the contract.
- Unsupported tokens must not be accepted for bounties. Accidentally sent ERC20 tokens, stuck balances and gas-griefing recipients need explicitly reviewed rescue/withdrawal specifications and test coverage under #16/#17; do not invent recovery authority now.
- No helper is deployed or invoked with real user assets, Portaldot V3 compatibility unverified (#18).

## Independent test coverage

The `FairEntitlementModuleV1.t.sol` suite includes pre-acceptance cancellation, no-submission deadline equality and strict > boundary, sponsor refund attempts after timely submission, rejection/incomplete-review hold, signed-quorum developer award after challenge window, human sponsor ruling after appeal window, verified challenge with both arbitrators silent, no-quorum timeout split, source SHA/attempt binding, wrong chain, replay protection, unexpected balance quarantine and fuzzed surplus conservation.

This suite and the updated arbitration tests characterize local Solidity behavior with Foundry synthetic signers and simulated clock. They do **not** demonstrate real GitHub fix provenance, human arbitration performance, Portaldot testnet custody or money transferred to accounts.

## Release blockers and priority

**NO-GO for external customer deposits or “production ready” marketing.** Before any launch:
- #16: audited pull credits and withdrawals, resilient to rejecting recipients and reentrancy.
- #17: full stateful invariants, timestamp/fuzz, refund/payout races and adversarial external calls.
- #18: organizer-confirmed Portaldot V3 network and genuine deployed contract receipts, explorer/genesis/chain identity.
- #20/#21/#22/#23/#24/#25: authenticated GitHub App, isolated before/after runner, signed, independently reproducible evidence and case disclosures.
- #26/#27/#32–#40: real sponsor/developer UX, notifications, durable case history, finality-aware indexer and browser-to-chain E2E.
- #41: independent external audit and explicit risk acceptance by founder before money.

The owner remains the **solo founder**. Independent verifier/arbitrator actors are customer/workflow roles, not additional CertiFiks software engineers.
