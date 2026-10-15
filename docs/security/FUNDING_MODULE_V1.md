# CertiFiks bounty funding terms — implementation status, Issue #9

**Status 2026-10-15:** Internal-only funding module with Foundry tests; **no user-facing funding interface, no release/refund mechanism, no approved Portaldot V3 deployment**.

## What is actually implemented in code
- `contracts/src/BountyFundingModuleV1.sol`: abstract module with an **internal-only** `_recordFunding` method, versioned immutable terms, native-asset escrow accounting and an indexed event.
- `contracts/test/BountyFundingModuleV1.t.sol`: Foundry-only public harness and unit/fuzz tests for initialization, native-asset amount, wrong-chain rejection, missing hashes/commits, invalid windows, unsupported asset types, monotonic bounty IDs, snapshot immutability and accounting conservation.
- Bound fields: sponsor, numeric GitHub repo ID, base Git SHA, manifest digest, verifier policy digest, dispute policy digest, submission deadline, verification/challenge/arbitration durations, native reward amount in atomic units and expected EVM chainId. No accepted ERC20 or arbitrary token address.
- No test or schema guarantees correct GitHub source; #20 must fetch authentic repository/commit and #19 must bind the canonical manifest. Matching hashes do not prove a fix.
- The module is abstract so a mainnet/testnet deployment cannot accept value unless someone writes a derived payable contract. The **test harness is only under test/**, not deployable production code.

## Why funding is deliberately unavailable to users
An external funding entrypoint before #10–#16 adds assignment, verifier policy enforcement, fair timeouts, fallback arbitration, refunds and pull withdrawals would permit deposits **without any settlement path**, resulting in trapped funds. That is not founder-grade and must not ship. The historical contract is demonstrably unsafe and is not repaired by this module.

## Security and integration gaps
1. Native-chain token atoms/decimals, EVM chainId and V3 runtime remain unverified (#18); the Foundry test chainId `31337` is only a local synthetic test.
2. `disputePolicyDigest` is a *commitment to a proposed fallback*, not functional arbitration. A missing arbitrator can still lock funds in future implementation (#14/#15).
3. No public funding API/wallet or actual on-chain tx, indexer, authenticated GitHub App, role registry, signed verifier attestation, challenge window or beneficiary withdrawal exists (#10–#16, #20, #27, #32, #36).
4. The `totalReservedAtoms` balance currently only increases, by design; accounting cannot become end-to-end until authorized claims and refunds are implemented. The module should be inherited and extended only under reviewed invariant suite and testnet readiness.
5. Constructor accepts a target chain ID; code checks `block.chainid` per deposit. Cross-chain identity should additionally bind authentic genesis and contract locator in signed reports (#13/#18).

## Go/no-go
**GO** for further local modular escrow engineering under #10–#17. **NO-GO** for claiming Issue #9's funding/deployment acceptance complete, shipping a derived funding wrapper, or accepting real user money. Keep #9 open with tests and honest evidence; require actual V3 contract receipt and downstream safety gate before merge as an end-user feature.
