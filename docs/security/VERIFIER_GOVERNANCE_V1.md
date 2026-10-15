# CertiFiks reviewer identity and governance policy v1

**Issue:** #12 · **Date:** 2026-10-15 · **Status:** local tested permissioned registry only, no approved external reviewer organizations or authenticated production jobs. **Not a security audit.**

## Trust choice

Start with **named, vetted, permissioned reviewer organizations**, publicly disclosed capability and conflicts policies, and cryptographically bound wallet-signed job evidence. **NOT trustless or decentralized verification.** Enrollment is a centrally governed act; no smart contract can independently prove beneficial ownership, corporate independence, or that someone tested a fix. Two EOAs do not prove two organizations. The starter test addresses/org IDs are synthetic and do not represent real people.

**Solo founder clarification:** CertiFiks remains a solo-built startup. Independent reviewer organizations are **eventual participants in the verification market**, not employees, cofounders, or extra software builders. Real company admission is a future operational dependency, not a condition to continue writing backend and contract code.

## Implementation and issuance

- `contracts/src/VerifierRegistryModuleV1.sol` is **abstract** and extends #9 funding, #10 assignment and #11 exact submission. It has no public funding or payment entrypoint.
- `registryGovernance` is a single, immutable governance wallet, selected when the future real contract is deployed. Today this is a **centralization and admin-compromise risk**. A secure multisig and independently published admission policy should be considered during #41 security/governance review. Do not equate a governance wallet with an independent admissions board.
- Governance registers an organization under a never-reusable `bytes32 organizationId`, a **controller wallet**, a **current signing wallet**, and nonzero SHA-256-like commitment fields representing identity dossier, technical capability profile and conflict disclosure.
- The controller separately signs an **activation** transaction. A merely registered, inactive organization cannot accept assignments.
- Each wallet used as controller or signer is permanently linked to exactly one on-chain organization ID, even after signer rotation or revocation. **A new wallet under the SAME organization is not a second reviewer**. Organizational independence across different wallet controllers still requires human checks; identity attestations alone do not solve Sybil attacks.
- At funding, the sponsor precommits an ordered organization roster and quorum using `SHA256(abi.encode('CertiFiks:verifier-roster:v1', uint8(quorum), bytes32[] ascendingOrgIds))` as `verifierPolicyDigest`. The sponsor must register the **same exact sorted roster and quorum once**, before any developer accepts an assignment. A different organization, reordered IDs, duplicate IDs, reduced quorum or arbitrary governance-selected reviewer **cannot substitute** the funded policy; the registry checks `isCommittedReviewer` before granting any job. This commitment is a Solidity-native encoding; off-chain JS canonicalization/manifest indexing must be tested against a signed vector in #13/#20. If the sponsor miscomputes this hash, funds would be unassignable: build preflight and safe refund paths before real funding (#14–#16/#32).
- Registry governance authorizes specific jobs for the exact current immutable bounty attempt, **limited to the sponsor-committed roster**. Only active, uniquely enrolled, non-conflicting organizations can be assigned.
- Only the current enrolled signer for the pinned **signer epoch** can accept a job and submit a **wallet-signed, single-use report digest** before the funded verifier timeout. This is *not* a passing test, signed off-chain attestation, consensus, or payout authorization. Formal signature validation and positive/verdict quorum are #13.
- Organization activity counters are **accepted jobs and reported evidence**, never an automatic quality/reputation score. Adjudication-based dispute/upheld-rate will require #13/#14 and safeguards against biased sponsors.

## Operator admission and independence checks (human/off-chain; not automated or done yet)

1. Collect explicit voluntary consent and verify the legal or public professional identity of the organization's controller without making identity documents public.
2. Review registered organizational ownership, shared founders, affiliate relationships, common control of devices/wallets, role relationships with the sponsor/contributor/arbitrator and conflict disclosure. **Two wallets or two claimed websites are insufficient.**
3. Confirm relevant technical competence for the project language/framework, available reproducible toolchain and safe read-only GitHub access; hash the capability profile and date it.
4. Approve organization ID via governance and require separate on-chain controller activation. Publish a non-sensitive reviewer profile, eligibility requirements, rotation reason, and revocation notices.
5. Before assigning a particular bounty, re-check conflicts across sponsor wallet, accepted developer wallet, primary arbitrator wallet, reviewer controller, signer and historic linked wallets; record human-checked common beneficial ownership.
6. Enforce explicit per-job timeouts. Missing or dissenting evidence must never silently turn into a passing report. Revoke on demonstrated conflict, compromised signing key, dishonest reporting or organizational misrepresentation; preserve evidence and offer due process.

**Important conflict rule:** A reviewer organization must also be present in the funded sponsor roster. Admin identity approval **alone is never sufficient** to appoint a reviewer. The roster minimum quorum is 2 and maximum approved organizations is 5. Its future verifier-decision contract (#13) must count **distinct organization IDs satisfying the committed quorum**, not distinct signer wallets.

**Operational reality:** These steps are a protocol and procedural plan. No identity records have been collected, no external reviewer has enrolled and no real customers/users have been granted trust in the registry.

## Governance abilities and limitations

| Action | Who may sign | Economic effect |
|---|---|---|
| Enroll organization | Immutable governance wallet | None; sets pending identity and profile |
| Activate | Enrolled controller wallet | None; eligible for future jobs only |
| Commit sponsor-approved reviewer roster | Sponsor wallet, **once** before developer acceptance | None; exact funded SHA-256 roster/quorum cannot change |
| Appoint reviewer to exact attempt | Governance wallet, restricted to committed organization IDs | None; pins org ID, signer epoch, attempt hash and deadline |
| Accept or declare report hash | Current active assigned signer | None; records participation, not a verdict |
| Rotate key | Controller proposes, governance approves | None; new key epoch; old key linked forever |
| Refresh job after rotation | Governance, **only if not accepted and not declared** | None; does not reset accepted/completed evidence |
| Revoke organization | Governance | Permanently disables new participation, does **not delete prior reports** |
| Override completed reports or rewrite previous reward | Nobody in registry | Not implemented nor authorized |

**Revocation versus trust of historical evidence:** Past records remain immutable for audit, but a newly discovered conflict may make older reports questionable. A real dispute/review module must provide an appeal/reversal process **without rewriting history** (#14/#15). A job accepted under an obsolete epoch but not yet declared cannot be silently reassigned by this registry; it must take the bonded fallback/escalation route, not manufacture approval.

## Conflict-of-interest matrix (contract rejection + social checks)

| Actor / scenario | Automatic on-chain decision | What remains human / future integration |
|---|---|---|
| Sponsor wallet is org controller or current signer | **Reject job assignment** | Look for sponsor-controlled *other* wallets or affiliate orgs |
| Developer wallet is org controller or current signer | **Reject job assignment** | Bind developer GitHub+wallet identity (#23) |
| Primary arbitrator wallet is org controller or signer | **Reject job assignment** | Confirm arbiter appointment and fallback body independence (#14) |
| Sponsor/developer/arbiter previously signed for org before rotation | **Reject** via permanent wallet-to-org linkage | Look for hidden control of new wallets |
| Same signing wallet or controller attempts a second org ID | **Reject enrollment** | Different named controllers under shared beneficial ownership can still collude |
| Same organization counted twice for one attempt | **Reject duplicate job**, max one current signer | Distinct organizations may also collude; allow challenges |
| Unknown, inactive, revoked, mismatched signer or key epoch | **Reject accepting/declaring** | Key compromise incident reporting and independent audit |
| Stale or expired attempt; old revision after reviewer retry | **Reject** | Secure verified #13 evidence and payment gating |
| Reporter repeats/changes declared digest | **Reject**; exact historical digest remains | Dispute processes assess truthfulness, not registry counters |
| Governance maliciously admits sock puppets | **Not preventable by wallet rules** | Publish review policy, independent audit, multi-party governance; don't market “trustless” |

## Review service level and compensation policy — SPECIFICATION ONLY

The on-chain job deadline is **the original submitted-at time plus the bounty's immutable verification-timeout seconds**. Governance cannot extend it ad hoc by appointing reviewers late. Funding policy commits the verifier policy digest. At present this records identity only; it does not collect fees or pay reviewers.

Provisional service targets to test with real operators:
- Reviewer **acknowledgment:** within 4 hours of assignment, but no later than the actual immutable verification deadline.
- Reproducibility work + evidence declaration: within **24–48 hours** for a small public-repo defect if agreed, otherwise the *funded verification window* controls.
- Sponsor/contributor challenge period: at least 24 hours for serious disputes (contract's current minimum is 1 hour from #9; update policy and tests in #14/#15 before accepting public money).
- One assigned reviewer may be replaced only through an audited/authorized review flow; no automated “approved” verdict when operators are unavailable.
- Independent reviewer compensation must be prepaid/committed in the future funding terms, with clear payment rules for valid, inconclusive, disputed or late reports. **No actual reviewer payment mechanism exists**.
- Abuse bond, challenge filing fee and who bears unsuccessful dispute costs are **not decided**. Prefer a pre-disclosed capped cost, no surprise charges to contributors and no unbounded fees from escrow. Governance cannot unilaterally take bounty reward funds.
- If reviewers disagree or deadline expires, preserve the contributor's timely submission and **escalate**, not sponsor-refund by default (#14/#15).
- All-arbitrators-unavailable still has **no enforceable terminal path** and is a hard deployment gate.

## Interface and integration blockers

- Funding records now include an **immutable primaryArbitrator wallet** alongside the committed dispute policy. This is an additive design change to stacked Issue #9 tests/structs *before any real deployment*; future real contract must ensure this wallet and chosen policy cannot be unilaterally altered.
- Actual named reviewer organizational onboarding, governance review evidence custody, CLI/operator dashboard and wallet enrollment service remain to be built (#23/#24/#26).
- Successful **wallet-authenticated report declarations** are on-chain audit signals, not a verified verdict or signed attempt attestation. Formal signature formats, nonce/expiry, cross-chain replay defense and quorum belong to #13.
- No V3 testnet deployment (#18), no secure runner (#21/#25), no real transfers (#16), no appeal/fallback (#14/#15), no external security sign-off (#41).
- The deployed report indexer and API must preserve the org ID, signer epoch, attempt digest, report digest and timestamps, with finalized chain receipts and reorg handling (#27).

## Release decision

**NO-GO for user money** and “independent proven verification” claims. Only the local reviewer identity/job registry code and its automated tests are complete. Keep Issue #12 and its stacked PR open for actual approved, independent external signers, signed #13 reviewer attestations, audit and verified chain integration. Public source and passing CI alone are not sufficient.
