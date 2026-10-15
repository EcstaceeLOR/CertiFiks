# CertiFiks immutable GitHub submission and proof — Issue #11

**Date:** 2026-10-15 · **Status:** Implemented local claim/verification primitives; **real GitHub App integration, persistence, reviewer signatures and Portaldot settlement NOT yet available**.

## Security boundary: code revision claim vs. authenticated verification

Two different actions must not be conflated:

1. **Developer claim, authorized on chain:** the wallet that explicitly accepted Issue #10's assignment signs an EVM transaction containing the numeric repository ID, exact PR number, immutable baseline SHA, candidate head SHA, approved test-image digest, off-chain evidence digest and manifest version. The new abstract `BountySubmissionModuleV1.sol` snapshots each attempt and SHA-256 hashes its exact context with chain ID, contract address, bounty ID, attempt number and wallet. It does **not** query GitHub, validate a PR, attest to tests passing, or release money.
2. **GitHub read evidence, authorized off chain:** an authenticated GitHub App installation token accesses exact REST repository, PR and commit resources. `apps/api/src/github/revision-verifier.ts` checks numeric repo ID, the sponsor-pinned coordinates/baseline, exact PR/head SHA, developer GitHub user ID, explicit fork policy, GitHub-reported commit signature and installation repo/read-permission grants. A successful immutable snapshot creates an **unsigned** SHA-256 evidence digest. Future #13 reviewers must independently authenticate/scope/sign an accepted report; the API cannot unilaterally approve a bounty.

**Critical integration requirement:** #20 must supply the real installation access token **and** the trusted permission/installed-repository snapshot from GitHub App APIs, never a browser field. #23 must bind the authenticated GitHub PR-author user ID to the wallet that accepted the bounty. Tests using local mock snapshots **do not establish a live installation**. No route to accept client-supplied `InstalledRepositoryPermissionsV1` is exposed.

## 1. Exact on-chain snapshot fields
- Bounty ID and monotonically numbered attempt ID (first = 1; retries increment).
- Developer wallet authenticated by `msg.sender`, contract address and pinned chain ID.
- GitHub **numeric repository ID** from immutable funding terms (#9) and exact PR number. The funded manifest now commits explicit fork, signed-commit and target-base-branch policies under `acceptance.githubPolicy`.
- Funding terms' immutable 20-byte baseline Git SHA-1 and 32-byte policy/manifest SHA-256.
- Exact 20-byte submitted head SHA-1, 32-byte image digest and 32-byte externally supplied evidence digest.
- Manifest version must match the funding terms **v1**; zero/unchanged head or empty image/evidence is rejected.
- `attemptDigest = SHA256(abi.encode("CertiFiks:github-attempt:v1", expectedChainId, contractAddress, bountyId, attemptId, submittingWallet, Candidate))`.
  Solidity's ABI struct encoding fixes field widths/order; **this is a new GitHub-claim envelope**, distinct from the standard cross-language *signed reviewer attestation* vector in Issue #5. Only a future trusted verifier may bridge them. Do not pass the claim digest off as a reviewer signature or a domain-separated EIP-712 typed signature.

All old attempts persist as a per-bounty indexed, immutable snapshot. A force-push to the branch does not rewrite prior on-chain head SHA; when the latest GitHub API PR points elsewhere, the off-chain verifier rejects it as `STALE_COMMIT`. Archived evidence must be independently attested before an old SHA can remain eligible after branch deletion.

## 2. Submission/resubmission authorization
- First submission uses `submitCandidate`, only by a wallet in Issue #10's `Accepted` state, only on the expected chain and before the funded submission deadline. It **locks the assignment** to `Submitted`, preventing sponsor replacement or no-submission expiry.
- `resubmitCandidate` fails unless the immediately preceding attempt received a **nonzero, unspent explicit review authorization** through the internal hook `_authorizeRetryFromReview`. Only a future #13 verified dispute/reviewer component may invoke this hook; there is **no publicly callable sponsor/admin retry permission** in production contract source.
- A retry must use the original PR number and pinned baseline/manifest, a new head SHA, the same accepted developer and a new attempt sequence. Previously used head SHAs cannot be replayed in that bounty.
- The only public `simulateReviewedRejection` is in a Foundry **test harness**, guarded by its test-controller. It is not deployable product code and is not real review evidence.
- The current policy permits retries **only before the original funded submission deadline**, and cannot edit the immutable acceptance criteria. Sponsor-requested changing tests requires terminating under legitimate future safe refund procedure and funding a new bounty.
- Future #14/#15 adjudication must decide whether a timely submitted developer receives extra review-time resubmission rights after the original deadline. That economic policy is *not* silently decided in #11.

## 3. GitHub App and identity validation

`verifyGitHubRevisionSnapshotV1` requires:
- Exact numeric target repo ID (repo renames/transfers do not change identity), plus the original funded full name. Any changed path requires **new sponsor-approved funding terms**, not automatic target reassignment.
- Exact PR number, base repo ID, latest base SHA/head SHA, **sponsor-approved base branch**, PR open state and PR author user ID matching a previously bound GitHub + wallet account.
- Fork PRs only if an explicit funded sponsor policy permits them, with a non-deleted and authenticated fork repository ID.
- Contents **read** and Pull requests **read** installation permissions, with the target numeric repo included in the installation scope. Permission context must come from trusted GitHub App integration, not a UI form.
- GitHub-reported signature verification for the requested candidate commit **when policy requires it**. When not required, unsigned commits can be accepted but their status remains in the evidence record.
- Strict lowercase 40-char Git commit SHA-1, nonzero safe numeric IDs and lowercase SHA-256 manifest/image values; rejection is explicit, never a default success.
- Read-only API endpoint host hardcoded as `https://api.github.com`; `GET /repos/{owner}/{repo}`, `GET /repos/{owner}/{repo}/pulls/{number}`, `GET /repos/{owner}/{repo}/commits/{headSHA}`; redirect disabled; token never logged. The caller must isolate the token from untrusted PR runner and the browser.

**What the validator does NOT prove:** cryptographic collision resistance of legacy Git SHA-1, verified contents of all PR parent commits, a tested patch, arbitrary GitHub provenance authenticity from an unsigned JSON object, or reviewer independence. GitHub Git SHA-1 is a platform identifier with known cryptographic limitations; the identity/manifest/image/evidence SHA-256 bindings and future signed reviewer reports reduce substitution risk but cannot turn it into a mathematical proof of correctness.

## 4. Real public GitHub source sanity check (read-only, 2026-10-15)

Via authenticated GitHub repository/PR reads (not a CertiFiks App installation), we observed:
- [CertiFiks repo](https://github.com/EcstaceeLOR/CertiFiks): numeric repository ID **1420771959**, public; canonical full name `EcstaceeLOR/CertiFiks`.
- [PR #56](https://github.com/EcstaceeLOR/CertiFiks/pull/56): numeric PR ID **4876328862**, PR number **56**, target repo ID **1420771959**, base SHA `d7a1a7f75512aac7fb488bb8329f1b091b66fab9`, head SHA `5caff6398a601b4179a343ace1a78a61b13b6f17` at observation, author numeric GitHub ID **202467598**. Same-repository PR at time of observation.

This is a **public API observation**, not a sponsor-authorized test fixture, consented external customer pilot, commit signature verification, live token validation, or Portaldot contract proof. Never assume those branch SHA values remain current; re-query and fail closed when stale.

**Protocol update in Issue #11:** v1 now requires `acceptance.githubPolicy`, with `allowForkPullRequests`, `requireVerifiedCommitSignature`, and `baseBranch`. The canonical example hash was updated to `0xddb62523e13ee6bc1a60f7921b171cccd3cd62cf1c4af7c9681c27904c47bd44`. This happened before any real funding or deployment; already funded policies can never be retroactively changed. Backend #20/#23 must hydrate these values from the exact committed manifest, not user query parameters.

## 5. Threat scenarios and tests

| Threat | Expected safe behavior | Evidence |
|---|---|---|
| Forge head SHA or PR # / wrong base SHA | Off-chain GitHub identity rejects stale, missing or unrelated PR; on-chain bounds original source policy | API tests + Foundry tests |
| Mutate funded manifest, repo, image or version | On-chain rejects mismatching fields; old attempts cannot be rewritten | Foundry malformed input cases |
| Replay first attempt or same head | Reject duplicate and require new review-authorized versioned attempt | Foundry replay and retry tests |
| Client impersonates developer | Only accepted wallet signs submission, authenticated GitHub PR author's user ID must match backend wallet binding | Foundry wrong wallet + API user test |
| Fork repo, deleted fork, transferred repo or lookalike owner | Enforce explicit fork policy, numeric owner ID, fail closed on rename/transfer or deleted source | API fork and transfer tests |
| GitHub App token lacks repo permission / expired | Reject 401/403 and unscoped access; no fabricated review result | API auth tests |
| Signed-commit policy not met | Reject GitHub-reported unverified commit | API signature-policy test |
| Force-push / deleted branch after original report | Original on-chain attempt remains immutable; live PR verification rejects new head; independent evidence required to uphold prior archived report | Foundry historical attempt + API stale-head test |
| SHA-1 collision / provenance confusion | Neither Git SHA nor PR number alone releases funds; pin chain, contract, manifest/test image, SHA-256 evidence and independent reviewer attestation | Cryptographic binding tests #5/#11; deeper review #41 |
| Project money moves on submission | Must remain conserved; no payable settlement action triggered | Foundry reserved-balance tests |

## 6. Next integration gates (don't falsify Issue #11 completion)
- #20 GitHub App authorization/installation permissions and ref validation from real trusted GitHub.
- #23 bind wallet to GitHub OAuth user ID with signed anti-replay challenge; cross-team RBAC.
- #24 durable evidence history, atomic insert/uniqueness, artifact access and retention.
- #13 authentically signed verifier-quorum reports, including review-authorization of resubmission.
- #18 qualifying Portaldot V3 contract deployment, genuine chain/genesis/tx evidence.
- #25 trusted baseline-fails/candidate-passes runner with archived independently reproducible evidence.
- #40 end-to-end real first-submission/force-push/retry flow on an actual repository.
- #41 independent security review before handling mainnet user funds.

**Decision:** Local source, contract and security-negative tests are concrete engineering work; **do not merge this as a finished product feature or close #11** before external GitHub identities, reviewer signatures and E2E proof are truly integrated. Store the implementation in a **stacked draft PR based on #10**.
