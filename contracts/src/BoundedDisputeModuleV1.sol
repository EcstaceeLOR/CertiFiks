// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SignedVerifierDecisionModuleV1} from "./SignedVerifierDecisionModuleV1.sol";

/**
 * @title BoundedDisputeModuleV1
 * @notice Immutable, challengeable adjudication with a precommitted fallback
 *         arbitrator and a finite deterministic last-resort outcome.
 *
 * SECURITY: Abstract, non-deployable as a safe escrow. Ruling records are
 * NOT payouts, refunds, balances, credits, withdrawals or real-world proof.
 * Actual value conservation and withdrawals are issue #15-#17; no user
 * deposits before reviewed settlement, qualifying V3 network and #41 audit.
 * Fallback adjudication remains permissioned human judgment, not a court.
 */
abstract contract BoundedDisputeModuleV1 is SignedVerifierDecisionModuleV1 {
    bytes internal constant DISPUTE_DOMAIN = "CertiFiks:dispute-policy:v1";
    bytes internal constant TIMEOUT_DOMAIN = "CertiFiks:review-timeout:v1";
    uint8 internal constant POLICY_VERSION = 1;

    enum CaseState { None, PrimaryReview, AppealWindow, FallbackReview, Finalized }
    enum CaseCause { None, SponsorChallenge, RejectedOrInconclusive, ReviewerTimeout }
    enum Ruling { None, Developer, Sponsor, Split }

    struct DisputePolicy {
        address fallbackArbitrator;
        bool configured;
    }

    struct DisputeCase {
        CaseState state;
        CaseCause cause;
        uint64 attemptId;
        uint64 openedAt;
        uint64 primaryUntil;
        uint64 appealUntil;
        uint64 fallbackUntil;
        bytes32 attemptDigest;
        bytes32 reasonDigest;
        bytes32 sponsorEvidenceDigest;
        bytes32 developerEvidenceDigest;
        bytes32 appealEvidenceDigest;
        bytes32 primaryDecisionDigest;
        bytes32 finalDecisionDigest;
        Ruling primaryRuling;
        Ruling finalRuling;
        address appealBy;
        address finalAdjudicator;
    }

    error DisputePolicyNotConfigured();
    error DisputePolicyAlreadyConfigured();
    error DisputePolicyMismatch();
    error InvalidFallbackArbitrator();
    error ConflictedArbitrator();
    error UnauthorizedChallenger();
    error UnauthorizedDisputeActor();
    error InvalidDisputeCause();
    error DisputeAlreadyOpened();
    error DisputeNotOpened();
    error IncorrectCaseState();
    error DisputeDeadlineNotReached();
    error DisputeWindowClosed();
    error MissingEvidenceDigest();
    error DuplicatePartyEvidence();
    error InvalidRuling();
    error IneligibleAppeal();
    error DecisionNotFinal();
    error DisputeTimestampOverflow();

    event DisputePolicyRegistered(
        uint256 indexed bountyId, address indexed primaryArbitrator,
        address indexed fallbackArbitrator, bytes32 policyDigest
    );
    event DisputeOpened(
        uint256 indexed bountyId, uint64 indexed attemptId,
        CaseCause cause, bytes32 reasonDigest, uint64 primaryUntil
    );
    event PartyEvidenceFiled(
        uint256 indexed bountyId, uint64 indexed attemptId,
        address indexed author, bytes32 evidenceDigest
    );
    event PrimaryArbitratorRuled(
        uint256 indexed bountyId, uint64 indexed attemptId,
        address indexed arbitrator, Ruling ruling,
        bytes32 decisionDigest, uint64 appealUntil
    );
    event DisputeAppealed(
        uint256 indexed bountyId, uint64 indexed attemptId,
        address indexed appellant, bytes32 appealEvidenceDigest, uint64 fallbackUntil
    );
    event DisputeEscalated(
        uint256 indexed bountyId, uint64 indexed attemptId,
        address indexed fallbackArbitrator, uint64 fallbackUntil
    );
    event DisputeFinalized(
        uint256 indexed bountyId, uint64 indexed attemptId,
        Ruling ruling, address adjudicator, bytes32 decisionDigest,
        uint256 developerAwardAtoms, uint256 sponsorRefundAtoms
    );

    mapping(uint256 => DisputePolicy) internal _disputePolicies;
    mapping(uint256 => mapping(uint64 => DisputeCase)) internal _disputeCases;

    constructor(uint256 chainId, address governance)
        SignedVerifierDecisionModuleV1(chainId, governance)
    {}

    function disputePolicyCommitment(address primary, address fallbackArbitrator)
        public pure returns (bytes32)
    {
        return sha256(abi.encode(DISPUTE_DOMAIN, POLICY_VERSION, primary, fallbackArbitrator));
    }

    /**
     * @dev The sponsor chooses fallback identity BEFORE developer acceptance,
     * and the immutable funding terms must already hash to this exact choice.
     * The operator cannot replace the fallback on a funded bounty later.
     */
    function registerDisputeFallback(uint256 bountyId, address fallbackArbitrator)
        external onlyCorrectChain
    {
        BountyTerms storage terms = _onlySponsor(bountyId);
        if (_disputePolicies[bountyId].configured) revert DisputePolicyAlreadyConfigured();
        if (_assignment[bountyId].state != AssignmentState.Open) revert IncorrectCaseState();
        if (
            fallbackArbitrator == address(0) ||
            fallbackArbitrator == terms.primaryArbitrator ||
            fallbackArbitrator == terms.sponsor ||
            fallbackArbitrator == registryGovernance ||
            terms.primaryArbitrator == registryGovernance
        ) revert InvalidFallbackArbitrator();
        if (
            walletOrganization[fallbackArbitrator] != bytes32(0) ||
            walletOrganization[terms.primaryArbitrator] != bytes32(0) ||
            (
                walletOrganization[terms.sponsor] != bytes32(0) &&
                isCommittedReviewer[bountyId][walletOrganization[terms.sponsor]]
            )
        ) revert ConflictedArbitrator();
        bytes32 computed = disputePolicyCommitment(terms.primaryArbitrator, fallbackArbitrator);
        if (computed != terms.disputePolicyDigest) revert DisputePolicyMismatch();

        _disputePolicies[bountyId] = DisputePolicy({
            fallbackArbitrator: fallbackArbitrator,
            configured: true
        });
        emit DisputePolicyRegistered(
            bountyId, terms.primaryArbitrator, fallbackArbitrator, computed
        );
    }

    /** Protected hook used by the #10 wallet-signed acceptance transaction. */
    function _validateAcceptedRole(uint256 bountyId, address developer)
        internal view override
    {
        if (!_disputePolicies[bountyId].configured) revert DisputePolicyNotConfigured();
        BountyTerms storage terms = _terms(bountyId);
        if (
            developer == terms.primaryArbitrator ||
            developer == _disputePolicies[bountyId].fallbackArbitrator ||
            developer == registryGovernance ||
            (
                walletOrganization[developer] != bytes32(0) &&
                isCommittedReviewer[bountyId][walletOrganization[developer]]
            )
        ) revert ConflictedArbitrator();
    }

    function _requireIndependentArbiters(uint256 bountyId) internal view {
        BountyTerms storage terms = _terms(bountyId);
        DisputePolicy storage policy = _disputePolicies[bountyId];
        if (!policy.configured) revert DisputePolicyNotConfigured();
        address developer = _assignment[bountyId].developer;
        if (
            developer == address(0) ||
            terms.primaryArbitrator == developer ||
            terms.primaryArbitrator == terms.sponsor ||
            terms.primaryArbitrator == registryGovernance ||
            policy.fallbackArbitrator == developer ||
            policy.fallbackArbitrator == terms.sponsor ||
            policy.fallbackArbitrator == terms.primaryArbitrator ||
            policy.fallbackArbitrator == registryGovernance ||
            walletOrganization[terms.primaryArbitrator] != bytes32(0) ||
            walletOrganization[policy.fallbackArbitrator] != bytes32(0)
        ) revert ConflictedArbitrator();
    }

    function _time64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) revert DisputeTimestampOverflow();
        return uint64(value);
    }

    function _activeLatestAttempt(uint256 bountyId) internal view returns (uint64 attemptId) {
        _terms(bountyId);
        attemptId = latestAttemptId[bountyId];
        if (
            attemptId == 0 ||
            _assignment[bountyId].state != AssignmentState.Submitted
        ) revert InvalidDisputeCause();
    }

    /**
     * Only the sponsor may challenge a two-org-approved fix, and only within
     * the immutable challenge window. Developer may file rebuttal evidence.
     * No challenge bond in v1: one case per attempt, bounded maximum delay.
     */
    function challengeApprovedFix(uint256 bountyId, bytes32 reasonDigest)
        external onlyCorrectChain
    {
        BountyTerms storage terms = _onlySponsor(bountyId);
        uint64 attemptId = _activeLatestAttempt(bountyId);
        ReviewDecision storage decision = _decisions[bountyId][attemptId];
        if (
            decision.status != ReviewStatus.ChallengeWindow ||
            block.timestamp >= decision.challengeUntil
        ) revert DisputeWindowClosed();
        if (reasonDigest == bytes32(0)) revert MissingEvidenceDigest();

        _openDispute(
            bountyId, attemptId, CaseCause.SponsorChallenge,
            reasonDigest, _time64(block.timestamp)
        );
        _disputeCases[bountyId][attemptId].sponsorEvidenceDigest = reasonDigest;
        emit PartyEvidenceFiled(bountyId, attemptId, msg.sender, reasonDigest);
        // Exact reward/deadline/manifest terms remain untouched.
        if (terms.sponsor == address(0)) revert UnauthorizedChallenger(); // defense in depth
    }

    /**
     * Anyone can materialize an already escalated verifier outcome; its
     * deadline begins at the original recorded decision, not the call time.
     * A caller cannot postpone a disputed case by refusing to open it.
     */
    function _onEscalatedReview(uint256 bountyId, uint64 attemptId)
        internal override
    {
        ReviewDecision storage decision = _decisions[bountyId][attemptId];
        CaseCause cause;
        bytes32 reason;
        if (decision.status == ReviewStatus.EscalationRequired) {
            cause = CaseCause.RejectedOrInconclusive;
            reason = decision.triggeringVoteDigest;
        } else if (decision.status == ReviewStatus.TimedOut) {
            cause = CaseCause.ReviewerTimeout;
            reason = sha256(abi.encode(
                TIMEOUT_DOMAIN, expectedChainId, address(this),
                bountyId, attemptId, _attempts[bountyId][attemptId].attemptDigest
            ));
        } else revert InvalidDisputeCause();
        if (decision.decidedAt == 0 || reason == bytes32(0)) revert InvalidDisputeCause();
        _openDispute(bountyId, attemptId, cause, reason, decision.decidedAt);
    }

    /**
     * Compatibility/readiness method. For this derived #14 contract cases
     * are already opened AT the verifier transition, not by the caller.
     * Replaying materialization never changes a clock or a reason digest.
     */
    function materializeEscalatedReview(uint256 bountyId) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        ReviewStatus status = _decisions[bountyId][attemptId].status;
        if (
            status != ReviewStatus.EscalationRequired &&
            status != ReviewStatus.TimedOut
        ) revert InvalidDisputeCause();
        if (_disputeCases[bountyId][attemptId].state == CaseState.None) {
            // Compatible with older #13 deployments, but in this derived
            // version the _onEscalatedReview hook creates it atomically.
            _onEscalatedReview(bountyId, attemptId);
        }
    }

    function _openDispute(
        uint256 bountyId, uint64 attemptId, CaseCause cause,
        bytes32 reason, uint64 effectiveStart
    ) internal {
        if (_disputeCases[bountyId][attemptId].state != CaseState.None) {
            revert DisputeAlreadyOpened();
        }
        // The case MUST open even if a later conflict is discovered:
        // conflicts block judicial votes, not the clock or timeout recovery.
        if (!_disputePolicies[bountyId].configured) revert DisputePolicyNotConfigured();
        DisputeCase storage record = _disputeCases[bountyId][attemptId];
        uint64 cutoff = _time64(
            uint256(effectiveStart) + uint256(_fundingTerms[bountyId].arbitrationSeconds)
        );
        record.state = CaseState.PrimaryReview;
        record.cause = cause;
        record.attemptId = attemptId;
        record.openedAt = effectiveStart;
        record.primaryUntil = cutoff;
        record.attemptDigest = _attempts[bountyId][attemptId].attemptDigest;
        record.reasonDigest = reason;
        emit DisputeOpened(bountyId, attemptId, cause, reason, cutoff);
    }

    /**
     * Each party gets one independently logged, immutable evidence reference.
     * The sponsor challenge itself occupies the sponsor's evidence slot.
     */
    function filePartyEvidence(uint256 bountyId, bytes32 evidenceDigest)
        external onlyCorrectChain
    {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.PrimaryReview ||
            block.timestamp >= record.primaryUntil) revert DisputeWindowClosed();
        if (evidenceDigest == bytes32(0)) revert MissingEvidenceDigest();
        BountyTerms storage terms = _terms(bountyId);
        if (msg.sender == terms.sponsor) {
            if (record.sponsorEvidenceDigest != bytes32(0)) revert DuplicatePartyEvidence();
            record.sponsorEvidenceDigest = evidenceDigest;
        } else if (msg.sender == _assignment[bountyId].developer) {
            if (record.developerEvidenceDigest != bytes32(0)) revert DuplicatePartyEvidence();
            record.developerEvidenceDigest = evidenceDigest;
        } else revert UnauthorizedDisputeActor();

        emit PartyEvidenceFiled(bountyId, attemptId, msg.sender, evidenceDigest);
    }

    function _openCurrent(uint256 bountyId, uint64 attemptId)
        internal view returns (DisputeCase storage record)
    {
        record = _disputeCases[bountyId][attemptId];
        if (record.state == CaseState.None) revert DisputeNotOpened();
        if (
            latestAttemptId[bountyId] != attemptId ||
            record.attemptDigest != _attempts[bountyId][attemptId].attemptDigest
        ) revert InvalidDisputeCause();
    }

    function _checkRuling(Ruling ruling, bytes32 reasonDigest) internal pure {
        if (
            ruling != Ruling.Developer && ruling != Ruling.Sponsor && ruling != Ruling.Split
        ) revert InvalidRuling();
        if (reasonDigest == bytes32(0)) revert MissingEvidenceDigest();
    }

    function decidePrimary(
        uint256 bountyId, Ruling ruling, bytes32 decisionDigest
    ) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.PrimaryReview) revert IncorrectCaseState();
        if (block.timestamp >= record.primaryUntil) revert DisputeWindowClosed();
        _requireIndependentArbiters(bountyId);
        if (msg.sender != _fundingTerms[bountyId].primaryArbitrator) {
            revert UnauthorizedDisputeActor();
        }
        _checkRuling(ruling, decisionDigest);
        record.primaryRuling = ruling;
        record.primaryDecisionDigest = decisionDigest;
        record.state = CaseState.AppealWindow;
        record.appealUntil = _time64(
            block.timestamp + uint256(_fundingTerms[bountyId].challengeSeconds)
        );
        emit PrimaryArbitratorRuled(
            bountyId, attemptId, msg.sender, ruling, decisionDigest, record.appealUntil
        );
    }

    /**
     * Exactly ONE appeal: only a party who does not receive the entire reward
     * in the primary decision, and only before the fixed appeal cutoff.
     * No arbitrator or sponsor can recursively reset appeal deadlines.
     */
    function appealPrimary(
        uint256 bountyId, bytes32 appealEvidenceDigest
    ) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.AppealWindow) revert IncorrectCaseState();
        if (block.timestamp >= record.appealUntil) revert DisputeWindowClosed();
        if (appealEvidenceDigest == bytes32(0)) revert MissingEvidenceDigest();

        BountyTerms storage terms = _terms(bountyId);
        bool sponsorIsLoser = (
            msg.sender == terms.sponsor && record.primaryRuling != Ruling.Sponsor
        );
        bool developerIsLoser = (
            msg.sender == _assignment[bountyId].developer &&
            record.primaryRuling != Ruling.Developer
        );
        if (!sponsorIsLoser && !developerIsLoser) revert IneligibleAppeal();

        record.appealBy = msg.sender;
        record.appealEvidenceDigest = appealEvidenceDigest;
        record.state = CaseState.FallbackReview;
        record.fallbackUntil = _time64(
            block.timestamp + uint256(terms.arbitrationSeconds)
        );
        emit DisputeAppealed(
            bountyId, attemptId, msg.sender, appealEvidenceDigest, record.fallbackUntil
        );
    }

    function finalizeUnappealedPrimary(uint256 bountyId) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.AppealWindow) revert IncorrectCaseState();
        if (block.timestamp < record.appealUntil) revert DisputeDeadlineNotReached();
        _finalize(bountyId, attemptId, record.primaryRuling,
            _fundingTerms[bountyId].primaryArbitrator, record.primaryDecisionDigest);
    }

    /**
     * If the primary arbitrator disappears, the fallback period is anchored
     * to the PRIMARY deadline, not the timestamp this function was called.
     */
    function escalateSilentPrimary(uint256 bountyId) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.PrimaryReview) revert IncorrectCaseState();
        if (block.timestamp < record.primaryUntil) revert DisputeDeadlineNotReached();
        record.state = CaseState.FallbackReview;
        record.fallbackUntil = _time64(
            uint256(record.primaryUntil) +
            uint256(_fundingTerms[bountyId].arbitrationSeconds)
        );
        emit DisputeEscalated(
            bountyId, attemptId, _disputePolicies[bountyId].fallbackArbitrator,
            record.fallbackUntil
        );
    }

    function decideFallback(
        uint256 bountyId, Ruling ruling, bytes32 decisionDigest
    ) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.FallbackReview) revert IncorrectCaseState();
        if (block.timestamp >= record.fallbackUntil) revert DisputeWindowClosed();
        _requireIndependentArbiters(bountyId);
        if (msg.sender != _disputePolicies[bountyId].fallbackArbitrator) {
            revert UnauthorizedDisputeActor();
        }
        _checkRuling(ruling, decisionDigest);
        _finalize(bountyId, attemptId, ruling, msg.sender, decisionDigest);
    }

    /**
     * Enforceable deterministic last resort when BOTH arbitrators do nothing.
     * If the case disputes two verified approvals, no unanswered challenge
     * can veto the contributor: developer wins. If reviewer results are
     * missing, rejected or inconclusive, precommitted split 50/50 avoids
     * allowing reviewer silence to confiscate all timely submitted work.
     * This SPLIT IS GAMEABLE; do not accept funds until business rules, bonds,
     * independent review and #41 security review approve this policy.
     *
     * An appealed primary ruling stands if the fallback arbitrator is silent,
     * so repeated baseless appeals cannot change the economic outcome.
     */
    function finalizeSilentFallback(uint256 bountyId) external onlyCorrectChain {
        uint64 attemptId = _activeLatestAttempt(bountyId);
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state != CaseState.FallbackReview) revert IncorrectCaseState();
        if (block.timestamp < record.fallbackUntil) revert DisputeDeadlineNotReached();

        Ruling ruling;
        bytes32 digest;
        if (record.primaryRuling != Ruling.None) {
            ruling = record.primaryRuling;
            digest = record.primaryDecisionDigest;
        } else if (record.cause == CaseCause.SponsorChallenge) {
            ruling = Ruling.Developer;
            digest = sha256(abi.encode(
                "CertiFiks:unanswered-challenge:v1", bountyId, attemptId,
                record.reasonDigest, record.attemptDigest
            ));
        } else {
            ruling = Ruling.Split;
            digest = sha256(abi.encode(
                "CertiFiks:unanswered-verification:v1", bountyId, attemptId,
                record.reasonDigest, record.attemptDigest
            ));
        }
        _finalize(bountyId, attemptId, ruling, address(0), digest);
    }

    function _finalize(
        uint256 bountyId, uint64 attemptId, Ruling ruling,
        address adjudicator, bytes32 finalReason
    ) internal {
        DisputeCase storage record = _openCurrent(bountyId, attemptId);
        if (record.state == CaseState.Finalized) revert IncorrectCaseState();
        record.state = CaseState.Finalized;
        record.finalRuling = ruling;
        record.finalDecisionDigest = finalReason;
        record.finalAdjudicator = adjudicator;
        (uint256 developer, uint256 sponsor) = _calculateShares(bountyId, ruling);
        emit DisputeFinalized(
            bountyId, attemptId, ruling, adjudicator, finalReason, developer, sponsor
        );
        // No ETH transfer. #16 must credit rights exactly ONCE, after checking
        // this terminal decision and any non-dispute approval finality.
    }

    function _calculateShares(uint256 bountyId, Ruling ruling)
        internal view returns (uint256 developer, uint256 sponsor)
    {
        uint256 atoms = _fundingTerms[bountyId].rewardAtoms;
        if (ruling == Ruling.Developer) return (atoms, 0);
        if (ruling == Ruling.Sponsor) return (0, atoms);
        developer = atoms / 2;
        sponsor = atoms - developer; // exact conservation even for odd atoms
    }

    function readDisputePolicy(uint256 bountyId)
        external view returns (DisputePolicy memory)
    {
        _terms(bountyId);
        return _disputePolicies[bountyId];
    }

    function readDisputeCase(uint256 bountyId, uint64 attemptId)
        external view returns (DisputeCase memory)
    {
        _terms(bountyId);
        if (attemptId == 0 || attemptId > latestAttemptId[bountyId]) revert UnknownAttempt();
        return _disputeCases[bountyId][attemptId];
    }

    function readFinalEntitlements(uint256 bountyId, uint64 attemptId)
        external view returns (uint256 developerAtoms, uint256 sponsorAtoms)
    {
        _terms(bountyId);
        DisputeCase storage record = _disputeCases[bountyId][attemptId];
        if (record.state != CaseState.Finalized || record.attemptId != attemptId) {
            revert DecisionNotFinal();
        }
        return _calculateShares(bountyId, record.finalRuling);
    }
}
