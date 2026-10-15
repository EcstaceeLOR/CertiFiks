# CertiFiks founder discovery and first-pilot validation

**Research date:** 2026-10-15
**Issue:** #7
**Status:** RESEARCH COMPLETED IN PART; **human demand and consent NOT VALIDATED**. This file intentionally distinguishes observed public facts from hypotheses and interviews.

## Executive decision
Do **not** claim product–market fit, paid customers, maintainer adoption or an approved pilot. Competing tools already offer GitHub issue bounties, USDC escrow and merge-based payouts. CertiFiks has a plausible **narrower** feature thesis: payment for a *precommitted, reproducibly verified defect correction* with a bounded dispute process, rather than acceptance based solely on merging a PR. That differentiation is a **hypothesis** and introduces more trust, expense and time than existing services. Go to a **no-real-value pilot discovery stage**, not a general-market launch.

**Actual researcher-recorded interviews:** 0/3 maintainers, 0/3 contributors.
**Explicit consenting pilot maintainers:** 0/1.
**Independent local reproductions of candidate defects:** 0/2.
**Funds, wallets, GitHub Apps granted by external projects:** none.

Do not close #7 until the missing external evidence is honestly obtained; never paraphrase public issue text as an interview.

## Publicly verified open issue candidates (NOT yet pilot partners)

### A. OpenZeppelin Contracts — issue #6805 (first choice if maintainers approve)

- **Repository:** https://github.com/OpenZeppelin/openzeppelin-contracts
- **Issue:** https://github.com/OpenZeppelin/openzeppelin-contracts/issues/6805
- **Observed on 2026-10-15:** Issue is **OPEN**; labelled hardhat-plugins. At discovery time no issue comments were returned by GitHub; current assignment/PR activity requires a fresh check before outreach. No engagement/consent has been recorded.
- **Problem as independently described by reporter:** The internal `hardhat-solidity-docgen` config hook assigns mutable references to shared defaults or a caller-owned docgen object, then writes `root` and `sourcesDir` into that reference. Subsequent configurations inherit stale fields, while a frozen caller object throws.
- **Why suitable as a controlled pilot hypothesis:** Has an exact GitHub code location, a minimal in-process reproduction using a fake continuation (report says no Hardhat install necessary), no wallet and no real production funds needed. Strong before/after acceptance condition: repeated independent config resolution leaves both `defaults` and the caller's `userDocgen` unchanged, including frozen inputs; real generated output is still correct.
- **Potential baseline-to-candidate test:** Pin a maintainer-approved commit SHA, write a unit fixture loading the original hook/defaults, prove failing assertion against baseline; apply isolated candidate patch; same immutable harness passes and unrelated docgen tests remain green. Include a second project root to detect leaked shared configuration.
- **Risks:** Maintainer may not want an external workflow; the issue may already be in progress elsewhere; patch scope may be too small to justify verification and escrow overhead. Tool must not publish a false guarantee of general code correctness.
- **Verification status:** Issue text inspected; baseline test **not run** by CertiFiks; maintainer **not contacted/consented**.

### B. OpenEverest — issue #3357 (alternative, Go/Helm-backed)

- **Repository:** https://github.com/openeverest/openeverest
- **Issue:** https://github.com/openeverest/openeverest/issues/3357
- **Observed on 2026-10-15:** Issue is **OPEN**, labelled `bug` and `needs-triage`; no comments returned from GitHub at discovery. No pilot consent.
- **Reported defect:** `pkg/kubernetes/object.go` / `getObjects` treats malformed YAML decode errors as EOF and `ApplyManifestFile` returns no error for invalid input. Reporter supplied a `[]byte(":")` reproduction, plus a valid-then-invalid multi-document case; says they ran `go test -count=1`.
- **Acceptance hypothesis:** A deterministic test checks malformed first document and valid-then-malformed manifest both return appropriate errors; genuinely empty input still terminates normally; normal valid multi-doc manifests still work. No real Kubernetes installation or cloud credentials permitted in runner; pin test fixtures.
- **Risks:** Some tests may depend on a Kubernetes cluster, heavier setup and reviewer cost; maintainer may reclassify/close bug; potentially incomplete report. Never run a production cluster or mutate an external deployment as part of pilot.
- **Verification status:** Issue and reporter's claim verified in public tracker, **not independently reproduced** locally, not triaged/authorized by maintainers.

### C. Reserve options, not active selections

- https://github.com/OpenZeppelin/openzeppelin-contracts/issues/6802 — another no-funds testable docgen memoized getter exception, **same maintainer organization**, so not an independent second maintainer.
- https://github.com/openpi-dev/openpi/issues/746 — repro for session-change pivot race, but a contributor **already publicly claimed the work** in issue comments; **do not approach as an unclaimed pilot**.
- https://github.com/ZecHub/zec-bounties/issues/159 — real past payout idempotency issue, **closed** with work in progress/PRs; useful pain evidence, **not an open bug pilot target**. Payout flows must never be tested with real ZEC without explicit approval.

## Pilot hypothesis and minimum experiment

**Hypothesis H1:** At least one maintainer with an existing reproducible software defect will choose a signed baseline-fails/candidate-passes review flow when offered beside GitHub's current merge workflow, and accept the extra reviewer challenge delay for higher confidence in payment conditions.

**Experiment:** Sponsor chooses an **already-open, unclaimed**, self-contained bug; confirms issue ownership and consents in writing; contributors choose to participate in a free dry run. Record exact numeric GitHub repository ID, immutable base SHA, deterministic defect reproduction, image digest, acceptable regression tests and fixed approval/dispute deadlines. Contributor submits a pinned patch SHA; two genuinely independent test reviewers inspect pre- and post-change evidence. Show escrow as **simulated only**, because Portaldot V3 deployment and security audit are incomplete; do not solicit funds or infer real settlement.

**Minimum completion criteria:**
1. At least **three real, consented maintainer interviews** and **three distinct potential paid contributors**; anonymized notes with dates and verbatim *consented* quotes where allowed.
2. At least one maintainer independently selects the exact pre-existing bug, approves before/after test rules, and gives unambiguous written permission for a **no-money** pilot.
3. Two real public repos have candidate bugs and reproducible test plans; confirm their open/unassigned state **at pilot start**, not only today.
4. Real evidence demonstrates baseline fails and candidate passes **without altering acceptance criteria after locking**; independent reviewer names/consent are recorded internally.
5. At least one interviewed maintainer explicitly answers whether they'd use the product again and what they would pay/avoid (time, cost, chain, escrow, private code).
6. If consent, interview or reproducibility criteria aren't met, record a **no-go / revise-market-thesis** outcome and do not misrepresent a simulated demo as pilot validation.

## Research insights to challenge in interviews

- **Owner pays for confidence vs speed:** A build can pass irrelevant tests; CertiFiks may offer a narrower evidence review, but independent review adds a queue and trust authority.
- **Bug-fix escrow may not be requested:** Maintainers may simply reward merged work through existing bounty services; ask whether they'd pay the premium.
- **Chain preference is unknown:** Any founder assumption that OSS maintainers want Portaldot, POT units or wallets must be tested; survey fiat, stablecoin, and no-wallet preferences without forcing one.
- **Permission and privacy:** Some code is private and cannot run in third-party sandboxes; measure readiness to grant read-only GitHub App permissions and whether redacted logs suffice.
- **Dispute liveness:** One silent arbitrator can freeze funds indefinitely in the historical contract. We must design and test enforceable fallback BEFORE a funded pilot.
- **Contributor rights:** Timely submitted work must not be lost to verifier outages. Ask whether applicants will accept challenge periods and independent-review fees.

## Validation scoreboard (do not invent results)

| Evidence item | Target | Actual now | Next responsible step |
|---|---:|---:|---|
| Maintainer discovery interviews | 3 | 0 | Request interviews using respectful opt-in invitation |
| Contributor discovery interviews | 3 | 0 | Recruit contributors independently of selected repo |
| Consent to pilot | 1 | 0 | Maintainer opts in to no-funds workflow and test digest |
| Open bug targets located | 2 | 2 public reported candidates | Recheck status and maintainer fit |
| Reproduced failing baseline tests | 2 | 0 | Clone exact revisions, run sandbox fixtures |
| Positive reviewed bugfix pilot | 1 | 0 | Can start only after consent and security isolation |
| Verified Portaldot V3 contract | 1 | 0 | Issue #18 remains blocked |
| Evidence of paid transaction | 0 required for no-funds pilot | 0 | Do not attempt real deposits |

## Outreach constraints and consent

Don't bulk-post generic project advertisements to unrelated issues or claim a maintainer recruited just because their public issue exists. Any recruitment must identify the contact channel and be respectful of repository contribution guidelines. The user should review outbound messages before posting as founder; no third-party emails/comments/DMs have been sent in this issue. Private contact details and raw consent logs are not to be committed to a public repo.

See [research interview guide](./INTERVIEW_GUIDE.md) and [competitive gap matrix](./COMPETITOR_GAP_MATRIX.md).
