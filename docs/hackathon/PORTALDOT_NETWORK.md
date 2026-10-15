# CertiFiks — Portaldot execution environment / chain qualification

**Issue:** #2 · **Observed:** 2026-10-15 · **Status:** Read-only chain investigation COMPLETE; qualifying V3 deployment **BLOCKED / NO-GO**. See [formal decision](./network.md) and hard on-chain deployment gate #18.

## Reliable published technical facts (NOT a fresh live transaction)

| Parameter | Published / observed value | Evidence and confidence |
|---|---|---|
| Chain implementation | Historical published developer docs show a Substrate/WASM contracts runtime; **the 2026 Portaldot V3 Hacker House separately advertises both WASM and EVM execution**, neither endpoint has yet been live-tested for this repo | Legacy docs: https://github.com/portaldotVolunteer/Portaldot ; 2026 event announcement: https://www.eventbrite.com/e/portaldot-hacker-house-2026-tickets-2002321816454 |
| Official docs mainnet URL | wss://mainnet.portaldot.io | https://portaldot-dev.readthedocs.io/en/latest/chain-info.html (published, not live-tested here) |
| Native denomination | POT | Same Portaldot chain information docs (published) |
| Native decimals | 14 | Same docs (published; must recheck via system_properties at live RPC) |
| SS58 format | 42 | Same docs (published; confirm actual chain system_properties) |
| Local dev RPC | ws://127.0.0.1:9944 after running local node | https://portaldot-dev.readthedocs.io/en/latest/getting-started/local_test.html |
| Official development node | portaldot_dev --dev --alice | Official local-dev guide, https://github.com/portaldotVolunteer/Portaldot-node |
| Community-reported live endpoint | wss://portaldot.philotheephilix.in | Third-party project https://github.com/freedanjeremiah/portaldot-hackathon-2026-inkport-dmk — **not an officially verified RPC** |
| Historical contracts RPC | contracts_call, contracts_instantiate, contracts_getStorage, contracts_rentProjection | Official legacy docs: https://portaldot-dev.readthedocs.io/en/latest/module-interface/rpc/contracts.html |
| Contracts ABI | Community reports legacy rent-era seal0 pallet-contracts on their reachable node | Third-party InkPort project above; independently confirm metadata + actual deployment before selecting toolchain |
| Public V3 EVM RPC / chain ID | **V3 EVM support advertised by organizer; concrete endpoint/chain ID and deployability not independently established** | 2026 organizer event announcement and DoraHacks listing; verify with signed deployment, not marketing alone |
| Public faucet/explorer URL supporting this specific 2026 hackathon | **Not independently established** | Ask organizers and show observed receipts, never invent URLs |

## EVM vs WASM: do not preselect the VM
The existing ProofPatch/CertiFiks escrow starter is Solidity targeting an EVM. Historical Portaldot developer docs describe a Substrate/WASM contracts runtime, and community projects report an older seal0 host-function ABI. **However, the 2026 Hacker House organizer advertises Portaldot Network V3.0 as EVM-compatible, supporting EVM and WASM smart contracts.** This is now a *live environment and endpoint discovery problem*, not evidence that V3 is WASM-only.

Do not treat a successfully compiled Solidity Foundry contract as a Portaldot deployment. If the actual qualifying V3 EVM endpoint supports deployment, Solidity/Foundry is the preferred path for existing escrow logic. If only a qualifying WASM contracts runtime can be verified and accepted, port/reimplement the on-chain escrow in Rust/WASM while preserving independently tested settlement invariants. Select the definitive execution backend only after probing current official/approved RPC metadata and successfully deploying a minimal read/write contract.

Alternative toolchains require scrutiny: (1) version-matched ink! and cargo-contract if the runtime truly accepts it; (2) auditable raw seal0 Rust for legacy pallet-contracts; (3) third-party Solidity-to-WASM translation **only after** separate equivalence, security and ABI verification. Translation does not make Solidity EVM-compatible or preserve security automatically.

## Read-only probe — repeatable
No package install required beyond Node.js >=22. The following only reads RPC metadata; it spends no POT and does not deploy code.

1. Run: PORTALDOT_WS_RPC=wss://mainnet.portaldot.io node scripts/probe-portaldot.mjs
2. Repeat: PORTALDOT_WS_RPC=wss://portaldot.philotheephilix.in node scripts/probe-portaldot.mjs
3. For local node, first run portaldot_dev --dev --alice, then PORTALDOT_WS_RPC=ws://127.0.0.1:9944 node scripts/probe-portaldot.mjs
4. Retain JSON probe transcript, UTC timestamp, runtime spec version, system_chain/system_properties, supported contracts_* methods, and whether eth_chainId and eth_blockNumber work.

Avoid embedding private RPC API keys in committed logs; the probe rejects URLs with credentials/query strings. WebSocket connection failures can result from local DNS/network restrictions, firewall or endpoint problems; **they are not proof that Portaldot is offline**.

### RPC matrix (observational, not asserted active)
The 2026 announcement advertises dual-VM V3, but as of this report we have neither an official V3 EVM HTTP/WS URL nor its chain ID. The legacy/docs endpoints below are candidates, not proof of V3 deployment.
| Candidate | Live handshake from this session | Chain / specVersion | contracts_* | eth_chainId | Contract tx |
|---|---|---|---|---|---|
| wss://mainnet.portaldot.io (official docs) | **SUCCESS via GitHub Actions 2026-10-15** | Portaldot Mainnet; specVersion 1002 | Advertises 4 older contracts_* methods; no deployment | **-32601 unsupported** | NOT DEPLOYED |
| wss://portaldot.philotheephilix.in (community report) | **Handshake failed from GitHub runner** | UNKNOWN | UNKNOWN | NOT TESTED | NOT DEPLOYED |
| ws://127.0.0.1:9944 (local) | NOT RUN (no local Portaldot node launched here) | UNKNOWN | UNKNOWN | UNKNOWN | NOT DEPLOYED |

The local execution container cannot resolve external hostnames, but GitHub Actions **did** establish a direct read-only connection to documented Portaldot Mainnet on 2026-10-15; the community endpoint handshake failed. Both outcomes are recorded in the [probe report](./evidence/2026-10-15-read-only-rpc.md). Mainnet proof is **not** V3 testnet deployment proof; no contracts were deployed.

## Deployment evidence needed to pass #2
1. Query latest real chain info, genesis hash, runtime version, feature availability and network approval, and capture a timestamped public/private trace.
2. Obtain a funded *test-only* signer approved for target chain; do not use real mainnet POT or share wallet seed.
3. Build a minimal compatible WASM contract with pinned toolchain matching the live pallet ABI, simulate gas/storage and deploy from a controlled wallet.
4. Execute one real state-changing method and one real read; save exact block/extrinsic hash, finalized block, emitted ContractInstantiated/ContractEmitted or equivalent events, SS58 contract address and relevant remote verification evidence.
5. Re-run against a clean local Portaldot dev node, document Genesis and runtime version, and verify no irreversible real funds were exposed.
6. The published 2026 event listing specifically requires Portaldot **testnet** deployment for the hackathon. Ask the organizer for the official V3 testnet RPC/faucet/explorer and whether a local legacy dev node or a public third-party node additionally qualifies; earlier Season 1 local-node acceptance is *not* transferable by assumption.
7. V3 EVM is organizer-advertised, but requires a concrete endpoint. Separately demonstrate eth_chainId, eth_estimateGas and an actual EVM contract deployment; do not infer deployability from publicity alone.

## Questions requiring first-party organizer confirmation
- Is the Portaldot V3 network live? Official RPC(s), genesis hash, contract VM, accepted chain IDs, blockchain explorer and faucet?
- Is a local Portaldot dev node with reproducible block/extrinsic proofs a qualifying deployment for **Hacker House 2026**?
- Which ink!/Rust, seal host ABI and contracts pallet version are accepted; what current build sample compiles *and executes*?
- Can a public read-only third-party node be used to prove deployment? Is any developer fee/token needed?
- What exact network integration proof must accompany the registration/check-in and final judging package?

## Engineering decision (conditional)
**First choice:** Confirm qualifying V3 EVM RPC. If compatible and deployable, keep the Solidity/Foundry escrow architecture and verified EVM wallet stack on that chain. **Fallback:** If only a qualifying WASM contracts runtime is deployable under current organizer rules, implement native Substrate/WASM custody using POT units and Polkadot.js wallets; maintain signed GitHub verification evidence and common immutable manifest hashes. Do not substitute the older community node for the V3 testnet merely because it appears reachable. These options are mutually exclusive *until* the actual network is established.

## Done vs blocked
**Implemented on issue branch:** dependency-free read-only Substrate/EVM probes, GitHub Actions syntax and live read-only diagnostics, verified public mainnet runtime metadata and source inventory. See [timestamped probe report](./evidence/2026-10-15-read-only-rpc.md) and [GitHub Actions run](https://github.com/EcstaceeLOR/CertiFiks/actions/runs/38746763936).

**Still required for *actual deployment*:** organizer-approved V3 live testnet RPC, eligibility confirmation, compatible minimal contract and signed finalized deployment/read/write receipts. **Issue #2's explicit alternative acceptance condition** is a documented BLOCKED verdict supported by reproducible evidence. The chain investigation can therefore be reviewed/merged/closed under that alternative, while #18 remains a hard blocker for any deployed-product or hackathon-qualification claim. This does **not** mean V3 integration or settlement has been implemented.


## 2026-specific event claims and qualification rule (updated)
- Eventbrite announcement from DoraHacks advertises **Portaldot Network V3.0** as compatible with both EVM and WASM smart contracts: https://www.eventbrite.com/e/portaldot-hacker-house-2026-tickets-2002321816454
- DoraHacks listing cached by HackathonRadar states **deployment to the Portaldot testnet is mandatory** for project eligibility, with verifiable transaction/contract evidence important for judges: https://www.hackathonradar.com/database/hackathon/portaldot-hacker-house-2026
- This listing is a third-party reproduction of organizer rules, so final eligibility still requires DoraHacks/organizer confirmation. Do NOT conclude a legacy local dev node alone is sufficient for the current V3 Hacker House.
- A recent InkPort competitor reports production-compatible raw seal0 WASM deployments to a community RPC; that is useful technical prior art but cannot establish the accepted V3 EVM network for CertiFiks.
