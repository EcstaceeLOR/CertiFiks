// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VerifierRegistryModuleV1} from "./VerifierRegistryModuleV1.sol";

/**
 * @title SignedVerifierDecisionModuleV1
 * @notice Checks exact EIP-712 reviewer signatures and transitions a submitted
 *         attempt into a challenge window, an escalated review or timeout.
 *
 * @dev ABSTRACT. No public funding, adjudication, payout or withdrawal here.
 *      EIP-712 proves which enrolled wallet signed a report, NOT that its
 *      tests were genuinely executed. GitHub provenance, independent worker
 *      evidence and social organization independence are dependencies.
 *      Do not deploy a funding harness or accept user funds (#14-#18, #41).
 */
abstract contract SignedVerifierDecisionModuleV1 is VerifierRegistryModuleV1 {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant EIP712_NAME_HASH = keccak256("CertiFiksVerifier");
    bytes32 internal constant EIP712_VERSION_HASH = keccak256("1");
    bytes32 internal constant VERDICT_TYPEHASH = keccak256(
        "CertiFiksVerifierVote(uint256 bountyId,uint64 attemptId,bytes32 organizationId,uint64 signerEpoch,bytes32 attemptDigest,bytes32 manifestDigest,bytes32 verifierPolicyDigest,bytes20 headGitSha,bytes32 reportDigest,bytes32 imageDigest,uint8 outcome,bool baselineFailed,bool candidatePassed,bool regressionsPassed,uint64 expiresAt)"
    );
    uint256 private constant SECP256K1_HALF_ORDER =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    enum Outcome { None, Approved, Rejected, Inconclusive, RunnerFailure }
    enum ReviewStatus { Pending, ChallengeWindow, EscalationRequired, TimedOut }

    /**
     * All fields are fixed-size. abi.encode(TYPEHASH, vote) is exactly the
     * EIP-712 struct encoding of this tuple in declaration order.
     */
    struct SignedVerdict {
        uint256 bountyId;
        uint64 attemptId;
        bytes32 organizationId;
        uint64 signerEpoch;
        bytes32 attemptDigest;
        bytes32 manifestDigest;
        bytes32 verifierPolicyDigest;
        bytes20 headGitSha;
        bytes32 reportDigest;
        bytes32 imageDigest;
        uint8 outcome;
        bool baselineFailed;
        bool candidatePassed;
        bool regressionsPassed;
        uint64 expiresAt;
    }

    struct RecordedVerdict {
        bytes32 typedDigest;
        bytes32 reportDigest;
        bytes32 attemptDigest;
        address signer;
        uint64 signerEpoch;
        uint64 recordedAt;
        uint8 outcome;
        bool baselineFailed;
        bool candidatePassed;
        bool regressionsPassed;
        bool recorded;
    }

    struct ReviewDecision {
        ReviewStatus status;
        uint8 recordedVotes;
        uint8 positiveVotes;
        uint64 challengeUntil;
        uint64 decidedAt;
        bytes32 triggeringVoteDigest;
    }

    error InvalidVerdict();
    error ContradictoryApproval();
    error MismatchedVerdictIdentity();
    error InvalidSignatureEncoding();
    error InvalidSignatureSigner();
    error StaleOrExpiredVerdict();
    error DuplicateVerdict();
    error ReviewIsNotPending();
    error ReviewDeadlineNotReached();
    error ChallengeTimeOverflow();

    event SignedVerdictRecorded(
        uint256 indexed bountyId,
        uint64 indexed attemptId,
        bytes32 indexed organizationId,
        address signer,
        bytes32 typedDigest,
        bytes32 reportDigest,
        uint8 outcome,
        uint64 signerEpoch
    );
    event ReviewDecisionChanged(
        uint256 indexed bountyId,
        uint64 indexed attemptId,
        ReviewStatus status,
        uint8 recordedVotes,
        uint8 positiveVotes,
        bytes32 triggeringVoteDigest,
        uint64 challengeUntil
    );

    mapping(uint256 => mapping(uint64 => mapping(bytes32 => RecordedVerdict))) internal _verdicts;
    mapping(uint256 => mapping(uint64 => ReviewDecision)) internal _decisions;

    constructor(uint256 chainId, address governance)
        VerifierRegistryModuleV1(chainId, governance)
    {}

    function verifierEip712DomainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                EIP712_NAME_HASH,
                EIP712_VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    function typedVerdictDigest(SignedVerdict calldata vote) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(VERDICT_TYPEHASH, vote));
        return keccak256(abi.encodePacked(hex"1901", verifierEip712DomainSeparator(), structHash));
    }

    /**
     * A relayer may submit the signed report but cannot choose the signer,
     * policy, vote or digest: these are all authenticated by EIP-712.
     * Signer must first directly accept the exact job and declare its report
     * hash on chain (#12). All other action is denied.
     */
    function submitSignedVerdict(SignedVerdict calldata vote, bytes calldata signature)
        external onlyCorrectChain
    {
        address assignedSigner = _assertEligibleVote(vote);
        bytes32 digest = typedVerdictDigest(vote);
        address recovered = _recoverSigner(digest, signature);
        if (recovered != assignedSigner) revert InvalidSignatureSigner();
        _commitVerifiedVote(vote, digest, recovered);
    }

    function _assertEligibleVote(SignedVerdict calldata vote)
        internal view returns (address assignedSigner)
    {
        BountyTerms storage terms = _terms(vote.bountyId);
        if (
            vote.attemptId == 0 ||
            latestAttemptId[vote.bountyId] != vote.attemptId ||
            _assignment[vote.bountyId].state != AssignmentState.Submitted
        ) revert MismatchedVerdictIdentity();
        if (_decisions[vote.bountyId][vote.attemptId].status != ReviewStatus.Pending) {
            revert ReviewIsNotPending();
        }
        if (!reviewerRoster[vote.bountyId].configured ||
            !isCommittedReviewer[vote.bountyId][vote.organizationId]) {
            revert ReviewerNotInCommittedRoster();
        }
        ReviewerJob storage job = _job(vote.bountyId, vote.attemptId, vote.organizationId);
        ReviewerOrganization storage organization = _active(vote.organizationId);
        _requireNoRoleConflict(vote.bountyId, vote.organizationId);
        if (
            !job.accepted ||
            job.declaredReportDigest == bytes32(0) ||
            job.declaredReportDigest != vote.reportDigest ||
            job.attemptDigest != vote.attemptDigest ||
            organization.signerEpoch != vote.signerEpoch ||
            job.signerEpoch != vote.signerEpoch ||
            job.assignedSigner != organization.currentSigner
        ) revert MismatchedVerdictIdentity();

        FixAttempt storage attempt = _attempts[vote.bountyId][vote.attemptId];
        if (
            attempt.attemptDigest != vote.attemptDigest ||
            attempt.candidate.headGitSha != vote.headGitSha ||
            attempt.candidate.imageDigest != vote.imageDigest ||
            terms.manifestDigest != vote.manifestDigest ||
            terms.verifierPolicyDigest != vote.verifierPolicyDigest
        ) revert MismatchedVerdictIdentity();
        if (
            vote.expiresAt <= block.timestamp ||
            vote.expiresAt > job.deadline ||
            block.timestamp >= job.deadline
        ) revert StaleOrExpiredVerdict();
        if (vote.outcome < uint8(Outcome.Approved) ||
            vote.outcome > uint8(Outcome.RunnerFailure)) revert InvalidVerdict();
        if (
            vote.outcome == uint8(Outcome.Approved) &&
            (!vote.baselineFailed || !vote.candidatePassed || !vote.regressionsPassed)
        ) revert ContradictoryApproval();
        if (_verdicts[vote.bountyId][vote.attemptId][vote.organizationId].recorded) {
            revert DuplicateVerdict();
        }
        assignedSigner = job.assignedSigner;
    }

    function _commitVerifiedVote(
        SignedVerdict calldata vote, bytes32 digest, address recovered
    ) internal {
        RecordedVerdict storage prior = _verdicts[vote.bountyId][vote.attemptId][vote.organizationId];
        prior.typedDigest = digest;
        prior.reportDigest = vote.reportDigest;
        prior.attemptDigest = vote.attemptDigest;
        prior.signer = recovered;
        prior.signerEpoch = vote.signerEpoch;
        prior.recordedAt = uint64(block.timestamp);
        prior.outcome = vote.outcome;
        prior.baselineFailed = vote.baselineFailed;
        prior.candidatePassed = vote.candidatePassed;
        prior.regressionsPassed = vote.regressionsPassed;
        prior.recorded = true;

        emit SignedVerdictRecorded(
            vote.bountyId, vote.attemptId, vote.organizationId, recovered,
            digest, vote.reportDigest, vote.outcome, vote.signerEpoch
        );

        ReviewDecision storage decision = _decisions[vote.bountyId][vote.attemptId];
        decision.recordedVotes += 1;
        if (vote.outcome == uint8(Outcome.Approved)) decision.positiveVotes += 1;

        if (vote.outcome != uint8(Outcome.Approved)) {
            decision.status = ReviewStatus.EscalationRequired;
        } else if (decision.positiveVotes >= reviewerRoster[vote.bountyId].quorum) {
            uint256 until = block.timestamp + uint256(_fundingTerms[vote.bountyId].challengeSeconds);
            if (until > type(uint64).max) revert ChallengeTimeOverflow();
            decision.status = ReviewStatus.ChallengeWindow;
            decision.challengeUntil = uint64(until);
        }
        if (decision.status != ReviewStatus.Pending) {
            decision.decidedAt = uint64(block.timestamp);
            decision.triggeringVoteDigest = digest;
            emit ReviewDecisionChanged(
                vote.bountyId, vote.attemptId, decision.status,
                decision.recordedVotes, decision.positiveVotes,
                digest, decision.challengeUntil
            );
        }
        // Nothing here can transfer ETH, mint credit or finalize a payout.
    }

    /**
     * Inadequate/missing reviewer evidence cannot silently become approval.
     * Anyone may flag an expired incomplete review for #14 escalation.
     */
    function expireIncompleteReview(uint256 bountyId, uint64 attemptId)
        external onlyCorrectChain
    {
        BountyTerms storage terms = _terms(bountyId);
        if (attemptId == 0 || latestAttemptId[bountyId] != attemptId ||
            _assignment[bountyId].state != AssignmentState.Submitted) {
            revert MismatchedVerdictIdentity();
        }
        ReviewDecision storage decision = _decisions[bountyId][attemptId];
        if (decision.status != ReviewStatus.Pending) revert ReviewIsNotPending();
        uint256 deadline = uint256(_attempts[bountyId][attemptId].submittedAt) +
            uint256(terms.verificationSeconds);
        if (block.timestamp < deadline) revert ReviewDeadlineNotReached();
        decision.status = ReviewStatus.TimedOut;
        decision.decidedAt = uint64(block.timestamp);
        emit ReviewDecisionChanged(
            bountyId, attemptId, ReviewStatus.TimedOut,
            decision.recordedVotes, decision.positiveVotes, bytes32(0), 0
        );
    }

    function readRecordedVerdict(uint256 bountyId, uint64 attemptId, bytes32 organizationId)
        external view returns (RecordedVerdict memory)
    {
        _terms(bountyId);
        if (attemptId == 0 || attemptId > latestAttemptId[bountyId]) revert UnknownAttempt();
        return _verdicts[bountyId][attemptId][organizationId];
    }

    function readReviewDecision(uint256 bountyId, uint64 attemptId)
        external view returns (ReviewDecision memory)
    {
        _terms(bountyId);
        if (attemptId == 0 || attemptId > latestAttemptId[bountyId]) revert UnknownAttempt();
        return _decisions[bountyId][attemptId];
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature)
        internal pure returns (address signer)
    {
        if (signature.length != 65) revert InvalidSignatureEncoding();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (
            uint256(r) == 0 || uint256(s) == 0 ||
            uint256(s) > SECP256K1_HALF_ORDER ||
            (v != 27 && v != 28)
        ) revert InvalidSignatureEncoding();
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignatureEncoding();
    }
}
