// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BountyFundingModuleV1
 * @notice INTERNAL-only immutable funding terms for a future approved escrow.
 * @dev ABSTRACT ON PURPOSE. It has NO external payable entrypoint.
 * DO NOT deploy or accept real funds using test harnesses. No release,
 * expiry, arbitration, indexer or withdrawal routes exist in this module yet.
 *
 * Issue #9 develops the funding invariant independently of the historical
 * CertiFiksEscrow (UNSAFE). #14-#17 implement fair terminal transitions.
 * #18 must prove compatibility with the qualifying Portaldot V3 testnet.
 */
abstract contract BountyFundingModuleV1 {
    uint8 internal constant TERMS_VERSION = 1;
    uint256 internal constant MAX_SUBMISSION_WINDOW = 90 days;
    uint64 internal constant MIN_REVIEW_WINDOW = 1 hours;
    uint64 internal constant MAX_REVIEW_WINDOW = 30 days;

    enum AssetKind { Native }

    struct FundingRequest {
        uint256 repositoryId;
        bytes20 baselineGitSha;
        bytes32 manifestDigest;
        bytes32 verifierPolicyDigest;
        bytes32 disputePolicyDigest;
        address primaryArbitrator;
        uint64 submissionDeadline;
        uint64 verificationSeconds;
        uint64 challengeSeconds;
        uint64 arbitrationSeconds;
        uint8 assetKind;
    }

    struct BountyTerms {
        uint8 version;
        address sponsor;
        uint256 repositoryId;
        bytes20 baselineGitSha;
        bytes32 manifestDigest;
        bytes32 verifierPolicyDigest;
        bytes32 disputePolicyDigest;
        address primaryArbitrator;
        uint64 submissionDeadline;
        uint64 verificationSeconds;
        uint64 challengeSeconds;
        uint64 arbitrationSeconds;
        uint256 rewardAtoms;
        uint8 assetKind;
    }

    error InvalidExpectedChain();
    error IncorrectChain(uint256 actual, uint256 expected);
    error EmptyReward();
    error InvalidRepositoryId();
    error MissingGitCommit();
    error MissingManifestDigest();
    error MissingVerifierPolicy();
    error MissingDisputePolicy();
    error InvalidPrimaryArbitrator();
    error UnsupportedAsset(uint8 kind);
    error InvalidSubmissionDeadline();
    error InvalidVerificationWindow();
    error InvalidChallengeWindow();
    error InvalidArbitrationWindow();
    error UnknownBounty(uint256 id);

    event BountyFunded(
        uint256 indexed id,
        address indexed sponsor,
        uint256 indexed repositoryId,
        bytes32 manifestDigest,
        uint256 rewardAtoms,
        uint64 submissionDeadline
    );

    uint256 public immutable expectedChainId;
    uint256 public nextBountyId = 1;
    uint256 public totalReservedAtoms;

    mapping(uint256 => BountyTerms) internal _fundingTerms;

    constructor(uint256 chainId) {
        if (chainId == 0) revert InvalidExpectedChain();
        expectedChainId = chainId;
    }

    /**
     * @dev This entrypoint deliberately remains INTERNAL. The final custody
     * contract may expose funding only after dispute liveness, withdrawals,
     * refunds, and role authorization have been implemented and independently
     * reviewed. No money is sent to an external address in this function.
     */
    function _recordFunding(FundingRequest calldata request)
        internal
        returns (uint256 bountyId)
    {
        if (block.chainid != expectedChainId) {
            revert IncorrectChain(block.chainid, expectedChainId);
        }
        if (msg.value == 0) revert EmptyReward();
        if (request.repositoryId == 0) revert InvalidRepositoryId();
        if (request.baselineGitSha == bytes20(0)) revert MissingGitCommit();
        if (request.manifestDigest == bytes32(0)) revert MissingManifestDigest();
        if (request.verifierPolicyDigest == bytes32(0)) revert MissingVerifierPolicy();
        if (request.disputePolicyDigest == bytes32(0)) revert MissingDisputePolicy();
        if (request.primaryArbitrator == address(0) || request.primaryArbitrator == msg.sender) {
            revert InvalidPrimaryArbitrator();
        }
        if (request.assetKind != uint8(AssetKind.Native)) {
            revert UnsupportedAsset(request.assetKind);
        }
        if (
            request.submissionDeadline <= block.timestamp ||
            uint256(request.submissionDeadline) > block.timestamp + MAX_SUBMISSION_WINDOW
        ) revert InvalidSubmissionDeadline();
        if (
            request.verificationSeconds < MIN_REVIEW_WINDOW ||
            request.verificationSeconds > MAX_REVIEW_WINDOW
        ) revert InvalidVerificationWindow();
        if (
            request.challengeSeconds < MIN_REVIEW_WINDOW ||
            request.challengeSeconds > MAX_REVIEW_WINDOW
        ) revert InvalidChallengeWindow();
        if (
            request.arbitrationSeconds < MIN_REVIEW_WINDOW ||
            request.arbitrationSeconds > MAX_REVIEW_WINDOW
        ) revert InvalidArbitrationWindow();

        bountyId = nextBountyId;
        nextBountyId = bountyId + 1;
        _fundingTerms[bountyId] = BountyTerms({
            version: TERMS_VERSION,
            sponsor: msg.sender,
            repositoryId: request.repositoryId,
            baselineGitSha: request.baselineGitSha,
            manifestDigest: request.manifestDigest,
            verifierPolicyDigest: request.verifierPolicyDigest,
            disputePolicyDigest: request.disputePolicyDigest,
            primaryArbitrator: request.primaryArbitrator,
            submissionDeadline: request.submissionDeadline,
            verificationSeconds: request.verificationSeconds,
            challengeSeconds: request.challengeSeconds,
            arbitrationSeconds: request.arbitrationSeconds,
            rewardAtoms: msg.value,
            assetKind: request.assetKind
        });
        totalReservedAtoms += msg.value;
        emit BountyFunded(
            bountyId,
            msg.sender,
            request.repositoryId,
            request.manifestDigest,
            msg.value,
            request.submissionDeadline
        );
    }

    function getFundingTerms(uint256 bountyId) external view returns (BountyTerms memory) {
        if (bountyId == 0 || bountyId >= nextBountyId) revert UnknownBounty(bountyId);
        return _fundingTerms[bountyId];
    }
}
