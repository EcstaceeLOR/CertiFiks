# Issue #27 — Canonical event observation and reorganization controls

**Status: partial implementation, not a connected production indexer, verified Portaldot bridge, or payout system.**

The read-only `ReadOnlyEvmObserverV1` adapter is intended **only for an independently approved EVM-compatible chain**. It checks the expected chain ID, genesis block hash, an operator-approved set of deployed contract addresses and emitted topic selectors, verifies block/log hashes twice, bounds log batch sizes, rejects malformed/redirected RPC replies, rejects unexpected contracts and fails on provider outage. Its hash-digested logs contain no private decoded contract data.

The new SQL migration `202610260004_chain_observation_ledger.sql` maintains a private **durable, append-preserving** chain observation ledger: one canonical block per height, blocks and logs keyed by chain ID/hash/transaction/index, a sequential scanned cursor, duplicate suppression, explicit rewind preserving orphaned branches, and a configurable confirmations gate. Deep reorganization across an already-finalized observation fails closed and must go to manual incident triage. RPC evidence *alone* is not a business authorization.

## Verification

```sh
npm ci
npm run test --workspace=@certifiks/api
```

The `relational-db` CI job applies migrations to a clean PostgreSQL service and asserts sequential continuity, replay handling, gap rejection, safe branch rewinds, finality boundaries, private RLS, and that synthetic chain events cannot mutate bounty funding. It then exercises database backup/restore.

## Still required for full Issue #27

- Verify the actual hackathon-approved **Portaldot** runtime and determine whether it even exposes EVM JSON-RPC. The existing `portaldot-runtime-probe.mjs` is a *Substrate* WS read-only probe; this EVM adapter must not be used on a Substrate-only chain.
- Deploy and verify actual compatible contracts, ABI/topic decoders, multi-provider RPC failover, WebSocket or poll scheduler, durable worker cursor initialization, and independently verified proof that returned logs match state at the expected chain finality.
- Map verified decoded events to a tenant bounty with an authorized service, using transaction receipt status, contract address, ABI version, expected deposit/payout amounts and state reconciliation. The observation ledger **does not credit funds** and **never** authorizes settlement.
- Handle deeper-than-finality incidents, provider disagreement, transaction replacement, withdrawal/refund receipts, block-height indexing lag, accounting alerts and deterministic end-to-end recovery on an approved live chain.
- Expose explorer-safe URLs and informative transaction states through authenticated APIs and browser UI.

**Do not close Issue #27** until real chain, escrow custody and accounting concordance have been independently established. Synthetic tests are not actual transaction evidence.
