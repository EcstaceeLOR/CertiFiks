# Issue #36 — Truthful wallet and transaction display states

This integration adds a pure, tested display-only state contract in `packages/shared/src/wallet-transaction-status.ts` for future wallet connectors and a separate public safety page at `/wallet`.

The display classifier distinguishes unapproved runtime, disconnected wallet, wrong chain, changed account, requested signature, user rejection, provider outage, broadcast-only, pending finality, replaced transaction, reverted receipt and canonical successful receipt **observation**. The classifier explicitly keeps `custodyVerified:false`, `payoutVerified:false` and `allowTransfer:false` in every state: neither browser-wallet events nor isolated JSON-RPC reports authorize money movement.

In particular, a changed wallet account does not disclose old transaction hashes; a wallet on the wrong chain is blocked; an apparently successful canonical receipt **still requires independent verified on-chain custody reconciliation** before a bounty can be considered funded. Portaldot is potentially Substrate-only. This classifier only accepts an independently configured EVM protocol and never assumes EVM compatibility on Portaldot.

CI unit tests verify exact transitions and prove no event sequence can produce a paid or transfer-authorized status. The `/wallet` page provides clear safety and unavailability messages rather than an inert working-looking “Connect Wallet” or “Fund” button.

## Still blocking full Issue #36

- Independent official confirmation of the approved Portaldot chain identity, runtime and EVM/Substrate wallet compatibility.
- Audited supported-chain wallet connector(s), explicit transaction origin/contract/amount/fee validation, account switch state invalidation and secure signing requests, without storing private keys.
- Real chain transaction receipt + finalized indexer reconciliation, replacement/cancel/fee-bump monitoring, retry/error recovery, explorer links and persistent user-authorized transaction history.
- Real wallet E2E matrix on the approved testnet including wrong chain/account, rejection, gas failure, reverted/forked/replaced transactions and cross-account data isolation.

Keep **Issue #36 OPEN** until live wallet flows and independent custody/finality proofs exist. No production payment support is implemented by this PR.
