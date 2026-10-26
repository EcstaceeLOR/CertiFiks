# Signed evidence reports — v1 integrity verification

**Issue #22; code delivered, external production storage and access control outstanding.**

A verifier's statement that tests passed is **not** proof of correctness, nor is it authority to settle a funded bounty. This subsystem proves that a statement and its referenced private artifacts have not changed, and that at least two **separately enrolled organizational** Ed25519 keys signed the same report.

## Report commitments

A strict version-1 report binds numeric repository, bounty, attempt IDs; canonical funded manifest SHA-256; runner image SHA-256; immutable base and candidate Git SHAs; test plan SHA-256; runner-result SHA-256; UTC timestamp; claimed decision; and **all three** baseline, candidate, and regression private-log descriptors (byte count and SHA-256). Extra fields, missing roles, reordered roles and public-log visibility are invalid.

Each reviewer signs the bytes of:

```
UTF8("CertiFiks:evidence-report:v1\\0") ||
UTF8(SHA256(UTF8("CertiFiks:evidence-report:v1\\0") || JCS(report)))
```

The downloaded envelope contains the public report and detached signatures, **not private logs**. Organizational trusted keys come from an independently authenticated trusted roster, not the downloaded envelope. A forged, revoked, reused or untrusted key fails verification. One organization with two keys never satisfies the two-organization requirement.

## Independent offline reproduction

For the TypeScript tests, generate unique nonproduction test keys and redacted fixture logs:

```sh
npm ci
npm run test --workspace=@certifiks/shared
```

Given an already downloaded `bundle.json`, a **separately provisioned and verified** `trusted-roster.json`, and an authorized local directory of private artifacts named `baseline-log.bin`, `candidate-log.bin` and `regression-log.bin`:

```sh
node --import tsx scripts/verify-evidence.mjs bundle.json trusted-roster.json private-artifacts/
```

Expected successful (integrity-only) structure:

```json
{"reportDigest":"0x<64 lowercase hex digits>","integrity":"verified","reportedDecision":"qualified","payoutAuthorized":false,"note":"Cryptographic integrity only; does not establish real tests or payment eligibility"}
```

Changing any result byte, supplied SHA, reported timestamp, commitment, signature or trust source, removing a required log, or using a revoked key results in nonzero exit status and `EVIDENCE_REJECTED`. The test suite also runs this CLI against redacted generated fixtures and checks the missing-artifact failure.

## Retention and authorization boundaries

Private logs can contain repository code and secrets. **Never** publish or embed them in public reports, download pages, CI logs, or an anonymous API. Public pages may show hashes and signer identities, not the bytes of private artifacts. The CLI requires artifact bytes only after an independently authorized download (not implemented here).

Do not enable payouts based on a signature or digest alone. Production completion of Issue #22 additionally requires the protected encrypted artifact store with tenant-scoped access, append-only audit entries, object-lock/integrity and retention/delete/backups, verified certificate enrollment with historical revocation, authenticated read-only download API, independent deployed reproduction, and unavailable-evidence blocking in the full settlement state machine. These depend on unfinished #23, #24, #25 and live reviewer enrollment. The issue remains **OPEN**.
