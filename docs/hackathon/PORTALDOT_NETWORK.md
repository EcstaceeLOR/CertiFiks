# CertiFiks — Portaldot execution environment / chain qualification

**Issue:** #2 · **Observed:** 2026-10-15 · **Status:** IN PROGRESS / BLOCKED on independent live RPC+deployment proof and current-organizer eligibility confirmation.

## Reliable published technical facts (NOT a fresh live transaction)

| Parameter | Published / observed value | Evidence and confidence |
|---|---|---|
| Chain implementation | Substrate runtime with a native contracts pallet; not intrinsically EVM | Official source and contracts RPC docs: https://github.com/portaldotVolunteer/Portaldot and https://portaldot-dev.readthedocs.io/en/latest/module-interface/rpc/contracts.html (high for historical architecture) |
| Official docs mainnet URL | wss://mainnet.portaldot.io | https://portaldot-dev.readthedocs.io/en/latest/chain-info.html (published, not live-tested here) |
| Native denomination | POT | Same Portaldot chain information docs (published) |
| Native decimals | 14 | Same docs (published; must recheck via system_properties at live RPC) |
| SS58 format | 42 | Same docs (published; confirm actual chain system_properties) |
| Local dev RPC | ws://127.0.0.1:9944 after running local node | https://portaldot-dev.readthedocs.io/en/latest/getting-started/local_test.html |
| Official development node | portaldot_dev --dev --alice | Official local-dev guide, https://github.com/portaldotVolunteer/Portaldot-node |
| Community-reported live endpoint | wss://portaldot.philotheephilix.in | Third-party project https://github.com/freedanjeremiah/portaldot-hackathon-2026-inkport-dmk — **not an officially verified RPC** |
| Historical contracts RPC | contracts_call, contracts_instantiate, contracts_getStorage, contracts_rentProjection | Official legacy docs: https://portaldot-dev.readthedocs.io/en/latest/module-interface/rpc/contracts.html |
| Contracts ABI | Community reports legacy rent-era seal0 pallet-contracts on their reachable node | Third-party InkPort project above; independently confirm metadata + actual deployment before selecting toolchain |
| Public V3 EVM RPC / chain ID | **Not independently established** | Do not assume standard MetaMask/Foundry EVM deployment supported |
| Public faucet/explorer URL supporting this specific 2026 hackathon | **Not independently established** | Ask organizers and show observed receipts, never invent URLs |

## Why Solidity starter is not immediately deployable
The existing ProofPatch/CertiFiks escrow starter is Solidity meant for an EVM. The official Portaldot documentation describes a Substrate / WASM contracts model, and third-party projects report an older seal0 host-function ABI. This is a *VM compatibility question*, not a code-copying task.

Do not treat a successfully compiled Solidity Foundry contract as a Portaldot deployment. Foundry remains useful for reference-domain accounting tests; implementing the real deployed escrow may require a separate Rust/WASM contract with SCALE-coded runtime transactions. The definitive execution backend must be selected only after probing official/approved RPC metadata and compiling + deploying a minimal read/write contract against it.

Alternative toolchains require scrutiny: (1) version-matched ink! and cargo-contract if the runtime truly accepts it; (2) auditable raw seal0 Rust for legacy pallet-contracts; (3) third-party Solidity-to-WASM translation **only after** separate equivalence, security and ABI verification. Translation does not make Solidity EVM-compatible or preserve security automatically.

## Read-only probe — repeatable
No package install required beyond Node.js >=22. The following only reads RPC metadata; it spends no POT and does not deploy code.

1. Run: PORTALDOT_WS_RPC=wss://mainnet.portaldot.io node scripts/probe-portaldot.mjs
2. Repeat: PORTALDOT_WS_RPC=wss://portaldot.philotheephilix.in node scripts/probe-portaldot.mjs
3. For local node, first run portaldot_dev --dev --alice, then PORTALDOT_WS_RPC=ws://127.0.0.1:9944 node scripts/probe-portaldot.mjs
4. Retain JSON probe transcript, UTC timestamp, runtime spec version, system_chain/system_properties, supported contracts_* methods, and whether eth_chainId and eth_blockNumber work.

Avoid embedding private RPC API keys in committed logs; the probe rejects URLs with credentials/query strings. WebSocket connection failures can result from local DNS/network restrictions, firewall or endpoint problems; **they are not proof that Portaldot is offline**.

### RPC matrix (observational, not asserted active)
| Candidate | Live handshake from this session | Chain / specVersion | contracts_* | eth_chainId | Contract tx |
|---|---|---|---|---|---|
| wss://mainnet.portaldot.io (official docs) | NOT RUN from outbound-enabled runner | UNKNOWN | UNKNOWN | UNKNOWN | NOT DEPLOYED |
| wss://portaldot.philotheephilix.in (community report) | NOT RUN from outbound-enabled runner | UNKNOWN | Community reports legacy seal0 | UNKNOWN | CertiFiks NOT DEPLOYED |
| ws://127.0.0.1:9944 (local) | NOT RUN (no local Portaldot node launched here) | UNKNOWN | UNKNOWN | UNKNOWN | NOT DEPLOYED |

The model execution container cannot resolve external hostnames currently; local DNS failures there should not be construed as provider downtime. CI includes a reproducible read-only diagnostic. Do not mark #2 complete from someone else's project receipts.

## Deployment evidence needed to pass #2
1. Query latest real chain info, genesis hash, runtime version, feature availability and network approval, and capture a timestamped public/private trace.
2. Obtain a funded *test-only* signer approved for target chain; do not use real mainnet POT or share wallet seed.
3. Build a minimal compatible WASM contract with pinned toolchain matching the live pallet ABI, simulate gas/storage and deploy from a controlled wallet.
4. Execute one real state-changing method and one real read; save exact block/extrinsic hash, finalized block, emitted ContractInstantiated/ContractEmitted or equivalent events, SS58 contract address and relevant remote verification evidence.
5. Re-run against a clean local Portaldot dev node, document Genesis and runtime version, and verify no irreversible real funds were exposed.
6. Ask the current Portaldot Hacker House 2026 organizers whether a local legacy dev node, public third-party node or official mainnet is sufficient and which execution environment is scored. Distinguish unverified competitor reports from official organizer confirmation.
7. If an EVM RPC really exists, separately demonstrate eth_chainId, eth_estimateGas and an actual EVM contract deployment; do not infer EVM from name alone.

## Questions requiring first-party organizer confirmation
- Is the Portaldot V3 network live? Official RPC(s), genesis hash, contract VM, accepted chain IDs, blockchain explorer and faucet?
- Is a local Portaldot dev node with reproducible block/extrinsic proofs a qualifying deployment for **Hacker House 2026**?
- Which ink!/Rust, seal host ABI and contracts pallet version are accepted; what current build sample compiles *and executes*?
- Can a public read-only third-party node be used to prove deployment? Is any developer fee/token needed?
- What exact network integration proof must accompany the registration/check-in and final judging package?

## Engineering decision (conditional)
Prefer **native Substrate/WASM custody and native POT units** if runtime probes confirm contracts pallet compatibility; use appropriate Polkadot.js wallets and RPC for user transactions, not EVM-only wallet connectors. Maintain off-chain GitHub verification, signed results and immutable manifest shared across VM implementations. Keep Foundry Solidity reference code for economic/invariant design, but do not deploy or describe it as production Portaldot code.

## Done vs blocked
**Implemented on issue branch:** dependency-free RPC read probe and GH Actions syntax/optional evidence workflow; compatibility notes and source inventory.

**Still required:** actual live RPC evidence, eligibility confirmation, compatibly compiled minimal contract and authentic funded testnet/local extrinsic receipts. Without these the issue stays OPEN and cannot be merged/closed as completed. Only merge a non-final PR if it is clearly marked partial and consciously accepted; prefer keep one issue open until its acceptance is real.
