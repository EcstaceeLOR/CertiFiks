# Issue #15 — Read-only sponsor-refund entitlement preview

**Status: signed EVM state-machine bookkeeping only. This feature does not transfer ETH, create withdrawable credits, constitute independent adjudication or authorize real-money escrow.**

The abstract `FairEntitlementModuleV1` now exposes `previewNoSubmissionEntitlement(bountyId)`, returning exactly three values: an enum reason, whether a sponsor-only refund **entitlement record can be created**, and its amount in native atomic units. This must **never** be presented as an available token balance or completed refund.

The preview and the actual permissionless `recordNoSubmissionRefund` share one internal `_noSubmissionReason` predicate, eliminating a UI/backend discrepancy. Neither permits cancellation after a developer has recorded any timely attempt.

| Current immutable state | Can record sponsor-only entitlement? | Money moved? |
| --- | --- | --- |
| Open/offered before sponsor cancellation | No | No |
| Sponsor cancelled while still open/offered, no attempt | Yes | No |
| Developer accepted but has not submitted and deadline not passed | No | No |
| Expired without submission, strictly after original deadline | Yes | No |
| **Any** pinned submitted attempt, even if verifier/arbitrators are silent | **Never through this shortcut** | No |
| Previously recorded entitlement | No (single use) | No |

Any submitted fix must instead reach the immutable signed-quorum or bounded human-arbitration case in the separate resolution path. The older sponsor timeout shortcut is not revived.

Foundry tests assert the same three preview fields both before and after cancellation, record creation, missed submission, and a developer's timely submission before/after the original deadline; the tests reject repeat recording and ensure reserved ETH is unchanged.

A complete production implementation still needs genuine on-chain receipt validation, finality-aware UI binding, reviewed economic policy, verified arbitrator identities, tested actual nonblocking withdrawal/refund transactions and an independent security audit. **Issue #15 remains open** until these exist.
