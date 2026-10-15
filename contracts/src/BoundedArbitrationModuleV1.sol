// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SignedVerifierDecisionModuleV1} from "./SignedVerifierDecisionModuleV1.sol";

/**
 * @title BoundedArbitrationModuleV1
 * @notice Permissioned human arbitration, one losing-party appeal, and
 *         permissionless bounded timeout paths.
 *
 * @dev ABSTRACT; no payable funding, transfer, refund credit, or settlement
 * exists. A terminal entitlement is NOT a transfer instruction until the
 * separately audited accounting module (#15/#16) verifies all invariants.
 * Human arbitrator judgments are trusted and can be incorrect or collusive.
 * A genuine fix and GitHub/test provenance are not established by this code.
 */
abstract contract BoundedArbitrationModuleV1 is SignedVerifierDecisionModuleV1 {
    bytes internal constant DISPUTE_DOMAIN = "CertiFiks:arbitration-policy:v1";

    enum CasePhase {
        None,
        PrimaryReview,
        FallbackReview,
        PrimaryAppealWindow,
        AppealReview,
        Resolved,
        Superseded
    }

    enum Award {
        None,
        DeveloperReward,
        SponsorRefund
    }

    struct DisputePolicy {
        address fallbackArbitrator;
        bool configured;
        bool governanceApproved;
        bool primaryAccepted;
        bool fallbackAccepted;
        bool primaryDisqualified;
        bool fallbackDisqualified;
    }

    struct DisputeCase {
        CasePhase phase;
        Award primaryAward;
        Award finalAward;
        address challenger;
        uint64 attemptId;
        uint64 primaryDeadline;
        uint64 fallbackDeadline;
        uint64 appealUntil;
        bytes32 attemptDigest;
        bytes32 openingReasonDigest;
        bytes32 openingEvidenceDigest;
        bytes32 primaryReasonDigest;
        bytes32 primaryEvidenceDigest;
        bytes32 fallbackReasonDigest;
        bytes32 fallbackEvidenceDigest;
        bytes32 appealReasonDigest;
        bytes32 appealEvidenceDigest;
    }

    error InvalidDisputePolicy();
    error DisputePolicyAlreadyConfigured();
    error DisputePolicyCommitmentMismatch();
    error DisputePolicyNotConfigured();
    error DuplicateArbitratorConsent();
    error DisputeNotReviewable();
    error InvalidCaseEvidence();
    error ArbitrationPhaseMismatch();
    error ChallengeWindowExpired();
    error PrimaryRulingNotAppealable();
    error UnauthorizedChallenger();
    error UnauthorizedArbitrator();
    error ArbitratorConflict();
    error ArbitrationNotExpired();
    error ArbitrationDeadlineExpired();
    error InvalidAward();
    error CaseAlreadyOpened();
    error AppealNotPermitted();
    error DisputeDeadlineOverflow();
    error ArbitratorAlreadyDisqualified();

    event DisputePolicyRegistered(
        uint256 indexed bountyId, address indexed primaryArbitrator,
        address indexed fallbackArbitrator, bytes32 policyDigest
    );
    event DisputePolicyApproved(uint256 indexed bountyId, address indexed governance);
    event ArbitratorConsented(uint256 indexed bountyId, address indexed arbitrator);
    event ArbitratorDisqualified(uint256 indexed bountyId, address indexed arbitrator, bytes32 indexed reasonDigest);
    event ArbitrationOpened(
        uint256 indexed bountyId, uint64 indexed attemptId, address indexed challenger,
        bytes32 attemptDigest, bytes32 reasonDigest, bytes32 evidenceDigest,
        uint64 primaryDeadline, uint64 fallbackDeadline
    );
    event ArbitrationRuling(
        uint256 indexed bountyId, uint64 indexed attemptId, address indexed arbitrator,
        Award award, bytes32 reasonDigest, bytes32 evidenceDigest, bool fallbackRuling
    );
    event ArbitrationAdvanced(
        uint256 indexed bountyId, uint64 indexed attemptId, CasePhase phase
    );
    event ArbitrationAppealed(
        uint256 indexed bountyId, uint64 indexed attemptId, address indexed appellant,
        bytes32 reasonDigest, bytes32 evidenceDigest
    );
    event ArbitrationResolved(
        uint256 indexed bountyId, uint64 indexed attemptId, Award award,
        bytes32 reasonDigest, bool appliedDeadlineDefault
    );
    event UnchallengedReviewFinalized(
        uint256 indexed bountyId, uint64 indexed attemptId, Award award
    );

    mapping(uint256 => DisputePolicy) internal _disputePolicy;
    mapping(uint256 => mapping(uint64 => DisputeCase)) internal _cases;

    constructor(uint256 chainId, address governance)
        SignedVerifierDecisionModuleV1(chainId, governance)
    {}

    /**
     * Exact bounded fallback policy is immutable and funded before anyone
     * takes a developer assignment. Governance cannot insert an arbitrator
     * or change this list after sponsor signing.
     */
    function registerDisputePolicy(uint256 bountyId, address fallbackArbitrator)
        external onlyCorrectChain
    {
        BountyTerms storage terms = _onlySponsor(bountyId);
        if (_disputePolicy[bountyId].configured) revert DisputePolicyAlreadyConfigured();
        if (_assignment[bountyId].state != AssignmentState.Open) revert InvalidReviewState();
        if (
            fallbackArbitrator == address(0) ||
            fallbackArbitrator == terms.primaryArbitrator ||
            fallbackArbitrator == terms.sponsor ||
            fallbackArbitrator == registryGovernance ||
            terms.primaryArbitrator == registryGovernance
        ) revert InvalidDisputePolicy();
        bytes32 commitment = sha256(
            abi.encode(DISPUTE_DOMAIN, terms.primaryArbitrator, fallbackArbitrator)
        );
        if (commitment != terms.disputePolicyDigest) revert DisputePolicyCommitmentMismatch();
        if (_isConflictedArbitrator(bountyId, terms.primaryArbitrator) ||
            _isConflictedArbitrator(bountyId, fallbackArbitrator)) {
            revert ArbitratorConflict();
        }
        _disputePolicy[bountyId] = DisputePolicy({
            fallbackArbitrator: fallbackArbitrator,
            configured: true,
            governanceApproved: false,
            primaryAccepted: false,
            fallbackAccepted: false,
            primaryDisqualified: false,
            fallbackDisqualified: false
        });
        emit DisputePolicyRegistered(
            bountyId, terms.primaryArbitrator, fallbackArbitrator, commitment
        );
    }

    function approveArbitrationPolicy(uint256 bountyId)
        external onlyCorrectChain onlyRegistryGovernance
    {
        DisputePolicy storage policy = _policy(bountyId);
        if (policy.governanceApproved) revert DisputePolicyAlreadyConfigured();
        if (_assignment[bountyId].state != AssignmentState.Open) revert InvalidReviewState();
        if (_isConflictedArbitrator(bountyId, _fundingTerms[bountyId].primaryArbitrator) ||
            _isConflictedArbitrator(bountyId, policy.fallbackArbitrator)) {
            revert ArbitratorConflict();
        }
        policy.governanceApproved = true;
        emit DisputePolicyApproved(bountyId, msg.sender);
    }

    function acceptArbitratorRole(uint256 bountyId) external onlyCorrectChain {
        DisputePolicy storage policy = _policy(bountyId);
        if (!policy.governanceApproved) revert InvalidDisputePolicy();
        if (_assignment[bountyId].state != AssignmentState.Open) revert InvalidReviewState();
        if (_isConflictedArbitrator(bountyId, msg.sender)) revert ArbitratorConflict();
        if (msg.sender == _fundingTerms[bountyId].primaryArbitrator) {
            if (policy.primaryDisqualified) revert ArbitratorAlreadyDisqualified();
            if (policy.primaryAccepted) revert DuplicateArbitratorConsent();
            policy.primaryAccepted = true;
        } else if (msg.sender == policy.fallbackArbitrator) {
            if (policy.fallbackDisqualified) revert ArbitratorAlreadyDisqualified();
            if (policy.fallbackAccepted) revert DuplicateArbitratorConsent();
            policy.fallbackAccepted = true;
        } else {
            revert UnauthorizedArbitrator();
        }
        emit ArbitratorConsented(bountyId, msg.sender);
    }

    /** Irreversible governance intervention for a compromised/suspected arbiter.
     * Historic rulings and evidence remain immutable; no replacement outside
     * sponsor-committed roster is possible. Fixed deadlines still guarantee
     * permissionless fallback resolution even if both are disqualified.
     */
    function disqualifyArbitrator(
        uint256 bountyId, address arbitrator, bytes32 reasonDigest
    ) external onlyCorrectChain onlyRegistryGovernance {
        DisputePolicy storage policy = _policy(bountyId);
        if (reasonDigest == bytes32(0)) revert InvalidCaseEvidence();
        if (arbitrator == _fundingTerms[bountyId].primaryArbitrator) {
            if (policy.primaryDisqualified) revert ArbitratorAlreadyDisqualified();
            policy.primaryDisqualified = true;
            policy.primaryAccepted = false;
        } else if (arbitrator == policy.fallbackArbitrator) {
            if (policy.fallbackDisqualified) revert ArbitratorAlreadyDisqualified();
            policy.fallbackDisqualified = true;
            policy.fallbackAccepted = false;
        } else revert UnauthorizedArbitrator();
        emit ArbitratorDisqualified(bountyId, arbitrator, reasonDigest);
    }

    function _policy(uint256 bountyId)
        internal view returns (DisputePolicy storage policy)
    {
        _terms(bountyId);
        policy = _disputePolicy[bountyId];
        if (!policy.configured) revert DisputePolicyNotConfigured();
    }

    function _isConflictedArbitrator(uint256 bountyId, address account)
        internal view returns (bool)
    {
        if (account == address(0)) return true;
        BountyTerms storage terms = _terms(bountyId);
        // A signer/controller ever linked to a reviewer organization cannot
        // act as the allegedly independent arbiter, even after key rotation.
        return (
            account == terms.sponsor ||
            account == _assignment[bountyId].developer ||
            account == registryGovernance ||
            walletOrganization[account] != bytes32(0)
        );
    }

    function _currentAttempt(uint256 bountyId, uint64 attemptId)
        internal view returns (FixAttempt storage attempt)
    {
        _terms(bountyId);
        if (attemptId == 0 || latestAttemptId[bountyId] != attemptId ||
            _assignment[bountyId].state != AssignmentState.Submitted) {
            revert DisputeNotReviewable();
        }
        attempt = _attempts[bountyId][attemptId];
    }

    function _party(uint256 bountyId, address who) internal view returns (bool) {
        return who == _fundingTerms[bountyId].sponsor ||
            who == _assignment[bountyId].developer;
    }

    function _requireReadyForAssignment(uint256 bountyId, address applicant)
        internal view override
    {
        ReviewerRoster storage roster = reviewerRoster[bountyId];
        if (!roster.configured) revert InvalidDisputePolicy();
        DisputePolicy storage policy = _disputePolicy[bountyId];
        if (
            !policy.configured || !policy.governanceApproved ||
            !policy.primaryAccepted || !policy.fallbackAccepted ||
            policy.primaryDisqualified || policy.fallbackDisqualified
        ) revert InvalidDisputePolicy();
        if (_isConflictedArbitrator(bountyId, _fundingTerms[bountyId].primaryArbitrator) ||
            _isConflictedArbitrator(bountyId, policy.fallbackArbitrator)) {
            revert ArbitratorConflict();
        }
        if (
            applicant == _fundingTerms[bountyId].primaryArbitrator ||
            applicant == policy.fallbackArbitrator ||
            isCommittedReviewer[bountyId][walletOrganization[applicant]]
        ) revert ConflictingBountyRole();

        // A committed list with unavailable organizations is not a usable
        // independent verifier quorum. An enrolled but inactive/revoked org
        // cannot be counted. This is still not a promise it will respond.
        uint256 available = 0;
        bytes32[] storage ids = _committedRosterMembers[bountyId];
        for (uint256 i = 0; i < ids.length; i++) {
            ReviewerOrganization storage org = _org[ids[i]];
            if (!org.active || org.revokedPermanently) continue;
            // Both current and historical org wallets are excluded from
            // sponsor and arbiter roles via the shared conflict validator.
            _requireNoRoleConflict(bountyId, ids[i]);
            available += 1;
        }
        if (available < roster.quorum) revert InvalidReviewState();
    }

    function _requireReadyForAcceptance(uint256 bountyId, address applicant)
        internal view override
    {
        _requireReadyForAssignment(bountyId, applicant);
    }

    /**
     * A green, independently signed quorum is subject to a real challenge
     * window. Only sponsor or developer can open one. Neither can extend it.
     */
    function challengeApprovedAttempt(
        uint256 bountyId, uint64 attemptId, bytes32 reasonDigest, bytes32 evidenceDigest
    ) external onlyCorrectChain {
        _currentAttempt(bountyId, attemptId);
        if (!_party(bountyId, msg.sender)) revert UnauthorizedChallenger();
        ReviewDecision storage review = _decisions[bountyId][attemptId];
        if (review.status != ReviewStatus.ChallengeWindow) revert DisputeNotReviewable();
        if (block.timestamp > review.challengeUntil) revert ChallengeWindowExpired();
        _openCase(bountyId, attemptId, msg.sender, reasonDigest, evidenceDigest);
    }

    /**
     * Missing, inconclusive or dissenting reviewer results also need an
     * appealable, bounded path. Before verification deadline only the two
     * interested parties may initiate escalation. Afterwards anyone may
     * initiate so an absent party cannot freeze custody.
     */
    function openReviewEscalation(
        uint256 bountyId, uint64 attemptId, bytes32 reasonDigest, bytes32 evidenceDigest
    ) external onlyCorrectChain {
        FixAttempt storage attempt = _currentAttempt(bountyId, attemptId);
        ReviewStatus status = _decisions[bountyId][attemptId].status;
        uint256 verificationCutoff =
            uint256(attempt.submittedAt) + _fundingTerms[bountyId].verificationSeconds;
        if (
            status == ReviewStatus.ChallengeWindow ||
            (status == ReviewStatus.Pending && block.timestamp < verificationCutoff)
        ) revert DisputeNotReviewable();
        if (!_party(bountyId, msg.sender) && block.timestamp < verificationCutoff) {
            revert UnauthorizedChallenger();
        }
        _openCase(bountyId, attemptId, msg.sender, reasonDigest, evidenceDigest);
    }

    function _openCase(
        uint256 bountyId, uint64 attemptId, address challenger,
        bytes32 reasonDigest, bytes32 evidenceDigest
    ) internal {
        if (reasonDigest == bytes32(0) || evidenceDigest == bytes32(0)) {
            revert InvalidCaseEvidence();
        }
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        if (caseData.phase != CasePhase.None) revert CaseAlreadyOpened();
        BountyTerms storage terms = _fundingTerms[bountyId];
        ReviewDecision storage review = _decisions[bountyId][attemptId];

        // Everything is anchored to the pre-funded submission timeline,
        // not mutable sponsor requests or the time this function is called.
        uint256 anchor = review.status == ReviewStatus.ChallengeWindow
            ? uint256(review.challengeUntil)
            : uint256(_attempts[bountyId][attemptId].submittedAt) +
                uint256(terms.verificationSeconds);
        uint256 primaryLimit = anchor + uint256(terms.arbitrationSeconds);
        uint256 fallbackLimit =
            primaryLimit + uint256(terms.challengeSeconds) +
            uint256(terms.arbitrationSeconds);
        if (fallbackLimit > type(uint64).max) revert DisputeDeadlineOverflow();

        caseData.phase = CasePhase.PrimaryReview;
        caseData.attemptId = attemptId;
        caseData.challenger = challenger;
        caseData.attemptDigest = _attempts[bountyId][attemptId].attemptDigest;
        caseData.primaryDeadline = uint64(primaryLimit);
        caseData.fallbackDeadline = uint64(fallbackLimit);
        caseData.openingReasonDigest = reasonDigest;
        caseData.openingEvidenceDigest = evidenceDigest;
        emit ArbitrationOpened(
            bountyId, attemptId, challenger, caseData.attemptDigest,
            reasonDigest, evidenceDigest, caseData.primaryDeadline,
            caseData.fallbackDeadline
        );
    }

    /**
     * Only precommitted, governance-vetted and explicitly opted-in wallet
     * signs a ruling transaction. Human truth of the ruling is NOT attested.
     */
    function ruleOnDispute(
        uint256 bountyId, uint64 attemptId, Award award,
        bytes32 reasonDigest, bytes32 evidenceDigest
    ) external onlyCorrectChain {
        _currentAttempt(bountyId, attemptId);
        if (award != Award.DeveloperReward && award != Award.SponsorRefund) {
            revert InvalidAward();
        }
        if (reasonDigest == bytes32(0) || evidenceDigest == bytes32(0)) {
            revert InvalidCaseEvidence();
        }
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        DisputePolicy storage policy = _policy(bountyId);
        if (!policy.governanceApproved) revert InvalidDisputePolicy();
        CasePhase phase = caseData.phase;
        bool primary = phase == CasePhase.PrimaryReview;
        bool fallbackReview = phase == CasePhase.FallbackReview ||
            phase == CasePhase.AppealReview;
        if (!primary && !fallbackReview) revert ArbitrationPhaseMismatch();
        address requiredSigner = primary
            ? _fundingTerms[bountyId].primaryArbitrator
            : policy.fallbackArbitrator;
        if (msg.sender != requiredSigner) revert UnauthorizedArbitrator();
        if (primary && (!policy.primaryAccepted || policy.primaryDisqualified) ||
            fallbackReview && (!policy.fallbackAccepted || policy.fallbackDisqualified)) {
            revert UnauthorizedArbitrator();
        }
        if (_isConflictedArbitrator(bountyId, msg.sender)) revert ArbitratorConflict();
        if (primary && block.timestamp >= caseData.primaryDeadline ||
            fallbackReview && block.timestamp >= caseData.fallbackDeadline) {
            revert ArbitrationDeadlineExpired();
        }
        if (primary) {
            caseData.primaryAward = award;
            caseData.primaryReasonDigest = reasonDigest;
            caseData.primaryEvidenceDigest = evidenceDigest;
            caseData.phase = CasePhase.PrimaryAppealWindow;
            uint256 appealLimit = block.timestamp + _fundingTerms[bountyId].challengeSeconds;
            uint256 cappedLimit = uint256(caseData.primaryDeadline) +
                uint256(_fundingTerms[bountyId].challengeSeconds);
            if (appealLimit > cappedLimit) appealLimit = cappedLimit;
            caseData.appealUntil = uint64(appealLimit);
        } else {
            caseData.fallbackReasonDigest = reasonDigest;
            caseData.fallbackEvidenceDigest = evidenceDigest;
            // Indexers observe evidence and the signed ruling BEFORE the
            // terminal entitlement event, in deterministic log order.
            emit ArbitrationRuling(
                bountyId, attemptId, msg.sender, award,
                reasonDigest, evidenceDigest, true
            );
            _resolve(bountyId, attemptId, award, reasonDigest, false);
            return;
        }
        emit ArbitrationRuling(
            bountyId, attemptId, msg.sender, award,
            reasonDigest, evidenceDigest, false
        );
    }

    /**
     * Exactly one losing-party appeal of a primary ruling. A developer may
     * appeal a sponsor refund; a sponsor may appeal a developer award.
     * Arbitrator fallback rules only once, and its ruling is final here.
     */
    function appealPrimaryRuling(
        uint256 bountyId, uint64 attemptId, bytes32 reasonDigest, bytes32 evidenceDigest
    ) external onlyCorrectChain {
        _currentAttempt(bountyId, attemptId);
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        if (caseData.phase != CasePhase.PrimaryAppealWindow) revert PrimaryRulingNotAppealable();
        if (block.timestamp > caseData.appealUntil) revert ChallengeWindowExpired();
        if (reasonDigest == bytes32(0) || evidenceDigest == bytes32(0)) {
            revert InvalidCaseEvidence();
        }
        address loser = caseData.primaryAward == Award.DeveloperReward
            ? _fundingTerms[bountyId].sponsor
            : _assignment[bountyId].developer;
        if (msg.sender != loser) revert AppealNotPermitted();
        caseData.appealReasonDigest = reasonDigest;
        caseData.appealEvidenceDigest = evidenceDigest;
        caseData.phase = CasePhase.AppealReview;
        emit ArbitrationAppealed(
            bountyId, attemptId, msg.sender, reasonDigest, evidenceDigest
        );
    }

    /**
     * Permissionless terminal progression. A silent primary is replaced by
     * the precommitted fallback. A silent fallback cannot veto forever.
     * Default: previously verified approval -> developer, otherwise sponsor.
     * This default MUST be independently reviewed before any real deposits.
     */
    function advanceDispute(uint256 bountyId, uint64 attemptId) external onlyCorrectChain {
        _currentAttempt(bountyId, attemptId);
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        if (caseData.phase == CasePhase.PrimaryReview) {
            if (block.timestamp < caseData.primaryDeadline) revert ArbitrationNotExpired();
            caseData.phase = CasePhase.FallbackReview;
            emit ArbitrationAdvanced(bountyId, attemptId, CasePhase.FallbackReview);
        } else if (caseData.phase == CasePhase.PrimaryAppealWindow) {
            if (block.timestamp <= caseData.appealUntil) revert ArbitrationNotExpired();
            _resolve(bountyId, attemptId, caseData.primaryAward,
                caseData.primaryReasonDigest, false);
        } else if (caseData.phase == CasePhase.FallbackReview) {
            if (block.timestamp < caseData.fallbackDeadline) revert ArbitrationNotExpired();
            _resolve(bountyId, attemptId, _defaultAward(bountyId, attemptId),
                caseData.openingReasonDigest, true);
        } else if (caseData.phase == CasePhase.AppealReview) {
            if (block.timestamp < caseData.fallbackDeadline) revert ArbitrationNotExpired();
            _resolve(bountyId, attemptId, caseData.primaryAward,
                caseData.primaryReasonDigest, true);
        } else revert ArbitrationPhaseMismatch();
    }

    function _defaultAward(uint256 bountyId, uint64 attemptId)
        internal view returns (Award)
    {
        // No silent 'green' when worker/reviewer consensus was missing.
        return _decisions[bountyId][attemptId].status == ReviewStatus.ChallengeWindow
            ? Award.DeveloperReward : Award.SponsorRefund;
    }

    function _resolve(
        uint256 bountyId, uint64 attemptId, Award award,
        bytes32 reasonDigest, bool deadlineDefault
    ) internal {
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        caseData.finalAward = award;
        caseData.phase = CasePhase.Resolved;
        emit ArbitrationResolved(bountyId, attemptId, award, reasonDigest, deadlineDefault);
        // Intentionally NO transfer / withdrawable credit / approved settlement.
    }

    function finalizeUnchallengedApproval(uint256 bountyId, uint64 attemptId)
        external onlyCorrectChain
    {
        _currentAttempt(bountyId, attemptId);
        ReviewDecision storage review = _decisions[bountyId][attemptId];
        if (review.status != ReviewStatus.ChallengeWindow) revert DisputeNotReviewable();
        if (block.timestamp <= review.challengeUntil) revert ArbitrationNotExpired();
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        if (caseData.phase != CasePhase.None) revert CaseAlreadyOpened();
        caseData.phase = CasePhase.Resolved;
        caseData.attemptId = attemptId;
        caseData.attemptDigest = _attempts[bountyId][attemptId].attemptDigest;
        caseData.finalAward = Award.DeveloperReward;
        emit UnchallengedReviewFinalized(bountyId, attemptId, Award.DeveloperReward);
    }

    function markSupersededCase(uint256 bountyId, uint64 attemptId)
        external onlyCorrectChain
    {
        _terms(bountyId);
        if (attemptId == 0 || attemptId >= latestAttemptId[bountyId]) {
            revert DisputeNotReviewable();
        }
        DisputeCase storage caseData = _cases[bountyId][attemptId];
        if (caseData.phase == CasePhase.None || caseData.phase == CasePhase.Resolved ||
            caseData.phase == CasePhase.Superseded) revert ArbitrationPhaseMismatch();
        caseData.phase = CasePhase.Superseded;
        emit ArbitrationAdvanced(bountyId, attemptId, CasePhase.Superseded);
    }

    function getDisputePolicy(uint256 bountyId) external view returns (DisputePolicy memory) {
        _terms(bountyId);
        return _disputePolicy[bountyId];
    }

    function getDisputeCase(uint256 bountyId, uint64 attemptId)
        external view returns (DisputeCase memory)
    {
        _terms(bountyId);
        if (attemptId == 0 || attemptId > latestAttemptId[bountyId]) revert UnknownAttempt();
        return _cases[bountyId][attemptId];
    }
}
