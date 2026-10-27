# Issue #42 — API liveness vs. transport readiness

**Status: partial operational implementation. Production, real-fund operations and backup/restore evidence are NOT approved.**

The public `GET /health` is a **liveness** endpoint: it reports that the Fastify process can answer HTTP. An HTTP 200 there never demonstrates that GitHub webhook ingestion, the database, any verifier, or on-chain custody works.

The new `GET /readyz` is a fail-closed **transport-readiness** endpoint. Before reporting HTTP 200 it requires:

- An HTTPS Supabase PostgREST origin passing the existing strict `.supabase.co` origin validation.
- A server-side service-role key and a successful, authenticated, read-only query of the actual `certifiks_public_bounties_v1` projection.
- A configured webhook signing secret and a durable PostgreSQL-backed webhook journal (filesystem-only storage cannot satisfy readiness).

HTTP 503 means do **not** route traffic to this instance. Both success and failure return `Cache-Control: no-store` and a fixed, bounded public schema. Credentials, response bodies, private database rows, upstream errors and URLs are not disclosed. A successful response explicitly sets `productReady: false` and `settlementReady: false`, because the endpoint does not exercise the runner, finalized RPC/escrow, GitHub installation permissions, notification delivery or real payment.

Run the deterministic transport readiness regressions:

```bash
npm run test --workspace=@certifiks/api
```

For a genuine deployment, operators should configure secrets through a provider secret manager, restrict ingress to the API, and have a trusted internal monitor exercise `/readyz` while a separate monitor tests GitHub deliveries, queue lag, chain finality, backup freshness and funds/evidence reconciliation. Do not use CI's synthetic credentials as deployment secrets.

## Remaining Issue #42 acceptance work

- Launch independently isolated staging and production services with verified deployment commit, managed secrets, migrations, controlled promotion and rollback, including real endpoints.
- Measure P95 latency, verifier queue, indexer lag/reorg, signed attestation failures, webhook/event backlog, notification delivery and escrow-accounting drift; wire paging and incident ownership.
- Run real forced API/worker/RPC outages, verify funds remain controlled by on-chain escrow, and retain independent traces.
- Verify encrypted offsite production backups and point-in-time restore using safe staging data; attach RPO/RTO, hashes, retention evidence and a restore transcript.
- Publish accurate public status/support instructions and sign off on wallet/signing key rotation and emergency pause.

Until these are evidenced, **Issue #42 remains OPEN** and production launch is blocked. The readiness endpoint is a narrow operational improvement, not a substitute for service-level monitoring.
