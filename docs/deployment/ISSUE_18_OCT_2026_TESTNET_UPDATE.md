# Issue #18 — October 2026 V3 network discovery refresh

**Read-only candidate observations only. No blockchain deployment, funding transaction, runtime/VM approval, testnet wallet authorization or independent chain evidence has been completed.**

## Newly announced endpoints (reported, not yet trusted)

The Portaldot Devs updates dated **October 17 and October 23, 2026** have been republished by the network's public social account. The announcements say that the old V3 testnet RPCs have changed, with a public Substrate endpoint `wss://test-node-v3.portaldot.dev`, an EVM RPC host identified as `test-evm-rpc-v3.portaldot.dev`, and an unchanged *reported* EVM chain ID of **420420777**.

- Announcement trail: https://teapawt.org/PortaldotL0 (Portaldot / Portaldot Devs announcements, October 17 and 23, 2026).
- HTTPS on the EVM host is a **candidate connection scheme** for observation, not organizer-verified service ownership or chain identity.
- These public claims **do not supply an independently pinned genesis hash, tested EVM deployment, signed release approval or escrow contract address**. Do not label CertiFiks "ready" from these announcements.
- Historical mainnet `wss://mainnet.portaldot.io` remains a separate comparison endpoint; never treat it as the new testnet.
- Even if the testnet is live, published token decimals from older Substrate documentation (14) cannot be safely assumed for the new EVM lane or native wallet withdrawal amounts.

## Actual read-only GitHub Actions observations — October 27, 2026

The exploratory CI [run #40577273797](https://github.com/EcstaceeLOR/CertiFiks/actions/runs/40577273797) saved unmodified 14-day JSON artifacts for all three endpoints:

| Endpoint | Result from GitHub hosted runner | What it does NOT prove |
| --- | --- | --- |
| `wss://test-node-v3.portaldot.dev` | **Connected**. `system_chain=PortaldotV3 Test`, `specName=portaldot-v3`, `specVersion=3002`, `tokenSymbol=tPOT`, `tokenDecimals=14`, and SS58=42; no `contracts_*` methods advertised. | Specific contract VM, whether testnet deposits/withdrawals are safe, and authorization for a production escrow |
| `https://test-evm-rpc-v3.portaldot.dev` | **Connected**. `eth_chainId=0x190f1ca9` (`420420777` decimal); `net_version=420420777`; head and `web3_clientVersion` returned. | EVM bytecode deployability, real escrow tx success, finality guarantees and independently verified code |
| `wss://mainnet.portaldot.io` | **Connected** as older `Portaldot Mainnet`, `specVersion=1002`, token `POT`; historic `contracts_*` RPCs advertised. | That this mainnet is the correct V3 testnet or that its old ABI can safely run this Solidity escrow |

**Caution:** the first probe queried `chain_getBlockHash` without a height (which typically reports the best block), and the first EVM probe queried only the latest EVM block. This PR subsequently corrected the tools to fetch **explicit block zero (genesis)** and the Substrate finalized head; the original artifacts **must not** be retroactively labeled genesis or finality evidence. Re-run the updated probes and independently cross-check returned genesis hashes before pinning a network manifest.

All three tests used read-only RPC calls. They did not send tokens, interact with a deployed CertiFiks contract, authorize private wallets, use a real sponsor or developer, or certify hackathon compliance. They are genuine *connectivity observations only*.

## Repeatable discovery workflow

`.github/workflows/portaldot-network-probe.yml` now defaults to the announced public V3 testnet WebSocket RPC on manual dispatch. The exploratory feature branch additionally collects **read-only** automated WebSocket and EVM-JSON-RPC observations, with explicit labeling and a 14-day artifact retention period.

For local developer investigations with Node 22+, using only public endpoints without secrets:

```sh
PORTALDOT_WS_RPC=wss://test-node-v3.portaldot.dev \
  node scripts/probe-portaldot.mjs > v3-ws-observation.json

PORTALDOT_EVM_RPC=https://test-evm-rpc-v3.portaldot.dev \
  node scripts/probe-portaldot-evm.mjs > v3-evm-observation.json
```

Review `system_chain`, genesis hash, runtime/spec version, token properties, `eth_chainId`, `eth_blockNumber`, `eth_getBlockByNumber`, and unexpected error responses. Confirm that all observations refer to a single legitimate, organizer-approved V3 testnet, not an EVM proxy returning someone else's chain. **If any call fails, record its exact failure; do not synthesize successful data.**

## Actual next milestones

1. Obtain **organizer confirmation** of the current V3 endpoints, chain/genesis identity, EVM/VM execution and the qualifying faucet/token distribution route. Only an independent verified chain ID + genesis + program identity is admissible.
2. Build the **production concrete escrow integration**: current Solidity modules are abstract, and the payable Foundry harness is intentionally test-only. Create a fundable implementation only after audit and a review of all authorization, beneficiary, refund and dispute conditions.
3. Prepare and independently review a deterministic production artifact, deployment script, deployer/governance separation, release ABI, verification source and immutably hashed manifest before any public custody.
4. With an authorized dedicated testnet wallet and faucet-sourced **test-only** tokens, record a finalized real deploy transaction, source verification, exact runtime bytecode and genuine sponsor-to-developer settlement plus independent refund/dispute path.
5. Verify finality across two independent RPCs or an authoritative explorer; index/replay all events and reconcile native accounting. Demonstrate a clean second wallet following the published instructions.

**Issue #18 remains OPEN**. No private signing operation, faucet claim, deployment, or real transfer can be inferred from the read-only GitHub Actions probe.
