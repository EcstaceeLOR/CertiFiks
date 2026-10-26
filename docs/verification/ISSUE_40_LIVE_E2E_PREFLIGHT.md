# Issue #40 — Read-only live infrastructure preflight

This is **not** the Issue #40 acceptance test. The complete independent sponsor → developer → verified patch → challenge → on-chain withdrawal/refund journey remains unverified. This small gate refuses to call even the *infrastructure* ready without checking external facts against operator-confirmed identities. No transaction is created, signed or submitted.

Run `npm run e2e:preflight` only in an authorized test environment with these **server-side process environment** values (never commit credentials or put them in shell command arguments):

| Variable | Source and requirement |
| --- | --- |
| `PORTALDOT_EVM_RPC` | Organizer-confirmed, root HTTPS EVM JSON-RPC endpoint (not the legacy mainnet or localhost) |
| `CERTIFIKS_E2E_CHAIN_ID` | Organizer-confirmed decimal chain ID, not inferred from the untrusted endpoint |
| `CERTIFIKS_E2E_GENESIS_HASH` | Independently confirmed lowercase `0x` + 64 hex genesis hash |
| `CERTIFIKS_E2E_ESCROW_ADDRESS` | Independently recorded lowercase deployed contract address |
| `CERTIFIKS_E2E_ESCROW_CODE_SHA256` | SHA-256 of independently reviewed deployed *runtime* bytecode, lowercase 64 hex; do not copy the value from the same untrusted RPC without checking deployment artifacts |
| `CERTIFIKS_E2E_GITHUB_REPOSITORY` | Exact approved `owner/repo` spelling |
| `CERTIFIKS_E2E_GITHUB_COMMIT_SHA` | Approved pinned 40-character lowercase Git revision |
| `CERTIFIKS_E2E_GITHUB_INSTALLATION_TOKEN` | Short-lived GitHub App **installation** token scoped to only this repository; request read-only permissions, rotate after use |
| `CERTIFIKS_E2E_API_ORIGIN` | Deployed root HTTPS CertiFiks API origin |

The CLI performs only read requests:

1. Compare `eth_chainId` and block-zero hash against independent expected values. Require a `finalized` block and deployed bytecode at that tag whose SHA-256 exactly matches the approved digest.
2. Require a genuine GitHub App installation token with exactly one accessible repository, then fetch the pinned commit through that same token.
3. Require actual `certifiks-api` health to report both `productReady: true` and webhook ingestion configured, plus a working public bounty projection. Empty published results may be valid before test setup and are **not** represented as funded bounties.

The output contains only fixed check-status codes, never private token values, responses or evidence. A failed or missing check exits nonzero. Even when `infrastructureReady` is true, `completeJourneyVerified` is **always false**. The backend currently reports `productReady: false`, so the real gate should be blocked; do not flip that boolean just to make it green.

## CI and remaining release evidence

Run `node --test scripts/e2e/live-preflight.test.mjs` with no secrets. The deterministic test set includes wrong network/genesis, absent finality, empty/mismatched contract code, overbroad installation scope, revision mismatch, unavailable API, invalid config and provider-error redaction. CI does **not** call a network, use real credentials or claim Portaldot support.

Still required before #40 can close:

- Approved Portaldot V3 testnet identity and deployment transaction/explorer evidence (Issue #18).
- Genuine wallet/GitHub sign-in with two independent user sessions and role-scoped API actions (#23/#30/#31), plus securely isolated runner and reviewer credentials.
- Signed sponsor deposit, immutable bounty, assigned real GitHub revision, reproducible baseline failure/candidate success, independent quorum, bounded challenge, genuine withdrawal and refund receipts. Capture chain state and API/UI balance history from the **same finalized blocks**.
- Negative-path failure injection (forged/tampered proof, wrong chain, unassigned patch, webhook replay, lost RPC, failed transaction, arbitration timeout), custody invariants and a second-machine reproducibility report.
- Human review of browser screenshots, accessibility output, private evidence controls and a witnessed real-flow video. Attach checksums/log references without publishing secret artifacts.

No live environment or testnet funds were accessed during this code change. The gate establishes conditional checks, not external-provider validation or permission to transact.
