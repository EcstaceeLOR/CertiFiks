# Portaldot network release gate — Issue #18

**Status: BLOCKED — no qualifying deployment or escrow settlement verified.**

## Why this gate exists

CertiFiks currently implements Solidity modules whose authorization, EIP-712 signatures, native transfers, `msg.sender` and `block.chainid` depend on an **EVM execution environment**. Portaldot is described by participants as a **Substrate / contracts-pallet (WASM)** runtime; public endpoints and local-dev deployments are *not* interchangeable with an organizer-approved Portaldot V3 testnet.

Do not silently compile the existing Solidity escrow for an unrelated EVM chain, advertise it as Portaldot, or deploy `contracts/test/PullWithdrawalModuleV1.t.sol:PullHarnessV1`: the publicly payable `testFund` harness is **test-only**.

## Reproducible, read-only network discovery

With Node.js 22 or later, choose an endpoint from the event organizer and set:

```sh
export PORTALDOT_RPC_WS='wss://YOUR-ORGANIZER-APPROVED-ENDPOINT'
export PORTALDOT_EXPECTED_GENESIS='0x...64 hexadecimal digits...'
export PORTALDOT_EXPECTED_SPEC_NAME='...'
export PORTALDOT_EXPECTED_SPEC_VERSION='...'
node --test scripts/portaldot-runtime-probe.test.mjs
node scripts/portaldot-runtime-probe.mjs --write
```

`portaldot-runtime-observation.json` is an **observation**, not a release manifest. Do not commit private endpoints or personally identifiable data. `--require-ready` always exits unsuccessfully until an independently verifiable deployment verification stage is implemented. A project cannot become "ready" by toggling a flag in an environment file.

The probe reads: chain name, immutable genesis hash, specName/specVersion, transaction version, finalized head, token metadata and exposed `contracts_*` RPC methods. An exposed Contracts RPC is **necessary in some Substrate deployments but insufficient** to prove bytecode, gas, ABI or EVM compatibility. Runtime metadata/pallet version and organizer policy must still be inspected before choosing any deployment toolchain.

## Mandatory network and execution compatibility decisions

1. Obtain organizer-issued **Portaldot V3** genesis hash, supported RPC endpoint, contract pallet/version and accepted deployment workflow; confirm whether localhost Portaldot dev-node evidence is explicitly eligible and for which milestone.
2. If approved runtime is Substrate WASM-only: **port and independently test the actual escrow business logic to ink!/WASM**, including ownership, approved verifier signatures, funded deposits, message/call semantics, event encoding and arbitrary user withdrawals. Never assume Solidity/EVM equivalence.
3. If organizers explicitly certify a native EVM runtime: independently prove chain ID, expected bytecode, canonical deployer, challenge/replay domain and full funds path before deployment. No such certification is recorded here.
4. Require release contract source to expose a *production* funding entrypoint only after #9–#17 integration, no mocked evidence, and security approval.
5. Use a limited-funds, dedicated deployer with separate governance wallet, never commit secret keys or reuse a privileged dev account on public infrastructure.

## Real evidence to fill before announcing deployment

Do **not** fabricate any of these fields:

| Field | Current state |
| --- | --- |
| Network genesis / spec / finality / approved execution mode | Not certified by organizer |
| Contract source commit, reproducible artifact hash, ABI/metadata | Not finalized |
| Real on-chain deployment tx / finalized block / verified address | Missing |
| Actual sponsor funding tx and receipt | Missing |
| Assignment, candidate submission and signed verifier evidence | Missing |
| Challenge expiration, terminal entitlement and recipient withdrawal | Missing |
| Genuine cancellation/refund or arbitration dispute path | Missing |
| Explorer or chain RPC receipts, indexer reconciliation, gas costs | Missing |
| Independent-wallet funded walkthrough | Missing |
| Independent security review for real-user funds (#41) | Missing |

## Conditions for release

- Block UI from claiming “deployed” or “escrow ready” without verified chain identity + approved contract artifact + finalized and independently replayable tx receipts.
- Record both chain/finality and event indexer details in a **versioned deployment manifest** bound to the exact audited source hash. Delay notification/settlement UI until #27 reconciliation.
- Expose exact fee denomination (token symbol, decimals and smallest-unit accounting) verified from the approved runtime rather than assuming ETH/18 decimals.
- Run a complete test-funds sponsor-to-contributor claim plus independent refund/dispute path, capture transaction hashes, block hashes, event index references and exact gas/fee; repeat with a clean wallet.
- Keep Issue #18 open until externally verifiable evidence exists. A green RPC probe is not an acceptable substitute.

## Dependencies

#9–#17, #27, #28 and a real contract/runtime deployment decision. The #17 PR is draft and upstream modules are not merged; do not override those controls.
