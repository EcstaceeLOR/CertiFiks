# Issue #40 — Live end-to-end release evidence intake

**Current release decision: BLOCKED. This is not a live Portaldot deployment, accepted audit, successful real-money payout or independent E2E proof.**

This PR adds a strict local integrity intake for *externally produced live evidence*. It cannot produce, simulate, authenticate or certify real-world receipts. It intentionally emits `productionApproved: false` and `verifiedOnChain: false` even for a structurally complete evidence bundle. No mocked scenario in CI authorizes release.

The intake requires a known immutable repository commit, independently approved chain name/genesis/chain ID URL, three distinct GitHub identities (sponsor, contributor and clean-room replay operator), two distinct verifier organizations, real explorer references for funding, withdrawal and refund, exact integer atomic-unit conservation, and every one of the 20 positive and negative journey scenarios in Issue #40. It walks a private artifact inventory, refuses symlinks, path traversal and duplicate names, checks each SHA-256 and byte size, and binds every scenario and transaction to local bytes. It explicitly refuses example.com, localhost or synthetic outcome labels as proof.

To validate a separately collected **real** evidence bundle:

```sh
node scripts/quality/check-live-e2e-evidence.mjs /absolute/private/evidence/intake.json
```

The schema is fully specified by `scripts/quality/live-e2e-evidence.mjs`. The evidence directory should contain the receipts, GitHub/webhook traces, runner logs, screenshots, signed review artifacts and redacted video, each listed with a relative `path`, lowercase 64-character `sha256`, `sizeBytes` and a supported `kind`. The intake is intentionally not published as web data. Never include passwords, signing keys, tokens, undisclosed sponsor tests or third-party personal data.

The CI job `node --test scripts/quality/live-e2e-evidence.test.mjs` is a *negative security gate*. It proves that an incomplete set, altered artifact, fake transaction, wrong ledger balance, path traversal and unapproved outcome are rejected. Its synthetic fixture returns `STRUCTURALLY_COMPLETE_UNVERIFIED`; that is an **explicit denial of production approval**, never a completed user journey.

## What would actually close this P0 issue

1. Obtain organizer-approved Portaldot chain and runtime identity from an independently verifiable official source. Verify the chain actually supports the chosen contract execution format.
2. Register and install the actual CertiFiks GitHub App with user-approved repositories, deploy the isolated runner, and migrate the live database.
3. Complete funding, assignment, before/after regression, independent signed attestations, review, payout and refund **using real services, two distinct participants and finalized verified transactions**.
4. Fault-inject wrong-network, unfunded requests, reorg, tampered manifests, webhook retries, malicious worker and wallet rejection. Prove zero false payouts or repeated settlement.
5. Record redacted authentic screenshots, receipts, hashes, reviewer attestations, source commit, full money conservation, and independent replay on a clean second machine.
6. Have a separate trusted reviewer **independently verify** the source chain/GitHub identities and actual on-chain state. The local intake cannot perform that verification and **must not be promoted to approval** without explicit external evidence and review.

**Issue #40 stays OPEN.** Green CI, correct document hashes or an intake report are necessary but not sufficient proof that this end-to-end product exists. The goal remains a complete production-grade product rather than a prototype with green statuses.
