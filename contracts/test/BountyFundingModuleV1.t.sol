// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";

interface VmFunding {
    function deal(address who, uint256 newBalance) external;
    function prank(address who) external;
    function chainId(uint256 newChainId) external;
    function warp(uint256 timestamp) external;
}

/** @dev Foundry-only test harness, NOT a deployable production escrow. */
contract FundingHarnessV1 is BountyFundingModuleV1 {
    constructor(uint256 chainId) BountyFundingModuleV1(chainId) {}

    function fund(FundingRequest calldata request)
        external
        payable
        returns (uint256)
    {
        return _recordFunding(request);
    }
}

/**
 * @notice Tests the funding module's immutable terms and reserved balance.
 * @dev Pass/fail does NOT establish a safe end-to-end bounty or V3 deployment.
 */
contract BountyFundingModuleV1Test {
    VmFunding constant vm = VmFunding(address(uint160(uint256(keccak256("hevm cheat code")))));

    FundingHarnessV1 private escrow;
    uint256 private constant EXPECTED_CHAIN = 31337;
    address private constant SPONSOR = address(0xA112);

    function setUp() public {
        vm.chainId(EXPECTED_CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        escrow = new FundingHarnessV1(EXPECTED_CHAIN);
    }

    function _valid() internal view returns (BountyFundingModuleV1.FundingRequest memory) {
        return BountyFundingModuleV1.FundingRequest({
            repositoryId: 123456,
            baselineGitSha: hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            manifestDigest: bytes32(uint256(1)),
            verifierPolicyDigest: bytes32(uint256(2)),
            disputePolicyDigest: bytes32(uint256(3)),
            submissionDeadline: uint64(block.timestamp + 10 days),
            verificationSeconds: 2 days,
            challengeSeconds: 1 days,
            arbitrationSeconds: 2 days,
            assetKind: 0
        });
    }

    function _fund(BountyFundingModuleV1.FundingRequest memory req, uint256 amount)
        internal
        returns (uint256)
    {
        vm.prank(SPONSOR);
        return escrow.fund{value: amount}(req);
    }

    function _requireReject(BountyFundingModuleV1.FundingRequest memory req, uint256 amount)
        internal
    {
        vm.prank(SPONSOR);
        (bool ok,) = address(escrow).call{value: amount}(
            abi.encodeWithSelector(FundingHarnessV1.fund.selector, req)
        );
        require(!ok, "invalid funding terms accepted");
    }

    function testLocksExactNativeRewardAndImmutableTerms() public {
        BountyFundingModuleV1.FundingRequest memory req = _valid();
        uint256 id = _fund(req, 2 ether);
        require(id == 1, "wrong id");
        BountyFundingModuleV1.BountyTerms memory terms = escrow.getFundingTerms(id);
        require(terms.version == 1 && terms.sponsor == SPONSOR, "wrong identity");
        require(terms.repositoryId == 123456 && terms.baselineGitSha == req.baselineGitSha, "bad source");
        require(terms.manifestDigest == req.manifestDigest, "wrong manifest");
        require(terms.disputePolicyDigest == req.disputePolicyDigest, "missing fallback policy");
        require(terms.rewardAtoms == 2 ether && terms.assetKind == 0, "bad reward");
        require(escrow.totalReservedAtoms() == 2 ether, "bad liabilities");
        require(address(escrow).balance == 2 ether, "wrong contract balance");
    }

    function testNoFundingWithWrongChain() public {
        vm.chainId(EXPECTED_CHAIN + 1);
        _requireReject(_valid(), 1 ether);
        require(escrow.totalReservedAtoms() == 0, "wrong-chain credit");
    }

    function testMissingFieldsAndUnsupportedAssetReject() public {
        BountyFundingModuleV1.FundingRequest memory a = _valid();
        _requireReject(a, 0);
        a.repositoryId = 0;
        _requireReject(a, 1 ether);
        a = _valid();
        a.baselineGitSha = bytes20(0);
        _requireReject(a, 1 ether);
        a = _valid();
        a.manifestDigest = bytes32(0);
        _requireReject(a, 1 ether);
        a = _valid();
        a.verifierPolicyDigest = bytes32(0);
        _requireReject(a, 1 ether);
        a = _valid();
        a.disputePolicyDigest = bytes32(0);
        _requireReject(a, 1 ether);
        a = _valid();
        a.assetKind = 1; // ERC20 not supported until separately reviewed.
        _requireReject(a, 1 ether);
        require(escrow.nextBountyId() == 1, "rejected terms consumed a bounty id");
    }

    function testDeadlineAndWindowBoundsReject() public {
        BountyFundingModuleV1.FundingRequest memory a = _valid();
        a.submissionDeadline = uint64(block.timestamp);
        _requireReject(a, 1 ether);
        a.submissionDeadline = uint64(block.timestamp + 91 days);
        _requireReject(a, 1 ether);
        a = _valid();
        a.verificationSeconds = 3599;
        _requireReject(a, 1 ether);
        a = _valid();
        a.challengeSeconds = 30 days + 1;
        _requireReject(a, 1 ether);
        a = _valid();
        a.arbitrationSeconds = 0;
        _requireReject(a, 1 ether);
    }

    function testIdMonotonicAndConservedLiabilities() public {
        BountyFundingModuleV1.FundingRequest memory a = _valid();
        uint256 first = _fund(a, 1 ether);
        uint256 second = _fund(a, 3 ether);
        require(first == 1 && second == 2 && escrow.nextBountyId() == 3, "duplicate bounty id");
        require(escrow.totalReservedAtoms() == 4 ether, "wrong liabilities");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "unbacked escrow");
    }

    function testCannotReadUnknownBounty() public {
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.getFundingTerms.selector, 1)
        );
        require(!ok, "accepted nonexistent bounty");
        _fund(_valid(), 1 ether);
        (ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.getFundingTerms.selector, 2)
        );
        require(!ok, "accepted invalid next id");
    }

    function testImmutableBountyFieldsCannotBeChangedByLaterFundings() public {
        uint256 first = _fund(_valid(), 1 ether);
        BountyFundingModuleV1.BountyTerms memory previous = escrow.getFundingTerms(first);
        BountyFundingModuleV1.FundingRequest memory second = _valid();
        second.manifestDigest = bytes32(uint256(999));
        second.repositoryId = 9876;
        _fund(second, 2 ether);
        BountyFundingModuleV1.BountyTerms memory afterFunding = escrow.getFundingTerms(first);
        require(afterFunding.manifestDigest == previous.manifestDigest, "spec mutated");
        require(afterFunding.repositoryId == previous.repositoryId, "repo mutated");
        require(afterFunding.rewardAtoms == previous.rewardAtoms, "reward mutated");
    }

    function testFuzzFundingBackedByContractBalance(uint96 reward) public {
        if (reward == 0) return;
        vm.deal(SPONSOR, uint256(reward));
        _fund(_valid(), reward);
        require(escrow.totalReservedAtoms() <= address(escrow).balance, "insolvent");
    }

    function testConstructorRejectsZeroChain() public {
        (bool ok,) = address(this).call(
            abi.encodeWithSignature("deployWithChain(uint256)", 0)
        );
        require(!ok, "zero expected chain accepted");
    }

    function deployWithChain(uint256 chainId) external returns (FundingHarnessV1) {
        return new FundingHarnessV1(chainId);
    }
}
