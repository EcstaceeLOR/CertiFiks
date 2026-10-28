# Issue #24 — Post-restore lifecycle integrity witness

**Status: executable PostgreSQL 16 synthetic disaster-recovery evidence only. Not a production disaster-recovery certification, encrypted offsite backup, or real funds proof.**

The CI workflow already initializes PostgreSQL from versioned migrations, creates synthetic sponsor and developer records, applies assignment/attempt/verification/audit events, executes a `pg_dump -Fc`, restores into a **new** database using `pg_restore`, and checks four row counts. Those counts alone could pass if manifest digests, identities, chain finality or private permissions had changed.

`scripts/db/ci_restore_integrity.sql` now runs **against the restored database** and independently verifies the following full chain of relationships:

- The sponsor tenant, authenticated sponsor, exact destination repository/installation and funded native-asset amounts are preserved.
- The immutable version-one manifest commitment and private storage *reference* are unchanged.
- The developer application links to the assigned developer, the pinned base/head SHAs, and the authenticated GitHub read receipt with the same repository/manifest/installation identities.
- The verification run retains its expected image and test-plan commitments and remains `pending`, not a fabricated green verdict.
- The synthetic finalized non-orphaned funding event is still linked to the funded transaction and blocks, so the separate published-finality view contains exactly one permitted entry.
- The funding audit entry retains its original action and digest, a second organization's repository is still present, and restored RLS/grants still deny anonymous inspection of sensitive tables.
- On the restored database, direct privileged modification of the original manifest or deletion of the immutable audit entry is **actively rejected by restored triggers**.

The CI test uses **synthetic fixture IDs, mock digests and fake chain observations**; success does not imply a real deposit, a real GitHub installation, or any production-ready database. Only the PostgreSQL schema and relational integrity are exercised. A `private/manifests/...` reference in a restored row is not proof the external blob is still retrievable or decryptable.

## Still required before Issue #24 closure

1. Provision persistent production-grade PostgreSQL, service-role isolation, audited scoped authorization, and separate operational credentials. Verify migrations on a clean hosted environment and a staged upgrade. Never make a browser a privileged SQL caller.
2. Encrypt actual private artifacts/installation credentials using managed secret infrastructure; test key rotation, offsite object storage retention, revocation and recoverable snapshot references.
3. Configure encrypted offsite database backup, PITR/WAL retention and independently witnessed restoration after a destructive failure of a nonproduction service; measure actual RPO/RTO and service recovery.
4. Run cross-tenant and user deletion/export/privacy procedures on realistic data, assess webhook/idempotency replays across replica restarts, and validate public exposure remains finalized-only.
5. Link the restored DB to an actual consented GitHub revision, finalized on-chain funded lifecycle and real verifier evidence; independently verify those externally owned resources.

Keep **Issue #24 OPEN** until these integration, security and independent recovery acceptance requirements are met. A green SQL backup/restore CI job is valuable engineering proof, not production readiness.
