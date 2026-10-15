# CertiFiks arbitration and appeals — protocol v1

**Issue #14** · 2026-10-15 · **Status:** internal, undeloyed, no public funding endpoint and no real funds. **This is not an external security audit or an existing adjudication service.**

## Founder/product boundary

CertiFiks remains a solo-built software product. **Arbitrators** are proposed, independent third-party adjudicators that would operate the eventual protocol, *not developers hired to build CertiFiks*. No arbitrators have been recruited, funded, trained, vetted or registered as real-world operators. Test addresses and test decisions are synthetic.

The historical `CertiFiksEscrow.sol` is unsafe. The new abstract `BoundedDisputeModuleV1.sol` follows the stacked modules #9 funding, #10 assignment, #11 immutable GitHub submission, #12 named reviewer roster, and #13 EIP-712 signed independent review. **Do not expose a user-payable subclass**, because no user withdrawal/refund and solvency-enforced terminal credit contract exists yet.

## Trust and immutability rules

The sponsor precommits `sha256(abi.encode("CertiFiks:dispute-policy:v1", uint8(1), primaryArbitrator, fallbackArbitrator))` as part of the immutable funding terms. The primary wallet is already fixed in the funded terms; sponsor may register **exactly one** matching fallback wallet before the accepted developer can start work.

Both wallets must differ from each other, the sponsor, accepted developer and governance signer. They cannot be registered reviewer organization signers/controllers (including historical links); this check repeats when either attempts a ruling. The developer-acceptance hook prohibits selection of either arbitrator **or a committed reviewer-org signer/controller** as the developer; dispute policy registration also rejects sponsor conflicts with that same roster. If later conflicts are discovered, permissionless timeouts still resolve to the precommitted deterministic final disposition, rather than permitting compromised arbiters to spend funds.

**Limitations:** independent wallet addresses are not guaranteed independent humans or legal organizations. A controller could secretly control both wallets, the reviewer registry governance remains single-wallet permissioned governance, and factual correctness is not provable from a hash. Disclose these risks publicly and retain independent oversight and appeals before launch.

## Dispute policy and clocks

| Scenario | Initiator / evidence | Deadline, stage and restriction |
|---|---|---|
| Two independent signed approvals | Signed #13 quorum | `ChallengeWindow`; **no payout yet** |
| Sponsor challenges approved fix | Sponsor wallet with nonzero evidence digest | Once, strictly before immutable challenge cutoff; record original reason and lock sponsor evidence |
| Developer answers challenge | Accepted developer with nonzero evidence hash | Once, before primary cutoff; cannot change sponsor's reason |
| Reviewer dissent/rejection/runner failure | Automatically opened **in the same transaction as** signed #13 EscalationRequired decision; anyone may call idempotent materialization as a compatibility path | Primary clock starts at the **original recorded verifier decision**, not at the time someone eventually calls materialization |
| Reviewers fail to reach quorum before funded review deadline | Anyone calls #13 expireIncompleteReview; the #14 hook **atomically opens the case** in that transaction | Primary clock anchored to timed-out decision, not a late sponsor-controlled call |
| Primary arbitrator rules | Exact precommitted primary EVM wallet | Before `openedAt + arbitrationSeconds`; nonzero auditable decision digest; award developer, refund sponsor or split |
| Losing party requests procedural/merits appeal | Sponsor or accepted developer **who wasn't awarded the entire reward** | Once, within `challengeSeconds` after primary ruling, with an immutable new appeal evidence digest |
| Unappealed primary ruling | Anyone permissionlessly finalizes | At end of exact one-time appeal window, the primary decision becomes terminal |
| Primary arbitrator non-response | Anyone permissionlessly escalates | At/after original primary cutoff, triggers fallback review; deadline fixed at **primary cutoff + arbitrationSeconds** |
| Fallback arbitrator rules | Exact precommitted fallback wallet | Before fallback cutoff; writes terminal ruling with nonzero decision evidence digest |
| Fallback non-response | Anyone permissionlessly finalizes | At/after fixed cutoff. No arbitrary judge-reselection, extension or locked EmergencyHold for the case outcome |
| Both adjudicators absent, case challenges two positive attestations | Precommitted rule | **Award developer**; unresponsive judges cannot veto a valid independently approved fix forever |
| Both adjudicators absent, insufficient/negative review evidence | Precommitted *experimental* rule | **Split nominal reward 50/50**; sponsor receives the odd atomic-unit remainder |
| Fallback fails to respond to losing party's appeal of a primary ruling | Precommitted rule | **Primary ruling stands**; a baseless appeal cannot change an already reasoned adjudication outcome |

All transitions are one-way; no arbitrary re-opening, duplicate reason replacement, deadline extension or repeated appeal. A case references one current immutable attempt digest and exact bounty ID. All external state-changing entrypoints require the immutable funding chain ID.

### Important failure mode: the 50/50 fallback needs an economic redesign before launch

The 50/50 split avoids an **indefinite legal/technical custody hold** when both human arbitrators disappear, but it can reward a contributor who submitted poor-quality work to a bounty whose independent verifiers failed to respond. It is **NOT approved for live-money use**. Alternatives to evaluate with customer interviews and external legal/security review: prepaid independent insurance/resolution liquidity, an accountable independent panel with binding service-level guarantees, or a contributor bond with slashing and a sponsor-funded nonresponse reserve. A fully safe and fair default cannot be assumed from two anonymous on-chain wallet keys.

For the same reason, the policy currently charges **zero on-chain dispute fee/bond**: no extra unexpected transfer is introduced, but a sponsor could start one frivolous challenge per approved attempt and impose a bounded delay. This is an explicit unpriced abuse risk. Future economics must precommit transparent fees and fund them in separate liabilities; there is no undisclosed governance withdrawal or operator sweep.

## Financial effects: no funds are paid by #14

A final ruling is a **right-to-payment calculation, not payment**. The module emits `DisputeFinalized` with the terminal reason digest, ruling, responsible adjudicator (or address(0) for predetermined timeout), and two nominal atom amounts. Its `readFinalEntitlements` returns zero/split/full values whose sum equals the original reward. It never calls `transfer`, `call{value:...}`, or grants user credits. The full originally funded reward remains in `totalReservedAtoms` until #15/#16 implement atomic release of liabilities and pull-based credited withdrawals. Later settlement must check both untouched one-time approval results and these dispute rulings, and reject double credit/refund or conflicting terminal outcomes.

**Real-life distinction:** The on-chain model can deterministically reach `Finalized` despite absent arbiters, but users **cannot withdraw** under this module. Do not claim “funds cannot be stranded” in production until #16+ run and demonstrate actual native-token claims, receiver failures, fee protection, solvency invariants and correct asset semantics.

## Evidence storage and privacy

All challenge, response, appeal and decision digests are immutable bytes32 audit commitments. They **do not themselves contain the test logs, reproduction output, witness signatures, GitHub checks, or court-like factual analysis**. A real operator system must use #22/#24 to archive exact report blobs (content addressing, access control, redacted logs, retention, signatures) and ensure every hash resolves to evidence the affected sponsor and developer can inspect. Do not post private source code, credentials, KYC documents or GitHub installation tokens to public logs.

The challenger and counterparty see the same immutable on-chain record; both have one opportunity to submit their evidence hash before the primary deadline. A reviewer verdict has a signed outcome digest but no mathematically guaranteed correct finding. The outcome and appeal process is a **permissioned human judgment trust model**, not an autonomous trustless court.

## Tests / go-no-go

The [Foundry dispute tests](../../contracts/test/BoundedDisputeModuleV1.t.sol) cover exact policy commit, sponsor-only challenge, missing evidence and false actor rejection, bounded deadlines, independent primary/fallback rulings, appeal eligibility and repeat prevention, no-response fallback, anchored timeouts, primary nonresponse, conflicting arbitrator, correct reason audit, wrong-chain actions, odd-atom conservation and no premature transfers.

Further release requirements:
- [ ] #14 genuine independent human decision on a real disputed evidence archive; actual provider identity and appeal policy validation.
- [ ] #15 fair timeout rights, legitimate refund conditions, challenge-window finality, no sponsor recoup of timely work.
- [ ] #16 credit ledger, safe reentrant-resistant pull withdrawals and insolvency invariants.
- [ ] #18 authentic qualifying Portaldot V3 network/contract, transaction history and finality.
- [ ] #20/#21/#22/#23/#24/#25 verified GitHub App, before/after tests, accessible independent evidence archive and identity controls.
- [ ] #26 frontend/API, #27 indexer, #40 actual end-to-end browser-to-chain case, #41 external security audit/legal review.
- [ ] Policy redesign/approval for no-response 50/50 split (high risk of economically incentivizing junk fixes).

**Decision: NO-GO for accepting user funds or advertising a completed dispute product.** Preserve this code as tested, reviewable internal protocol progress on a stacked draft PR; keep #14 open until actual end-to-end and financial conditions pass.
