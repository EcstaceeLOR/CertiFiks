// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SignedVerifierDecisionModuleV1} from "../src/SignedVerifierDecisionModuleV1.sol";
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
contract SignedDecisionHarness is SignedVerifierDecisionModuleV1 {
    address internal immutable fixtureOwner;

    constructor(uint256 chain, address governance)
        SignedVerifierDecisionModuleV1(chain, governance)
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

contract SignedVerifierDecisionModuleV1Test {
    VmSignedReport private constant vm = VmSignedReport(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );
    uint256 private constant CHAIN = 31337;
    uint256 private constant KEY_A = 111;
    uint256 private constant KEY_B = 222;
    uint256 private constant KEY_C = 333;
    uint256 private constant KEY_ATTACKER = 999;
    address private constant SPONSOR = address(0xA110);
    address private constant DEVELOPER = address(0xCAFE);
    address private constant ARBITRATOR = address(0xA4B);
    address private constant CONTROLLER_A = address(0xC111);
    address private constant CONTROLLER_B = address(0xC222);
    address private constant CONTROLLER_C = address(0xC333);
    bytes32 private constant ORG_A = keccak256("independent-reviewer-A");
    bytes32 private constant ORG_B = keccak256("independent-reviewer-B");
    bytes32 private constant ORG_C = keccak256("independent-reviewer-C");
    bytes20 private constant BASE_SHA = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes20 private constant FIRST_HEAD = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    bytes20 private constant SECOND_HEAD = hex"cccccccccccccccccccccccccccccccccccccccc";
    bytes32 private constant REPORT_A = keccak256("actual signed report A");
    bytes32 private constant REPORT_B = keccak256("actual signed report B");
    bytes32 private constant REPORT_C = keccak256("actual signed report C");
    SignedDecisionHarness private escrow;
    address private signerA;
    address private signerB;
    address private signerC;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        signerA = vm.addr(KEY_A);
        signerB = vm.addr(KEY_B);
        signerC = vm.addr(KEY_C);
        escrow = new SignedDecisionHarness(CHAIN, address(this));
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
        escrow.enrollReviewerOrganization(
            ORG_C, CONTROLLER_C, signerC, bytes32(uint256(31)),
            bytes32(uint256(32)), bytes32(uint256(33))
        );
        vm.prank(CONTROLLER_C);
        escrow.activateReviewerOrganization(ORG_C);
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
                disputePolicyDigest: bytes32(uint256(102)),
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

    function _rosterThree() internal pure returns (bytes32[] memory roster) {
        roster = new bytes32[](3);
        roster[0] = ORG_A;
        roster[1] = ORG_B;
        roster[2] = ORG_C;
        if (roster[0] > roster[1]) (roster[0], roster[1]) = (roster[1], roster[0]);
        if (roster[1] > roster[2]) (roster[1], roster[2]) = (roster[2], roster[1]);
        if (roster[0] > roster[1]) (roster[0], roster[1]) = (roster[1], roster[0]);
    }

    function _submittedWithThreeReviewers() internal returns (uint256 bounty) {
        bytes32[] memory roster = _rosterThree();
        BountyFundingModuleV1.FundingRequest memory req =
            BountyFundingModuleV1.FundingRequest({
                repositoryId: 888,
                baselineGitSha: BASE_SHA,
                manifestDigest: bytes32(uint256(100)),
                verifierPolicyDigest: sha256(
                    abi.encode("CertiFiks:verifier-roster:v1", uint8(2), roster)
                ),
                disputePolicyDigest: bytes32(uint256(102)),
                primaryArbitrator: ARBITRATOR,
                submissionDeadline: uint64(block.timestamp + 10 days),
                verificationSeconds: 2 days,
                challengeSeconds: 1 days,
                arbitrationSeconds: 2 days,
                assetKind: 0
            });
        vm.prank(SPONSOR);
        bounty = escrow.testFund{value: 1 ether}(req);
        vm.prank(SPONSOR);
        escrow.registerCommittedReviewerRoster(bounty, roster, 2);
        vm.prank(DEVELOPER);
        escrow.applyForBounty(bounty);
        vm.prank(SPONSOR);
        escrow.offerAssignment(bounty, DEVELOPER);
        vm.prank(DEVELOPER);
        escrow.acceptAssignment(bounty);
        vm.prank(DEVELOPER);
        escrow.submitCandidate(bounty, _candidate(FIRST_HEAD));
        _assignAndDeclare(bounty, 1);
        escrow.assignReviewerJob(bounty, ORG_C);
        vm.prank(signerC);
        escrow.acceptReviewerJob(bounty, 1, ORG_C);
        vm.prank(signerC);
        escrow.declareReviewerEvidence(bounty, 1, ORG_C, REPORT_C);
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
            reportDigest: org == ORG_A ? REPORT_A : (org == ORG_B ? REPORT_B : REPORT_C),
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

    function testTwoIndependentlySignedApprovalsEnterChallengeNotPayout() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory a =
            _vote(bounty, ORG_A, uint8(SignedVerifierDecisionModuleV1.Outcome.Approved));
        SignedVerifierDecisionModuleV1.SignedVerdict memory b =
            _vote(bounty, ORG_B, uint8(SignedVerifierDecisionModuleV1.Outcome.Approved));
        _submit(a, KEY_A);
        SignedVerifierDecisionModuleV1.ReviewDecision memory interim =
            escrow.readReviewDecision(bounty, 1);
        require(interim.status == SignedVerifierDecisionModuleV1.ReviewStatus.Pending, "single key approved");
        require(interim.positiveVotes == 1, "first approval not counted");

        uint256 initialSponsor = SPONSOR.balance;
        uint256 initialDeveloper = DEVELOPER.balance;
        _submit(b, KEY_B);
        SignedVerifierDecisionModuleV1.ReviewDecision memory result =
            escrow.readReviewDecision(bounty, 1);
        require(
            result.status == SignedVerifierDecisionModuleV1.ReviewStatus.ChallengeWindow,
            "independent quorum did not open challenge"
        );
        require(result.positiveVotes == 2 && result.recordedVotes == 2, "quorum miscount");
        require(result.challengeUntil == block.timestamp + 1 days, "challenge not bounded");
        require(escrow.readRecordedVerdict(bounty, 1, ORG_A).typedDigest ==
            escrow.typedVerdictDigest(a), "signature reference not persisted");
        require(escrow.readRecordedVerdict(bounty, 1, ORG_B).signer == signerB, "wrong reviewer signer");
        require(SPONSOR.balance == initialSponsor && DEVELOPER.balance == initialDeveloper,
            "review moved user money");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "review minted payout");
    }

    function testThirdIndependentDissentStopsEarlyQuorumDuringChallenge() public {
        uint256 bounty = _submittedWithThreeReviewers();
        VerifierRegistryModuleV1.ReviewerJob memory job =
            escrow.getReviewerJob(bounty, 1, ORG_C);
        vm.warp(uint256(job.deadline) - 3);

        SignedVerifierDecisionModuleV1.SignedVerdict memory a = _vote(bounty, ORG_A, 1);
        SignedVerifierDecisionModuleV1.SignedVerdict memory b = _vote(bounty, ORG_B, 1);
        a.expiresAt = job.deadline - 1;
        b.expiresAt = job.deadline - 1;
        _submit(a, KEY_A);
        _submit(b, KEY_B);
        SignedVerifierDecisionModuleV1.ReviewDecision memory beforeDispute =
            escrow.readReviewDecision(bounty, 1);
        require(
            beforeDispute.status == SignedVerifierDecisionModuleV1.ReviewStatus.ChallengeWindow,
            "quorum did not open challenge"
        );

        // A third *approval* cannot extend a completed quorum, even from a
        // committed reviewer. But its signed contradiction must be heard.
        SignedVerifierDecisionModuleV1.SignedVerdict memory c = _vote(bounty, ORG_C, 1);
        c.expiresAt = job.deadline - 1;
        _reject(c, _sign(c, KEY_C));

        vm.warp(uint256(job.deadline) + 10);
        c = _vote(bounty, ORG_C, 2);
        c.expiresAt = uint64(block.timestamp + 60);
        _submit(c, KEY_C);
        SignedVerifierDecisionModuleV1.ReviewDecision memory afterDispute =
            escrow.readReviewDecision(bounty, 1);
        require(
            afterDispute.status == SignedVerifierDecisionModuleV1.ReviewStatus.EscalationRequired,
            "conflicting independent finding failed to halt approval"
        );
        require(afterDispute.recordedVotes == 3 && afterDispute.positiveVotes == 2,
            "signed dissent did not preserve the original quorum history");
        require(afterDispute.challengeUntil == 0, "old challenge deadline remained payable");
        require(afterDispute.triggeringVoteDigest == escrow.typedVerdictDigest(c),
            "signed dissent was not audit-bound");
        _reject(c, _sign(c, KEY_C));
        require(address(escrow).balance == escrow.totalReservedAtoms(),
            "post-quorum dissent moved protected funds");
    }

    function testOneSignedVoteCannotPassCommittedQuorum() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        require(escrow.readReviewDecision(bounty, 1).status ==
            SignedVerifierDecisionModuleV1.ReviewStatus.Pending, "one vote became approval");
    }

    function testDissentEscalatesEvenAfterOnePositiveVote() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        _submit(_vote(bounty, ORG_B, 2), KEY_B);
        SignedVerifierDecisionModuleV1.ReviewDecision memory d =
            escrow.readReviewDecision(bounty, 1);
        require(d.status == SignedVerifierDecisionModuleV1.ReviewStatus.EscalationRequired,
            "dissent auto approved");
        require(d.positiveVotes == 1 && d.recordedVotes == 2, "disagreement lost");
        _reject(_vote(bounty, ORG_A, 1), _sign(_vote(bounty, ORG_A, 1), KEY_A));
        require(d.challengeUntil == 0, "challenged review looks payable");
    }

    function testInconclusiveAndRunnerFailuresNeverApprove() public {
        for (uint8 outcome = 3; outcome <= 4; outcome++) {
            uint256 bounty = _ready();
            _submit(_vote(bounty, ORG_A, outcome), KEY_A);
            require(escrow.readReviewDecision(bounty, 1).status ==
                SignedVerifierDecisionModuleV1.ReviewStatus.EscalationRequired,
                "unreliable runner created approval");
        }
    }

    function testClaimedApprovalCannotContradictBeforeAfterEvidence() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        v.baselineFailed = false;
        _reject(v, _sign(v, KEY_A));
        v.baselineFailed = true;
        v.candidatePassed = false;
        _reject(v, _sign(v, KEY_A));
        v.candidatePassed = true;
        v.regressionsPassed = false;
        _reject(v, _sign(v, KEY_A));
        v.regressionsPassed = true;
        v.outcome = 0;
        _reject(v, _sign(v, KEY_A));
        v.outcome = 5;
        _reject(v, _sign(v, KEY_A));
        require(escrow.readReviewDecision(bounty, 1).recordedVotes == 0,
            "invalid approvals counted");
    }

    function testWrongKeyAndSignatureTamperingFail() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory a = _vote(bounty, ORG_A, 1);
        _reject(a, _sign(a, KEY_B));
        _reject(a, _sign(a, KEY_ATTACKER));
        bytes memory original = _sign(a, KEY_A);
        bytes memory short = new bytes(64);
        _reject(a, short);
        bytes memory corrupted = _sign(a, KEY_A);
        corrupted[64] = 0x01;
        _reject(a, corrupted);
        corrupted = _sign(a, KEY_A);
        corrupted[32] = 0xff;
        _reject(a, corrupted);
        _submit(a, KEY_A);
        require(escrow.readReviewDecision(bounty, 1).recordedVotes == 1,
            "incorrect signer bypass");
    }

    function testSignedPayloadCannotChangeReportHeadManifestPolicyOrImage() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory correct = _vote(bounty, ORG_A, 1);
        bytes memory signature = _sign(correct, KEY_A);
        SignedVerifierDecisionModuleV1.SignedVerdict memory changed = _vote(bounty, ORG_A, 1);
        changed.headGitSha = SECOND_HEAD;
        _reject(changed, signature);
        changed = _vote(bounty, ORG_A, 1);
        changed.manifestDigest = bytes32(uint256(899));
        _reject(changed, signature);
        changed = _vote(bounty, ORG_A, 1);
        changed.verifierPolicyDigest = bytes32(uint256(898));
        _reject(changed, signature);
        changed = _vote(bounty, ORG_A, 1);
        changed.reportDigest = REPORT_B;
        _reject(changed, signature);
        changed = _vote(bounty, ORG_A, 1);
        changed.imageDigest = bytes32(uint256(897));
        _reject(changed, signature);
        changed = _vote(bounty, ORG_A, 1);
        changed.attemptDigest = bytes32(uint256(896));
        _reject(changed, signature);
        _submit(correct, KEY_A);
    }

    function testSignerCannotApproveAnotherBountyOrContract() public {
        uint256 bounty = _ready();
        uint256 otherBounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        bytes memory signature = _sign(v, KEY_A);
        v.bountyId = otherBounty;
        _reject(v, signature);
        SignedDecisionHarness otherContract = new SignedDecisionHarness(CHAIN, address(this));
        SignedVerifierDecisionModuleV1.SignedVerdict memory w = _vote(bounty, ORG_A, 1);
        require(otherContract.typedVerdictDigest(w) != escrow.typedVerdictDigest(w),
            "verifying contract domain does not change hash");
        require(escrow.readReviewDecision(bounty, 1).recordedVotes == 0, "cross bounty accepted");
    }

    function testSignedPayloadRejectsExpiredFutureAndWrongEpoch() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        v.expiresAt = uint64(block.timestamp);
        _reject(v, _sign(v, KEY_A));
        v.expiresAt = uint64(block.timestamp + 3 days);
        _reject(v, _sign(v, KEY_A)); // beyond committed reviewer deadline
        v = _vote(bounty, ORG_A, 1);
        v.signerEpoch += 1;
        _reject(v, _sign(v, KEY_A));
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
    }

    function testOldSignerCannotAuthorizeAfterRotationOrRevocation() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        bytes memory signature = _sign(v, KEY_A);
        address successor = vm.addr(444);
        vm.prank(CONTROLLER_A);
        escrow.proposeReviewerSigner(ORG_A, successor);
        escrow.approveReviewerSignerRotation(ORG_A);
        _reject(v, signature);
        SignedVerifierDecisionModuleV1.SignedVerdict memory v2 = _vote(bounty, ORG_B, 1);
        escrow.revokeReviewerOrganization(ORG_B);
        _reject(v2, _sign(v2, KEY_B));
    }

    function testDuplicateAttestationAndReplayFail() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        bytes memory signature = _sign(v, KEY_A);
        escrow.submitSignedVerdict(v, signature);
        _reject(v, signature);
        require(escrow.readReviewDecision(bounty, 1).recordedVotes == 1, "duplicate increased count");
    }

    function testWrongChainSignatureAndRuntimeFailClosed() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        bytes32 originalDigest = escrow.typedVerdictDigest(v);
        bytes memory signature = _sign(v, KEY_A);
        vm.chainId(CHAIN + 1);
        _reject(v, signature);
        require(escrow.typedVerdictDigest(v) != originalDigest,
            "wrong chain reuses same EIP712 domain");
    }

    function testNoReportDeclarationOrUnacceptedJobCannotSign() public {
        uint256 bounty = _submitted();
        escrow.assignReviewerJob(bounty, ORG_A);
        SignedVerifierDecisionModuleV1.SignedVerdict memory v = _vote(bounty, ORG_A, 1);
        _reject(v, _sign(v, KEY_A));
        vm.prank(signerA);
        escrow.acceptReviewerJob(bounty, 1, ORG_A);
        _reject(v, _sign(v, KEY_A));
        vm.prank(signerA);
        escrow.declareReviewerEvidence(bounty, 1, ORG_A, REPORT_A);
        _submit(v, KEY_A);
    }

    function testMissingQuorumCanOnlyTimeoutToEscalationState() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        uint256 deadline = escrow.getReviewerJob(bounty, 1, ORG_A).deadline;
        vm.prank(SPONSOR);
        (bool premature,) = address(escrow).call(
            abi.encodeWithSelector(escrow.expireIncompleteReview.selector, bounty, uint64(1))
        );
        require(!premature, "sponsor terminated review early");
        vm.warp(deadline);
        vm.prank(DEVELOPER);
        escrow.expireIncompleteReview(bounty, 1);
        SignedVerifierDecisionModuleV1.ReviewDecision memory d =
            escrow.readReviewDecision(bounty, 1);
        require(d.status == SignedVerifierDecisionModuleV1.ReviewStatus.TimedOut,
            "missing vote became success");
        _reject(_vote(bounty, ORG_B, 1), _sign(_vote(bounty, ORG_B, 1), KEY_B));
        require(address(escrow).balance == escrow.totalReservedAtoms(),
            "timeout stole contributor reward");
    }

    function testReviewStatusDoesNotPermitEarlyDeadlinePayoutOrRepeat() public {
        uint256 bounty = _ready();
        _submit(_vote(bounty, ORG_A, 1), KEY_A);
        _submit(_vote(bounty, ORG_B, 1), KEY_B);
        vm.warp(block.timestamp + 31 days);
        SignedVerifierDecisionModuleV1.ReviewDecision memory status =
            escrow.readReviewDecision(bounty, 1);
        require(status.status == SignedVerifierDecisionModuleV1.ReviewStatus.ChallengeWindow,
            "challenge state unexpectedly settled");
        (bool ok,) = address(escrow).call(
            abi.encodeWithSelector(escrow.expireIncompleteReview.selector, bounty, uint64(1))
        );
        require(!ok, "approved challenge was overwritten by timeout");
        require(address(escrow).balance == 1 ether, "fake approval drained escrow");
    }

    function testOldAttemptAttestationCannotApproveNewRevision() public {
        uint256 bounty = _ready();
        SignedVerifierDecisionModuleV1.SignedVerdict memory original = _vote(bounty, ORG_A, 1);
        bytes memory signed = _sign(original, KEY_A);
        escrow.testReviewAuthorizesRetry(bounty, 1, bytes32(uint256(955)));
        BountySubmissionModuleV1.Candidate memory newer = _candidate(SECOND_HEAD);
        vm.prank(DEVELOPER);
        escrow.resubmitCandidate(bounty, newer);
        _reject(original, signed);
        require(escrow.latestAttemptId(bounty) == 2, "new attempt missing");
        require(escrow.readReviewDecision(bounty, 2).status ==
            SignedVerifierDecisionModuleV1.ReviewStatus.Pending,
            "new attempt inherited previous decision");
    }
}
