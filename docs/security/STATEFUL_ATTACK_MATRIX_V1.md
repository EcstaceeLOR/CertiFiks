# Issue #17 — adversarial settlement verification (work in progress)

## Scope and rerun commands

This suite operates **only on the test-funded PullHarnessV1** from `contracts/test/PullWithdrawalModuleV1.t.sol`. It is not a deployed escrow, network test, formal proof or independent audit.

From a clean checkout with Foundry **v1.8.5** and Solidity **0.8.24** installed:

```sh
cd contracts
forge build
forge test -vv
forge test --match-contract EscrowStatefulInvariantTest -vvv
forge test --gas-report
forge coverage --report summary
```

The stateful handler performs adversarial sequences of attempted withdrawals (legitimate and foreign signer, null or self destination, zero, partial, excessive and repeated amounts), duplicate accrual attempts, and cancellation probes. The persistent invariants check:

* all successful transfers plus remaining escrow reserve equal original test funding;
* credits can never exceed reserved liabilities or fund unrelated wallets;
* accrued credit equals the sum of the two known sponsor entitlements;
* a third funded but unresolved bounty cannot become payable;
* account balances cover booked liabilities after arbitrary attempted operations.

### Attack matrix

| Scenario | Coverage | Caveat |
| --- | --- | --- |
| Repeated payout, partial withdrawal, wrong beneficiary | Stateful handler and #16 unit tests | Synthetic actors |
| Repeated credit accrual | Stateful handler | Already finalized fixtures |
| Wrong-chain beneficiary payout | Stateful handler with chain ID mutation | Local EVM identity only |
| Unexpected ETH deposited into escrow | Stateful balance mutation and liability checks | No real asset transfers |
| Cancellation replay and stranger cancellation | Stateful handler | No randomized assignment progression |
| Failing recipient / callback reentrancy | #16 direct regression tests | Not statefully mixed with arbitrary arbitration |
| Signed verdict replay, chain separation and forged approvals | #13 direct tests | No external signer infrastructure |
| Arbitration and deadline escalation | #14 direct tests | No real independent arbitrators |
| Timely submission/refund fairness | #15 direct tests | 50/50 fallback still needs policy review |
| Real Portaldot chain, reorg and finalized receipts | **NOT TESTED** | Requires #18 and #27 |
| Entire lifecycle random transitions and proxy/redeployment | **NOT TESTED** | Requires extended multi-role handler |
| Gas griefing, mutation coverage, CI artifacts and hard coverage thresholds | **NOT VERIFIED** | Requires measured runs |

## Release gates

Do not merge/close #17 solely because these synthetic invariants pass. The complete issue requires actual CI logs, pinned build reproducibility, expanded stateful lifecycle and externally verified network/economic evidence. #9–#16 are stacked draft dependencies. #41 independent review remains mandatory before real asset custody.
