// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolCommitmentV1} from "../src/ProtocolCommitmentV1.sol";

contract ProtocolCommitmentV1Test {
    function testMatchesPublishedTypeScriptPythonVector() public pure {
        ProtocolCommitmentV1.AttemptV1 memory a = ProtocolCommitmentV1.AttemptV1({
            chainGenesis: bytes32(uint256(type(uint256).max / 0xff * 0x11)),
            contractLocatorHash: bytes32(uint256(type(uint256).max / 0xff * 0x22)),
            bountyId: 17,
            attemptId: 2,
            repositoryId: 123456,
            baseCommitSha: hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            headCommitSha: hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            manifestDigest: bytes32(uint256(type(uint256).max / 0xff * 0x33)),
            imageDigest: bytes32(uint256(type(uint256).max / 0xff * 0x44)),
            resultDigest: bytes32(uint256(type(uint256).max / 0xff * 0x55)),
            expiryUnix: 1790000000
        });
        require(ProtocolCommitmentV1.digestAttempt(a) ==
            0x5330e70c15792fbcd598707c61d589fe3032b6afd20c9592f83cf6e1a59c42b6, "hash mismatch");
    }
}
