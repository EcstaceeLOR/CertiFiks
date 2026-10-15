# Issue #19: sponsor manifest admission and conformance

Status: internal protocol validation only. Not real verification of a fix or production escrow release.

## Admission contract

The exported @certifiks/shared admitCommittedManifestV1(rawCanonicalJson, expectedDigest) entry point enforces:

1. A lowercase SHA-256 commitment supplied by a trusted finalized on-chain state reader, never from the manifest submitter.
2. Raw bytes exactly match canonical RFC 8785 JSON; duplicate keys, whitespace and alternate encodings fail before hashing.
3. A strictly validated v1 bounty-manifest JSON schema with no unknown fields. Repository numeric ID, pinned base SHA, baseline/candidate tests, regression suite, image digest, offline runner policy, GitHub policy, amounts, deadlines and verifier policy are required.
4. A semantic check that quorum does not exceed eligible reviewer roster length.
5. A constant-time comparison of the 32-byte expected commitment with SHA256 of the manifest domain prefix plus canonical UTF-8 bytes.
6. Explicit separation from actual GitHub ownership, signed reviewer attestations, hidden-test privacy, runnable evidence, deployment and payout eligibility.

## Reproduce

- npm ci
- npm run test --workspace=@certifiks/shared
- python -m unittest discover -s research/reference-model -p 'test_*.py' -v
- python research/reference-model/protocol_hash_reference.py

Cross-language conformance fixtures: protocol/vectors/manifest-v1.json and protocol/vectors/manifest-tamper-v1.json. TypeScript and independent Python both check the published gold digest and independently prove tampering of repository, baseline, acceptance tests, failure fingerprint, environment image, runner/network policy, GitHub branch/fork policy, reviewer roster/quorum, fallback policy, deadlines, amount and version changes the digest.

Python reference limitation: only the published ASCII/I-JSON subset; it is not general RFC 8785 Unicode and floating-point compliance. Solidity stores the immutable bytes32 hash and does not parse JSON.

## Still needed to fully close Issue #19

- Actual baseline failure/candidate success and regression runner receipts with signed executable provenance, artifact hashes, timestamps and retention.
- Hidden sponsor test commitments with encrypted disclosure to trusted runners, availability/audit flow and protections against secret leakage to developers.
- Real deployed runtime contract and indexer reconciliation proving that the same funded digest gates authorization.
- Authenticated reviewer identities, context-aware chronology/quorum checks and end-to-end replayable real bug-fix evidence.

Keep Issue #19 OPEN until production acceptance is genuinely complete.
