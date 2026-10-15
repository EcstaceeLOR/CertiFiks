# CertiFiks — native pull credits, withdrawal safety and receipts (Issue #16)

**As of October 15, 2026** · **Abstract contract and Foundry tests only; not deployed on Portaldot V3, not live escrow and not an external audit.**

## Design decision

**Pull withdrawals only.** A verified/adjudicated #15 entitlement is an immutable decision, not a synchronous transfer. Any wallet may call `accrueFinalCredits(bountyId)` exactly once to book its sponsor/developer allocation, after which **only the beneficiary wallet** can call `withdrawBountyCredit(bountyId, recipient, amountAtoms)`.

`contracts/src/PullWithdrawalModuleV1.sol` is abstract and exposes **no public funding entrypoint**. The only payable deposit wrapper is `contracts/test/PullWithdrawalModuleV1.t.sol:PullHarnessV1`, clearly a Foundry-only fixture. Deploying it with real user money would be unsafe. The legacy `CertiFiksEscrow.sol` must not be used for live custody.

### Token and recipient policy

- **Only native-chain EVM currency atomic units** are supported. No ERC20 support, no token approval/permit/transferFrom, no unknown token withdrawal or admin sweep. Do not label the native currency "POT" or assume 18 decimals until the **official Portaldot V3 runtime and denomination** are verified under #18. EVM `1 ether` in local tests is simply `10^18` test wei.
- Credits are per `bountyId × beneficiaryWallet`, not fungible across unrelated bounties. Each withdraw call emits its exact bounty, signer, destination, number of atoms and remaining beneficiary entitlement.
- A beneficiary may select a **different recipient** in its own signed transaction. A third party, sponsor, arbitrator, verifier, governance wallet or server has **no delegated withdraw authority**. The frontend should make recipient changes explicit and sign through the user's own wallet.
- A recipient refusing native ETH causes a full transaction revert; the credit and global liabilities remain unchanged. The beneficiary may authorize a retry to a compatible wallet. A smart-contract beneficiary lacking *any* ability to call the escrow cannot self-rescue its payout; that is a **hard product-onboarding restriction** requiring a compatible wallet interface or separately audited recovery process. Do not misrepresent this as automatically recoverable.
- No gas reimbursements, reviewer fees, relayer fee, split deduction or arbitration bond are implemented. All funded reward atoms are allocated exactly to sponsor/developer by the **already recorded and challenge-finalized #15 ruling**. The sender pays transaction gas separately.

## Liability conservation

Let `F` be the total originally funded rewards still unpaid, `C` the amount booked as pending beneficiary credits, `U` the amount funded but not yet fully credited, and `B` the native balance of the custody contract.

```
F = U + C
B >= F
surplus = max(B - F, 0)
```

Existing `totalReservedAtoms` is `F`. New `totalClaimableCreditsAtoms` is `C`. `unfinalizedRewardLiabilitiesAtoms()` reports `U = F - C`, not a separate mutable counter that could drift.

| Transition | F | C | U | Native balance B |
|---|---|---|---|---|
| New fund of x, internal-only harness | +x | unchanged | +x | +x |
| `record*Entitlement` | unchanged | unchanged | unchanged | unchanged |
| Accrue exact final split x | unchanged | +x | −x | unchanged |
| Beneficiary withdraw y | −y | −y | unchanged | −y |
| Reverting destination | unchanged (full transaction revert) | unchanged | unchanged | unchanged |
| Forced native transfer z | unchanged | unchanged | unchanged | +z surplus |
| Fee allocation | **Not supported** | **Not supported** | **Not supported** | no hidden deduction |

Accrual checks bounty existence, exact asset kind, a genuine immutable entitlement, beneficiary identity, full amount conservation, prior credit flag and global solvency **before committing**. Exactly one accrual per bounty is possible. Reconciliation across receipts can reconstruct liabilities by replaying actual `BountyFunded`, `EntitlementRecorded`, `NativeCreditAccrued` and `NativeCreditWithdrawn` events in chain-finality order, with reorg handling still needed in #27.

Withdrawal checks correct chain, known bounty, caller’s own credit, nonzero amount and permitted recipient. The code implements **checks–effects–interactions**: it reduces per-bounty credit and `C/F` in storage before performing the native call; a nonreentrant guard blocks callbacks from reentering either the credit path or withdrawal path. Any rejected native call reverts the *entire* state transition and preserves the right to retry. Posttransfer solvency is checked; any failing check reverts transfer and accounting together.

Direct or force-sent ETH **never increases claimable credits or bounty entitlement**. Unreserved surplus has no withdraw/rescue method and must be quarantined pending asset-policy review. ERC20 or other unexpected tokens are outside this contract's native accounting and have **no rescue path**.

## Native-asset receipts (source of truth)

`NativeCreditAccrued(bountyId, beneficiary, amountAtoms, reason, sourceAttemptDigest, decisionReasonDigest)` binds each allocation to its exact #15 entitlement. For a shared adjudication this event fires separately for sponsor and developer.

`NativeCreditWithdrawn(bountyId, beneficiary, recipient, amountAtoms, remainingBeneficiaryAtoms)` is emitted **only after the external payment succeeds**. The enclosing finalized transaction hash + chain ID + contract address + event log index identify the payout uniquely; contracts cannot emit their own transaction hash. API/frontend must preserve exact integer atoms (no JS floating-point money) and wait for chain finality before showing `paid`. If the receipt reverted it is not a successful payout, no matter what a pending UI showed.

## Adversarial tests

`contracts/test/PullWithdrawalModuleV1.t.sol` exercises:
- No accrual before terminal entitlement; duplicate accrual rejected.
- Real sponsor-cancelled refund credited exactly once and withdrawn to signer-selected wallet.
- Unauthorized caller, zero recipient, contract's own address, zero/oversized transfer and unknown bounty rejected.
- Reverting destination retains credit and cannot block a **different** bounty.
- A *contract beneficiary* which rejects incoming native funds can sign a withdrawal to another recipient through its own method.
- A reentrant *contract beneficiary* tries to withdraw a second time in its own `receive()` callback; guard prevents second extraction.
- Partial withdrawal and fuzzed partial amounts preserve `F = C + U`.
- Multiple bounties isolate claim rights and permit unrelated funding while old credits exist.
- **Actual EIP-712-signed 2-reviewer approval** enters a challenge window; developer receives credit only after legitimate window expiry and finalized entitlement.
- Both arbiters silent after an incomplete review reaches the **precommitted 50/50 terminal fallback**; each signer receives only its recorded share.
- Force-added native ETH remains unreserved when all actual credits are withdrawn.

These are local synthetic adversarial tests, **not** signed evidence produced by a real GitHub runner or Portaldot on-chain settlement. Clean CI is a functional regression baseline, not proof of economic security.

## Open security / launch gates

1. **#17** stateful invariant runner, gas-grief and all permutations of deadline, partial withdraw, adjudication, force ETH and external calls; independent security review **#41** after full contracts.
2. **#18** qualifying Portaldot V3 chain/genesis/RPC/token decimals and actual deployed contract address, signed transactions, finalized withdrawal log receipts.
3. **#20–#25** authenticated real GitHub installation/wallet account binding, isolated deterministic before-and-after test runner, durable signed reviewer/appeal evidence, anti-collusion operations and secure evidence retention.
4. **#26/#27/#32–#40** real API, durable data, finality-aware indexer, usable wallet UI with original beneficiary sign-off, safe recipient retry and end-to-end user tests.
5. **Governance design:** silent dual-arbitrator 50/50 fallback in #15 remains provisional, and delayed dispute opening may reduce procedural response time. No customer funds until the founder, informed beneficiaries and auditor approve fairness/costs and fallback.
6. **Wallet compatibility:** payable receiver contracts must be tested; smart-contract beneficiaries should support a withdrawal delegation mechanism only if explicitly consented and separately reviewed. Current v1 is direct `msg.sender` only.
7. **Conflicted PRs #60/#61:** #16 follows the approved-in-code #14 branch underlying #15, not the competing experimental arbitration branch. Before eventual merge, reconcile and retire the duplicate #14 branch intentionally; never mix both state machines.

## Decision

**GO** for code-level engineering verification and Issue #17 fuzz/invariant development. **NO-GO** for launching, closing Issue #16 as end-to-end complete or merging a user-facing payable deployment while critical network and independent audit evidence is absent.

[Source code](../../contracts/src/PullWithdrawalModuleV1.sol) · [Foundry tests](../../contracts/test/PullWithdrawalModuleV1.t.sol) · [Fair entitlement policy](./FAIR_ENTITLEMENTS_V1.md)
