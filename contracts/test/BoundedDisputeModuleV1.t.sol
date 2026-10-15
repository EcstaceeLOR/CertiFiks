// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BoundedDisputeModuleV1} from "../src/BoundedDisputeModuleV1.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";
import {BountySubmissionModuleV1} from "../src/BountySubmissionModuleV1.sol";
import {SignedVerifierDecisionModuleV1} from "../src/SignedVerifierDecisionModuleV1.sol";

interface VmDispute {
    function prank(address who) external;
    function deal(address who, uint256 balance) external;
    function chainId(uint256 id) external;
    function warp(uint256 ts) external;
    function addr(uint256 key) external returns (address);
    function sign(uint256 key, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

/** Test-only externally payable harness. NOT safe to deploy on any user chain. */
contract BoundedDisputeHarness is BoundedDisputeModuleV1 {
    constructor(uint256 chainId, address governance)
        BoundedDisputeModuleV1(chainId, governance)
    {}

    function testFund(FundingRequest calldata spec) external payable returns (uint256) {
        return _recordFunding(spec);
    }
}

contract BoundedDisputeModuleV1Test {
    VmDispute internal constant vm = VmDispute(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );
    uint256 internal constant CHAIN = 31337;
    uint256 internal constant KEY_A = 311;
    uint256 internal constant KEY_B = 322;
    address internal constant SPONSOR = address(0xA110);
    address internal constant DEV = address(0xCAFE);
    address internal constant PRIMARY = address(0xA4B);
    address internal constant FALLBACK = address(0xFA11);
    address internal constant GOVERNANCE = address(0x600D);
    address internal constant FOREIGN = address(0xBAD);
    address internal constant CONTROLLER_A = address(0xC111);
    address internal constant CONTROLLER_B = address(0xC222);
    bytes32 internal constant ORG_A = keccak256("reviewer-one");
    bytes32 internal constant ORG_B = keccak256("reviewer-two");
    bytes20 internal constant BASE_SHA = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes20 internal constant HEAD_SHA = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    bytes32 internal constant REPORT_A = keccak256("independent verifiable report alpha");
    bytes32 internal constant REPORT_B = keccak256("independent verifiable report beta");

    BoundedDisputeHarness internal escrow;
    address internal signerA;
    address internal signerB;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        signerA = vm.addr(KEY_A);
        signerB = vm.addr(KEY_B);
        escrow = new BoundedDisputeHarness(CHAIN, GOVERNANCE);
        vm.prank(GOVERNANCE);
        escrow.enrollReviewerOrganization(ORG_A, CONTROLLER_A, signerA,
            bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)));
        vm.prank(GOVERNANCE);
        escrow.enrollReviewerOrganization(ORG_B, CONTROLLER_B, signerB,
            bytes32(uint256(4)), bytes32(uint256(5)), bytes32(uint256(6)));
        vm.prank(CONTROLLER_A);
        escrow.activateReviewerOrganization(ORG_A);
        vm.prank(CONTROLLER_B);
        escrow.activateReviewerOrganization(ORG_B);
    }

    function _roster() internal pure returns (bytes32[] memory sorted) {
        sorted = new bytes32[](2);
        (sorted[0], sorted[1]) = ORG_A < ORG_B ? (ORG_A, ORG_B) : (ORG_B, ORG_A);
    }

    function _spec(uint256 amount) internal view returns (BountyFundingModuleV1.FundingRequest memory) {
        amount; // funding value is passed separately to payable function
        return BountyFundingModuleV1.FundingRequest({
            repositoryId: 998877,
            baselineGitSha: BASE_SHA,
            manifestDigest: bytes32(uint256(100)),
            verifierPolicyDigest: sha256(
                abi.encode("CertiFiks:verifier-roster:v1", uint8(2), _roster())
            ),
            disputePolicyDigest: escrow.disputePolicyCommitment(PRIMARY, FALLBACK),
            primaryArbitrator: PRIMARY,
            submissionDeadline: uint64(block.timestamp + 10 days),
            verificationSeconds: 2 days,
            challengeSeconds: 1 days,
            arbitrationSeconds: 1 days,
            assetKind: 0
        });
    }

    function _fundUnconfigured(uint256 reward) internal returns (uint256 id) {
        // Build the request BEFORE prank: _spec queries the contract, and that
        // external view would otherwise consume the single-call impersonation.
        BountyFundingModuleV1.FundingRequest memory request = _spec(reward);
        bytes32[] memory roster = _roster();
        vm.prank(SPONSOR);
        id = escrow.testFund{value: reward}(request);
        vm.prank(SPONSOR);
        escrow.registerCommittedReviewerRoster(id, roster, 2);
    }

    function _fund(uint256 reward) internal returns (uint256 id) {
        id = _fundUnconfigured(reward);
        vm.prank(SPONSOR);
        escrow.registerDisputeFallback(id, FALLBACK);
    }

    function _submitted(uint256 reward) internal returns (uint256 id) {
        id = _fund(reward);
        vm.prank(DEV);
        escrow.applyForBounty(id);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, DEV);
        vm.prank(DEV);
        escrow.acceptAssignment(id);
        BountySubmissionModuleV1.Candidate memory c = BountySubmissionModuleV1.Candidate({
            repositoryId: 998877,
            pullNumber: 42,
            baseGitSha: BASE_SHA,
            headGitSha: HEAD_SHA,
            imageDigest: bytes32(uint256(103)),
            evidenceDigest: bytes32(uint256(104)),
            manifestDigest: bytes32(uint256(100)),
            manifestVersion: 1
        });
        vm.prank(DEV);
        escrow.submitCandidate(id, c);
    }

    function _submitted() internal returns (uint256) {
        return _submitted(1 ether);
    }

    function _assignReports(uint256 id) internal {
        vm.prank(GOVERNANCE);
        escrow.assignReviewerJob(id, ORG_A);
        vm.prank(GOVERNANCE);
        escrow.assignReviewerJob(id, ORG_B);
        vm.prank(signerA);
        escrow.acceptReviewerJob(id, 1, ORG_A);
        vm.prank(signerB);
        escrow.acceptReviewerJob(id, 1, ORG_B);
        vm.prank(signerA);
        escrow.declareReviewerEvidence(id, 1, ORG_A, REPORT_A);
        vm.prank(signerB);
        escrow.declareReviewerEvidence(id, 1, ORG_B, REPORT_B);
    }

    function _vote(uint256 id, bytes32 org, uint8 outcome)
        internal view returns (SignedVerifierDecisionModuleV1.SignedVerdict memory v)
    {
        BountySubmissionModuleV1.FixAttempt memory att = escrow.getPinnedAttempt(id, 1);
        BountyFundingModuleV1.BountyTerms memory funding = escrow.getFundingTerms(id);
        v = SignedVerifierDecisionModuleV1.SignedVerdict({
            bountyId: id,
            attemptId: 1,
            organizationId: org,
            signerEpoch: 1,
            attemptDigest: att.attemptDigest,
            manifestDigest: funding.manifestDigest,
            verifierPolicyDigest: funding.verifierPolicyDigest,
            headGitSha: att.candidate.headGitSha,
            reportDigest: org == ORG_A ? REPORT_A : REPORT_B,
            imageDigest: att.candidate.imageDigest,
            outcome: outcome,
            baselineFailed: true,
            candidatePassed: outcome == 1,
            regressionsPassed: outcome == 1,
            expiresAt: uint64(block.timestamp + 1 days)
        });
    }

    function _sign(SignedVerifierDecisionModuleV1.SignedVerdict memory vote, uint256 key)
        internal returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, escrow.typedVerdictDigest(vote));
        return abi.encodePacked(r, s, v);
    }

    function _verified() internal returns (uint256 id) {
        id = _submitted();
        _assignReports(id);
        SignedVerifierDecisionModuleV1.SignedVerdict memory a = _vote(id, ORG_A, 1);
        SignedVerifierDecisionModuleV1.SignedVerdict memory b = _vote(id, ORG_B, 1);
        escrow.submitSignedVerdict(a, _sign(a, KEY_A));
        escrow.submitSignedVerdict(b, _sign(b, KEY_B));
        require(
            escrow.readReviewDecision(id, 1).status ==
            SignedVerifierDecisionModuleV1.ReviewStatus.ChallengeWindow,
            "not approved in fixture"
        );
    }

    function _dissent() internal returns (uint256 id) {
        id = _submitted();
        _assignReports(id);
        SignedVerifierDecisionModuleV1.SignedVerdict memory positive = _vote(id, ORG_A, 1);
        SignedVerifierDecisionModuleV1.SignedVerdict memory negative = _vote(id, ORG_B, 2);
        escrow.submitSignedVerdict(positive, _sign(positive, KEY_A));
        escrow.submitSignedVerdict(negative, _sign(negative, KEY_B));
    }

    function _revertAs(address who, bytes memory data) internal {
        vm.prank(who);
        (bool ok,) = address(escrow).call(data);
        require(!ok, "invalid or repeated arbitration action unexpectedly succeeded");
    }

    function _challenge(uint256 id) internal {
        vm.prank(SPONSOR);
        escrow.challengeApprovedFix(id, bytes32(uint256(1000)));
    }

    function testDisputePolicyHashRequiresSponsorPrecommitmentAndSeparateFallback() public {
        uint256 id = _fundUnconfigured(1 ether);
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, FALLBACK));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, address(0)));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, PRIMARY));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, SPONSOR));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, GOVERNANCE));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, FOREIGN));
        vm.prank(SPONSOR);
        escrow.registerDisputeFallback(id, FALLBACK);
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.registerDisputeFallback.selector, id, FALLBACK));
        require(escrow.readDisputePolicy(id).fallbackArbitrator == FALLBACK, "fallback not pinned");
    }

    function testSponsorCannotForceAcceptanceUntilFallbackSelected() public {
        uint256 id = _fundUnconfigured(1 ether);
        vm.prank(DEV);
        escrow.applyForBounty(id);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, DEV);
        _revertAs(DEV, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        vm.prank(SPONSOR);
        escrow.revokeOffer(id);
        vm.prank(SPONSOR);
        escrow.registerDisputeFallback(id, FALLBACK);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, DEV);
        vm.prank(DEV);
        escrow.acceptAssignment(id);
        require(escrow.canSubmit(id, DEV), "configured consent blocked");
    }

    function testNeitherArbitratorCanBecomeTheAssignedDeveloper() public {
        uint256 id = _fund(1 ether);
        vm.prank(PRIMARY);
        escrow.applyForBounty(id);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, PRIMARY);
        _revertAs(PRIMARY, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
        vm.prank(SPONSOR);
        escrow.revokeOffer(id);
        vm.prank(FALLBACK);
        escrow.applyForBounty(id);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, FALLBACK);
        _revertAs(FALLBACK, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
    }

    function testSponsorChallengeRecordsOriginalReasonAndDeveloperResponse() public {
        uint256 id = _verified();
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.challengeApprovedFix.selector, id, bytes32(uint256(9))));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedFix.selector, id, bytes32(0)));
        _challenge(id);
        BoundedDisputeModuleV1.DisputeCase memory record = escrow.readDisputeCase(id, 1);
        require(record.state == BoundedDisputeModuleV1.CaseState.PrimaryReview, "not opened");
        require(record.reasonDigest == bytes32(uint256(1000)), "reason substituted");
        require(record.sponsorEvidenceDigest == bytes32(uint256(1000)), "challenge evidence lost");
        require(record.attemptDigest == escrow.getPinnedAttempt(id, 1).attemptDigest, "wrong attempt");
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.filePartyEvidence.selector, id, bytes32(uint256(2))));
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.filePartyEvidence.selector, id, bytes32(uint256(2))));
        vm.prank(DEV);
        escrow.filePartyEvidence(id, bytes32(uint256(77)));
        _revertAs(DEV, abi.encodeWithSelector(
            escrow.filePartyEvidence.selector, id, bytes32(uint256(88))));
        record = escrow.readDisputeCase(id, 1);
        require(record.developerEvidenceDigest == bytes32(uint256(77)), "reply overwritten");
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedFix.selector, id, bytes32(uint256(8))));
        require(address(escrow).balance == escrow.totalReservedAtoms(), "dispute moved funds");
    }

    function testPrimaryDeveloperJudgmentCanFinalizeAfterFixedAppealPeriod() public {
        uint256 id = _verified();
        _challenge(id);
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(1))));
        _revertAs(PRIMARY, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.None, bytes32(uint256(1))));
        vm.prank(PRIMARY);
        escrow.decidePrimary(id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(44)));
        _revertAs(DEV, abi.encodeWithSelector(
            escrow.appealPrimary.selector, id, bytes32(uint256(66))));
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.appealPrimary.selector, id, bytes32(uint256(66))));
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.finalizeUnappealedPrimary.selector, id));
        uint64 cutoff = escrow.readDisputeCase(id, 1).appealUntil;
        vm.warp(cutoff);
        escrow.finalizeUnappealedPrimary(id);
        (uint256 developer, uint256 sponsor) = escrow.readFinalEntitlements(id, 1);
        require(developer == 1 ether && sponsor == 0, "developer award not deterministic");
        require(escrow.readDisputeCase(id, 1).finalDecisionDigest == bytes32(uint256(44)),
            "adjudication reason missing");
        _revertAs(FOREIGN, abi.encodeWithSelector(escrow.finalizeUnappealedPrimary.selector, id));
        require(address(escrow).balance == 1 ether, "case close moved actual funds");
    }

    function testLosingSponsorMayAppealOnlyOnceAndFallbackRulesAgainstDeveloper() public {
        uint256 id = _verified();
        _challenge(id);
        vm.prank(PRIMARY);
        escrow.decidePrimary(id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(100)));
        vm.prank(SPONSOR);
        escrow.appealPrimary(id, bytes32(uint256(101)));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.appealPrimary.selector, id, bytes32(uint256(102))));
        _revertAs(PRIMARY, abi.encodeWithSelector(
            escrow.decideFallback.selector, id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(uint256(103))));
        vm.prank(FALLBACK);
        escrow.decideFallback(id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(uint256(104)));
        (uint256 developer, uint256 sponsor) = escrow.readFinalEntitlements(id, 1);
        require(developer == 0 && sponsor == 1 ether, "fallback decision not enforced");
        require(escrow.readDisputeCase(id, 1).appealEvidenceDigest == bytes32(uint256(101)),
            "appeal evidence erased");
        _revertAs(FALLBACK, abi.encodeWithSelector(
            escrow.decideFallback.selector, id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(1))));
    }

    function testDeveloperCanAppealAdversePrimaryDecision() public {
        uint256 id = _dissent();
        escrow.materializeEscalatedReview(id);
        vm.prank(PRIMARY);
        escrow.decidePrimary(id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(uint256(50)));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.appealPrimary.selector, id, bytes32(uint256(40))));
        vm.prank(DEV);
        escrow.appealPrimary(id, bytes32(uint256(60)));
        vm.prank(FALLBACK);
        escrow.decideFallback(id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(70)));
        (uint256 developer, uint256 sponsor) = escrow.readFinalEntitlements(id, 1);
        require(developer == 1 ether && sponsor == 0, "developer appeal ignored");
    }

    function testPrimarySilenceSwitchesToFallbackAfterOriginalDeadline() public {
        uint256 id = _verified();
        _challenge(id);
        uint64 primaryUntil = escrow.readDisputeCase(id, 1).primaryUntil;
        _revertAs(FOREIGN, abi.encodeWithSelector(escrow.escalateSilentPrimary.selector, id));
        vm.warp(primaryUntil);
        vm.prank(FOREIGN);
        escrow.escalateSilentPrimary(id);
        require(escrow.readDisputeCase(id, 1).state ==
            BoundedDisputeModuleV1.CaseState.FallbackReview, "primary silence trapped case");
        vm.prank(FALLBACK);
        escrow.decideFallback(id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(13)));
        (uint256 developer, ) = escrow.readFinalEntitlements(id, 1);
        require(developer == 1 ether, "fallback failed");
    }

    function testBothArbitratorsSilentAfterQuorumCannotVetoValidWork() public {
        uint256 id = _verified();
        _challenge(id);
        uint64 primaryUntil = escrow.readDisputeCase(id, 1).primaryUntil;
        vm.warp(primaryUntil + 2 days);
        escrow.escalateSilentPrimary(id);
        uint64 fallbackUntil = escrow.readDisputeCase(id, 1).fallbackUntil;
        require(fallbackUntil == primaryUntil + 1 days, "silent case deadline extended");
        escrow.finalizeSilentFallback(id);
        require(escrow.readDisputeCase(id, 1).finalRuling ==
            BoundedDisputeModuleV1.Ruling.Developer, "sponsor won by exhausting reviewers");
        (uint256 developer, uint256 sponsor) = escrow.readFinalEntitlements(id, 1);
        require(developer == 1 ether && sponsor == 0, "precommitted no-answer policy wrong");
        _revertAs(SPONSOR, abi.encodeWithSelector(escrow.challengeApprovedFix.selector, id, bytes32(uint256(99))));
    }

    function testDissentEscalationStartsAtOriginalSignedDecisionNotCallerDelay() public {
        uint256 id = _dissent();
        uint64 decisionAt = escrow.readReviewDecision(id, 1).decidedAt;
        require(decisionAt == block.timestamp, "review transition time not recorded");
        vm.warp(block.timestamp + 5 days);
        escrow.materializeEscalatedReview(id);
        BoundedDisputeModuleV1.DisputeCase memory rec = escrow.readDisputeCase(id, 1);
        require(rec.openedAt == decisionAt, "caller extended grievance clock");
        require(rec.primaryUntil == decisionAt + 1 days, "primary arbitration clock shifted");
        escrow.escalateSilentPrimary(id);
        escrow.finalizeSilentFallback(id);
        require(escrow.readDisputeCase(id, 1).finalRuling ==
            BoundedDisputeModuleV1.Ruling.Split, "inconclusive fixed split not enforced");
        (uint256 developer, uint256 sponsor) = escrow.readFinalEntitlements(id, 1);
        require(developer + sponsor == 1 ether, "split lost money");
        require(developer == 0.5 ether, "contract ignored half split");
    }

    function testDissentAutomaticallyOpensCaseInSameSignedReviewTransition() public {
        uint256 id = _dissent();
        BoundedDisputeModuleV1.DisputeCase memory record = escrow.readDisputeCase(id, 1);
        require(record.state == BoundedDisputeModuleV1.CaseState.PrimaryReview,
            "dissent did not immediately trigger a case");
        require(record.openedAt == escrow.readReviewDecision(id, 1).decidedAt,
            "review and case timestamps are not atomic");
        uint64 cutoff = record.primaryUntil;
        vm.warp(block.timestamp + 12 hours);
        vm.prank(FOREIGN);
        escrow.materializeEscalatedReview(id);
        require(escrow.readDisputeCase(id, 1).primaryUntil == cutoff,
            "late caller reset original arbitration clock");
    }

    function testReviewTimeoutOpensCaseImmediatelyWithoutManualRequest() public {
        uint256 id = _submitted();
        vm.warp(uint256(escrow.getPinnedAttempt(id, 1).submittedAt) + 2 days);
        escrow.expireIncompleteReview(id, 1);
        BoundedDisputeModuleV1.DisputeCase memory record = escrow.readDisputeCase(id, 1);
        require(record.state == BoundedDisputeModuleV1.CaseState.PrimaryReview,
            "timeout left no case for a timely contributor");
        require(record.openedAt == block.timestamp, "case did not begin at timeout");
    }

    function testCommittedReviewerSignerCannotAlsoAcceptDeveloperAssignment() public {
        uint256 id = _fund(1 ether);
        vm.prank(signerA);
        escrow.applyForBounty(id);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, signerA);
        _revertAs(signerA, abi.encodeWithSelector(escrow.acceptAssignment.selector, id));
    }

    function testNoVerifierQuorumTimeoutAllowsDeterministicResolution() public {
        uint256 id = _submitted(5);
        uint64 submitted = escrow.getPinnedAttempt(id, 1).submittedAt;
        vm.warp(uint256(submitted) + 2 days);
        escrow.expireIncompleteReview(id, 1);
        uint64 decidedAt = escrow.readReviewDecision(id, 1).decidedAt;
        vm.warp(uint256(decidedAt) + 3 days);
        vm.prank(FOREIGN);
        escrow.materializeEscalatedReview(id);
        escrow.escalateSilentPrimary(id);
        escrow.finalizeSilentFallback(id);
        (uint256 developer, uint256 sponsor) = escrow.readFinalEntitlements(id, 1);
        require(developer == 2 && sponsor == 3, "odd-atom remainder not conserved");
        require(address(escrow).balance == 5 && escrow.totalReservedAtoms() == 5,
            "synthetic terminal ruling moved user assets");
    }

    function testAppealSilentFallbackCannotDiscardValidPrimaryDecision() public {
        uint256 id = _verified();
        _challenge(id);
        vm.prank(PRIMARY);
        escrow.decidePrimary(id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(3)));
        vm.prank(SPONSOR);
        escrow.appealPrimary(id, bytes32(uint256(4)));
        uint64 until = escrow.readDisputeCase(id, 1).fallbackUntil;
        vm.warp(until);
        escrow.finalizeSilentFallback(id);
        require(escrow.readDisputeCase(id, 1).finalRuling ==
            BoundedDisputeModuleV1.Ruling.Developer, "baseless appeal reversed primary ruling");
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.finalizeSilentFallback.selector, id));
    }

    function testUnresolvedCaseMustNotClaimFinalEntitlement() public {
        uint256 id = _verified();
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.readFinalEntitlements.selector, id, uint64(1)));
        _challenge(id);
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.readFinalEntitlements.selector, id, uint64(1)));
        _revertAs(FOREIGN, abi.encodeWithSelector(escrow.finalizeSilentFallback.selector, id));
    }

    function testChallengeClosedAfterFixedWindowWithoutSponsorVeto() public {
        uint256 id = _verified();
        uint64 challengeUntil = escrow.readReviewDecision(id, 1).challengeUntil;
        vm.warp(challengeUntil);
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.challengeApprovedFix.selector, id, bytes32(uint256(90))));
        _revertAs(SPONSOR, abi.encodeWithSelector(
            escrow.materializeEscalatedReview.selector, id));
        require(address(escrow).balance == 1 ether, "deadline moved money");
    }

    function testForgedArbitratorAndChangedEvidenceHashCannotResolve() public {
        uint256 id = _dissent();
        escrow.materializeEscalatedReview(id);
        _revertAs(FOREIGN, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(uint256(2))));
        _revertAs(PRIMARY, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(0)));
        vm.prank(DEV);
        escrow.filePartyEvidence(id, bytes32(uint256(7)));
        _revertAs(DEV, abi.encodeWithSelector(
            escrow.filePartyEvidence.selector, id, bytes32(uint256(8))));
        vm.prank(PRIMARY);
        escrow.decidePrimary(id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(uint256(20)));
        vm.warp(escrow.readDisputeCase(id, 1).appealUntil);
        escrow.finalizeUnappealedPrimary(id);
        require(escrow.readDisputeCase(id, 1).primaryDecisionDigest == bytes32(uint256(20)),
            "reason substitution altered case");
    }

    function testArbitratorWhoBecomesEnrolledReviewerIsPreventedFromRuling() public {
        uint256 id = _verified();
        _challenge(id);
        bytes32 otherOrg = keccak256("judge-hidden-reviewer-organization");
        vm.prank(GOVERNANCE);
        escrow.enrollReviewerOrganization(
            otherOrg, PRIMARY, address(0x5151),
            bytes32(uint256(5)), bytes32(uint256(6)), bytes32(uint256(7))
        );
        _revertAs(PRIMARY, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(2))));
        uint64 until = escrow.readDisputeCase(id, 1).primaryUntil;
        vm.warp(until);
        escrow.escalateSilentPrimary(id);
        // The independent fallback must also reject unvetted identity changes:
        _revertAs(FALLBACK, abi.encodeWithSelector(
            escrow.decideFallback.selector, id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(3))));
        vm.warp(escrow.readDisputeCase(id, 1).fallbackUntil);
        escrow.finalizeSilentFallback(id);
        require(escrow.readDisputeCase(id, 1).state ==
            BoundedDisputeModuleV1.CaseState.Finalized, "identity conflict trapped funds");
    }

    function testChangingChainNeverPermitsCaseDecisionOrChallenge() public {
        uint256 id = _verified();
        _challenge(id);
        vm.chainId(CHAIN + 1);
        _revertAs(PRIMARY, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.Developer, bytes32(uint256(3))));
        _revertAs(FOREIGN, abi.encodeWithSelector(escrow.escalateSilentPrimary.selector, id));
    }

    function testSplitPrimaryAllowsAppealButFinalizesOnlyOnce() public {
        uint256 id = _verified();
        _challenge(id);
        vm.prank(PRIMARY);
        escrow.decidePrimary(id, BoundedDisputeModuleV1.Ruling.Split, bytes32(uint256(51)));
        _revertAs(FOREIGN, abi.encodeWithSelector(escrow.appealPrimary.selector, id, bytes32(uint256(52))));
        vm.prank(DEV);
        escrow.appealPrimary(id, bytes32(uint256(53)));
        vm.prank(FALLBACK);
        escrow.decideFallback(id, BoundedDisputeModuleV1.Ruling.Split, bytes32(uint256(54)));
        require(escrow.readDisputeCase(id, 1).finalDecisionDigest == bytes32(uint256(54)),
            "fallthrough reason lost");
        _revertAs(PRIMARY, abi.encodeWithSelector(
            escrow.decidePrimary.selector, id, BoundedDisputeModuleV1.Ruling.Sponsor, bytes32(uint256(54))));
    }
}
