# CertiFiks architecture decision records — protocol v1

**Status:** Initial ADRs. Decision statuses: ACCEPTED for design-only invariant, PROVISIONAL for implementation pending Portaldot V3 deployment. Date: 2026-10-15.

## ADR-001 — On-chain custody is authoritative (ACCEPTED)
**Context:** Sponsor escrow cannot be represented by a database row or optimistic UI.
**Decision:** Keep immutable acceptance digest, funded amount, role/settlement conditions, allocated credits and withdrawals enforceable on the qualifying chain. Off-chain users can request state changes but cannot directly rewrite custody.
**Tradeoffs:** Requires careful gas/finality and on-chain storage costs; no mainnet product until reviewed (#9/#16/#17/#18/#41).

## ADR-002 — Off-chain isolated CI plus accountable proof (ACCEPTED)
**Context:** Running arbitrary GitHub patches on chain is infeasible, and a passing test is not global correctness.
**Decision:** Run pinned baseline/candidate tests in isolated ephemeral workers without production tokens, publish hashed before/after evidence and require independent human verifier organizations to sign an exact attempt commitment.
**Tradeoffs:** Sandbox escape risk, oracle/reviewer collusion and reproducibility costs remain; CI failure is inconclusive, not approval (#20–#25).

## ADR-003 — Initial permissioned reviewer governance (PROVISIONAL)
**Context:** Two wallet addresses do not imply two independent decision makers.
**Decision:** Initial quorum is at least two approved separately controlled reviewer organizations with explicit conflicts policy and auditable enrollment/rotation. Signer may be EVM secp256k1 or an explicitly approved Substrate scheme according to actual target VM.
**Tradeoffs:** The service retains an off-chain identity trust assumption and must never market itself as trustless; registry authority, sybil defenses and delegation are implemented/tested in #12/#13.

## ADR-004 — Content-addressed restricted evidence storage (ACCEPTED)
**Context:** Arbitrators must inspect the exact result that was signed and verify that it wasn't silently replaced.
**Decision:** Hash evidence bundles and store separately from on-chain digests with least-privilege access, retention through challenge/appeal and downloadable independent verifier.
**Tradeoffs:** Storage cost, encryption, private repo access and retention law; implementation in #22/#24/#44.

## ADR-005 — Chain finality-aware event indexer (ACCEPTED)
**Context:** RPC out-of-order events and reorgs can show false paid statuses.
**Decision:** Event ingest uses chain genesis, contract ID, block/tx/log identity, canonical finality and replay-safe idempotency. UI must display pending vs finalized and reconcile actual balances.
**Tradeoffs:** Eventual consistency and extra indexing cost; exact chain finality configured only after V3 environment is real (#27/#36).

## ADR-006 — VM adapter is conditional, not guessed (PROVISIONAL; BLOCKED)
**Context:** Historical Portaldot Mainnet RPC exposes legacy Substrate contracts_* and lacks eth_chainId; 2026 V3 event advertises EVM and WASM support but qualifying V3 endpoint is not established.
**Decision:** Build VM-neutral 32-byte commitment and evidence schema now. Deploy Solidity/Foundry only if a qualifying V3 EVM runtime actually accepts it; otherwise implement equivalent native WASM custody. Keep deployment receipts in #18, which is hard-blocked until the network is confirmed.
**Tradeoffs:** Dual-VM work may cost more, but false chain-integrated claims would disqualify the product.

## ADR-007 — Immutable policy and bounded challenge/dispute (ACCEPTED goal, NOT implemented)
**Context:** Sponsor must not change terms or exploit unavailable verifier; arbitrator silence cannot strand funds indefinitely.
**Decision:** Commit deadlines and fallback arbitration authority at funding, enforce a review window, protect submitted-on-time contributors, use non-blocking withdrawals and auditable bounded dispute cases.
**Tradeoffs:** Human judgment and all-arbitrators-offline fallback are unresolved; *no user money permitted* until #14/#15 design/code tests establish a real terminal path.

## ADR-008 — Typed HTTP API is secondary to chain truth (ACCEPTED)
**Context:** The frontend needs stable types without spoofed funded/settled state.
**Decision:** Version JSON Schemas and OpenAPI together, generate checked-in TypeScript endpoint definitions, use strict runtime Ajv input validation, enforce wallet/GitHub RBAC in server; API responses cannot supersede chain.
**Tradeoffs:** Schemas and clients alone are not API implementation. Implement actual routes, tenancy and reliable jobs in #23–#28.

## ADR-009 — No real funds in research baseline (ACCEPTED)
**Context:** Existing ProofPatch Solidity contract includes unfair timeout refund and pushing payout to potentially reverting receiver, and its verifier identity model is weak.
**Decision:** Mark reference model clearly unsafe; #6 compiles/reviews, #9–#17 reimplement and test a safe protocol. Do not deploy unreviewed code or expose real-money funding button.
**Tradeoffs:** More work before hackathon demo, but security claims stay true.

**Architecture rule:** An ADR defines a design intention; it is not evidence of compiled/tested functionality or deployed Portaldot contract.
