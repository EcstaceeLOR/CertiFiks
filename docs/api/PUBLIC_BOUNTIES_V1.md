# Issue #26 — Public bounty API v1 (read-only first integration)

**Status:** tested API transport and secure PostgREST projection; not a complete authenticated lifecycle API.

Two HTTP handlers expose real data from the server-only Supabase REST view, or fail closed:

- `GET /v1/bounties?limit=20&offset=0` (limit 1–50, offset 0–10000, no leading zeros; returns `items`, cursor offset and explicit caveat).
- `GET /v1/bounties/:bountyId` (canonical UUID; 404 for unpublished/unknown).

The API **never** returns synthetic bounty fixtures, secrets, private artifacts, unverified CI badges or money as unsafe JavaScript floats. Large numeric repository IDs, chain IDs, atomic-unit rewards and on-chain bounty IDs are **decimal strings**. Every returned summary carries `verificationProven:false`, preventing display of a fabricated repair-validation claim.

The database migration `202610260003_public_bounty_projection.sql` adds opt-in `public_listing=false` to each bounty and a narrow security-invoker view. A bounty can only be explicitly made public after it records finalized, non-orphaned indexed chain evidence and funded transaction coordinates. The indexer must still independently verify the chain event; rows inserted by privileged SQL alone are not blockchain evidence.

Use backend-only `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. The API is unavailable (503) without them. Never publish those credentials or copy them into a browser bundle. PostgREST redirects are forbidden and requests have bounded timeouts. The view has no direct anon/authenticated grants.

## Reproduce

```sh
npm ci
npm run test --workspace=@certifiks/api
```

The PostgreSQL CI job applies all migrations, verifies that unfinalized synthetic bounties are not listed, checks explicit publication after a synthetic finalized event, and confirms that the redacted view survives `pg_dump` and restore. The API unit tests stub the PostgREST transport to assert fixed origin, exact query, safe numbers, 400/404/503 error states and no mock fallback.

## Still required for full Issue #26

Authenticated sponsor funding intents, applications, assignment/submission, independent verification decisions, disputes, artifact downloads and payments; wallet/GitHub login and RBAC/IDOR (Issue #23); idempotent and auditable writes; complete OpenAPI-generated SDK; production database connection; front-end consumption; real finality/reorg indexer; rate limiting; real human-operated end-to-end tests. Until those are proven, Issue #26 must stay **open**.
