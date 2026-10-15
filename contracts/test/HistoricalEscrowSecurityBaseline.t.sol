// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CertiFiksEscrow} from "../src/CertiFiksEscrow.sol";

interface Vm {
    function warp(uint256 timestamp) external;
    function prank(address sender) external;
    function deal(address account, uint256 amount) external;
}

contract DeveloperRejectsNativeCurrency {
    CertiFiksEscrow public immutable escrow;

    constructor(CertiFiksEscrow _escrow) {
        escrow = _escrow;
    }

    function submit(uint256 id) external {
        escrow.submitFix(id, keccak256("legitimate patch sha"));
    }

    receive() external payable {
        revert("cannot receive native currency");
    }
}

/**
 * Historical reference contract characterization.
 *
 * SECURITY WARNING: These tests intentionally demonstrate *known unsafe*
 * behaviors; a green CI run DOES NOT mean the escrow is production-safe.
 * Remediation and future inverted regression tests are tracked by #9–#17.
 */
contract HistoricalEscrowSecurityBaselineTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    CertiFiksEscrow private escrow;
    address private constant VERIFIER_A = address(0xA11CE);
    address private constant VERIFIER_B = address(0xB0B);
    address private constant ARBITRATOR = address(0xA4B);
    address payable private constant DEV = payable(address(0xD0D));

    receive() external payable {}

    function setUp() public {
        vm.warp(1780000000);
        vm.deal(address(this), 100 ether);
        escrow = new CertiFiksEscrow();
    }

    function _create(uint64 deadline) private returns (uint256) {
        return escrow.createBounty{value: 1 ether}(
            keccak256("immutable promised acceptance tests"),
            VERIFIER_A,
            VERIFIER_B,
            ARBITRATOR,
            deadline,
            1 days,
            1 days
        );
    }

    function _createAndAssign() private returns (uint256 id) {
        id = _create(uint64(block.timestamp + 7 days));
        escrow.assignDeveloper(id, DEV);
    }

    function _submit(uint256 id) private {
        vm.prank(DEV);
        escrow.submitFix(id, keccak256("exact candidate"));
    }

    function _approve(uint256 id) private {
        vm.prank(VERIFIER_A);
        escrow.recordVerification(id, true, keccak256("report A"));
        vm.prank(VERIFIER_B);
        escrow.recordVerification(id, true, keccak256("report B"));
    }

    function _expectFailure(bytes memory callData) private {
        (bool ok,) = address(escrow).call(callData);
        require(!ok, "expected contract call to revert");
    }

    function testFundedBountyRecordsSponsorAndReward() public {
        uint256 id = _create(uint64(block.timestamp + 7 days));
        CertiFiksEscrow.Bounty memory b = escrow.bounty(id);
        require(b.sponsor == address(this) && b.reward == 1 ether, "wrong custody");
        require(b.status == CertiFiksEscrow.Status.Open, "wrong status");
        require(address(escrow).balance == 1 ether, "balance mismatch");
    }

    function testCannotFundZeroNativeOrZeroSpec() public {
        (bool fundedZero,) = address(escrow).call(
            abi.encodeWithSelector(
                escrow.createBounty.selector,
                keccak256("spec"),
                VERIFIER_A,
                VERIFIER_B,
                ARBITRATOR,
                uint64(block.timestamp + 7 days),
                uint64(1 days),
                uint64(1 days)
            )
        );
        require(!fundedZero, "zero reward accepted");
        (bool badSpec,) = address(escrow).call{value: 1 ether}(
            abi.encodeWithSelector(
                escrow.createBounty.selector,
                bytes32(0),
                VERIFIER_A,
                VERIFIER_B,
                ARBITRATOR,
                uint64(block.timestamp + 7 days),
                uint64(1 days),
                uint64(1 days)
            )
        );
        require(!badSpec, "empty spec accepted");
    }

    function testUnauthorizedAndConflictedAssignmentFails() public {
        uint256 id = _create(uint64(block.timestamp + 7 days));
        vm.prank(address(0xABCD));
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.assignDeveloper.selector, id, DEV)
        );
        require(!ok, "attacker assigned developer");
        _expectFailure(abi.encodeWithSelector(escrow.assignDeveloper.selector, id, payable(address(this))));
        _expectFailure(abi.encodeWithSelector(escrow.assignDeveloper.selector, id, payable(VERIFIER_A)));
        escrow.assignDeveloper(id, DEV);
        _expectFailure(abi.encodeWithSelector(escrow.assignDeveloper.selector, id, payable(address(0x1234))));
    }

    function testOnlyAssignedDeveloperCanSubmitAndNoDuplicate() public {
        uint256 id = _createAndAssign();
        vm.prank(address(0xBAD));
        (bool unauthorized,) = address(escrow).call(
            abi.encodeWithSelector(escrow.submitFix.selector, id, keccak256("fake"))
        );
        require(!unauthorized, "unassigned wallet submitted");
        _submit(id);
        CertiFiksEscrow.Bounty memory b = escrow.bounty(id);
        require(b.status == CertiFiksEscrow.Status.Submitted, "submission did not lock");
        vm.prank(DEV);
        (bool duplicate,) = address(escrow).call(
            abi.encodeWithSelector(escrow.submitFix.selector, id, keccak256("duplicate"))
        );
        require(!duplicate, "duplicate submission");
    }

    function testTwoVerifiersAndWindowPermitSettlement() public {
        uint256 id = _createAndAssign();
        _submit(id);
        vm.prank(VERIFIER_A);
        escrow.recordVerification(id, true, keccak256("report A"));
        _expectFailure(abi.encodeWithSelector(escrow.settle.selector, id));
        vm.prank(VERIFIER_B);
        escrow.recordVerification(id, true, keccak256("report B"));
        CertiFiksEscrow.Bounty memory b = escrow.bounty(id);
        require(b.status == CertiFiksEscrow.Status.Approved, "not approved");
        _expectFailure(abi.encodeWithSelector(escrow.settle.selector, id));
        vm.warp(block.timestamp + 1 days);
        uint256 beforeBalance = DEV.balance;
        escrow.settle(id);
        require(DEV.balance == beforeBalance + 1 ether, "developer not paid");
        require(address(escrow).balance == 0, "escrow not drained exactly");
        _expectFailure(abi.encodeWithSelector(escrow.settle.selector, id));
    }

    function testDisagreementEscalatesAndArbitratorResolvesSponsorRefund() public {
        uint256 id = _createAndAssign();
        _submit(id);
        vm.prank(VERIFIER_A);
        escrow.recordVerification(id, true, keccak256("report A"));
        vm.prank(VERIFIER_B);
        escrow.recordVerification(id, false, keccak256("report B"));
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Disputed, "no dispute");
        vm.prank(ARBITRATOR);
        escrow.resolveDispute(id, false);
        CertiFiksEscrow.Bounty memory b = escrow.bounty(id);
        require(b.status == CertiFiksEscrow.Status.Refunded, "no refund");
        require(address(escrow).balance == 0, "funds trapped");
    }

    function testChallengeStopsAutomaticDeveloperPayout() public {
        uint256 id = _createAndAssign();
        _submit(id);
        _approve(id);
        escrow.challenge(id, keccak256("evidence of incorrect results"));
        _expectFailure(abi.encodeWithSelector(escrow.settle.selector, id));
        vm.prank(ARBITRATOR);
        escrow.resolveDispute(id, true);
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Paid, "arbitrator decision not applied");
    }

    function testNoSubmissionRefundAtExpiredDeadline() public {
        uint256 id = _createAndAssign();
        _expectFailure(abi.encodeWithSelector(escrow.refundExpired.selector, id));
        vm.warp(block.timestamp + 8 days);
        escrow.refundExpired(id);
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Refunded, "refund not allowed");
    }

    function testSubmissionDeadlineBoundary() public {
        uint64 deadline = uint64(block.timestamp + 1 days);
        uint256 id = _create(deadline);
        escrow.assignDeveloper(id, DEV);
        vm.warp(deadline);
        _submit(id);
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Submitted, "deadline equality rejected");
        uint256 id2 = _create(uint64(block.timestamp + 1 days));
        escrow.assignDeveloper(id2, DEV);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(DEV);
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.submitFix.selector, id2, keccak256("too late"))
        );
        require(!ok, "accepted past deadline");
    }

    function testVerifierCannotVoteTwiceOrFromUnknownAddress() public {
        uint256 id = _createAndAssign();
        _submit(id);
        vm.prank(address(0x5AFE));
        (bool fake,) = address(escrow).call(
            abi.encodeWithSelector(escrow.recordVerification.selector, id, true, keccak256("fake"))
        );
        require(!fake, "unknown verifier counted");
        vm.prank(VERIFIER_A);
        escrow.recordVerification(id, true, keccak256("first"));
        vm.prank(VERIFIER_A);
        (bool duplicate,) = address(escrow).call(
            abi.encodeWithSelector(escrow.recordVerification.selector, id, true, keccak256("second"))
        );
        require(!duplicate, "same verifier duplicated vote");
    }

    function testKnownCriticalSponsorCanRefundTimelySubmissionWhenReviewersAreSilent() public {
        // Known exploit recorded as a *passing characterization test*, not desired behavior.
        // #15 must invert this assertion by protecting the contributor's timely submission.
        uint256 id = _createAndAssign();
        _submit(id);
        vm.warp(block.timestamp + 1 days + 1);
        escrow.refundExpired(id);
        CertiFiksEscrow.Bounty memory b = escrow.bounty(id);
        require(b.status == CertiFiksEscrow.Status.Refunded, "historical exploit no longer reproduced");
        require(b.reward == 0 && address(escrow).balance == 0, "historical refund did not drain reward");
    }

    function testKnownHighRevertingRecipientTrapsApprovedReward() public {
        uint256 id = _create(uint64(block.timestamp + 7 days));
        DeveloperRejectsNativeCurrency dev = new DeveloperRejectsNativeCurrency(escrow);
        escrow.assignDeveloper(id, payable(address(dev)));
        dev.submit(id);
        _approve(id);
        vm.warp(block.timestamp + 1 days);
        (bool settled,) = address(escrow).call(abi.encodeWithSelector(escrow.settle.selector, id));
        require(!settled, "historical push-payment failure no longer reproduced");
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Approved, "reverted settlement changed state");
        require(address(escrow).balance == 1 ether, "escrow unexpectedly released");
    }

    function testKnownHighDisputeCanRemainLockedIfArbitratorDisappears() public {
        uint256 id = _createAndAssign();
        _submit(id);
        _approve(id);
        escrow.challenge(id, keccak256("fair sponsor challenge"));
        vm.warp(block.timestamp + 365 days);
        _expectFailure(abi.encodeWithSelector(escrow.settle.selector, id));
        _expectFailure(abi.encodeWithSelector(escrow.refundExpired.selector, id));
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Disputed, "case unexpectedly resolved");
        require(address(escrow).balance == 1 ether, "funds unexpectedly released");
    }

    function testKnownHighTwoWalletsFromSameControllerCanApprove() public {
        // Governance hole: role checks only distinct EOAs, not independent organizations.
        uint256 id = _createAndAssign();
        _submit(id);
        _approve(id);
        require(escrow.bounty(id).status == CertiFiksEscrow.Status.Approved, "not approved");
    }
}
