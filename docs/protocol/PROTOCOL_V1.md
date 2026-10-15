# CertiFiks Protocol v1 — normative commitments and document identity

**Status:** SPECIFIED, NOT DEPLOYED · **Version:** 1 · **Issue:** #5 · **Date:** 2026-10-15

## 1. Purpose and explicit trust boundary
Define exactly which GitHub revision, bounty terms, CI image, results, verifier identities and chain context are cryptographically bound to an authorization. This does **not** implement independent code verification or cryptographically guarantee a software defect was fixed.

- On-chain custody and payout eligibility must eventually be enforced by approved Portaldot VM-specific contracts (#9–#18).
- A report signature is evidence a registered, non-conflicted organizational signer made a claim. It is not objective proof the claim is true.
- The backend and untrusted runner may store/run evidence but cannot unilaterally authorize escrow release.
- The V3 chain ID, contract locator, signature encoding, finalized-block policy and specific arbitration fallbacks remain blocked until independently confirmed in #18/#13/#14.

## 2. Versioned schemas and examples
Authoritative JSON Schema Draft-07 files live in packages/shared/src/schemas/v1:
- bounty-manifest.schema.json — committed sponsor terms, numeric GitHub repository ID, fixed base commit SHA, trusted acceptance tests, pinned image digest, reward as decimal atomic-unit string, time windows and organizational verifier quorum.
- candidate-attempt.schema.json — bounty/attempt identities, assigned account, pinned repository/base/head SHAs, manifest digest, submission time.
- verification-report.schema.json — baseline/candidate results, regression status, image/result digests, signer identity, scheme, signature and expiry.
- dispute-case.schema.json — challenger/attempt identity, immutable reason/evidence hashes and response/escalation windows.
- chain-event.schema.json — typed event-name envelope bound to chain/contract/transaction/block/log index, with finality indicator. **Specific contract ABI/event payload types remain future implementation work** (#9–#17/#27); do not accept untyped payload fields as payout authority.

Each schema enforces version exactly "1" and rejects undeclared fields. Economic values and potentially large IDs are decimal strings, not unsafe JavaScript floating-point numbers. Git SHAs must be lower-case 20-byte hexadecimal. Content/manifest digests are lower-case SHA-256, 32 bytes and prefixed with 0x.

Validation is strict Ajv in packages/shared/src/validation.ts with no automatic coercion/default/removal. *Schema-level validation cannot replace context validation*: for example, verifier quorum must be no greater than the number of eligible independent organizations; deadlines must be chronological; chain/contract IDs must match the true deployed contract; signatures must be verified in #13; and actual GitHub facts must be independently fetched in #20.

## 3. Raw manifest canonicalization and hash
Algorithm: RFC 8785 canonical JSON (JCS), encoded UTF-8, prefixed with the ASCII bytes "CertiFiks:manifest:v1" followed by a **NUL (0x00)** byte, then SHA-256. Return lower-case 0x-prefixed 32-byte digest.

SHA256(domain || JCS(manifest)).

- The shared implementation uses the pinned npm canonicalize package and rejects non-object documents.
- **Never verify signatures against arbitrary JSON.parse output from unauthenticated raw bytes.** parseCanonicalManifestV1 rejects all raw text not byte-for-byte identical to canonical JCS serialization. That rule catches duplicated keys, noncanonical whitespace and alternate escape encoding.
- A platform must validate schemas and identity constraints **before** accepting the manifest commitment. The Solidity code stores/verifies bytes32 commitments; it does not parse JSON.
- Reference canonicalization vector protocol/vectors/manifest-v1.json is a standards-compatible ASCII/I-JSON subset. The Python reference demonstrates this subset only, not general Unicode/floating-point JCS conformance.

## 4. Attempt attestation digest — all fields required, fixed-width
On-chain/off-chain attestation signers MUST hash a byte string with the following exact fixed-width field order.

| Order | Field | Encoding | Bytes |
|---|---|---|---|
| 0 | domain = "CertiFiks:attempt-attestation:v1" + NUL | UTF8 ASCII | 33 |
| 1 | chainGenesis | raw bytes32 | 32 |
| 2 | contractLocatorHash | raw bytes32 | 32 |
| 3 | bountyId | uint256 big endian | 32 |
| 4 | attemptId | uint64 big endian | 8 |
| 5 | repositoryId | uint256 big endian | 32 |
| 6 | baseCommitSha | 20 raw Git SHA-1 bytes | 20 |
| 7 | headCommitSha | 20 raw Git SHA-1 bytes | 20 |
| 8 | manifestDigest | raw bytes32 SHA-256 | 32 |
| 9 | imageDigest | raw bytes32 SHA-256 | 32 |
| 10 | resultDigest | raw bytes32 SHA-256 | 32 |
| 11 | expiryUnix | uint64 big endian | 8 |

AttestationDigestV1 = SHA256(concatenation of all rows exactly as above). No delimiters other than the fixed domain prefix, no JSON encoding of numeric fields, no decimal string bytes and no missing fields.

**Chain identity:** chainGenesis identifies a verified genesis hash of the intended runtime; **contractLocatorHash** is an immutable domain-separated hash of the full deployed contract locator (including VM namespace, chain context and contract address). The canonical locator derivation and wallet chain acceptance are **blocked** until actual V3 deployment (#2/#18). For V1 hash vector the two 32-byte identities are synthetic constants, *never a production chain binding*. A verifier must compare supplied identities to approved on-chain deployment metadata and not merely check hash format.

**Cross-language:** TS library packages/shared/src/commitments.ts, independent Python research/reference-model/protocol_hash_reference.py and Solidity library contracts/src/ProtocolCommitmentV1.sol use exactly these bytes. Published deterministic fixtures under protocol/vectors are asserted in CI by TS, Python and Foundry. This tests equality of hashes, NOT authenticity of claimed results.

## 5. Attestation signing and reviewer independence
Protocol v1 distinguishes: manifest digest; attempt digest; runner result digest; eligible reviewer *signature over the attempt digest*; quorum decision; final on-chain credit.

- Each signer organization must be admitted to the disclosed permissioned verifier registry, have a registered key and be conflict checked against sponsor/developer/arbitrator beneficial ownership.
- At least two independently enrolled organizational controllers must attest the **same** valid attempt binding and compatible evidence verdict. Two wallets under a single organization do not count.
- Domain-separated report hashes and nonces are not a substitute for checking signature validity, enrollment, expiry, chain, attempt number and final on-chain state.
- Authentication scheme, signature byte-level encoding, governance and contract reconciliation are formally assigned to #12/#13; the v1 schema enumerates proposed secp256k1/ed25519 formats but does NOT certify validation.
- Positive quorum **opens a time-bounded challenge**, it does not immediately pay.

## 6. Completion / failure states
No schema, API or report success status moves money by itself. See [all transition and deadline cases](./TRANSITIONS.md), [errors/events](./ERRORS_AND_EVENTS.md) and [architecture decisions](../architecture/DECISIONS_V1.md). Funds may settle only by an authorized contract state that meets immutable terms, review/challenge and finality requirements. **No public funds until the unresolved all-arbitrators-unavailable fallback is resolved and tested** (#14/#15).

## 7. Implementation-status disclosure
- Versioned schemas, typed hashing functions, illustrative API types and cross-language fixtures are *real testable code* under this issue.
- The public /v1 OpenAPI methods are **not implemented endpoints**. They specify a future API; #26 implements them and #20/#23 provides real GitHub/wallet identity.
- The historical escrow in contracts/src/CertiFiksEscrow.sol remains unsafe; the new hash library is only a pure conformance reference, not a drop-in security fix.
- No V3 contract deployed or on-chain attestation signature verified in this issue.
