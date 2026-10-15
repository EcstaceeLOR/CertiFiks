// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BountyAssignmentModuleV1} from "../src/BountyAssignmentModuleV1.sol";

interface VmAssignment {
    function deal(address who, uint256 newBalance) external;
    function prank(address who) external;
    function chainId(uint256 newChainId) external;
    function warp(uint256 timestamp) external;
}

/** @dev Test harness, NOT a deployable user-funds escrow. */
contract AssignmentHarnessV1 is BountyAssignmentModuleV1 {
    constructor(uint256 chainId) BountyAssignmentModuleV1(chainId) {}

    function fund(FundingRequest calldata request) external payable returns (uint256) {
        return _recordFunding(request);
    }

    // The real #11 submitter MUST validate pinned GitHub identity / head SHA.
    // This hook exists ONLY to characterize the authorization transition.
    function simulatePinnedSubmission(uint256 bountyId) external {
        _lockTimelySubmission(bountyId, msg.sender);
    }
}

/** EVM wallet calls are transaction-signed; no trust in caller-provided account. */
contract BountyAssignmentModuleV1Test {
    VmAssignment private constant vm =
        VmAssignment(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant CHAIN = 31337;
    address private constant SPONSOR = address(0xA112);
    address private constant DEV_A = address(0xDA1);
    address private constant DEV_B = address(0xDB2);
    address private constant THIRD_PARTY = address(0xC0FFEE);

    AssignmentHarnessV1 private escrow;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        escrow = new AssignmentHarnessV1(CHAIN);
    }

    function _spec(uint64 deadline)
        internal pure returns (BountyAssignmentModuleV1.FundingRequest memory)
    {
        return BountyAssignmentModuleV1.FundingRequest({
            repositoryId: 150721,
            baselineGitSha: hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            manifestDigest: bytes32(uint256(1)),
            verifierPolicyDigest: bytes32(uint256(2)),
            disputePolicyDigest: bytes32(uint256(3)),
            submissionDeadline: deadline,
            verificationSeconds: 1 days,
            challengeSeconds: 1 days,
            arbitrationSeconds: 1 days,
            assetKind: 0
        });
    }

    function _fund() internal returns (uint256) {
        vm.prank(SPONSOR);
        return escrow.fund{value: 1 ether}(_spec(uint64(block.timestamp + 7 days)));
    }

    function _fundWithDeadline(uint64 deadline) internal returns (uint256) {
        vm.prank(SPONSOR);
        return escrow.fund{value: 1 ether}(_spec(deadline));
    }

    function _apply(uint256 bountyId, address developer) internal {
        vm.prank(developer);
        escrow.applyForBounty(bountyId);
    }

    function _offer(uint256 bountyId, address developer) internal {
        vm.prank(SPONSOR);
        escrow.offerAssignment(bountyId, developer);
    }

    function _accept(uint256 bountyId, address developer) internal {
        vm.prank(developer);
        escrow.acceptAssignment(bountyId);
    }

    function _accepted(uint256 bountyId) internal {
        _apply(bountyId, DEV_A);
        _offer(bountyId, DEV_A);
        _accept(bountyId, DEV_A);
    }

    function _rejectAs(address actor, bytes memory callData) internal {
        vm.prank(actor);
        (bool ok,) = address(escrow).call(callData);
        require(!ok, "unauthorized operation unexpectedly succeeded");
    }

    function testCompleteApplicationSponsorOfferSignedAcceptanceJourney() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        require(
            escrow.applicationState(id, DEV_A) ==
                BountyAssignmentModuleV1.ApplicationState.Applied,
            "application not registered"
        );
        require(escrow.getAssignment(id).pendingApplicants == 1, "pending count wrong");
        _offer(id, DEV_A);
        require(
            escrow.getAssignment(id).state ==
                BountyAssignmentModuleV1.AssignmentState.Offered,
            "offer missing"
        );
        _accept(id, DEV_A);
        BountyAssignmentModuleV1.Assignment memory assigned = escrow.getAssignment(id);
        require(assigned.state == BountyAssignmentModuleV1.AssignmentState.Accepted, "not accepted");
        require(assigned.developer == DEV_A && assigned.offeredTo == address(0), "wrong assignee");
        require(assigned.pendingApplicants == 0, "pending count not decremented");
        require(escrow.canSubmit(id, DEV_A), "accepted developer cannot submit");
        require(!escrow.canSubmit(id, DEV_B), "unselected developer can submit");
        require(address(escrow).balance == 1 ether, "unexpected transfer");
    }

    function testUnknownBountyAndSponsorSelfApplicationAreRejected() public {
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.applyForBounty.selector, 1));
        uint256 id = _fund();
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.applyForBounty.selector, id));
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.applyForBounty.selector, 0));
    }

    function testNoUninvitedOrSpoofedDeveloperAcceptance() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _apply(id, DEV_B);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _offer(id, DEV_A);
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _accept(id, DEV_A);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.simulatePinnedSubmission.selector, id));
    }

    function testSponsorCannotAssignNonApplicantOrOverrideActiveOffer() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _apply(id, DEV_B);
        _rejectAs(THIRD_PARTY, abi.encodeWithSelector(escrow.offerAssignment.selector, id, DEV_A));
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.offerAssignment.selector, id, THIRD_PARTY));
        _offer(id, DEV_A);
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.offerAssignment.selector, id, DEV_B));
        _accept(id, DEV_A);
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.offerAssignment.selector, id, DEV_B));
        require(escrow.getAssignment(id).developer == DEV_A, "sponsor changed developer");
    }

    function testOfferRevocationAndReassignmentBeforeAcceptance() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _apply(id, DEV_B);
        _offer(id, DEV_A);
        vm.prank(SPONSOR);
        escrow.revokeOffer(id);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _offer(id, DEV_B);
        _accept(id, DEV_B);
        require(escrow.getAssignment(id).developer == DEV_B, "reassignment failed");
        require(!escrow.canSubmit(id, DEV_A), "revoked wallet can submit");
    }

    function testApplicantCanWithdrawPendingOrOfferedButNotRepeatApplication() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        vm.prank(DEV_A);
        escrow.withdrawApplication(id);
        require(escrow.getAssignment(id).pendingApplicants == 0, "application not removed");
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.applyForBounty.selector, id));
        _apply(id, DEV_B);
        _offer(id, DEV_B);
        vm.prank(DEV_B);
        escrow.withdrawApplication(id);
        require(
            escrow.getAssignment(id).state == BountyAssignmentModuleV1.AssignmentState.Open,
            "offer still active"
        );
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        require(escrow.getAssignment(id).pendingApplicants == 0, "offered withdrawal not counted");
    }

    function testSponsorCanRejectAndReclaimedCapacityIsReusable() public {
        uint256 id = _fund();
        for (uint160 i = 1; i <= 32; ++i) {
            _apply(id, address(0x10000 + i));
        }
        require(escrow.getAssignment(id).pendingApplicants == 32, "cap not reached");
        _rejectAs(address(0x20000), abi.encodeWithSelector(escrow.applyForBounty.selector, id));
        vm.prank(SPONSOR);
        escrow.rejectApplication(id, address(0x10001));
        require(escrow.getAssignment(id).pendingApplicants == 31, "capacity not released");
        _rejectAs(address(0x10001), abi.encodeWithSelector(escrow.applyForBounty.selector, id));
        _apply(id, address(0x20000));
        require(escrow.getAssignment(id).pendingApplicants == 32, "slot not reusable");
    }

    function testSelectedApplicantRejectionAlsoInvalidatesOffer() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _offer(id, DEV_A);
        vm.prank(SPONSOR);
        escrow.rejectApplication(id, DEV_A);
        require(escrow.getAssignment(id).pendingApplicants == 0, "slot not freed");
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.applyForBounty.selector, id));
    }

    function testOfferExpiryAndReplayPrevention() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _apply(id, DEV_B);
        _offer(id, DEV_A);
        uint64 until = escrow.getAssignment(id).offerUntil;
        _rejectAs(THIRD_PARTY, abi.encodeWithSelector(escrow.expireOffer.selector, id));
        vm.warp(uint256(until) + 1);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        vm.prank(THIRD_PARTY);
        escrow.expireOffer(id);
        _offer(id, DEV_B);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _accept(id, DEV_B);
        require(escrow.getAssignment(id).developer == DEV_B, "stale offer accepted");
    }

    function testExpiredDeadlineNeverAllowsAcceptanceOrNewApplications() public {
        uint64 deadline = uint64(block.timestamp + 2 hours);
        uint256 id = _fundWithDeadline(deadline);
        _apply(id, DEV_A);
        _offer(id, DEV_A);
        uint64 until = escrow.getAssignment(id).offerUntil;
        vm.warp(uint256(until) + 1);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.applyForBounty.selector, id));
        require(!escrow.canSubmit(id, DEV_A), "expired offer treated as accepted");
    }

    function testAcceptedDeveloperMayResignBeforeSubmissionAndAnotherMayAccept() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _apply(id, DEV_B);
        _offer(id, DEV_A);
        _accept(id, DEV_A);
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.resignAssignment.selector, id));
        vm.prank(DEV_A);
        escrow.resignAssignment(id);
        require(!escrow.canSubmit(id, DEV_A), "resigned wallet can submit");
        _offer(id, DEV_B);
        _accept(id, DEV_B);
        require(escrow.canSubmit(id, DEV_B), "replacement cannot submit");
        require(!escrow.canSubmit(id, DEV_A), "old assignee still authorized");
    }

    function testSponsorCannotCancelAfterDeveloperAccepts() public {
        uint256 id = _fund();
        _accepted(id);
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, id));
        require(escrow.getAssignment(id).developer == DEV_A, "sponsor displaced developer");
        require(address(escrow).balance == 1 ether, "unilateral refund");
    }

    function testUnassignedCancelFlagsOnlyFutureRefundAndNeverTransfersMoney() public {
        uint256 id = _fund();
        _apply(id, DEV_A);
        _offer(id, DEV_A);
        vm.prank(SPONSOR);
        escrow.cancelUnassignedBounty(id);
        require(
            escrow.getAssignment(id).state ==
                BountyAssignmentModuleV1.AssignmentState.CancelledPendingRefund,
            "wrong cancel state"
        );
        require(address(escrow).balance == 1 ether, "pending refund paid early");
        require(escrow.totalReservedAtoms() == 1 ether, "refund ledger incorrectly reduced");
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, id));
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.applyForBounty.selector, id));
    }

    function testExpiredUnsubmittedBountyFlagsRefundWithoutTransfer() public {
        uint256 id = _fund();
        _accepted(id);
        _rejectAs(THIRD_PARTY, abi.encodeWithSelector(escrow.expireUnsubmittedBounty.selector, id));
        uint256 deadline = escrow.getFundingTerms(id).submissionDeadline;
        vm.warp(deadline + 1);
        vm.prank(THIRD_PARTY);
        escrow.expireUnsubmittedBounty(id);
        require(
            escrow.getAssignment(id).state ==
                BountyAssignmentModuleV1.AssignmentState.ExpiredPendingRefund,
            "did not mark expired"
        );
        require(address(escrow).balance == 1 ether, "expiring moved funds");
        require(escrow.totalReservedAtoms() == 1 ether, "expiring minted refund credit");
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.simulatePinnedSubmission.selector, id));
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, id));
    }

    function testOnTimeSubmittedFixIsProtectedFromCancellationAndExpiry() public {
        uint256 id = _fund();
        _accepted(id);
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.simulatePinnedSubmission.selector, id));
        vm.prank(DEV_A);
        escrow.simulatePinnedSubmission(id);
        require(
            escrow.getAssignment(id).state == BountyAssignmentModuleV1.AssignmentState.Submitted,
            "timely submission not protected"
        );
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, id));
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.resignAssignment.selector, id));
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.simulatePinnedSubmission.selector, id));
        vm.warp(block.timestamp + 8 days);
        _rejectAs(THIRD_PARTY, abi.encodeWithSelector(escrow.expireUnsubmittedBounty.selector, id));
        require(address(escrow).balance == 1 ether, "timely fix forfeited by timeout");
    }

    function testCannotSubmitAfterContractualDeadlineEvenWhenAccepted() public {
        uint256 id = _fund();
        _accepted(id);
        vm.warp(uint256(escrow.getFundingTerms(id).submissionDeadline) + 1);
        require(!escrow.canSubmit(id, DEV_A), "expired submitted allowed");
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.simulatePinnedSubmission.selector, id));
    }

    function testWrongChainRejectsWalletActionsAndSubmission() public {
        uint256 id = _fund();
        _accepted(id);
        vm.chainId(CHAIN + 1);
        _rejectAs(DEV_A, abi.encodeWithSelector(escrow.simulatePinnedSubmission.selector, id));
        _rejectAs(DEV_B, abi.encodeWithSelector(escrow.applyForBounty.selector, id));
        _rejectAs(SPONSOR, abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, id));
        require(!escrow.canSubmit(id, DEV_A), "wrong network authorized");
    }

    function testAssignmentNeverMutatesImmutableFundingTerms() public {
        uint256 id = _fund();
        BountyAssignmentModuleV1.BountyTerms memory beforeTerms = escrow.getFundingTerms(id);
        _accepted(id);
        vm.prank(DEV_A);
        escrow.resignAssignment(id);
        BountyAssignmentModuleV1.BountyTerms memory afterTerms = escrow.getFundingTerms(id);
        require(beforeTerms.manifestDigest == afterTerms.manifestDigest, "manifest mutated");
        require(beforeTerms.baselineGitSha == afterTerms.baselineGitSha, "base mutated");
        require(beforeTerms.rewardAtoms == afterTerms.rewardAtoms, "payout edited");
        require(beforeTerms.submissionDeadline == afterTerms.submissionDeadline, "deadline changed");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "solvency changed");
    }

    function testMultipleBountiesMaintainIndependentAssignees() public {
        uint256 first = _fund();
        uint256 second = _fund();
        _accepted(first);
        _apply(second, DEV_B);
        _offer(second, DEV_B);
        _accept(second, DEV_B);
        require(escrow.canSubmit(first, DEV_A), "first assignee lost");
        require(escrow.canSubmit(second, DEV_B), "second assignee lost");
        require(!escrow.canSubmit(first, DEV_B), "cross-bounty developer leakage");
        require(!escrow.canSubmit(second, DEV_A), "cross-bounty developer leakage");
        require(escrow.totalReservedAtoms() == 2 ether, "reserve changed");
    }

    function testFuzzRandomUnselectedWalletCannotAccept(address attacker) public {
        if (attacker == address(0) || attacker == DEV_A) return;
        uint256 id = _fund();
        _apply(id, DEV_A);
        _offer(id, DEV_A);
        _rejectAs(attacker, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        require(!escrow.canSubmit(id, attacker), "attacker treated as assigned");
    }
}
