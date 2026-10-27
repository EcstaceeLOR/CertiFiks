# Issue #17 — Mixed-beneficiary escrow-accounting fuzz regression

The existing Foundry suite already covers per-bounty native-asset reentrancy, reverting receivers, stale signatures, withdrawal receipts, partial withdrawals, chain confusion, forced native balance surplus and seeded stateful invariants. One residual accounting scenario deserves explicit coverage: several live liabilities with **different eligible beneficiary wallets**, including an unfinalized bounty that must never be accidentally spent to satisfy another claimant.

`testFuzzMixedSponsorAndDeveloperCreditsCannotCrossCharge` in `contracts/test/PullWithdrawalModuleV1.t.sol` builds **three independent synthetic bounty records** within one escrow:
1. A fully adjudicated 3 ETH sponsor cancellation/refund credit.
2. An unresolved 2 ETH bounty with no claimable credit.
3. A 1 ETH reward for a developer, earned from actual signed reviewer quorum in the Foundry test harness.

The test randomizes two partial withdrawal amounts and both execution orders. It asserts sponsor/developer account separation, unauthorized cross-bounty withdrawal rejection, 100% conservation of booked credits and remaining obligations, exact reserved-liability backing and the impossibility of converting the unresolved 2 ETH into credit. Finally both rightful beneficiaries withdraw their remaining portions while **exactly 2 ETH remains reserved and untouched**.

Run the seeded negative-path tests from a clean checkout:

```sh
cd contracts
forge test --match-test testFuzzMixedSponsorAndDeveloperCreditsCannotCrossCharge --fuzz-seed 0x17 -vv
forge test --match-contract EscrowStatefulInvariantTest --fuzz-seed 0x17 -vv
```

GitHub CI runs the full Foundry regression and seeded invariant suites; this is locally reproducible synthetic security evidence, not an external audit. This test neither exercises a real Portaldot asset transfer nor guarantees every economic attack is modeled. Issue #17 stays open until an independent test assessment, coverage review, live deployment and transaction-evidence requirements are fulfilled.
