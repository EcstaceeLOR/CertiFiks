# Issue #16 — Finality-bound native payout receipt witness

**Status: read-only verification tool, NOT a completed withdrawal, a live Portaldot integration or an independent audit.**

CertiFiks already implements a native pull-withdrawal accounting module and Foundry adversarial coverage in \`contracts/src/PullWithdrawalModuleV1.sol\` and \`contracts/test/PullWithdrawalModuleV1.t.sol\`. The missing real-world step is witnessing a transfer on the **independently confirmed, qualifying chain**. The CLI added in this PR will **refuse to produce success without real, finalized JSON-RPC evidence**.

Run \`npm run payout:proof:test\` for completely synthetic parser tests. After a **safe and independently reviewed** deployment exists, run:

\`\`\`sh
npm run payout:proof -- /path/to/withdrawal-proof-config.json
\`\`\`

The JSON config must contain **exactly** the following fields (all values below are placeholders, not valid evidence):

\`\`\`json
{
  "rpcOrigin": "https://rpc-from-official-chain-documentation.invalid",
  "chainId": "CHAIN_ID_AS_BASE10_STRING",
  "genesisHash": "0x64_LOWERCASE_HEX",
  "escrowAddress": "0x40_LOWERCASE_HEX",
  "escrowCodeSha256": "64_LOWERCASE_HEX",
  "transactionHash": "0x64_LOWERCASE_HEX",
  "logIndex": "0x0",
  "bountyId": "BOUNTY_ID_AS_BASE10_STRING",
  "beneficiary": "0x40_LOWERCASE_HEX",
  "recipient": "0x40_LOWERCASE_HEX",
  "amountAtoms": "PAID_AMOUNT_AS_BASE10_STRING",
  "remainingAtoms": "REMAINING_CREDIT_AS_BASE10_STRING"
}
\`\`\`

**Never provide RPC secret query strings, wallet keys, installation tokens or private identities**. The tool uses public RPC calls only, and it emits a generic error without printing RPC responses or credentials on failure. Do not run it with a harness's synthetic data and claim proof of real transfers.

## What it verifies

- \`eth_chainId\` exactly matches a supplied chain ID, and genesis block hash matches the independently verified network genesis hash. Neither is guessed.
- The exact supplied transaction has \`status=0x1\` and targets the independently verified escrow address.
- The named receipt block is on the node's *current canonical chain*, has matching hash and is no later than a reported \`finalized\` block. Nodes without finalized-block support are rejected, not treated as successful.
- The actual code at the transaction block has the approved bytecode's independently verified SHA-256 digest; a copied event emitted by arbitrary attacker bytecode does not count.
- The exact log index, emitting contract, transaction/block provenance, canonical **Keccak-256 event topic**, bounty ID, beneficiary, designated recipient, amount atoms and remaining credit all match the asserted evidence. All monetary amounts use exact decimal BigInts, never floating point.

It returns \`verifiedOnConfiguredRpc: true\` only after every check. The output explicitly keeps \`securityAuditApproved: false\` and \`productReady: false\`. An independently trusted RPC is still a prerequisite: a malicious node could fabricate an internally consistent result. The witness proves **a particular withdrawal event on the selected node**, not that the bounty's real-world bug was fixed or that funds were delivered by a production-approved system.

## Completion gates for Issue #16

1. An authorized operator confirms the correct Portaldot chain ID, genesis, finality rules, native token denomination and audited production bytecode, then deploys/independently verifies the release contract after security approval. This repo's abstract module and test funding harness must **never** be deployed to accept real deposits.
2. Real sponsor and developer wallets execute authentic, independently checked funding, signed-review settlement, and a beneficiary-authorized withdrawal to an approved recipient on a qualifying testnet.
3. Record the finalized transaction hash, log index, on-chain bytecode digest, on-chain credit before/after and complete chain evidence. Cross-check the raw receipt with a **second independent RPC/explorer** and full indexer replay.
4. Independently challenge with real reverting smart-wallet recipients, reentrancy probes, interrupted transactions and positive retry to a compatible recipient. Obtain a third-party audit/launch approval.
5. Only then move Issue #16 to closed. Foundry/CI success, by itself, is never testnet payout evidence.
