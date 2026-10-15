// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BountyAssignmentModuleV1} from "./BountyAssignmentModuleV1.sol";

/**
 * @title BountySubmissionModuleV1
 * @notice Exact GitHub commit claims anchored to a wallet-signed application.
 * @dev Abstract. The chain CANNOT query GitHub; these values are NOT verified
 * GitHub facts until an authorized GitHub App separately authenticates and
 * attests repository/PR identity, access and commit signatures (#20/#13).
 * No reward approval, credits, refunds or public funding method exist here.
 * Never deploy a funding harness or use with real tokens before #14–#18/#41.
 */
abstract contract BountySubmissionModuleV1 is BountyAssignmentModuleV1 {
    uint8 internal constant ATTEMPT_VERSION = 1;
    bytes internal constant ATTEMPT_DOMAIN = "CertiFiks:github-attempt:v1";

    struct Candidate {
        uint256 repositoryId;
        uint256 pullNumber;
        bytes20 baseGitSha;
        bytes20 headGitSha;
        bytes32 imageDigest;
        bytes32 evidenceDigest;
        bytes32 manifestDigest;
        uint8 manifestVersion;
    }

    struct FixAttempt {
        uint64 attemptId;
        uint64 submittedAt;
        address developer;
        Candidate candidate;
        bytes32 attemptDigest;
    }

    error InvalidPullNumber();
    error InvalidCandidateSHA();
    error UnchangedCandidateSHA();
    error EmptyImageDigest();
    error EmptyEvidenceDigest();
    error RepositoryIdentityMismatch();
    error BaselineIdentityMismatch();
    error InvalidManifestVersion();
    error NoSubmission();
    error UnknownAttempt();
    error ReviewRetryNotAuthorized();
    error PreviouslySubmittedRevision();
    error AttemptOverflow();

    event GitHubAttemptPinned(
        uint256 indexed bountyId,
        uint64 indexed attemptId,
        address indexed developer,
        uint256 repositoryId,
        uint256 pullNumber,
        bytes20 baseGitSha,
        bytes20 headGitSha,
        bytes32 imageDigest,
        bytes32 evidenceDigest,
        bytes32 manifestDigest,
        bytes32 attemptDigest
    );
    event ReviewRetryAuthorized(uint256 indexed bountyId, uint64 indexed attemptId, bytes32 reviewDigest);

    // Indexed by immutable bounty ID and monotonic attempt number. Old records
    // are NEVER overwritten even when a future reviewer authorizes a retry.
    mapping(uint256 => mapping(uint64 => FixAttempt)) internal _attempts;
    mapping(uint256 => uint64) public latestAttemptId;
    mapping(uint256 => mapping(bytes20 => bool)) public seenHeadGitSha;
    mapping(uint256 => bytes32) internal _retryReviewDigest;

    constructor(uint256 chainId) BountyAssignmentModuleV1(chainId) {}

    /** First attempt: direct wallet transaction from accepted developer only. */
    function submitCandidate(uint256 bountyId, Candidate calldata candidate) external onlyCorrectChain {
        _assertCanSubmit(bountyId, msg.sender);
        if (latestAttemptId[bountyId] != 0) revert InvalidAssignmentState();
        _validateCandidate(bountyId, candidate);
        _recordAttempt(bountyId, 1, candidate);
        _lockTimelySubmission(bountyId);
    }

    /**
     * @notice Re-submit only after future independent review explicitly
     * authorizes a retry of the immediately preceding attempt.
     * This contract has NO public function that can authorize a retry.
     */
    function resubmitCandidate(uint256 bountyId, Candidate calldata candidate) external onlyCorrectChain {
        BountyTerms storage terms = _terms(bountyId);
        Assignment storage assignment = _assignment[bountyId];
        if (
            assignment.state != AssignmentState.Submitted ||
            assignment.developer != msg.sender ||
            msg.sender == address(0)
        ) revert InvalidAssignmentState();
        if (block.timestamp > terms.submissionDeadline) revert SubmissionDeadlinePassed();

        uint64 previousId = latestAttemptId[bountyId];
        if (previousId == 0) revert NoSubmission();
        bytes32 authorization = _retryReviewDigest[bountyId];
        if (authorization == bytes32(0)) revert ReviewRetryNotAuthorized();

        _validateCandidate(bountyId, candidate);
        FixAttempt storage previous = _attempts[bountyId][previousId];
        // Re-review must be the same bounty and PR, not a different request.
        if (candidate.pullNumber != previous.candidate.pullNumber) revert InvalidPullNumber();
        if (candidate.headGitSha == previous.candidate.headGitSha) revert UnchangedCandidateSHA();
        if (previousId == type(uint64).max) revert AttemptOverflow();

        _retryReviewDigest[bountyId] = bytes32(0);
        _recordAttempt(bountyId, previousId + 1, candidate);
    }

    function _validateCandidate(uint256 bountyId, Candidate calldata candidate) internal view {
        BountyTerms storage terms = _terms(bountyId);
        if (candidate.repositoryId != terms.repositoryId) revert RepositoryIdentityMismatch();
        if (candidate.baseGitSha != terms.baselineGitSha) revert BaselineIdentityMismatch();
        if (candidate.manifestVersion != terms.version || candidate.manifestVersion != ATTEMPT_VERSION) {
            revert InvalidManifestVersion();
        }
        if (candidate.pullNumber == 0) revert InvalidPullNumber();
        if (candidate.headGitSha == bytes20(0)) revert InvalidCandidateSHA();
        if (candidate.headGitSha == candidate.baseGitSha) revert UnchangedCandidateSHA();
        if (candidate.imageDigest == bytes32(0)) revert EmptyImageDigest();
        if (candidate.evidenceDigest == bytes32(0)) revert EmptyEvidenceDigest();
        if (seenHeadGitSha[bountyId][candidate.headGitSha]) revert PreviouslySubmittedRevision();
    }

    function _recordAttempt(uint256 bountyId, uint64 attemptId, Candidate calldata candidate) internal {
        BountyTerms storage terms = _terms(bountyId);
        bytes32 digest = sha256(
            abi.encode(
                ATTEMPT_DOMAIN,
                expectedChainId,
                address(this),
                bountyId,
                attemptId,
                msg.sender,
                candidate.repositoryId,
                candidate.pullNumber,
                candidate.baseGitSha,
                candidate.headGitSha,
                terms.manifestDigest,
                candidate.manifestVersion,
                candidate.imageDigest,
                candidate.evidenceDigest
            )
        );
        Candidate memory immutableCandidate = Candidate({
            repositoryId: candidate.repositoryId,
            pullNumber: candidate.pullNumber,
            baseGitSha: candidate.baseGitSha,
            headGitSha: candidate.headGitSha,
            imageDigest: candidate.imageDigest,
            evidenceDigest: candidate.evidenceDigest,
            manifestDigest: terms.manifestDigest,
            manifestVersion: candidate.manifestVersion
        });
        _attempts[bountyId][attemptId] = FixAttempt({
            attemptId: attemptId,
            submittedAt: uint64(block.timestamp),
            developer: msg.sender,
            candidate: immutableCandidate,
            attemptDigest: digest
        });
        latestAttemptId[bountyId] = attemptId;
        seenHeadGitSha[bountyId][candidate.headGitSha] = true;
        emit GitHubAttemptPinned(
            bountyId, attemptId, msg.sender, candidate.repositoryId,
            candidate.pullNumber, candidate.baseGitSha, candidate.headGitSha,
            candidate.imageDigest, candidate.evidenceDigest, terms.manifestDigest, digest
        );
    }

    /**
     * @dev Integration hook for a future #13 reviewer quorum verifying the
     * precise previous attempt + reason, not a public admin/sponsor override.
     * A test-only harness may exercise this, but cannot ship to production.
     */
    function _authorizeRetryFromReview(uint256 bountyId, uint64 attemptId, bytes32 reviewDigest) internal {
        _terms(bountyId);
        if (_assignment[bountyId].state != AssignmentState.Submitted) revert InvalidAssignmentState();
        if (attemptId == 0 || latestAttemptId[bountyId] != attemptId) revert UnknownAttempt();
        if (reviewDigest == bytes32(0) || _retryReviewDigest[bountyId] != bytes32(0)) {
            revert ReviewRetryNotAuthorized();
        }
        _retryReviewDigest[bountyId] = reviewDigest;
        emit ReviewRetryAuthorized(bountyId, attemptId, reviewDigest);
    }

    function getPinnedAttempt(uint256 bountyId, uint64 attemptId) external view returns (FixAttempt memory) {
        _terms(bountyId);
        if (attemptId == 0 || attemptId > latestAttemptId[bountyId]) revert UnknownAttempt();
        return _attempts[bountyId][attemptId];
    }

    function retryReviewDigest(uint256 bountyId) external view returns (bytes32) {
        _terms(bountyId);
        return _retryReviewDigest[bountyId];
    }
}
