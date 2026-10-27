# Issue #19 — Cross-language Unicode canonical manifest conformance

**Status:** offline hashing conformance; not a test runner, funded escrow proof, verified GitHub installation, release approval, or signed attestation.

All CertiFiks v1 manifests are committed as **SHA-256 of the domain-prefixed RFC8785 canonical JSON bytes**:

```
SHA256(UTF8("CertiFiks:manifest:v1\\0") || canonical_json_utf8)
```

The domain includes an actual NUL byte, **not** the two literal text characters backslash and zero. Numeric repository IDs, code base SHAs, funding terms, test fingerprints, allowed GitHub policy, environment image digest and independent reviewer selection are immutable through this commitment and must match a **separately trusted, finalized chain value**; the expected digest must not be copied from the untrusted downloaded manifest.

Previously the Python reference vector used ASCII keys and ordinary `sort_keys=True`, which sorts Unicode by scalar value. JavaScript's RFC8785 key order is based on **UTF-16 code units**, so a key in the supplementary plane (e.g. an emoji) sorts before U+E000 (a Basic Multilingual Plane private-use code point), while ordinary Python sorting puts them in the opposite order. This can produce a dangerous false cross-language mismatch in independent verifier tooling.

The corrected `canonical_ijson_v1` implementation:
- Sorts all object keys by strict UTF-16 big-endian code units, matching ECMAScript key comparison.
- Uses exact UTF-8, unnormalized Unicode strings and JavaScript-compatible control-character escaping for the v1 I-JSON subset.
- Rejects nonstring map keys, unpaired Unicode surrogates, unsafe JSON integers above `2^53 - 1`, floats (including NaN) and unsupported types. **It does not claim to be a general floating-point RFC8785 implementation.**
- Retains the same already-published ASCII manifest golden digest so existing funded policies do not change.

The new `protocol/vectors/manifest-unicode-v1.json` is a **synthetic cryptographic vector, not a production-valid bounty manifest**. It contains supplementary-plane, BMP and accented keys and escaped control characters with an independently computed digest. Both TypeScript and Python test that exact digest and reject tampering; the Python unit tests additionally require unsafe inputs to fail closed.

This work strengthens the hash format used by Issue #19 and the cross-language reproducibility requirements, but **does not** prove funded chain state, repository authorization, signed reviewer independence, production artifact retention or real before/after test execution. Those controls require their own evidence and operational acceptance before Issue #19 can close.
