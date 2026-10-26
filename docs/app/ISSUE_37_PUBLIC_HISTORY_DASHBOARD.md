# Issue #37 — Searchable public bounty history (bounded first integration)

## Implemented
- Server-rendered `/dashboard` public history with independently validated URL filters (exact repository, published state, chronological/repository ordering), clear page boundaries, pagination, bookmarkable preset views, error/empty/unconfigured states and meaningful disabled private history disclosure.
- A `/dashboard/bounties/[bountyId]` link to real public indexed metadata. This is not a wallet-owned or tenant-private detail route.
- A public-only `/dashboard/export` CSV download limited by backend to 50 filtered public records with sanitized spreadsheet values. No service role credentials or private artifacts leave the server; no payout or verifier proof is inferred.
- API `/v1/bounties` now supports a strictly allowlisted sort and the new `/v1/bounties/export.csv` endpoint uses the finalized-only public projection, not private escrow data.
- Existing API and Next web test suites cover sorting, injection resistance, precise atomic reward strings, public-only data and fail-closed outage behavior.

## Trust boundaries

The public projection is purposefully incomplete. The displayed reward is **nominal atomic units**, not a custody liability reconciliation or spendable asset balance. Published `state` is not proof of verified fix, actual payment, confirmations, or fairness. All receipts and underlying private documents remain restricted. There are no global volume counts derived by multiplying a page count, fake platform activity numbers, or locally seeded records.

The query page is indexed up to 10,000 rows and uses deterministic pagination. Sorted history is still a mutable live dataset: concurrent publishing may move rows between pages. Repeatable ledger-grade history requires snapshot/as-of semantics and reconciliation.

The exported page contains only published metadata. It is not a financial report, and its file size and row count are capped. A shareable URL does not confer org-level permissions.

## Incomplete production acceptance

- Authenticated wallet/GitHub/organization sessions and role-bound sponsor, developer and operator dashboards for private, assigned, disputed, paid or refunded records.
- Server-side tenant RBAC, durable saved views and secure export scopes, direct links to authorized private receipts and evidence, and cross-organization IDOR tests.
- Real PostgREST migrations, live indexer transaction reconciliation, on-chain escrow liability/state check, verified timestamps and multi-provider freshness indicators.
- Production deployment, actual two-user continuity across restart, timed refreshes, partial outages, and mobile/keyboard/screen-reader browser validation.

Issue #37 remains OPEN. This PR adds working public-data integration but does not satisfy the full dashboard or real chain-reconciliation criteria.
