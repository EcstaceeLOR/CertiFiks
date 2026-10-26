# Issue #39 — Actual read API, offline verification CLI, and GitHub Check safety

**Implemented in this milestone:** A distinct, implemented-only OpenAPI contract, independently reproducible offline canonical-manifest and signed-evidence CLI tests, hashed server-only partner key authorization, transactional shared rate limiting and revocation, plus a pure GitHub Check Run state mapper that refuses unsupported verified claims.

**Not implemented / not claimed:** live partner account registration, a private-evidence download API, deployed GitHub Checks publishing, actual live user credentials, or an independently verified funded transaction. The original broad `protocol/openapi.v1.json` contains **specification-only** operations. The accurate, already-implemented read surface is `protocol/public-api.v1.json`.

## Run independent verification on a clean machine

Use Node.js 22+ with an exact dependency install. Obtain the expected manifest digest from a separately authenticated, **finalized** contract observation; never trust a digest supplied by the same person supplying the manifest:

```sh
npm ci --ignore-scripts --no-audit --no-fund
node --import tsx scripts/verify-manifest.mjs \
  canonical-manifest.json --expected-digest 0x<64-lowercase-hex>
```

The CLI rejects wrong version/schema, noncanonical UTF-8 encoding, field tampering and mismatched hash and emits only a short boolean/digest receipt. A matching hash **does not prove any funds exist**.

The signed report CLI needs three private log artifacts (baseline-log.bin, candidate-log.bin, regression-log.bin), an `EvidenceBundleV1` JSON report with >=2 independent Ed25519 signatures, and an external **trusted-roster.json**. The roster must be obtained from independently authenticated reviewer enrollment and never from the report author:

```sh
node --import tsx scripts/verify-evidence.mjs \
  bundle.json trusted-roster.json ./private-artifacts/
```

It verifies strict report content hashes, signer identity uniqueness, signatures, revoked signers and all private artifact hashes. It never returns a payout authorization, and the tests generate ephemeral signed fixtures rather than checking in secret keys. Reproduce both clean-machine suites with:

```sh
node --import tsx --test \
  scripts/verify-manifest.test.mjs scripts/verify-evidence.test.mjs
```

## Partner credentials and API boundary

The endpoint `GET /v1/partner/bounties` offers the same restricted published, finalized-only projection already exposed by `GET /v1/bounties`. It requires `x-certifiks-api-key`, validates an operator-provisioned `cfk_<43-char-base64url>` token against a **SHA-256 digest only**, and enforces scope `bounties:read` with shared, atomic PostgreSQL **60 requests per minute per key**, expiry <=90 days, active operator membership and immediate revocation.

The migration `supabase/migrations/202610260011_partner_keys.sql` creates the private service-only key ledger and authorization/revocation procedures. No public endpoint issues keys. Operators must generate high-entropy tokens in a secure secret manager, record their digests only in the database following independently authenticated org-owner approval, and deliver the plaintext only to the authorized partner over a protected channel. The backend service-role key must never appear in browsers or partner responses.

Example (illustrative only; use a real server and actual issued key):

```sh
curl --fail \
  -H 'x-certifiks-api-key: <your-issued-key>' \
  'https://<deployed-api>/v1/partner/bounties?limit=10&offset=0&sort=newest'
```

The backend fails closed with `401` for unknown, expired, revoked, malformed or quota-exhausted keys and `503` on database/provider outages. Query state, repository, page and sort are whitelisted. No private organization history, signed artifacts, cash accounting, contributor identities or unverifiable claims are ever exposed through this route.

## GitHub status accuracy

`prepareGitHubCheckV1` creates **only a proposed Check Run payload** for a source-proven, immutable SHA. `pending` is in-progress; `inconclusive` is neutral; `disputed` requests human action. A successful verified claim requires report digest, confirmed independent reviewer quorum, artifact-integrity checks and separately established qualification. The module never calls the GitHub API, merges a PR or authorizes payments. A real check publisher needs an actual CertiFiks-owned GitHub App with `checks:write`, owner consent, installation-scoped token, secure idempotency and persisted signed qualification state.

## Remaining production acceptance

- Actual partner account creation, authenticated org-owner API-key issuance and rotation, revoked-token lifecycle, tenant/user session access control, and real shared PostgreSQL deployment.
- API version compatibility exercised by a separate external partner, typed SDK with pinned releases and credential-scoped private data where consent is independently established.
- Real independently enrolled reviewer public keys, actual retained signed reports and permission-scoped artifact download, including retention and revocation.
- GitHub Checks creation and updating with real app installation permissions, PR-specific SHA tracking, app-event reconciler and human review.
- Real sponsor/developer/payout workflow and finalized on-chain receipt. Nothing here says funds were moved.

Issue #39 must stay **OPEN** until live evidence, production configuration and all acceptance criteria are met.
