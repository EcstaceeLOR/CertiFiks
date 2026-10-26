# Issue #41 — Independent security-review signature and release integrity gate

**Release status: BLOCKED.** The CertiFiks repository has not been independently audited, and this gate does not pretend otherwise.

The Node.js verifier in `scripts/security/independent-review-gate.mjs` checks the *cryptographic integrity* of a canonical report signed by a separately approved Ed25519 organization. Its trusted public key, expected release commit and approved reviewer organization must be provisioned **out of band by a release security authority**. The report is forbidden from installing its own trust anchor or changing the pinned commit.

The signed report must cover: smart contracts, GitHub authentication and webhooks, API tenant isolation, verifier sandboxing, wallet/settlement, and private evidence access. It binds the release commit, reproducible source-archive digest, SBOM digest, CI test run digest, secure review methodology URL and independent retest URL. Every critical/high finding must be `remediated_retested` with a pinned test artifact; unaudited risk acceptance for a critical/high finding blocks the gate. The validator rejects noncanonical report JSON, signature tampering, untrusted keys, malformed findings, fake example URLs, missing scopes and a mismatched commit.

To validate **real externally provided** security review documents:

```sh
node scripts/security/check-independent-review.mjs \
  /secure/report.canonical.json \
  /secure/report.sig \
  /secure/trusted-reviewer.pub.pem \
  VERIFIED_RELEASE_COMMIT_SHA \
  approved-independent-reviewer-organization
```

Test the negative security boundaries without fabricating actual audits:

```sh
node --test scripts/security/independent-review-gate.test.mjs
```

The green local result says `verifiedReviewerSignature: true` and `productionApproved: false`. It authenticates a *statement*, not its technical quality, third-party independence, proof of sandbox escape resistance or verified deployment. Review the actual audit scope, identity, source-to-bytecode matching, SBOM and exploit retest outputs using a separate security authority before any release approval. Tests use synthetic local keys and never claim an independent external audit.

## What actually blocks closing Issue #41

1. Obtain an independent smart-contract and application security review, including fuzzing, Slither/SAST, wallet signing, webhook authentication, GitHub App permissions, SSRF, IDOR, RLS, sandbox escapes and contract accounting.
2. Resolve **all high/critical findings**, then obtain independent retests linked to code commits and reproducible test artifacts; retain medium/low risk register and sign-offs.
3. Cross-check SBOM/lockfiles, release source hash, signed artifacts, deployed bytecode and actual chain runtime.
4. Complete real end-to-end security fault injection for Issue #40; pass both money-path and private-data denial tests against live services.
5. Verify an authorized security release sign-off from a reviewer who was not the author or fund custodian and publish redacted evidence without exposing secrets.

Issue #41 remains **OPEN**. Real fund custody must stay disabled until all independent review and release gates are satisfied.
