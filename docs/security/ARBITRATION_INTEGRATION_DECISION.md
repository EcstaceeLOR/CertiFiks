# Arbitration integration decision — Issue #14

**Decision:** `BoundedArbitrationModuleV1` in PR #60 is the *single integration baseline*. PR #61 (`BoundedDisputeModuleV1`) is an incompatible alternative, not a second production arbitration module.

## Technical reasons

1. `FairEntitlementModuleV1` (#15) inherits `BoundedArbitrationModuleV1` and reads `_cases[bountyId][attemptId]`, `CasePhase.Resolved`, `Award.DeveloperReward` / `Award.SponsorRefund` / `Award.SharedResolution`, `finalAward`, and `primaryReasonDigest` / `fallbackReasonDigest`. PR #61 instead has `CaseState`, `Ruling`, `_disputeCases`, `finalRuling` and `finalDecisionDigest`; it cannot replace PR #60 by simply adding an import.
2. PR #60 includes precommitted independent fallback-arbiter consent, governance approval, role-conflict checks, an immutable dispute trace and permissionless deadlines. PR #61 contains useful additional architectural ideas, but combining both as independent finality authorities would risk contradictory entitlements and stuck funds.
3. PRs #62–#65 were stacked on #60; their code/tests must be validated together after #60 lands.

## Cross-checks before any custody release

- Ensure all challenger/party evidence and appeals are domain- and attempt-bound, immutable and independently inspectable.
- Preserve **deadline anchoring at the original signed reviewer outcome**, especially if an open review-escalation call is delayed. No actor can indefinitely renew the clock.
- Prevent primary/fallback arbitrator conflicts, former reviewer conflicts, and governance substitution after a bounty has been funded.
- Require objective liveness transitions if both arbiters become unavailable.
- Reconcile `Award.SharedResolution` across the downstream code and the arbitration enum. This is a **compile blocker** if downstream refers to a variant missing in the inherited contract.
- Have real sponsors, developers and an independent security reviewer assess and accept the 50/50 silent-review fallback. It creates incentives for strategic reviewer absence; it is *not* automatically fair.
- Ensure no public payable escrow, operator sweep or payout method is exposed by the abstract module or its tests.
- Require full Foundry compile/unit/fuzz/invariant results for the **latest cumulative head**, independent review and authentic chain payout evidence before closing #14.

## Merge policy

PR #61 should be closed as superseded, without deleting its branch or its test history. PR #60 is the chosen implementation, **not yet accepted as production-ready**. Close Issue #14 only after its full on-chain and off-chain acceptance criteria, not merely after code integration.

This decision is reversible only with a deliberate, tested migration of the downstream interfaces and safety properties.
