// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SignedVerifierDecisionModuleV1} from "../src/SignedVerifierDecisionModuleV1.sol";
import {BoundedArbitrationModuleV1} from "../src/BoundedArbitrationModuleV1.sol";
import {VerifierRegistryModuleV1} from "../src/VerifierRegistryModuleV1.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";
import {BountySubmissionModuleV1} from "../src/BountySubmissionModuleV1.sol";

interface VmSignedReport {
    function prank(address who) external;
    function deal(address who, uint256 balance) external;
    function chainId(uint256 id) external;
    function warp(uint256 unixTime) external;
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 hash)
        external returns (uint8 v, bytes32 r, bytes32 s);
}

/** Foundry test harness ONLY. Contains no public production funding or payment. */
contract ArbitrationHarness is BoundedArbitrationModuleV1 {
    address internal immutable fixtureOwner;

    constructor(uint256 chain, address governance)
        BoundedArbitrationModuleV1(chain, governance)
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

contract BoundedArbitrationModuleV1Test {
    VmSignedReport private constant vm = VmSignedReport(
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
    ArbitrationHarness private escrow;
    address private signerA;
    address private signerB;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        signerA = vm.addr(KEY_A);
        signerB = vm.addr(KEY_B);
        escrow = new ArbitrationHarness(CHAIN, address(this));
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

    function _fund() internal returns (uint256 bountyId) {
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
    }

    function _openEscalation(uint256 bounty) internal {
        vm.prank(DEVELOPER);
        escrow.openReviewEscalation(
            bounty, 1, keccak256("independent review disagreed"),
            keccak256("reproduction transcript evidence")
        );
    }

    function _failAs(address actor, bytes memory calldataPayload) internal {
        vm.prank(actor);
        (bool success,) = address(escrow).call(calldataPayload);
        require(!success, "invalid dispute operation succeeded");
    }

    function testUnchallengedPositiveQuorumMaturesToAwardButCannotMoveMoney() public {
        uint256 bounty = _approved();
        BoundedArbitrationModuleV1.DisputeCase memory existing = escrow.getDisputeCase(bounty, 1);
        require(existing.phase == BoundedArbitrationModuleV1.CasePhase.None, "synthetic dispute");
        uint256 until = escrow.readReviewDecision(bounty, 1).challengeUntil;
        _failAs(DEVELOPER, abi.encodeWithSelector(
            escrow.finalizeUnchallengedApproval.selector, bounty, uint64(1)
        ));
        vm.warp(until + 1);
        vm.prank(DEVELOPER);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        BoundedArbitrationModuleV1.DisputeCase memory resolved = escrow.getDisputeCase(bounty, 1);
        require(resolved.phase == BoundedArbitrationModuleV1.CasePhase.Resolved, "no final award");
        require(resolved.finalAward == BoundedArbitrationModuleV1.Award.DeveloperReward, "award changed");
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.finalizeUnchallengedApproval.selector, bounty, uint64(1)
        ));
        require(address(escrow).balance == 1 ether &&
            escrow.totalReservedAtoms() == 1 ether, "a verdict moved locked user funds");
    }

    function testSponsorChallengeRecordsImmutableReasonAndDoesNotExtendWindow() public {
        uint256 bounty = _approved();
        uint256 challengeUntil = escrow.readReviewDecision(bounty, 1).challengeUntil;
        _failAs(CONTROLLER_A, abi.encodeWithSelector(
            escrow.challengeApprovedAttempt.selector, bounty, uint64(1),
            bytes32(uint256(2)), bytes32(uint256(3))
        ));
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedAttempt.selector, bounty, uint64(1),
            bytes32(0), bytes32(uint256(3))
        ));
        _openChallenge(bounty);
        BoundedArbitrationModuleV1.DisputeCase memory c = escrow.getDisputeCase(bounty, 1);
        require(c.challenger == SPONSOR, "challenger spoofed");
        require(c.attemptDigest == escrow.getPinnedAttempt(bounty, 1).attemptDigest,
            "not linked to immutable attempt");
        require(c.primaryDeadline == challengeUntil +
            escrow.getFundingTerms(bounty).arbitrationSeconds, "deadline changed");
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedAttempt.selector, bounty, uint64(1),
            bytes32(uint256(4)), bytes32(uint256(5))
        ));
        require(escrow.getDisputeCase(bounty, 1).openingReasonDigest == c.openingReasonDigest,
            "evidence overwritten");
    }

    function testPrimaryRulingThenLosingSponsorAppealsToIndependentFallback() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        vm.prank(ARBITRATOR);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.DeveloperReward,
            keccak256("primary finding"), keccak256("primary reproduction artifacts")
        );
        require(escrow.getDisputeCase(bounty, 1).phase ==
            BoundedArbitrationModuleV1.CasePhase.PrimaryAppealWindow, "no appeal stage");
        _failAs(DEVELOPER, abi.encodeWithSelector(
            escrow.appealPrimaryRuling.selector, bounty, uint64(1),
            bytes32(uint256(10)), bytes32(uint256(11))
        ));
        vm.prank(SPONSOR);
        escrow.appealPrimaryRuling(bounty, 1, bytes32(uint256(30)), bytes32(uint256(31)));
        require(escrow.getDisputeCase(bounty, 1).phase ==
            BoundedArbitrationModuleV1.CasePhase.AppealReview, "appeal ignored");
        vm.prank(FALLBACK);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.SponsorRefund,
            bytes32(uint256(40)), bytes32(uint256(41))
        );
        BoundedArbitrationModuleV1.DisputeCase memory finished = escrow.getDisputeCase(bounty, 1);
        require(finished.phase == BoundedArbitrationModuleV1.CasePhase.Resolved, "appeal not resolved");
        require(finished.primaryAward == BoundedArbitrationModuleV1.Award.DeveloperReward,
            "first ruling altered");
        require(finished.finalAward == BoundedArbitrationModuleV1.Award.SponsorRefund,
            "independent appeal ruling ignored");
        require(finished.appealReasonDigest == bytes32(uint256(30)), "appeal evidence erased");
        require(finished.fallbackReasonDigest == bytes32(uint256(40)), "fallback evidence missing");
        _failAs(FALLBACK, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(42)), bytes32(uint256(43))
        ));
        require(address(escrow).balance == escrow.totalReservedAtoms(), "appeal moved funds");
    }

    function testDeveloperCanAppealUnfavorablePrimaryRefundOnce() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 2), KEY_A);
        _openEscalation(bounty);
        vm.prank(ARBITRATOR);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.SponsorRefund,
            bytes32(uint256(44)), bytes32(uint256(45))
        );
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.appealPrimaryRuling.selector, bounty, uint64(1),
            bytes32(uint256(50)), bytes32(uint256(51))
        ));
        vm.prank(DEVELOPER);
        escrow.appealPrimaryRuling(
            bounty, 1, bytes32(uint256(46)), bytes32(uint256(47))
        );
        _failAs(DEVELOPER, abi.encodeWithSelector(
            escrow.appealPrimaryRuling.selector, bounty, uint64(1),
            bytes32(uint256(48)), bytes32(uint256(49))
        ));
        vm.prank(FALLBACK);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(50)), bytes32(uint256(51))
        );
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.DeveloperReward, "developer appeal lost");
    }

    function testPrimaryRulingUnappealedFinalizesAfterFixedWindow() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        vm.prank(ARBITRATOR);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(80)), bytes32(uint256(81))
        );
        uint256 appealDeadline = escrow.getDisputeCase(bounty, 1).appealUntil;
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.advanceDispute.selector, bounty, uint64(1)
        ));
        vm.warp(appealDeadline + 1);
        vm.prank(DEVELOPER);
        escrow.advanceDispute(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.DeveloperReward, "unappealed result changed");
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.appealPrimaryRuling.selector, bounty, uint64(1),
            bytes32(uint256(9)), bytes32(uint256(10))
        ));
    }

    function testSilentPrimaryTriggersFallbackAndFallbackMayRule() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        uint256 primaryDeadline = escrow.getDisputeCase(bounty, 1).primaryDeadline;
        _failAs(CONTROLLER_A, abi.encodeWithSelector(
            escrow.advanceDispute.selector, bounty, uint64(1)
        ));
        vm.warp(primaryDeadline);
        vm.prank(DEVELOPER);
        escrow.advanceDispute(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).phase ==
            BoundedArbitrationModuleV1.CasePhase.FallbackReview, "silent primary not replaced");
        _failAs(ARBITRATOR, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.SponsorRefund,
            bytes32(uint256(20)), bytes32(uint256(21))
        ));
        vm.prank(FALLBACK);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(22)), bytes32(uint256(23))
        );
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.DeveloperReward, "fallback couldn't resolve");
    }

    function testBothArbitratorsSilentCannotFreezeVerifiedFixForever() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        uint256 primary = escrow.getDisputeCase(bounty, 1).primaryDeadline;
        vm.warp(primary);
        vm.prank(CONTROLLER_A);
        escrow.advanceDispute(bounty, 1);
        uint256 terminal = escrow.getDisputeCase(bounty, 1).fallbackDeadline;
        vm.warp(terminal);
        vm.prank(CONTROLLER_B);
        escrow.advanceDispute(bounty, 1);
        BoundedArbitrationModuleV1.DisputeCase memory finished = escrow.getDisputeCase(bounty, 1);
        require(finished.phase == BoundedArbitrationModuleV1.CasePhase.Resolved, "still stuck");
        require(finished.finalAward == BoundedArbitrationModuleV1.Award.DeveloperReward,
            "sponsor vetoed a positive quorum by silence");
        require(address(escrow).balance == 1 ether, "timeout paid funds directly");
    }

    function testBothArbitratorsSilentAfterMissingQuorumDefaultToRefund() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        uint256 deadline = escrow.getPinnedAttempt(bounty, 1).submittedAt +
            escrow.getFundingTerms(bounty).verificationSeconds;
        vm.warp(deadline);
        vm.prank(CONTROLLER_B);
        escrow.openReviewEscalation(
            bounty, 1, bytes32(uint256(61)), bytes32(uint256(62))
        );
        vm.warp(escrow.getDisputeCase(bounty, 1).primaryDeadline);
        vm.prank(CONTROLLER_B);
        escrow.advanceDispute(bounty, 1);
        uint256 terminal = escrow.getDisputeCase(bounty, 1).fallbackDeadline;
        vm.warp(terminal);
        vm.prank(CONTROLLER_B);
        escrow.advanceDispute(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.SponsorRefund,
            "unverified work was counted as a verified fix");
    }

    function testDissentDoesNotAutomaticallyMakeContributorPayable() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        _submit(_vote(bounty, ORG_B, 2), KEY_B);
        _openEscalation(bounty);
        _failAs(DEVELOPER, abi.encodeWithSelector(
            escrow.finalizeUnchallengedApproval.selector, bounty, uint64(1)
        ));
        require(escrow.getDisputeCase(bounty, 1).phase ==
            BoundedArbitrationModuleV1.CasePhase.PrimaryReview,
            "dissent directly settled");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "dissent transferred");
    }

    function testUnauthorizedPartyCannotEscalateBeforeReviewDeadline() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 3), KEY_A);
        _failAs(CONTROLLER_A, abi.encodeWithSelector(
            escrow.openReviewEscalation.selector, bounty, uint64(1),
            bytes32(uint256(10)), bytes32(uint256(11))
        ));
        vm.prank(DEVELOPER);
        escrow.openReviewEscalation(
            bounty, 1, bytes32(uint256(10)), bytes32(uint256(11))
        );
    }

    function testFakeChallengeAndMissingEvidenceAreRejected() public {
        uint256 bounty = _approved();
        _failAs(CONTROLLER_A, abi.encodeWithSelector(
            escrow.challengeApprovedAttempt.selector, bounty, uint64(1),
            bytes32(uint256(1)), bytes32(uint256(2))
        ));
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedAttempt.selector, bounty, uint64(1),
            bytes32(0), bytes32(uint256(2))
        ));
        _openChallenge(bounty);
        _failAs(ARBITRATOR, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.None,
            bytes32(uint256(1)), bytes32(uint256(2))
        ));
        _failAs(ARBITRATOR, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(0), bytes32(uint256(2))
        ));
        _failAs(CONTROLLER_A, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(1)), bytes32(uint256(2))
        ));
    }

    function testLateChallengeCannotResetTheReviewClock() public {
        uint256 bounty = _approved();
        uint256 deadline = escrow.readReviewDecision(bounty, 1).challengeUntil;
        vm.warp(deadline + 1);
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedAttempt.selector, bounty, uint64(1),
            bytes32(uint256(1)), bytes32(uint256(2))
        ));
        vm.prank(CONTROLLER_B);
        escrow.finalizeUnchallengedApproval(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.DeveloperReward, "late sponsor veto");
    }

    function testUnsignedOrUnvettedArbitratorCannotRuleAndTimeoutStillWorks() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        escrow.enrollReviewerOrganization(
            keccak256("later-linked-primary-key"), address(0xC333), ARBITRATOR,
            bytes32(uint256(2)), bytes32(uint256(3)), bytes32(uint256(4))
        );
        _failAs(ARBITRATOR, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.SponsorRefund,
            bytes32(uint256(5)), bytes32(uint256(6))
        ));
        vm.warp(escrow.getDisputeCase(bounty, 1).primaryDeadline);
        vm.prank(CONTROLLER_B);
        escrow.advanceDispute(bounty, 1);
        vm.prank(FALLBACK);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(7)), bytes32(uint256(8))
        );
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.DeveloperReward, "fallback blocked");
    }

    function testAppealReviewTimeoutPreservesPrimaryRulingWithoutInactionVeto() public {
        uint256 bounty = _approved();
        _openChallenge(bounty);
        vm.prank(ARBITRATOR);
        escrow.ruleOnDispute(
            bounty, 1, BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(91)), bytes32(uint256(92))
        );
        vm.prank(SPONSOR);
        escrow.appealPrimaryRuling(bounty, 1, bytes32(uint256(93)), bytes32(uint256(94)));
        vm.warp(escrow.getDisputeCase(bounty, 1).fallbackDeadline);
        vm.prank(CONTROLLER_B);
        escrow.advanceDispute(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.DeveloperReward,
            "silent fallback vetoed developer's primary ruling");
    }

    function testIncorrectFundedArbitrationPolicyCannotBeSwappedAfterDeposit() public {
        uint256 bounty = _fund();
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputePolicy.selector, bounty, address(0xBEEF)
        ));
        _failAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputePolicy.selector, bounty, FALLBACK
        ));
        BoundedArbitrationModuleV1.DisputePolicy memory p = escrow.getDisputePolicy(bounty);
        require(p.governanceApproved && p.primaryAccepted && p.fallbackAccepted,
            "unaccepted arbitrators slipped into policy");
        require(p.fallbackArbitrator == FALLBACK, "arbitration roster mutated");
    }

    function testOldAttemptDisputeCannotSettleAfterAuthorizedResubmission() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 2), KEY_A);
        _openEscalation(bounty);
        escrow.testReviewAuthorizesRetry(bounty, 1, bytes32(uint256(555)));
        vm.prank(DEVELOPER);
        escrow.resubmitCandidate(bounty, _candidate(SECOND_HEAD));
        _failAs(ARBITRATOR, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(2)), bytes32(uint256(3))
        ));
        vm.prank(CONTROLLER_A);
        escrow.markSupersededCase(bounty, 1);
        require(escrow.getDisputeCase(bounty, 1).phase ==
            BoundedArbitrationModuleV1.CasePhase.Superseded,
            "stale attempt still has live dispute");
        require(escrow.getDisputeCase(bounty, 1).finalAward ==
            BoundedArbitrationModuleV1.Award.None, "old refund or payout leaked");
    }

    function testFuzzAttackerCannotArbitrateUnrelatedCase(address attacker) public {
        if (attacker == ARBITRATOR || attacker == FALLBACK || attacker == address(0)) return;
        uint256 bounty = _approved();
        _openChallenge(bounty);
        _failAs(attacker, abi.encodeWithSelector(
            escrow.ruleOnDispute.selector, bounty, uint64(1),
            BoundedArbitrationModuleV1.Award.DeveloperReward,
            bytes32(uint256(40)), bytes32(uint256(41))
        ));
    }
}
