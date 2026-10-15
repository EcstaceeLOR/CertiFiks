# Issue #20 — Real GitHub App authentication and durable ingress

This milestone adds server-side RSA-signed GitHub App JWTs, narrow repository/permission-scoped installation tokens, authenticated immutable-commit readbacks, and database-backed webhook delivery acceptance.

## Configure a CertiFiks-owned GitHub App

A GitHub connector installation for ChatGPT does **not** constitute a CertiFiks GitHub App installation. Register a separate GitHub App belonging to the product and grant repository Contents read, Pull requests read, Metadata read and the Installation, Installation repositories and Pull request events. Install it only on expressly selected repositories with the maintainer's consent.

Store the GitHub App ID, its private RSA signing key and the webhook secret only in your secure backend secret manager; never commit them, send them to the browser or expose them in GitHub Actions fork jobs. An authenticated user/repository connection database must record installation ID, numeric repository ID, user identity, consent and revocation. A webhook's installation ID must not be substituted for that authenticated binding.

The protected `mintRepositoryInstallationToken` function mints a fresh JWT and POSTs to the GitHub App token API with one repository ID and read-only permissions. It refuses an expired, incorrect, ambiguous or underprivileged token response. `getAuthenticatedRevisionReceiptV1` then validates the owner binding and independently re-reads the exact PR/base/head/commit via the installation token. An unsigned revision snapshot can never authorize escrow release.

## Production database ingestion

The API's `/webhooks/github` endpoint now requires `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in production and uses `PostgresWebhookJournal`. The older exclusive-create filesystem journal is development-only. Create the schema through:

- `supabase/migrations/202610150001_github_delivery_queue.sql`
- `supabase/migrations/202610150002_github_delivery_leases.sql`

The SQL RPC is available only to the service role, performs atomic insert/deduplication for delivery UUID and signed body SHA-256, refuses stale/invalid envelopes, blocks pending jobs on installation deletion/suspension, and provides skip-locked leases, bounded retries and attempt-fenced completion. API responses stay fail-closed when the journal is down. Background workers must always re-read current repository access and pinned PR metadata; delivery order alone never proves PR freshness.

**Do not set a browser-exposed Supabase anon key as the service key.** Use RLS and server-only privileges. Do not expose the service key to browser bundles.

## Verification and outstanding work

Unit/integration tests use locally generated RSA keys and stubbed GitHub responses. They do not prove a real installed app or database deployment. Remaining live requirements: real GitHub App registration, installation authorization and maintainer session binding, verified selected-repository consent, migrated production database, live authenticated webhook delivery, transactional worker processing, actual token expiry/revocation tests with GitHub, redacted logs, and deployed multi-instance recovery exercise.

**Issue #20 must remain open.** These integrations must not generate a green fix-verification or payout badge until real independent verification and contracts are ready.
