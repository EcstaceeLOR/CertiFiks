// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Domain-separated fixed-width protocol hash conformance reference.
 * @dev This only computes hashes: it is NOT a payout/verifier implementation,
 *      not a signature check, and NOT deployed or qualified on Portaldot V3.
 */
library ProtocolCommitmentV1 {
    bytes internal constant ATTESTATION_DOMAIN = hex"436572746946696b733a617474656d70742d6174746573746174696f6e3a763100";

    struct AttemptV1 {
        bytes32 chainGenesis;
        bytes32 contractLocatorHash;
        uint256 bountyId;
        uint64 attemptId;
        uint256 repositoryId;
        bytes20 baseCommitSha;
        bytes20 headCommitSha;
        bytes32 manifestDigest;
        bytes32 imageDigest;
        bytes32 resultDigest;
        uint64 expiryUnix;
    }

    function digestAttempt(AttemptV1 memory a) internal pure returns (bytes32) {
        return sha256(
            abi.encodePacked(
                ATTESTATION_DOMAIN,
                a.chainGenesis,
                a.contractLocatorHash,
                a.bountyId,
                a.attemptId,
                a.repositoryId,
                a.baseCommitSha,
                a.headCommitSha,
                a.manifestDigest,
                a.imageDigest,
                a.resultDigest,
                a.expiryUnix
            )
        );
    }
}
