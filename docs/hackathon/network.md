# Portaldot environment decision — CertiFiks Issue #2

**Date:** 2026-10-15
**Outcome:** **NO-GO for declaring qualifying Portaldot V3 integration/deployment at this time**. Chain-specific deployment is blocked pending verified V3 testnet connection details and an actual compatible contract receipt. This is an evidence-backed block decision, **not proof Portaldot V3 is unavailable**.

## Confirmed read-only evidence
- GitHub Actions successfully probed the documented endpoint wss://mainnet.portaldot.io: returned Portaldot Mainnet, Substrate runtime spec 1002, POT/14 decimals, SS58 42, legacy contracts RPC; eth_chainId and eth_blockNumber unsupported on that endpoint.
- The community-reported endpoint wss://portaldot.philotheephilix.in did not complete a WebSocket handshake from a GitHub-hosted runner.
- Raw response artifacts: https://github.com/EcstaceeLOR/CertiFiks/actions/runs/38746763936
- Timestamped analysis: [evidence/2026-10-15-read-only-rpc.md](./evidence/2026-10-15-read-only-rpc.md)
- Full compatibility investigation and two reusable probe tools: [PORTALDOT_NETWORK.md](./PORTALDOT_NETWORK.md), ../../scripts/probe-portaldot.mjs and ../../scripts/probe-portaldot-evm.mjs.

## Critical unknowns, explicitly BLOCKED
- No organizer-confirmed public **Portaldot V3 testnet** RPC URL / network ID / genesis hash / EVM-vs-WASM ABI version.
- No verified 2026 testnet faucet, explorer, user gas costs or deployment transaction from CertiFiks.
- No verified permission that the historical legacy/mainnet endpoint or older local dev node qualifies for Hacker House 2026.
- Number of contest entries allowed per builder not independently established; verify current organizer rules before making a second submission.

## Safe engineering direction
- The **product, hash protocol, human review and trust design** can proceed without selecting a VM (#3, #5).
- **Do not execute mainnet funds** or deploy Solidity to the historical Substrate RPC assuming Ethereum compatibility.
- If V3 Ethereum RPC, actual EVM bytecode creation and testnet receipts are confirmed, continue Solidity/Foundry. If qualifying WASM is confirmed instead, implement a compatible native contract and rerun economic/security invariants.
- Keep [#18](https://github.com/EcstaceeLOR/CertiFiks/issues/18) as a **hard deployment gate**: it cannot be closed until actual Portaldot-compatible contract lifecycle and receipts exist; #9–#17 must not misrepresent chain compatibility.
- Official Hackathon [Discord](https://discord.gg/portaldot) is the currently published organizer support channel; request V3 RPC, chain ID, faucet/explorer and exact acceptance of local test node there.

## Issue #2 completion interpretation
This is the explicitly allowed **BLOCKED with reproducible reason** alternative in the issue's definition of done. It completes the *technical investigation and go/no-go deliverable*, **not** the on-chain deployment. Future code and landing pages must display the deployment status as unverified until #18 succeeds.

No private keys, wallet seed, tokens or signed transactions were used.
