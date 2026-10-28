# Issue #22 — Independent evidence receipt hygiene and private-log integrity

**Status:** offline verification hardening only. This PR does not create, deploy or operate the missing private artifact delivery API. It does not attest that a real fix passed tests or independently authorize an escrow payout.

The existing `verifyEvidenceBundleV1` already verifies committed report/manifest/image/commit fields, checks each private artifact's SHA-256 and byte count, verifies Ed25519 signatures against a separately provisioned trusted roster and **always returns `payoutAuthorized: false`**. The additional guards address two concrete remaining denial-of-service and identity-alias risks.

## Reader changes

`scripts/verify-evidence.mjs` now opens each input as a regular file with no-follow semantics, checks the **opened inode**, and reads at most **1 MiB + 1 byte**. Any missing, symlinked, non-regular, empty or excessive bundle, roster or private log is rejected without reading arbitrary volumes or printing filesystem paths or private log contents. Input failures produce only `EVIDENCE_REJECTED` and a nonzero process exit.

Verification continues to require **all three** protected private logs plus the separately acquired trust roster; a public report alone is not sufficient.

## Reviewer alias protection

In addition to rejecting repeated key IDs and organization IDs, the independent verifier now fingerprints the *actual* Ed25519 SPKI public keys used to sign the report. A single cryptographic signer cannot be relabeled into two different organization/key IDs to satisfy the two-reviewer minimum, even if an incorrectly enrolled roster contains both aliases. The registrar must still verify that different cryptographic keys represent genuinely independent controlling humans/entities; that is an **external** identity assurance and collusion review, not provable from PEM alone.

New regressions cover alias keys across two organizational labels, oversized private logs, a symlink to the *correct* hash-matching file (which must still be refused) and restoration of the original valid CLI transcript.

## Remaining acceptance evidence

- Build a tenant-authorized, audited private artifact retention and download service with short-lived access, revocation and backup/restore, ensuring a cross-tenant read cannot fetch private logs.
- Obtain independent reviewer identities and approved trust roots; publish signed roster epochs/revocation and ensure a signer can't register aliases in other organizations.
- Produce **real** baseline/candidate GitHub checkouts and isolated runner results, with a live signed report; make an external reviewer independently download the private bundle and verify all hashes and signatures.
- Verify deletion/redaction/retention policies, expired access, missing-artifact rejection, and independent audit of the entire evidence custody chain.

**Issue #22 remains open** until these real acceptance conditions are met. A passing offline synthetic cryptographic test is not an observed customer deployment.
