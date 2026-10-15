# CertiFiks — signed reviewer decisions and audit contract v1

**Issue:** #13 · **2026-10-15** · **Status:** concrete abstract Solidity contract + shared EIP-712 types/schema and local tests; **NOT production-verified or deployed**. This is not a third-party audit or independent-verifier attestation.

## 1. Core trust boundary

- A real EIP-712/secp256k1 signature proves the registered signing **wallet** authorized the exact message. It does not prove a fix is correct, tests ran honestly, the GitHub commit is authentic, two organizations have different beneficial owners, or user funds are safely payable.
- The prior #12 registry centrally admits **named reviewer organizations**. Each independently admitted organization has one current signing key and frozen jobs per attempt/signer epoch. No second wallet of the same organization counts as an extra vote; hidden social collusion remains possible.
- The reviewer must first accept a current, eligible job **by an on-chain wallet transaction**, then declare an immutable, nonzero report hash. The explicit signed vote must identify that same digest and exact job.
- The signature can be submitted by any relayer; `msg.sender` on vote submission cannot impersonate the actual signer, who is recovered and checked against the registry's assigned wallet.
- The existing `verification-report.schema.json` documents observed test outputs; `signed-verifier-vote.schema.json` is a **separate EIP-712 decision envelope**. The signed vote's `reportDigest` is a pointer to immutable report bytes, not a runner execution certificate. Genuine report construction, content addressing and sandbox provenance are blocked by #19/#21/#25.

## 2. EIP-712 version and field layout (normative for this module)

Domain:
- name = `CertiFiksVerifier`
- version = `1`
- chainId = live `block.chainid`, checked against the immutable expected chain
- verifyingContract = `address(this)`, preventing cross-contract replay

Primary type: `CertiFiksVerifierVote`. Fixed fields in **exact order**:
```solidity
uint256 bountyId;
uint64 attemptId;
bytes32 organizationId;
uint64 signerEpoch;
bytes32 attemptDigest;
bytes32 manifestDigest;
bytes32 verifierPolicyDigest;
bytes20 headGitSha;
bytes32 reportDigest;
bytes32 imageDigest;
uint8 outcome; // 1=approved, 2=rejected, 3=inconclusive, 4=runner_failure
bool baselineFailed;
bool candidatePassed;
bool regressionsPassed;
uint64 expiresAt;
```

Digest: `keccak256(0x1901 || domainSeparator || keccak256(abi.encode(VOTE_TYPEHASH, vote)))`. Domain separator is `keccak256(abi.encode(EIP712Domain typehash, keccak256(name), keccak256(version), chainId, verifyingContract))`. This typed digest is **not** the SHA-256 attempt commitment, and is not interchangeable with Issue #5's SHA-256 cross-language attestation context vector. Explicitly keep both representations, their purposes and their hash algorithms separate.

A 65-byte signature is required: `r || s || v`, where `v` must be 27 or 28, `r` and `s` nonzero, and `s` must be the lower half of the secp256k1 order. ERC-1271 smart-contract signatures and 64-byte EIP-2098 compact signatures are **not yet supported**, by design; don't label a contract-account reviewer as eligible if it cannot sign this format.

The shared `packages/shared/src/verifier-vote.ts` exports these fields and a type-safe **unsigned** vote preparation function suitable for a future wallet signer. `validateProtocolDocument("voteUnsigned")` accepts only an unsigned object; `validateProtocolDocument("vote")` requires the 65-byte signature and fails closed if omitted. Never show a toy fixture signature as a live review. The example contains **synthetic placeholder bytes**, solely for schema conformance.

## 3. Eligibility and decision algorithm

Every accepted signed verdict requires:
1. Existing funded bounty, exact latest submitted attempt and `Submitted` assignment state.
2. Organization present in **one-time sponsor-committed funded reviewer roster**, active in governance and free of sponsor/developer/arbitrator role conflict.
3. Existing assigned job on that exact attempt, accepted by its signer and with a prior immutable report-digest declaration.
4. Current assigned key/signing epoch; no rotated, revoked, expired or unassigned signer may cast a vote.
5. Matching attempt digest, immutable funded manifest/policy, pinned head SHA, image digest and on-chain report digest.
6. Signature's `expiresAt` is in the future, at most the original funded job deadline, and the review hasn't already timed out/escalated.
7. An `Approved` verdict requires **baselineFailed=true, candidatePassed=true, regressionsPassed=true**. Fake green CI screenshots or a missing/rejected test may not satisfy these flags.
8. One **immutable** vote per organization per attempt. No editing, duplicate, same-report retry or cross-attempt carryover.

After a valid vote:

| Current state | Incoming verdict | Next state | Custody |
|---|---|---|---|
| Pending | Approved but fewer than sponsor's committed quorum | Pending | No credit/payment |
| Pending | Approved reaches quorum of distinct admitted organizations | **ChallengeWindow** until immutable `now + challengeSeconds` | No credit/payment |
| Pending | Rejected, inconclusive or runner failure | **EscalationRequired** | No credit/payment; future #14 case |
| Pending | Original verification window expires before approval | **TimedOut** (permissionless explicit transition) | No credit/payment; future #14 case |
| ChallengeWindow / EscalationRequired / TimedOut | Any additional verdict | Revert | No mutation/payout |

A negative result does **not** automatically refund the sponsor. A passing quorum does **not** automatically credit the developer even after the challenge deadline. Actual challenges, evidence response, fee rules, bounded fallback and release decisions must be fully implemented and independently reviewed in #14/#15/#16.

**Policy subtlety:** If the funded roster has 3 organizations but a 2-of-3 quorum, the first 2 valid approvals may start the challenge window; a third organization cannot later unilaterally overturn that already reached decision. For high-value fixes a sponsor should commit an appropriate threshold and the future governance/challenge rules must allow real dissenting evidence. Two wallets under the same hidden beneficial controller remain an unresolved social failure, not a solved cryptographic one.

## 4. Audit and indexing contract

`SignedVerdictRecorded` logs the `bountyId`, `attemptId`, `organizationId` (indexed), recovered signer wallet, full EIP-712 typed digest, immutable report hash, outcome and signer epoch. `ReviewDecisionChanged` logs a transition into ChallengeWindow/EscalationRequired/TimedOut, vote counts, trigger digest and exact challenge deadline.

A real database/indexer (#24/#27) must derive state from **finalized chain events** keyed by chain genesis, contract and transaction/log index, preserve reorg/revert provenance and allow independent retrieval of `readRecordedVerdict`, `readReviewDecision`, `getPinnedAttempt`, `getReviewerJob` and the original signed report bytes. A report URL alone or a green CI job is not a verified binding. Schema types are versioned in OpenAPI, but API POST endpoints and worker signatures **remain unimplemented**. Do not claim full cross-component E2E parity until those services actually emit and ingest these events.

## 5. Tests and security caveats

Foundry negative-path tests exercise two independent `vm.sign` reviewer keys; one-vote incompleteness, two-organization quorum, challenge deadline without funds movement, dissent, inconclusive and runner-failure escalation, tampered report/head/image/manifest/policy, cross-bounty/contract/chain replay, early/repeated approval, wrong key and malformed/malleable signatures, expiry, obsolete signing epoch, revocation, old-attempt retry, and permissionless no-quorum timeout. The shared TypeScript tests check schema strictness, EVM integer widths and typed-data order for wallet integration.

These tests are **local synthetic fixtures**, not genuine independent reports. The public GitHub App, isolated reproducible before/after runner, actual reviewer organizations and Portaldot V3 deployment are absent (#18–#25).

**Release decision: NO-GO for funded user bounties.** Keep Issue #13 OPEN and its stacked PR DRAFT until real signed reviewer reports from independent vetted organizations are validated against genuine GitHub and runner evidence; their resulting events are indexed and tested end-to-end, and arbitration, fair timeouts, withdrawals and external custody audit (#14–#17/#41) are complete.
