// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PullWithdrawalModuleV1} from "../src/PullWithdrawalModuleV1.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";
import {BountySubmissionModuleV1} from "../src/BountySubmissionModuleV1.sol";
import {BoundedArbitrationModuleV1} from "../src/BoundedArbitrationModuleV1.sol";
import {VerifierRegistryModuleV1} from "../src/VerifierRegistryModuleV1.sol";
import {SignedVerifierDecisionModuleV1} from "../src/SignedVerifierDecisionModuleV1.sol";

interface VmPull {
    function prank(address who) external;
    function deal(address who, uint256 value) external;
    function warp(uint256 value) external;
    function chainId(uint256 id) external;
    function addr(uint256 key) external returns (address);
    function sign(uint256 key, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract PullHarnessV1 is PullWithdrawalModuleV1 {
    constructor(uint256 chainId, address governance) PullWithdrawalModuleV1(chainId, governance) {}
    /** TEST ONLY. No public funding exists in production src/. */
    function testFund(FundingRequest calldata data) external payable returns (uint256) {
        return _recordFunding(data);
    }
}

/** A funded smart-contract beneficiary can redirect to an authorized EOA. */
contract RevertingSponsorV1 {
    PullHarnessV1 private immutable escrow;

    constructor(PullHarnessV1 _escrow) {
        escrow = _escrow;
    }

    function fund(BountyFundingModuleV1.FundingRequest calldata req)
        external payable returns (uint256)
    {
        return escrow.testFund{value: msg.value}(req);
    }

    function cancel(uint256 bounty) external {
        escrow.cancelUnassignedBounty(bounty);
    }

    function withdrawTo(uint256 bounty, address payable target, uint256 amount) external {
        escrow.withdrawBountyCredit(bounty, target, amount);
    }

    receive() external payable {
        revert("This sponsor contract never accepts ETH");
    }
}

/** Beneficiary contract purposely retries its own withdrawal on callback. */
contract ReentrantSponsorV1 {
    PullHarnessV1 private immutable escrow;
    uint256 public targetBounty;
    bool public attackEnabled;
    bool public reentryRejected;

    constructor(PullHarnessV1 _escrow) {
        escrow = _escrow;
    }

    function fund(BountyFundingModuleV1.FundingRequest calldata req)
        external payable returns (uint256 bounty)
    {
        bounty = escrow.testFund{value: msg.value}(req);
        targetBounty = bounty;
    }

    function cancel(uint256 bounty) external {
        escrow.cancelUnassignedBounty(bounty);
    }

    function withdrawTo(uint256 bounty, address payable target, uint256 amount) external {
        escrow.withdrawBountyCredit(bounty, target, amount);
    }

    function arm() external {
        attackEnabled = true;
    }

    receive() external payable {
        if (attackEnabled) {
            attackEnabled = false; // single attempt; otherwise recursion on vulnerable code
            (bool ok,) = address(escrow).call(
                abi.encodeWithSelector(
                    escrow.withdrawBountyCredit.selector, targetBounty,
                    payable(address(this)), 1 wei
                )
            );
            reentryRejected = !ok;
        }
    }
}

contract PullWithdrawalModuleV1Test {
    VmPull private constant vm =
        VmPull(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant CHAIN = 31337;
    uint256 private constant KEY_A = 111;
    uint256 private constant KEY_B = 222;
    address private constant SPONSOR = address(0xA110);
    address private constant DEVELOPER = address(0xCAFE);
    address private constant ARBITRATOR = address(0xA4B);
    address private constant FALLBACK = address(0xF411);
    address private constant CONTROLLER_A = address(0xC111);
    address private constant CONTROLLER_B = address(0xC222);
    address private constant OUTSIDER = address(0xBAD);
    bytes32 private constant ORG_A = keccak256("independent-reviewer-A");
    bytes32 private constant ORG_B = keccak256("independent-reviewer-B");
    bytes20 private constant BASE_SHA = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes20 private constant FIRST_HEAD = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    bytes32 private constant REPORT_A = keccak256("actual signed report A");
    bytes32 private constant REPORT_B = keccak256("actual signed report B");

    PullHarnessV1 private escrow;
    address private signerA;
    address private signerB;

    receive() external payable {}

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        vm.deal(address(this), 100 ether);
        signerA = vm.addr(KEY_A);
        signerB = vm.addr(KEY_B);
        escrow = new PullHarnessV1(CHAIN, address(this));
        escrow.enrollReviewerOrganization(
            ORG_A, CONTROLLER_A, signerA, bytes32(uint256(11)),
            bytes32(uint256(12)), bytes32(uint256(13))
        );
        escrow.enrollReviewerOrganization(
            ORG_B, CONTROLLER_B, signerB, bytes32(uint256(21)),
            bytes32(uint256(22)), bytes32(uint256(23))
        );
        vm.prank(CONTROLLER_A);
        escrow.activateReviewerOrganization(ORG_A);
        vm.prank(CONTROLLER_B);
        escrow.activateReviewerOrganization(ORG_B);
    }

    function _roster() private pure returns (bytes32[] memory roster) {
        roster = new bytes32[](2);
        (roster[0], roster[1]) = ORG_A < ORG_B ? (ORG_A, ORG_B) : (ORG_B, ORG_A);
    }

    function _policy(uint64 deadline)
        private pure returns (BountyFundingModuleV1.FundingRequest memory)
    {
        return BountyFundingModuleV1.FundingRequest({
            repositoryId: 888,
            baselineGitSha: BASE_SHA,
            manifestDigest: bytes32(uint256(100)),
            verifierPolicyDigest: sha256(
                abi.encode("CertiFiks:verifier-roster:v1", uint8(2), _roster())
            ),
            disputePolicyDigest: sha256(
                abi.encode("CertiFiks:arbitration-policy:v1", ARBITRATOR, FALLBACK)
            ),
            primaryArbitrator: ARBITRATOR,
            submissionDeadline: deadline,
            verificationSeconds: 2 days,
            challengeSeconds: 1 days,
            arbitrationSeconds: 2 days,
            assetKind: 0
        });
    }

    function _fund(uint256 amount) private returns (uint256 bounty) {
        BountyFundingModuleV1.FundingRequest memory req =
            _policy(uint64(block.timestamp + 10 days));
        vm.prank(SPONSOR);
        bounty = escrow.testFund{value: amount}(req);
    }

    function _fundRegistered() private returns (uint256 bounty) {
        bounty = _fund(1 ether);
        vm.prank(SPONSOR);
        escrow.registerCommittedReviewerRoster(bounty, _roster(), 2);
        vm.prank(SPONSOR);
        escrow.registerDisputePolicy(bounty, FALLBACK);
        escrow.approveArbitrationPolicy(bounty);
        vm.prank(ARBITRATOR);
        escrow.acceptArbitratorRole(bounty);
        vm.prank(FALLBACK);
        escrow.acceptArbitratorRole(bounty);
    }

    function _refund(uint256 bounty) private {
        vm.prank(SPONSOR);
        escrow.cancelUnassignedBounty(bounty);
        escrow.recordNoSubmissionRefund(bounty);
    }

    function _creditRefund(uint256 bounty) private {
        _refund(bounty);
        escrow.accrueFinalCredits(bounty);
    }

    function _assertLedger(uint256 reserve, uint256 credits) private view {
        require(escrow.totalReservedAtoms() == reserve, "bad unpaid liabilities");
        require(escrow.totalClaimableCreditsAtoms() == credits, "bad unpaid claimables");
        require(escrow.unfinalizedRewardLiabilitiesAtoms() == reserve - credits, "bad unresolved");
        (uint256 onchain, uint256 booked,, bool solvent) = escrow.nativeLiabilityHealth();
        require(onchain == reserve && booked == credits && solvent, "insolvent accounting");
        require(address(escrow).balance >= reserve, "liability unsupported");
    }

    function _reject(address actor, bytes memory calldataPayload) private {
        vm.prank(actor);
        (bool ok,) = address(escrow).call(calldataPayload);
        require(!ok, "expected unsafe payout action to revert");
    }

    function _candidate() private pure returns (BountySubmissionModuleV1.Candidate memory) {
        return BountySubmissionModuleV1.Candidate({
            repositoryId: 888,
            pullNumber: 42,
            baseGitSha: BASE_SHA,
            headGitSha: FIRST_HEAD,
            imageDigest: bytes32(uint256(103)),
            evidenceDigest: bytes32(uint256(104)),
            manifestDigest: bytes32(uint256(100)),
            manifestVersion: 1
        });
    }

    function _submitted() private returns (uint256 bounty) {
        bounty = _fundRegistered();
        vm.prank(DEVELOPER);
        escrow.applyForBounty(bounty);
        vm.prank(SPONSOR);
        escrow.offerAssignment(bounty, DEVELOPER);
        vm.prank(DEVELOPER);
        escrow.acceptAssignment(bounty);
        vm.prank(DEVELOPER);
        escrow.submitCandidate(bounty, _candidate());
    }

    function _ready() private returns (uint256 bounty) {
        bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG_A);
        escrow.assignReviewerJob(bounty, ORG_B);
        vm.prank(signerA);
        escrow.acceptReviewerJob(bounty, 1, ORG_A);
        vm.prank(signerB);
        escrow.acceptReviewerJob(bounty, 1, ORG_B);
        vm.prank(signerA);
        escrow.declareReviewerEvidence(bounty, 1, ORG_A, REPORT_A);
        vm.prank(signerB);
        escrow.declareReviewerEvidence(bounty, 1, ORG_B, REPORT_B);
    }

    function _vote(uint256 bounty, bytes32 org, uint8 outcome)
        private view returns (SignedVerifierDecisionModuleV1.SignedVerdict memory v)
    {
        VerifierRegistryModuleV1.ReviewerJob memory job = escrow.getReviewerJob(bounty, 1, org);
        BountySubmissionModuleV1.FixAttempt memory attempt = escrow.getPinnedAttempt(bounty, 1);
        BountyFundingModuleV1.BountyTerms memory terms = escrow.getFundingTerms(bounty);
        v = SignedVerifierDecisionModuleV1.SignedVerdict({
            bountyId: bounty,
            attemptId: 1,
            organizationId: org,
            signerEpoch: job.signerEpoch,
            attemptDigest: attempt.attemptDigest,
            manifestDigest: terms.manifestDigest,
            verifierPolicyDigest: terms.verifierPolicyDigest,
            headGitSha: attempt.candidate.headGitSha,
            reportDigest: org == ORG_A ? REPORT_A : REPORT_B,
            imageDigest: attempt.candidate.imageDigest,
            outcome: outcome,
            baselineFailed: true,
            candidatePassed: true,
            regressionsPassed: true,
            expiresAt: uint64(block.timestamp + 1 days)
        });
    }

    function _voteSigned(uint256 bounty, bytes32 org, uint8 outcome, uint256 key) private {
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, org, outcome);
        (uint8 y, bytes32 r, bytes32 s) = vm.sign(key, escrow.typedVerdictDigest(v));
        escrow.submitSignedVerdict(v, abi.encodePacked(r, s, y));
    }

    function _approved() private returns (uint256 bounty) {
        bounty = _ready();
        _voteSigned(bounty, ORG_A, 1, KEY_A);
        _voteSigned(bounty, ORG_B, 1, KEY_B);
        uint64 deadline = escrow.readReviewDecision(bounty, 1).challengeUntil;
        vm.warp(uint256(deadline) + 1);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        escrow.recordResolvedEntitlement(bounty, 1);
    }

    function _sharedSilence() private returns (uint256 bounty) {
        bounty = _ready();
        _voteSigned(bounty, ORG_A, 1, KEY_A);
        uint256 deadline =
            uint256(escrow.getPinnedAttempt(bounty, 1).submittedAt) +
            uint256(escrow.getFundingTerms(bounty).verificationSeconds);
        vm.warp(deadline);
        vm.prank(DEVELOPER);
        escrow.openReviewEscalation(
            bounty, 1, keccak256("reviewers silent"),
            keccak256("archived before-after transcript")
        );
        vm.warp(escrow.getDisputeCase(bounty, 1).primaryDeadline);
        escrow.advanceDispute(bounty, 1);
        vm.warp(escrow.getDisputeCase(bounty, 1).fallbackDeadline);
        escrow.advanceDispute(bounty, 1);
        escrow.recordResolvedEntitlement(bounty, 1);
    }

    function testCannotCreditUnresolvedBountyOrNonexistentBounty() public {
        uint256 bounty = _fund(1 ether);
        _reject(OUTSIDER, abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty));
        _reject(OUTSIDER, abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty + 1));
        _assertLedger(1 ether, 0);
    }

    function testSponsorRefundCreditIsBookedOnceAndNotPaidAutomatically() public {
        uint256 bounty = _fund(1 ether);
        _refund(bounty);
        escrow.accrueFinalCredits(bounty);
        require(escrow.bountyCreditsAccrued(bounty), "unbooked refund");
        require(escrow.claimableByBounty(bounty, SPONSOR) == 1 ether, "wrong claim account");
        require(escrow.claimableByBounty(bounty, DEVELOPER) == 0, "stranger credited");
        _assertLedger(1 ether, 1 ether);
        _reject(SPONSOR, abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty));
        _assertLedger(1 ether, 1 ether);
    }

    function testOnlyBeneficiaryCanAuthorizeExactRecipientAndAmount() public {
        uint256 bounty = _fund(1 ether);
        _creditRefund(bounty);
        _reject(OUTSIDER, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, bounty, payable(OUTSIDER), 1 ether
        ));
        _reject(DEVELOPER, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, bounty, payable(DEVELOPER), 1 ether
        ));
        uint256 beforeBalance = OUTSIDER.balance;
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(bounty, payable(OUTSIDER), 1 ether);
        require(OUTSIDER.balance == beforeBalance + 1 ether, "requested recipient not paid");
        require(escrow.claimableByBounty(bounty, SPONSOR) == 0, "beneficiary credit not consumed");
        _assertLedger(0, 0);
    }

    function testRejectedReceiverCannotBurnCreditsOrFreezeOtherBounties() public {
        uint256 one = _fund(1 ether);
        uint256 two = _fund(2 ether);
        _creditRefund(one);
        _creditRefund(two);
        RevertingSponsorV1 rejecting = new RevertingSponsorV1(escrow);
        _reject(SPONSOR, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, one, payable(address(rejecting)), 1 ether
        ));
        require(escrow.claimableByBounty(one, SPONSOR) == 1 ether, "revert stole credit");
        _assertLedger(3 ether, 3 ether);
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(two, payable(OUTSIDER), 2 ether);
        _assertLedger(1 ether, 1 ether);
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(one, payable(SPONSOR), 1 ether);
        _assertLedger(0, 0);
    }

    function testContractBeneficiaryWithRejectingReceiveCanWithdrawToAnotherAddress() public {
        RevertingSponsorV1 sponsorContract = new RevertingSponsorV1(escrow);
        uint256 bounty = sponsorContract.fund{value: 1 ether}(
            _policy(uint64(block.timestamp + 7 days))
        );
        sponsorContract.cancel(bounty);
        escrow.recordNoSubmissionRefund(bounty);
        escrow.accrueFinalCredits(bounty);
        require(escrow.claimableByBounty(bounty, address(sponsorContract)) == 1 ether, "contract not credited");
        (bool success,) = address(sponsorContract).call(
            abi.encodeWithSelector(
                sponsorContract.withdrawTo.selector, bounty, payable(address(sponsorContract)), 1 ether
            )
        );
        require(!success, "bad receiver unexpectedly accepted reward");
        _assertLedger(1 ether, 1 ether);
        uint256 beforeBalance = OUTSIDER.balance;
        sponsorContract.withdrawTo(bounty, payable(OUTSIDER), 1 ether);
        require(OUTSIDER.balance == beforeBalance + 1 ether, "authorized recipient not paid");
        _assertLedger(0, 0);
    }

    function testBeneficiaryCallbackCannotReenterAndDoubleWithdraw() public {
        ReentrantSponsorV1 attackingSponsor = new ReentrantSponsorV1(escrow);
        uint256 bounty = attackingSponsor.fund{value: 1 ether}(
            _policy(uint64(block.timestamp + 7 days))
        );
        attackingSponsor.cancel(bounty);
        escrow.recordNoSubmissionRefund(bounty);
        escrow.accrueFinalCredits(bounty);
        attackingSponsor.arm();
        attackingSponsor.withdrawTo(bounty, payable(address(attackingSponsor)), 1 ether);
        require(attackingSponsor.reentryRejected(), "same-beneficiary callback reentered escrow");
        require(escrow.claimableByBounty(bounty, address(attackingSponsor)) == 0,
            "attacker retained paid credit");
        require(address(attackingSponsor).balance == 1 ether, "unexpected attacker payment");
        _assertLedger(0, 0);
    }

    function testPartialWithdrawalsPreserveTotalAndExactRemainder() public {
        uint256 bounty = _fund(1 ether);
        _creditRefund(bounty);
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(bounty, payable(OUTSIDER), 0.25 ether);
        require(escrow.claimableByBounty(bounty, SPONSOR) == 0.75 ether, "partial remainder wrong");
        _assertLedger(0.75 ether, 0.75 ether);
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(bounty, payable(SPONSOR), 0.75 ether);
        _assertLedger(0, 0);
        _reject(SPONSOR, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, bounty, payable(SPONSOR), 1
        ));
    }

    function testZeroAmountUnknownBountyZeroRecipientAndExcessClaimReject() public {
        uint256 bounty = _fund(1 ether);
        _creditRefund(bounty);
        for (uint256 i = 0; i < 4; i++) {
            address payable target = i == 0 ? payable(address(0)) :
                i == 1 ? payable(address(escrow)) : payable(SPONSOR);
            uint256 amount = i == 2 ? 0 : i == 3 ? 2 ether : 1 ether;
            _reject(SPONSOR, abi.encodeWithSelector(
                escrow.withdrawBountyCredit.selector, bounty, target, amount
            ));
        }
        _reject(SPONSOR, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, bounty + 2, payable(SPONSOR), 1 ether
        ));
        _assertLedger(1 ether, 1 ether);
    }

    function testWrongChainCannotCreditOrWithdrawAndStateRemainsSafe() public {
        uint256 bounty = _fund(1 ether);
        _refund(bounty);
        vm.chainId(CHAIN + 1);
        _reject(SPONSOR, abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty));
        vm.chainId(CHAIN);
        escrow.accrueFinalCredits(bounty);
        vm.chainId(CHAIN + 1);
        _reject(SPONSOR, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, bounty, payable(SPONSOR), 1 ether
        ));
        _assertLedger(1 ether, 1 ether);
    }

    function testTwoSeparateBountiesCannotCrossChargeOrDoublePay() public {
        uint256 a = _fund(1 ether);
        uint256 b = _fund(2 ether);
        _creditRefund(a);
        _creditRefund(b);
        require(escrow.claimableByBounty(a, SPONSOR) == 1 ether, "first credit wrong");
        require(escrow.claimableByBounty(b, SPONSOR) == 2 ether, "second credit wrong");
        _reject(SPONSOR, abi.encodeWithSelector(
            escrow.withdrawBountyCredit.selector, a, payable(SPONSOR), 2 ether
        ));
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(a, payable(OUTSIDER), 1 ether);
        require(escrow.claimableByBounty(b, SPONSOR) == 2 ether, "other bounty credit leaked");
        _assertLedger(2 ether, 2 ether);
    }

    function testFreshFundedBountyAndExistingCreditsRemainDistinct() public {
        uint256 oldBounty = _fund(1 ether);
        _creditRefund(oldBounty);
        uint256 newBounty = _fund(3 ether);
        require(newBounty != oldBounty, "duplicate bounty");
        _assertLedger(4 ether, 1 ether);
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(oldBounty, payable(SPONSOR), 1 ether);
        _assertLedger(3 ether, 0);
        require(address(escrow).balance == 3 ether, "new reward withdrawn by old beneficiary");
    }

    function testActualSignedQuorumDeveloperRewardWithdrawableAfterChallengeOnly() public {
        uint256 bounty = _ready();
        _reject(DEVELOPER, abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty));
        _voteSigned(bounty, ORG_A, 1, KEY_A);
        _voteSigned(bounty, ORG_B, 1, KEY_B);
        _reject(DEVELOPER, abi.encodeWithSelector(escrow.accrueFinalCredits.selector, bounty));
        vm.warp(uint256(escrow.readReviewDecision(bounty, 1).challengeUntil) + 1);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        escrow.recordResolvedEntitlement(bounty, 1);
        escrow.accrueFinalCredits(bounty);
        require(escrow.claimableByBounty(bounty, DEVELOPER) == 1 ether, "earned reward missing");
        require(escrow.claimableByBounty(bounty, SPONSOR) == 0, "unwarranted sponsor credit");
        _assertLedger(1 ether, 1 ether);
        uint256 before = DEVELOPER.balance;
        vm.prank(DEVELOPER);
        escrow.withdrawBountyCredit(bounty, payable(DEVELOPER), 1 ether);
        require(DEVELOPER.balance == before + 1 ether, "developer not paid");
        _assertLedger(0, 0);
    }

    function testTwoSilentArbitratorsSharedDecisionCreditsExactAmounts() public {
        uint256 bounty = _sharedSilence();
        escrow.accrueFinalCredits(bounty);
        require(escrow.claimableByBounty(bounty, SPONSOR) == 0.5 ether, "wrong sponsor split");
        require(escrow.claimableByBounty(bounty, DEVELOPER) == 0.5 ether, "wrong developer split");
        _assertLedger(1 ether, 1 ether);
        vm.prank(DEVELOPER);
        escrow.withdrawBountyCredit(bounty, payable(DEVELOPER), 0.5 ether);
        _assertLedger(0.5 ether, 0.5 ether);
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(bounty, payable(SPONSOR), 0.5 ether);
        _assertLedger(0, 0);
    }

    function testForcedExtraNativeAtomsCannotCreateExtraCreditOrBeSwept() public {
        uint256 bounty = _fund(1 ether);
        _creditRefund(bounty);
        vm.deal(address(escrow), 6 ether);
        (uint256 liabilities, uint256 credits, uint256 surplus, bool solvent) =
            escrow.nativeLiabilityHealth();
        require(liabilities == 1 ether && credits == 1 ether && surplus == 5 ether && solvent,
            "surplus mistakenly counted as beneficiary credit");
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(bounty, payable(SPONSOR), 1 ether);
        require(address(escrow).balance == 5 ether, "forced surplus was spent");
        require(escrow.unreservedNativeSurplus() == 5 ether, "wrong quarantined surplus");
        _assertLedger(0, 0);
    }

    function testFuzzPartialNativeWithdrawalConservesAccounting(uint96 randomPart) public {
        uint256 bounty = _fund(1 ether);
        _creditRefund(bounty);
        uint256 part = uint256(randomPart) % (1 ether) + 1;
        vm.prank(SPONSOR);
        escrow.withdrawBountyCredit(bounty, payable(OUTSIDER), part);
        uint256 remaining = 1 ether - part;
        require(escrow.claimableByBounty(bounty, SPONSOR) == remaining, "fuzz credit mismatch");
        _assertLedger(remaining, remaining);
        if (remaining != 0) {
            vm.prank(SPONSOR);
            escrow.withdrawBountyCredit(bounty, payable(SPONSOR), remaining);
        }
        _assertLedger(0, 0);
    }
}
