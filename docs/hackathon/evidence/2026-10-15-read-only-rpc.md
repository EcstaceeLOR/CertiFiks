# Portaldot RPC evidence — 2026-10-15 (READ ONLY)

**Status:** Public RPC diagnostics succeeded for documented mainnet. **NOT a V3 testnet deployment or proof of hackathon qualification.**

Runner: GitHub Actions (ubuntu-latest, Node 22); [run 38746763936](https://github.com/EcstaceeLOR/CertiFiks/actions/runs/38746763936). Original JSON reports are in run artifacts:
- rpc-probe-published-mainnet — artifact ID 11979581160
- rpc-probe-community-reported — artifact ID 11980006025

## Mainnet probe (2026-10-15T13:54:54.680Z)

| Query | Verified result |
|---|---|
| WebSocket URL | wss://mainnet.portaldot.io/ |
| Connection | Successful |
| rpc_methods | 93 advertised methods |
| system_chain | Portaldot Mainnet |
| system_properties | POT, decimals 14, SS58 prefix 42 |
| system_version | 2.0.0-unknown-x86_64-linux-gnu |
| state_getRuntimeVersion | specName portaldot, specVersion 1002, transactionVersion 2 |
| Advertised contracts_* | contracts_call, contracts_getStorage, contracts_instantiate, contracts_rentProjection |
| eth_chainId | JSON-RPC error -32601 Method not found |
| eth_blockNumber | JSON-RPC error -32601 Method not found |
| chain_getBlockHash | 0x965cc18727bdf00d26c05687a84b697fdfb994a9a9b4ba4b4053b08be8ae618f |

Interpretation: This particular endpoint presents a legacy Substrate-style Portaldot runtime, not a standard Ethereum RPC. Presence of contracts-related RPC methods **does not prove** compatibility with modern ink!/WASM contracts, and an absent EVM method here does not disprove V3 EVM on a different endpoint.

## Community-reported RPC probe (2026-10-15T13:54:55.085Z)

| Query | Result |
|---|---|
| WebSocket URL | wss://portaldot.philotheephilix.in/ |
| Connection | Failed with WebSocket handshake or network error |
| Other methods | Skipped because no successful connection |

Interpretation: Not reachable from this GitHub runner at that time. This alone is **not proof** that the endpoint or Portaldot network is offline.

## Hard blockers to closing Issue #2
- Organizer-approved 2026 V3 **testnet RPC**, chain ID, faucet, explorer and VM not established.
- CertiFiks has not deployed a contract or performed an actual qualifying state transition.
- No confirmed funding mechanism for a test-only account or finalized extrinsic/deployment receipt.
- We have not signed or broadcast transactions or spent native POT.

## Acceptance-gate action
1. Obtain official V3 RPC and approved deployment parameters from event organizers.
2. Probe V3 EVM (HTTP eth_chainId) and/or approved WASM contracts runtime, including genesis and metadata.
3. Deploy minimal contract with test-only wallet, mutate and read state, capture contract address and block/extrinsic receipt.
4. Record whether the existing Solidity starter can be retained or the chain-facing escrow must be reimplemented in WASM.

**Do not merge/close #2 just because a legacy mainnet RPC responds.**

See [compatibility report](../PORTALDOT_NETWORK.md) and [issue #2](https://github.com/EcstaceeLOR/CertiFiks/issues/2).
