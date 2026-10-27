# Issue #11 — Immutable authenticated GitHub snapshot admission

**Status:** implemented private admission and PostgreSQL integrity gates. This is not an independent GitHub App deployment, live fund settlement, or signer-approved review.

## New server-only implementation

`apps/api/src/github/attempt-receipt-store.ts` accepts a **trusted** tenant/attempt binding, an existing consented repository installation, and a sponsor-pinned revision policy. It re-mints an exact-repository GitHub App installation token, fetches the repository, PR and commit from GitHub's fixed HTTPS API, verifies numeric IDs/branch/base/head/author/signature policy, and then inserts the resulting immutable snapshot into Supabase with service-role authorization. If storage rejects it, the helper **does not return an admitted receipt**. No upsert, overwrite, fake fallback or browser endpoint exists.

The authenticated GitHub receipt now explicitly exposes the numeric **source repository ID**, including fork identity. The digest already committed to this identity; surfacing it removes ambiguity in the stored record.

## Database integrity enforcement

Migration `202610270001_github_revision_receipts.sql` introduces `certifiks_github_revision_receipts` with per-tenant attempt primary key and compound foreign keys into the submitted attempt and authorized repository. Its insert trigger locks parent rows and checks:
- Exact tenant/bounty/attempt identity, base and candidate Git SHAs.
- Exact canonical numeric destination repository, current installation ID, unrevoked repository connection, and funded manifest digest.
- Fork vs. source-repository identity, nonzero IDs and canonical SHA formats.

Both receipt updates and deletes fail. Identity-bearing fields of the underlying attempt are also protected from UPDATE/DELETE; status transitions remain possible. Anonymous and authenticated browser roles have no receipt table permissions. GitHub App tokens are never persisted in the receipt or returned as evidence.

The PostgreSQL 16 CI run applies the migration and rejects duplicate inserts, forged heads, in-place edits and browser-role reads before performing an actual `pg_dump` / `pg_restore` synthetic-data recovery drill. API tests exercise the protected GitHub → storage boundary with injected, controlled fake providers, ensuring no external credentials are involved.

## Security limits and remaining acceptance

**Important:** The database constraints do not prove that a service-role caller genuinely authenticated against GitHub. Only the protected caller performing the authorized live API request can establish that; a compromised service role could insert fabricated rows. Connect the helper to a deployed authenticated session workflow that loads the attempt/funding policy from tenant-scoped PostgreSQL, checks on-chain submission and installation consent, and privately stores signed provider evidence before allowing any verifier job. Neither UI/browser nor an unauthenticated webhook should ever supply these trusted context parameters.

No independent verifier vote, GitHub App live installation, on-chain attempt reconciliation, archival content hash verification or actual Portaldot escrow transaction has been completed by these synthetic regression tests. Issue #11 **remains open** until true end-to-end authenticated submission, force-push/retry, identity/revocation and on-chain proof are exercised with authorized participants.
