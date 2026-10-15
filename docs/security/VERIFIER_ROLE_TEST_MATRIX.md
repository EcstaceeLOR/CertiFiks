# Issue #12 — Verifier registry negative-role regression matrix

All cases below are tested with **synthetic wallets and organizations in Foundry**. These fixtures are *not* live real-world verifier identities or a demonstration of actual organizational independence.

| Case | Expected result | Foundry test |
|---|---|---|
| Two separately enrolled active organizations | Each can accept own exact attempt job; each may declare once | testApprovedTwoOrganizationsCanAcceptAndDeclareOnOneAttempt |
| Organization registered but controller has not accepted | Inactive, cannot be appointed | testUnapprovedOrInactiveCannotAcceptReview |
| Unknown caller tries enrolling/activating | Reject unauthorized governance/controller | testGovernanceAdmissionAndControllerAcceptanceCannotBeForged |
| Same controller or signer reused across org IDs | Reject enrollment, regardless of second key | testCannotManufactureTwoOrganizationsWithAnotherSigningKey |
| Sponsor is signing wallet or org controller | Reject as conflicted job | testBountySponsorCannotBeOrganizationSignerOrController |
| Developer or designated primary arbitrator is verifier | Reject job | testBountyDeveloperAndArbitratorCannotBeVerifiers |
| Developer was **historic** signer and key rotated | Reject via permanent org linkage | testPriorKeyRotationDoesNotEraseConflictIdentity |
| Signer replaced before accepting job | Old epoch rejected; governance can refresh unaccepted job; new signer acts | testStaleKeyBlockedAndGovernanceCanRefreshUnacceptedJob |
| Key rotated after declaration | Historical digest, wallet and epoch unchanged | testRotationAfterCompletedDeclarationNeverRewritesHistory |
| Organization revoked after declaration | No new participation; old on-chain record retained; cannot self-reactivate | testRevocationStopsNewSignaturesButDoesNotDeleteOldEvidence |
| Organization revoked before declaration | Signer cannot submit new report | testRevocationBeforeDeclarationBlocksSignerForever |
| Sponsor/outsider appoints job or governance duplicates org | Reject both | testOnlyGovernanceCanAssignAndJobsCannotDuplicate |
| Repeat report, blank report, wrong job/org signer | Reject | testOneReviewerCannotDeclareTwiceOrSignForAnotherOrg |
| Deadline reached | Reject accept, refresh and late appointment | testJobsExpireByFundedVerificationWindow |
| A newer authorized re-review attempt supersedes old attempt | Old job cannot declare as latest, new job tied to new attempt digest | testOldAttemptJobCannotDecideOnNewHeadOrNewReviewAttempt |
| Reviewer participation changes bounty liabilities | Must never happen | testRegistryStatusDoesNotChangeFinancialLiability |
| Attacker attempts other organization's signer rotation | Reject | testSignerCannotBeClaimedByMultipleOrgControllers |

## Further required tests for product release

Test financial invariant, signer replay with real cryptographic signatures, organizational quorum disagreement, misleading CI output, job outages, all-arbitrators-absent fallback, reverted withdrawals, unauthorized ability to prepay/reassign reviewers, PR force-push during real runner execution and auth token scope. These depend on #13–#17/#20–#25/#40/#41; do not mark them complete from local wallet-signed hash declarations.
