// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BoundedArbitrationModuleV1} from "./BoundedArbitrationModuleV1.sol";

/**
 * @title FairEntitlementModuleV1
 * @notice Single-use beneficiary accounting decisions, never transfers.
 *
 * ABSTRACT SECURITY BOUNDARY: there is NO public funding/withdrawal method.
 * Recording an entitlement does not move ETH, create a claimable credit or
 * release reserved collateral. Those features require #16 and #17 audits.
 * Existing real-money custody must NOT be pointed at this module.
 */
abstract contract FairEntitlementModuleV1 is BoundedArbitrationModuleV1 {
    enum Reason {
        None,
        UnassignedSponsorCancellation,
        NoSubmissionAtDeadline,
        ApprovedFix,
        IndependentlyAdjudicatedSponsorRefund,
        SharedSilenceFallback
    }

    struct Entitlement {
        Reason reason;
        uint64 sourceAttemptId;
        uint64 recordedAt;
        address sponsor;
        address developer;
        uint256 sponsorAtoms;
        uint256 developerAtoms;
        bytes32 sourceAttemptDigest;
        bytes32 decisionReasonDigest;
    }

    error EntitlementAlreadyRecorded();
    error NotEligibleForEntitlement();
    error InvalidEntitlementDecision();
    error AccountingNotBacked();

    event EntitlementRecorded(
        uint256 indexed bountyId,
        uint64 indexed attemptId,
        Reason indexed reason,
        address sponsor,
        address developer,
        uint256 sponsorAtoms,
        uint256 developerAtoms,
        bytes32 sourceAttemptDigest,
        bytes32 decisionReasonDigest
    );

    mapping(uint256 => Entitlement) internal _entitlements;

    constructor(uint256 chainId, address governance)
        BoundedArbitrationModuleV1(chainId, governance)
    {}

    /**
     * Pre-assignment sponsor cancellation or missed submission both
     * qualify ONLY if there is no pinned attempt and the assignment state
     * has already reached its immutable terminal eligibility condition.
     * No sponsor may cancel a completed and timely submitted candidate.
     */
    function recordNoSubmissionRefund(uint256 bountyId) external onlyCorrectChain {
        BountyTerms storage terms = _terms(bountyId);
        if (_entitlements[bountyId].reason != Reason.None) {
            revert EntitlementAlreadyRecorded();
        }
        if (latestAttemptId[bountyId] != 0) revert NotEligibleForEntitlement();

        AssignmentState state = _assignment[bountyId].state;
        Reason reason;
        if (state == AssignmentState.CancelledPendingRefund) {
            reason = Reason.UnassignedSponsorCancellation;
        } else if (state == AssignmentState.ExpiredPendingRefund &&
                   block.timestamp > terms.submissionDeadline) {
            reason = Reason.NoSubmissionAtDeadline;
        } else {
            revert NotEligibleForEntitlement();
        }

        // Write the single immutable accounting decision before any future
        // #16 contract is permitted to issue a credit or transfer.
        Entitlement memory draft;
        draft.reason = reason;
        draft.recordedAt = uint64(block.timestamp);
        draft.sponsor = terms.sponsor;
        draft.sponsorAtoms = terms.rewardAtoms;
        _commitEntitlement(bountyId, draft);
    }

    /**
     * A timely submitted fix cannot produce a sponsor refund from the
     * starter's original verifier-silence shortcut. A resolved exact
     * on-chain arbitration case, or final unchallenged positive quorum,
     * is the sole authority for its entitlement classification.
     */
    function recordResolvedEntitlement(uint256 bountyId, uint64 attemptId)
        external onlyCorrectChain
    {
        BountyTerms storage terms = _terms(bountyId);
        if (_entitlements[bountyId].reason != Reason.None) {
            revert EntitlementAlreadyRecorded();
        }
        if (
            attemptId == 0 ||
            attemptId != latestAttemptId[bountyId] ||
            _assignment[bountyId].state != AssignmentState.Submitted
        ) revert NotEligibleForEntitlement();

        DisputeCase storage adjudication = _cases[bountyId][attemptId];
        if (
            adjudication.phase != CasePhase.Resolved ||
            adjudication.attemptId != attemptId ||
            adjudication.attemptDigest != _attempts[bountyId][attemptId].attemptDigest
        ) revert NotEligibleForEntitlement();

        Reason reason;
        uint256 sponsorAtoms;
        uint256 developerAtoms;
        Award outcome = adjudication.finalAward;
        if (outcome == Award.DeveloperReward) {
            reason = Reason.ApprovedFix;
            developerAtoms = terms.rewardAtoms;
        } else if (outcome == Award.SponsorRefund) {
            reason = Reason.IndependentlyAdjudicatedSponsorRefund;
            sponsorAtoms = terms.rewardAtoms;
        } else if (outcome == Award.SharedResolution) {
            // Only the explicit dual-arbitrator nonresponse fallback may
            // produce a shared result. Human rulings cannot request it.
            if (_decisions[bountyId][attemptId].status == ReviewStatus.ChallengeWindow) {
                revert InvalidEntitlementDecision();
            }
            reason = Reason.SharedSilenceFallback;
            developerAtoms = terms.rewardAtoms / 2;
            sponsorAtoms = terms.rewardAtoms - developerAtoms;
        } else {
            revert InvalidEntitlementDecision();
        }

        bytes32 reasonDigest = adjudication.fallbackReasonDigest;
        if (reasonDigest == bytes32(0)) reasonDigest = adjudication.primaryReasonDigest;
        if (reasonDigest == bytes32(0)) reasonDigest = adjudication.openingReasonDigest;
        if (reasonDigest == bytes32(0)) {
            // Unchallenged positive-quorum settlement is identifiable from
            // its immutable signed EIP712 review decision.
            reasonDigest = _decisions[bountyId][attemptId].triggeringVoteDigest;
        }
        if (reasonDigest == bytes32(0)) revert InvalidEntitlementDecision();

        Entitlement memory draft;
        draft.reason = reason;
        draft.sourceAttemptId = attemptId;
        draft.recordedAt = uint64(block.timestamp);
        draft.sponsor = terms.sponsor;
        draft.developer = _assignment[bountyId].developer;
        draft.sponsorAtoms = sponsorAtoms;
        draft.developerAtoms = developerAtoms;
        draft.sourceAttemptDigest = _attempts[bountyId][attemptId].attemptDigest;
        draft.decisionReasonDigest = reasonDigest;
        _commitEntitlement(bountyId, draft);
    }

    function _commitEntitlement(uint256 bountyId, Entitlement memory draft) internal {
        BountyTerms storage terms = _terms(bountyId);
        if (
            draft.reason == Reason.None ||
            _entitlements[bountyId].reason != Reason.None ||
            draft.sponsor != terms.sponsor ||
            draft.sponsorAtoms + draft.developerAtoms != terms.rewardAtoms ||
            (draft.sourceAttemptId != 0 &&
                (draft.developer == address(0) || draft.developer == terms.sponsor)) ||
            address(this).balance < totalReservedAtoms
        ) revert AccountingNotBacked();
        _entitlements[bountyId] = draft;
        emit EntitlementRecorded(
            bountyId, draft.sourceAttemptId, draft.reason,
            draft.sponsor, draft.developer,
            draft.sponsorAtoms, draft.developerAtoms,
            draft.sourceAttemptDigest, draft.decisionReasonDigest
        );
    }

    /**
     * Surplus is NEVER attributed to a bounty. ETH can be force-sent to an
     * EVM address without invoking a payable function. Governance may not
     * spend or rescue these unaccounted assets in this incomplete module.
     */
    function unreservedNativeSurplus() external view returns (uint256) {
        uint256 held = address(this).balance;
        return held > totalReservedAtoms ? held - totalReservedAtoms : 0;
    }

    function getEntitlement(uint256 bountyId) external view returns (Entitlement memory) {
        _terms(bountyId);
        return _entitlements[bountyId];
    }
}
