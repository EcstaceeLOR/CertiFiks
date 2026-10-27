// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SignedVerifierDecisionModuleV1} from "../src/SignedVerifierDecisionModuleV1.sol";
import {BoundedArbitrationModuleV1} from "../src/BoundedArbitrationModuleV1.sol";
import {FairEntitlementModuleV1} from "../src/FairEntitlementModuleV1.sol";
import {VerifierRegistryModuleV1} from "../src/VerifierRegistryModuleV1.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";
import {BountySubmissionModuleV1} from "../src/BountySubmissionModuleV1.sol";
import {BountyAssignmentModuleV1} from "../src/BountyAssignmentModuleV1.sol";

interface VmFairSettlement {
    function prank(address who) external;
    function deal(address who, uint256 balance) external;
    function chainId(uint256 id) external;
    function warp(uint256 unixTime) external;
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 hash)
        external returns (uint8 v, bytes32 r, bytes32 s);
}

/** Foundry test harness ONLY. Contains no public production funding or payment. */
contract FairEntitlementHarness is FairEntitlementModuleV1 {
    address internal immutable fixtureOwner;

    constructor(uint256 chain, address governance)
        FairEntitlementModuleV1(chain, governance)
    {
        fixtureOwner = msg.sender;
    }

    function testFund(FundingRequest calldata request) external payable returns (uint256) {
        return _recordFunding(request);
    }

    function testReviewAuthorizesRetry(uint256 bounty, uint64 attempt, bytes32 decisionDigest)
        external
    {
        require(msg.sender == fixtureOwner, "fixture only");
        _authorizeRetryFromReview(bounty, attempt, decisionDigest);
    }
}

contract FairEntitlementModuleV1Test {
    VmFairSettlement private constant vm = VmFairSettlement(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );
    uint256 private constant CHAIN = 31337;
    uint256 private constant KEY_A = 111;
    uint256 private constant KEY_B = 222;
    uint256 private constant KEY_ATTACKER = 999;
    address private constant SPONSOR = address(0xA110);
    address private constant DEVELOPER = address(0xCAFE);
    address private constant ARBITRATOR = address(0xA4B);
    address private constant FALLBACK = address(0xF4B);
    address private constant CONTROLLER_A = address(0xC111);
    address private constant CONTROLLER_B = address(0xC222);
    bytes32 private constant ORG_A = keccak256("independent-reviewer-A");
    bytes32 private constant ORG_B = keccak256("independent-reviewer-B");
    bytes20 private constant BASE_SHA = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes20 private constant FIRST_HEAD = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    bytes20 private constant SECOND_HEAD = hex"cccccccccccccccccccccccccccccccccccccccc";
    bytes32 private constant REPORT_A = keccak256("actual signed report A");
    bytes32 private constant REPORT_B = keccak256("actual signed report B");
    FairEntitlementHarness private escrow;
    address private signerA;
    address private signerB;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        signerA = vm.addr(KEY_A);
        signerB = vm.addr(KEY_B);
        escrow = new FairEntitlementHarness(CHAIN, address(this));
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

    function _roster() internal pure returns (bytes32[] memory roster) {
        roster = new bytes32[](2);
        (roster[0], roster[1]) = ORG_A < ORG_B ? (ORG_A, ORG_B) : (ORG_B, ORG_A);
    }

    function _fundBare() internal returns (uint256 bountyId) {
        BountyFundingModuleV1.FundingRequest memory req =
            BountyFundingModuleV1.FundingRequest({
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
                submissionDeadline: uint64(block.timestamp + 10 days),
                verificationSeconds: 2 days,
                challengeSeconds: 1 days,
                arbitrationSeconds: 2 days,
                assetKind: 0
            });
        vm.prank(SPONSOR);
        bountyId = escrow.testFund{value: 1 ether}(req);
        vm.prank(SPONSOR);
        escrow.registerCommittedReviewerRoster(bountyId, _roster(), 2);
    }

    function _fund() internal returns (uint256 bountyId) {
        bountyId = _fundBare();
        vm.prank(SPONSOR);
        escrow.registerDisputePolicy(bountyId, FALLBACK);
        escrow.approveArbitrationPolicy(bountyId);
        vm.prank(ARBITRATOR);
        escrow.acceptArbitratorRole(bountyId);
        vm.prank(FALLBACK);
        escrow.acceptArbitratorRole(bountyId);
    }

    function _candidate(bytes20 head)
        internal pure returns (BountySubmissionModuleV1.Candidate memory)
    {
        return BountySubmissionModuleV1.Candidate({
            repositoryId: 888,
            pullNumber: 42,
            baseGitSha: BASE_SHA,
            headGitSha: head,
            imageDigest: bytes32(uint256(103)),
            evidenceDigest: bytes32(uint256(104)),
            manifestDigest: bytes32(uint256(100)),
            manifestVersion: 1
        });
    }

    function _submitted() internal returns (uint256 bounty) {
        bounty = _fund();
        vm.prank(DEVELOPER);
        escrow.applyForBounty(bounty);
        vm.prank(SPONSOR);
        escrow.offerAssignment(bounty, DEVELOPER);
        vm.prank(DEVELOPER);
        escrow.acceptAssignment(bounty);
        vm.prank(DEVELOPER);
        escrow.submitCandidate(bounty, _candidate(FIRST_HEAD));
    }

    function _assignAndDeclare(uint256 bounty, uint64 attempt) internal {
        escrow.assignReviewerJob(bounty, ORG_A);
        escrow.assignReviewerJob(bounty, ORG_B);
        vm.prank(signerA);
        escrow.acceptReviewerJob(bounty, attempt, ORG_A);
        vm.prank(signerB);
        escrow.acceptReviewerJob(bounty, attempt, ORG_B);
        vm.prank(signerA);
        escrow.declareReviewerEvidence(bounty, attempt, ORG_A, REPORT_A);
        vm.prank(signerB);
        escrow.declareReviewerEvidence(bounty, attempt, ORG_B, REPORT_B);
    }

    function _ready() internal returns (uint256 bounty) {
        bounty = _submitted();
        _assignAndDeclare(bounty, 1);
    }

    function _vote(
        uint256 bounty, bytes32 org, uint8 outcome
    ) internal view returns (SignedVerifierDecisionModuleV1.SignedVerdict memory v) {
        VerifierRegistryModuleV1.ReviewerJob memory job =
            escrow.getReviewerJob(bounty, 1, org);
        BountySubmissionModuleV1.FixAttempt memory attempt =
            escrow.getPinnedAttempt(bounty, 1);
        BountyFundingModuleV1.BountyTerms memory terms =
            escrow.getFundingTerms(bounty);
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

    function _sign(SignedVerifierDecisionModuleV1.SignedVerdict memory v, uint256 key)
        internal returns (bytes memory)
    {
        // The verifier signs the contract's official EIP-712 digest.
        // No backend impersonation or hardcoded fake signature is accepted.
        bytes32 typed = escrow.typedVerdictDigest(v);
        (uint8 sv, bytes32 r, bytes32 s) = vm.sign(key, typed);
        return abi.encodePacked(r, s, sv);
    }

    function _submit(
        SignedVerifierDecisionModuleV1.SignedVerdict memory v, uint256 key
    ) internal {
        escrow.submitSignedVerdict(v, _sign(v, key));
    }

    function _reject(
        SignedVerifierDecisionModuleV1.SignedVerdict memory v, bytes memory signature
    ) internal {
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.submitSignedVerdict.selector, v, signature)
        );
        require(!ok, "invalid verifier attestation succeeded");
    }


    function _approved() internal returns (uint256 bounty) {
        bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        _submit(_vote(bounty, ORG_B, 1), KEY_B);
    }

    function _openChallenge(uint256 bounty) internal {
        vm.prank(SPONSOR);
        escrow.challengeApprovedAttempt(
            bounty, 1, keccak256("sponsor challenges result"),
            keccak256("archive evidence, baseline reproduction")
        );
        // Existing tests exercise primary rulings after the guaranteed
        // counterparty evidence grace period, not unfair instant rulings.
        vm.warp(block.timestamp + 1 hours);
    }

    function _openEscalation(uint256 bounty) internal {
        vm.prank(DEVELOPER);
        escrow.openReviewEscalation(
            bounty, 1, keccak256("independent review disagreed"),
            keccak256("reproduction transcript evidence")
        );
        vm.warp(block.timestamp + 1 hours);
    }

    function _failAs(address actor, bytes memory calldataPayload) internal {
        vm.prank(actor);
        (bool success,) = address(escrow).call(calldataPayload);
        require(!success, "invalid dispute operation succeeded");
    }


    function _entitlement(uint256 bounty) internal view returns (FairEntitlementModuleV1.Entitlement memory) {
        return escrow.getEntitlement(bounty);
    }

    function _failedCall(address caller, bytes memory callData) internal {
        vm.prank(caller);
        (bool success,) = address(escrow).call(callData);
        require(!success, "bad settlement action accepted");
    }

    function testSponsorCanRecoverUnassignedCancelledBountyButNoTokenTransfer() public {
        uint256 bounty = _fund();
        vm.prank(SPONSOR);
        escrow.cancelUnassignedBounty(bounty);
        vm.prank(CONTROLLER_A);
        escrow.recordNoSubmissionRefund(bounty);
        FairEntitlementModuleV1.Entitlement memory e = _entitlement(bounty);
        require(e.reason == FairEntitlementModuleV1.Reason.UnassignedSponsorCancellation, "wrong entitlement");
        require(e.sponsorAtoms == 1 ether && e.developerAtoms == 0, "not sponsor refund");
        require(e.sourceAttemptId == 0 && e.developer == address(0), "fake developer assigned");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "refund transferred funds early");
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        require(escrow.unreservedNativeSurplus() == 0, "reserved assets called surplus");
    }

    function testReadOnlyRefundPreviewMatchesActualImmutableDecision() public {
        uint256 bounty = _fund();
        (FairEntitlementModuleV1.Reason reason, bool ready, uint256 atoms) =
            escrow.previewNoSubmissionEntitlement(bounty);
        require(reason == FairEntitlementModuleV1.Reason.None &&
            !ready && atoms == 0, "open bounty falsely called refundable");

        vm.prank(SPONSOR);
        escrow.cancelUnassignedBounty(bounty);
        (reason, ready, atoms) = escrow.previewNoSubmissionEntitlement(bounty);
        require(reason == FairEntitlementModuleV1.Reason.UnassignedSponsorCancellation &&
            ready && atoms == 1 ether, "cancelled sponsor preview incorrect");
        require(address(escrow).balance == escrow.totalReservedAtoms(),
            "read-only preview modified liabilities");

        escrow.recordNoSubmissionRefund(bounty);
        (reason, ready, atoms) = escrow.previewNoSubmissionEntitlement(bounty);
        require(reason == FairEntitlementModuleV1.Reason.None &&
            !ready && atoms == 0, "recorded refund could be replayed");
        require(address(escrow).balance == escrow.totalReservedAtoms(),
            "refund bookkeeping transferred ETH");
    }

    function testTimelySubmittedFixNeverBecomesSponsorRefundPreview() public {
        uint256 bounty = _submitted();
        (FairEntitlementModuleV1.Reason reason, bool ready, uint256 atoms) =
            escrow.previewNoSubmissionEntitlement(bounty);
        require(reason == FairEntitlementModuleV1.Reason.None &&
            !ready && atoms == 0, "timely submission is sponsor-refundable");
        vm.warp(uint256(escrow.getFundingTerms(bounty).submissionDeadline) + 1);
        (reason, ready, atoms) = escrow.previewNoSubmissionEntitlement(bounty);
        require(reason == FairEntitlementModuleV1.Reason.None &&
            !ready && atoms == 0, "timeout stole submitted developer entitlement");
        _failedCall(SPONSOR, abi.encodeWithSelector(
            escrow.recordNoSubmissionRefund.selector, bounty
        ));
    }

    function testSponsorCannotRefundAfterDeveloperSubmittedBeforeDeadline() public {
        uint256 bounty = _submitted();
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.cancelUnassignedBounty.selector, bounty));
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        require(_entitlement(bounty).reason == FairEntitlementModuleV1.Reason.None, "unfair immediate refund");
        require(address(escrow).balance == 1 ether, "locked funds vanished");
    }

    function testAcceptedButUnsubmittedFixRefundOnlyAfterImmutableDeadline() public {
        uint256 bounty = _fund();
        vm.prank(DEVELOPER);
        escrow.applyForBounty(bounty);
        vm.prank(SPONSOR);
        escrow.offerAssignment(bounty, DEVELOPER);
        vm.prank(DEVELOPER);
        escrow.acceptAssignment(bounty);
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        (, bool beforeDeadline, uint256 beforeAtoms) =
            escrow.previewNoSubmissionEntitlement(bounty);
        require(!beforeDeadline && beforeAtoms == 0, "accepted work treated as refundable");
        uint256 deadline = escrow.getFundingTerms(bounty).submissionDeadline;
        vm.warp(deadline);
        _failedCall(CONTROLLER_A, abi.encodeWithSelector(escrow.expireUnsubmittedBounty.selector, bounty));
        vm.warp(deadline + 1);
        vm.prank(CONTROLLER_A);
        escrow.expireUnsubmittedBounty(bounty);
        (FairEntitlementModuleV1.Reason reason, bool ready, uint256 atoms) =
            escrow.previewNoSubmissionEntitlement(bounty);
        require(reason == FairEntitlementModuleV1.Reason.NoSubmissionAtDeadline &&
            ready && atoms == 1 ether, "missed-deadline preview not supported");
        vm.prank(CONTROLLER_B);
        escrow.recordNoSubmissionRefund(bounty);
        require(_entitlement(bounty).reason == FairEntitlementModuleV1.Reason.NoSubmissionAtDeadline,
            "missed deadline not refundable");
        require(_entitlement(bounty).sponsorAtoms == 1 ether, "sponsor shorted");
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        require(address(escrow).balance == 1 ether, "refund paid before withdrawal module");
    }

    function testPositiveSignedQuorumAfterChallengeWindowAllocatesDeveloperFullAmount() public {
        uint256 bounty = _approved();
        _failedCall(DEVELOPER, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        uint256 deadline = escrow.readReviewDecision(bounty, 1).challengeUntil;
        vm.warp(deadline + 1);
        vm.prank(CONTROLLER_A);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        vm.prank(CONTROLLER_B);
        escrow.recordResolvedEntitlement(bounty, 1);
        FairEntitlementModuleV1.Entitlement memory e = _entitlement(bounty);
        require(e.reason == FairEntitlementModuleV1.Reason.ApprovedFix, "wrong reason");
        require(e.developer == DEVELOPER && e.developerAtoms == 1 ether, "developer unpaid entitlement");
        require(e.sponsorAtoms == 0, "phantom sponsor rebate");
        require(e.sourceAttemptDigest == escrow.getPinnedAttempt(bounty, 1).attemptDigest,
            "attempt hash not retained");
        require(e.decisionReasonDigest != bytes32(0), "signed approval source missing");
        require(address(escrow).balance == 1 ether, "decision transferred value");
    }

    function testHumanRejectedFixCanRecordSponsorRefundOnlyAfterAppealWindow() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 2), KEY_A);
        _openEscalation(bounty);
        vm.prank(ARBITRATOR);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.SponsorRefund,
            bytes32(uint256(414)), bytes32(uint256(415))
        );
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        uint256 deadline = escrow.getDisputeCase(bounty, 1).appealUntil;
        vm.warp(deadline + 1);
        vm.prank(CONTROLLER_A);
        escrow.advanceDispute(bounty, 1);
        vm.prank(CONTROLLER_B);
        escrow.recordResolvedEntitlement(bounty, 1);
        FairEntitlementModuleV1.Entitlement memory e = _entitlement(bounty);
        require(e.reason == FairEntitlementModuleV1.Reason.IndependentlyAdjudicatedSponsorRefund,
            "sponsor refund lacked reviewed decision");
        require(e.sponsorAtoms == 1 ether && e.developerAtoms == 0, "wrong sponsor ruling");
        _failedCall(DEVELOPER, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
    }

    function testTwoSilentArbitratorsCannotStealFullRewardAfterPositiveQuorum() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        vm.warp(escrow.getDisputeCase(bounty, 1).primaryDeadline);
        escrow.advanceDispute(bounty, 1);
        vm.warp(escrow.getDisputeCase(bounty, 1).fallbackDeadline);
        escrow.advanceDispute(bounty, 1);
        vm.prank(DEVELOPER);
        escrow.recordResolvedEntitlement(bounty, 1);
        FairEntitlementModuleV1.Entitlement memory e = _entitlement(bounty);
        require(e.reason == FairEntitlementModuleV1.Reason.ApprovedFix, "sponsor silence vetoed signed proof");
        require(e.developerAtoms == 1 ether && e.sponsorAtoms == 0, "full reward was stolen");
    }

    function testSilentReviewersAndArbitratorsProduceDisclosedEvenSplitNotSponsorWindfall() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        uint256 deadline = escrow.getPinnedAttempt(bounty, 1).submittedAt +
            escrow.getFundingTerms(bounty).verificationSeconds;
        vm.warp(deadline);
        vm.prank(CONTROLLER_A);
        escrow.openReviewEscalation(bounty, 1, bytes32(uint256(551)), bytes32(uint256(552)));
        vm.warp(escrow.getDisputeCase(bounty, 1).primaryDeadline);
        vm.prank(CONTROLLER_A);
        escrow.advanceDispute(bounty, 1);
        vm.warp(escrow.getDisputeCase(bounty, 1).fallbackDeadline);
        vm.prank(CONTROLLER_B);
        escrow.advanceDispute(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.SharedResolution, "unreviewed failure became all-or-nothing");
        vm.prank(DEVELOPER);
        escrow.recordResolvedEntitlement(bounty, 1);
        FairEntitlementModuleV1.Entitlement memory e = _entitlement(bounty);
        require(e.reason == FairEntitlementModuleV1.Reason.SharedSilenceFallback, "no shared status");
        require(e.sponsorAtoms == 0.5 ether && e.developerAtoms == 0.5 ether,
            "settlement lacks neutral precommitted fallback");
        require(e.decisionReasonDigest == bytes32(uint256(551)), "missing provenance");
        require(address(escrow).balance == 1 ether, "shared decision moved money prematurely");
    }

    function testNegativeVoteDoesNotPermitPrematureRefundBeforeArbitration() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 2), KEY_A);
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        _openEscalation(bounty);
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        require(_entitlement(bounty).reason == FairEntitlementModuleV1.Reason.None, "adjudication bypassed");
    }

    function testPendingUnreviewedAttemptCannotBeConvertedToSponsorRefund() public {
        uint256 bounty = _submitted();
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        uint256 end = escrow.getPinnedAttempt(bounty, 1).submittedAt +
            escrow.getFundingTerms(bounty).verificationSeconds;
        vm.warp(end + 1);
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        require(address(escrow).balance == escrow.totalReservedAtoms(), "malicious refund bypassed hold");
    }

    function testWrongChainAndWrongAttemptCannotFinalizeEntitlement() public {
        uint256 bounty = _approved();
        uint256 deadline = escrow.readReviewDecision(bounty, 1).challengeUntil;
        vm.warp(deadline + 1);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        _failedCall(CONTROLLER_A, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(2)));
        vm.chainId(CHAIN + 1);
        _failedCall(DEVELOPER, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        vm.chainId(CHAIN);
        escrow.recordResolvedEntitlement(bounty, 1);
        require(_entitlement(bounty).reason == FairEntitlementModuleV1.Reason.ApprovedFix,
            "correct chain unable to finalize");
    }

    function testUnreservedDirectFundsNeverExpandBountyEntitlement() public {
        uint256 bounty = _fund();
        vm.deal(address(escrow), 3 ether);
        require(escrow.unreservedNativeSurplus() == 2 ether, "unreserved transfer treated as liability");
        vm.prank(SPONSOR);
        escrow.cancelUnassignedBounty(bounty);
        escrow.recordNoSubmissionRefund(bounty);
        require(_entitlement(bounty).sponsorAtoms == 1 ether, "surplus was included in refund");
        require(escrow.unreservedNativeSurplus() == 2 ether, "unexpected external funds became claimable");
        require(address(escrow).balance == 3 ether, "surplus was moved via policy");
    }

    function testFuzzFundingRecordDoesNotLeakUnexpectedSurplus(uint96 surplus) public {
        uint256 bounty = _fund();
        vm.deal(address(escrow), 1 ether + uint256(surplus));
        vm.prank(SPONSOR);
        escrow.cancelUnassignedBounty(bounty);
        escrow.recordNoSubmissionRefund(bounty);
        require(_entitlement(bounty).sponsorAtoms == 1 ether, "unexpected payout amount");
        require(escrow.unreservedNativeSurplus() == uint256(surplus), "surplus misallocated");
        require(address(escrow).balance == 1 ether + uint256(surplus), "contract balance changed");
    }

    function testNoDuplicateCreditsCanAriseFromRepeatedFinalization() public {
        uint256 bounty = _approved();
        vm.warp(uint256(escrow.readReviewDecision(bounty, 1).challengeUntil) + 1);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        escrow.recordResolvedEntitlement(bounty, 1);
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordNoSubmissionRefund.selector, bounty));
        _failedCall(SPONSOR, abi.encodeWithSelector(escrow.recordResolvedEntitlement.selector, bounty, uint64(1)));
        require(_entitlement(bounty).sponsorAtoms + _entitlement(bounty).developerAtoms ==
            escrow.getFundingTerms(bounty).rewardAtoms, "liability minted by replay");
    }
}
