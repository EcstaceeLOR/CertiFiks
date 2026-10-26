# Issue #24 — Transactional lifecycle data, tenancy and recovery

**Status:** reproducible schema and synthetic backup/restore verification, not a deployed customer database.

The versioned migration `supabase/migrations/202610260002_lifecycle_tenancy.sql` creates PostgreSQL constraints and indexes for organizations, installed repositories, bounties, manifest revisions, developer applications, active assignments, immutable Git attempts, verification runs, encrypted evidence metadata, distinct verifier votes, disputes, payments, finalized/reorg-aware chain events, notifications, tamper-resistant audit entries and encrypted secret metadata. It builds on the existing GitHub delivery migrations and Issue #23 auth tables.

## Security properties enforced at the database layer

- Composite (organization_id, parent_id) foreign keys stop a tenant from inserting attempts, assignments or applications into another organization's bounty.
- Unique developer applications, one active assignment per bounty, head SHA per bounty, reviewer organization per verification run, funding chain/transaction, payment transaction, and finalized log identity reduce double effects on retries.
- Native numeric atomic-unit amounts prevent rounding; both funding and payment hashes are canonical lower-hex. On-chain settlement authorization is **not** implemented by this schema.
- Manifest versions, verifier votes and audit records have append-only triggers; modification/deletion raises an error. A database superuser is still able to disable triggers, so append-only checks are not a substitute for immutable external anchors.
- Encrypted credential and artifact pointers do not store raw secrets or public private-log bytes. Encryption/key management and storage backend still require implementation.
- RLS is enabled and anon/authenticated roles have no direct table grants. A server-only service-role API MUST authorize each tenant/user/role independently and must never expose the service key to clients.

## Real migration and recovery test

GitHub Actions adds a PostgreSQL 16 service test that applies **all migrations** to a fresh database and uses `scripts/db/ci_assertions.sql` to exercise funded bounty lifecycle persistence, replay suppression, duplicate application prevention, cross-tenant foreign keys, append-only audit/manifest behavior and denied browser-role reads. It then uses PostgreSQL's actual `pg_dump` and `pg_restore` to restore a new database and verifies that the funded bounty, immutable submission and audit entry survive exactly.

The CI database uses only synthetic fixtures. Production migration must use controlled credentials and secure snapshots; never point this test script at customer infrastructure or include sensitive database backups in GitHub artifacts.

## Still outstanding to close #24

- Deployed PostgreSQL migrations with managed secrets, encryption and tenant-scoped repository layer.
- Full idempotent transaction boundaries across authorized API handlers, finalized chain indexer and real escrow payouts.
- Real encrypted artifact object-store lifecycle, retention/deletion and GDPR-compatible export policy with legal-hold exceptions.
- Production backup retention/restore and disaster recovery drill on actual redacted sandbox bounty data, with documented recovery point and time objectives.
- Robust reconciliation against chain reorgs, privilege escalation/IDOR integration tests, replays across replicas and audited data access logs.

Do not close #24 until these operational checks are complete.
