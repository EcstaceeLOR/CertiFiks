# CertiFiks bounty state machine (proposal; NOT IMPLEMENTED)

This is a product-level contract. Formal chain-validated transition tables, hash formats, and verifier rules belong to #3, #5 and #9–#17 after confirming Portaldot capability (#2).

## Core states

Draft -> Funded -> Assigned -> Submitted -> Verifying -> Review -> Payable -> Settled.

Alternative paths:
- Funded -> Refundable -> Refunded (unassigned expiry or safe cancellation).
- Assigned -> Refundable (missed contractual submission deadline) or reassignment under preset terms.
- Verifying -> ResubmissionAllowed -> Submitted (rejected tests within agreed attempt window).
- Verifying -> Escalated -> Disputed (timeouts, flaky tests, incompatible evidence, disagreement).
- Review -> Disputed (valid timely challenge).
- Disputed -> Payable OR Refundable (reasoned time-bounded adjudication).
- Payable -> Settled (authorized developer withdrawal), Refundable -> Refunded (sponsor withdrawal).

Draft, Verifying and ResubmissionAllowed can be application-side states, but escrowed value and claim authorization MUST derive from verified on-chain authority. A database flag or UI status never releases money.

## Transition/authorization table

| From | Action and signer | Guards | Value impact |
|---|---|---|---|
| Draft | Sponsor creates funded bounty | Verified chain, exact payment, fixed acceptance manifest, valid windows | Lock reward in escrow |
| Funded | Sponsor selects and developer accepts | Eligible identities, one active assignee, deadline not passed | None |
| Funded | Sponsor refunds after unassigned expiry | Objective policy predicate, no timely protected claim | Sponsor withdrawal credit |
| Assigned | Developer submits GitHub attempt | Authorized assignee, pinned repo/base/head SHA, before cutoff, unique attempt | None |
| Assigned | Submission deadline passes | No protected timely submitted attempt, contractual timeout | Possible refund or bounded reassignment |
| Submitted | Worker starts reproducible run | Job hash matches pinned immutable manifest | None |
| Verifying | Approved reviewers attest matching results | Baseline fails, candidate passes, regression suite passes, trusted harness, policy quorum | Enter mandatory review window |
| Verifying | Qualified fix fails | Signed rejection; retry policy explicitly permits | None, optional new attempt |
| Verifying | Runner/verifier silent, inconclusive or dissent | No false success; preserve timely submission rights | Retry/escalation without unilateral refund |
| Review | No valid timely challenge | Quorum proof, immutable challenge period elapsed | Developer withdrawal credit |
| Review | Valid challenge | Eligible challenger, within deadline, frozen evidence | Hold pending time-bounded dispute |
| Disputed | Authorized independent ruling | Unconflicted arbitrator, opportunity to respond, liveness fallback | Developer OR sponsor credit |
| Payable | Developer withdraws | Authorized beneficiary, credit nonzero | Transfer authorized amount exactly once |
| Refundable | Sponsor withdraws | Authorized sponsor, eligible credit | Transfer refund exactly once |

## Money and fairness invariants
1. Aggregate unpaid credits and outstanding escrow liabilities never exceed available contract funds and never become negative.
2. A bounty never creates both sponsor-refund and developer-reward credits for the same entire locked amount.
3. All value-moving effects are checks-effects-interactions safe; a reverting receiver cannot halt others' withdrawals.
4. An assigned developer can submit only a specific immutable GitHub attempt; replay or changed repo/chain/commit is rejected.
5. Acceptance manifest, payout, challenge policy and deadlines do not silently change after sponsor funds.
6. Payout is impossible from a worker success toast or a single unauthenticated/off-policy signature.
7. A timely submission cannot be stolen by a unilateral sponsor timeout claim while verification is unavailable.
8. Reviewers and arbitrators cannot judge their own bounty/repair; further sybil/collusion remains a disclosed governance risk.
9. Timely challenge cannot be suppressed by immediate payout; sponsor cannot stall a passing fix forever.
10. Every funded valid lifecycle has a bounded, auditable route to terminal credit/withdrawal; adversarial liveness and recovery need formal design in #14/#15.
11. Off-chain indexer state must eventually reconcile to canonical finalized on-chain state; pending or reverted TX is never labeled settled.
12. Every accepted report binds chain, contract, bounty, spec, numeric GitHub repo ID, baseline SHA, candidate SHA, test image digest and report digest.

## Example: successful fix (illustrative, no live transaction)
- Sponsor S funds reward W against repo ID R, baseline commit B, spec digest M, trusted image I and agreed expiry/challenge periods.
- Developer D accepts, opens GitHub PR P and submits exact candidate SHA H; submission lock records that revision.
- Runner executes the trusted acceptance test against B (expected failing assertion) and H (expected passing assertion), plus regression suite.
- Independently approved reviewers V1 and V2, who satisfy conflict policy, sign the same evidence digest.
- Review window ends without valid challenge; contract allocates W less any precommitted transparent fee to D as a withdrawal credit.
- D withdraws using their wallet; contract tx confirms; indexer/API/UI present exactly the same receipt.

## Example: CI failure after timely submission (illustrative)
- D submits valid H before cutoff. Runner crashes; no test verdict can be established.
- System records Inconclusive rather than Approved/Rejected, retries within bounded policy and notifies both parties.
- Sponsor cannot immediately refund solely on this timeout.
- If retry fails, parties can escalate to review/arbitration; an authorized bounded ruling eventually permits developer or sponsor withdrawal.
- This case must become adversarial invariant and E2E tests before release.

## Outstanding protocol questions; not silently assumed solved
- How long are submission/verification/challenge/arbitration windows, and can they be extended only by both parties?
- If the sole arbitrator disappears, who takes over, when, and with what conflict controls?
- How to handle dishonest acceptance specifications, flaky tests, hidden specs and dependency network access?
- How will token decimals, fee accounting, gas, finality/reorgs and contract runtime be defined on actual Portaldot?
- Who is legally permitted to operate verification and arbitration for users in each target market?

These are blocking design questions assigned across #2, #3, #12–#17 and #41. This document does not claim contract implementation.
