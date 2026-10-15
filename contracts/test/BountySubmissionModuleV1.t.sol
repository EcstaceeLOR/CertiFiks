// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BountySubmissionModuleV1} from "../src/BountySubmissionModuleV1.sol";
import {BountyFundingModuleV1} from "../src/BountyFundingModuleV1.sol";

interface VmGitSubmission {
    function prank(address sender) external;
    function deal(address who, uint256 balance) external;
    function warp(uint256 timestamp) external;
    function chainId(uint256 newChainId) external;
}

/**
 * TEST ONLY. No verifier contract exists to approve resubmission, so the
 * restricted review hook is exposed solely for characterization here.
 */
contract GitSubmissionHarnessV1 is BountySubmissionModuleV1 {
    address private immutable fixtureController;

    constructor(uint256 chainId) BountySubmissionModuleV1(chainId) {
        fixtureController = msg.sender;
    }

    function testFund(FundingRequest calldata terms) external payable returns (uint256) {
        return _recordFunding(terms);
    }

    function simulateReviewedRejection(uint256 bountyId, uint64 attemptId, bytes32 reviewDigest) external {
        require(msg.sender == fixtureController, "test fixture controller only");
        _authorizeRetryFromReview(bountyId, attemptId, reviewDigest);
    }
}

/** These are local authorization/data-integrity tests, not live GitHub checks. */
contract GitSubmissionProtocolV1Test {
    VmGitSubmission private constant vm =
        VmGitSubmission(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant CHAIN = 31337;
    address private constant SPONSOR = address(0xA110);
    address private constant CONTRIBUTOR = address(0xCAFE);
    address private constant OTHER = address(0xBEEF);

    bytes20 private constant BASE = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes20 private constant FIRST = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    bytes20 private constant SECOND = hex"cccccccccccccccccccccccccccccccccccccccc";

    GitSubmissionHarnessV1 private escrow;

    function setUp() public {
        vm.chainId(CHAIN);
        vm.warp(1780000000);
        vm.deal(SPONSOR, 100 ether);
        escrow = new GitSubmissionHarnessV1(CHAIN);
    }

    function _terms() private view returns (BountyFundingModuleV1.FundingRequest memory) {
        return BountyFundingModuleV1.FundingRequest({
            repositoryId: 150721,
            baselineGitSha: BASE,
            manifestDigest: bytes32(uint256(10)),
            verifierPolicyDigest: bytes32(uint256(11)),
            disputePolicyDigest: bytes32(uint256(12)),
            primaryArbitrator: address(0xA4B),
            submissionDeadline: uint64(block.timestamp + 10 days),
            verificationSeconds: 1 days,
            challengeSeconds: 1 days,
            arbitrationSeconds: 1 days,
            assetKind: 0
        });
    }

    function _fundAndAssign() private returns (uint256 id) {
        vm.prank(SPONSOR);
        id = escrow.testFund{value: 1 ether}(_terms());
        vm.prank(CONTRIBUTOR);
        escrow.applyForBounty(id);
        vm.prank(SPONSOR);
        escrow.offerAssignment(id, CONTRIBUTOR);
        vm.prank(CONTRIBUTOR);
        escrow.acceptAssignment(id);
    }

    function _candidate(bytes20 head) private pure returns (BountySubmissionModuleV1.Candidate memory) {
        return BountySubmissionModuleV1.Candidate({
            repositoryId: 150721,
            pullNumber: 42,
            baseGitSha: BASE,
            headGitSha: head,
            imageDigest: bytes32(uint256(20)),
            evidenceDigest: bytes32(uint256(21)),
            manifestDigest: bytes32(uint256(10)),
            manifestVersion: 1
        });
    }

    function _submit(uint256 id, bytes20 sha) private {
        vm.prank(CONTRIBUTOR);
        escrow.submitCandidate(id, _candidate(sha));
    }

    function _reject(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool success,) = address(escrow).call(data);
        require(!success, "invalid submission unexpectedly accepted");
    }

    function testWalletSignedSubmitPinsExactGitHubFacts() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        BountySubmissionModuleV1.FixAttempt memory result = escrow.getPinnedAttempt(id, 1);
        require(result.attemptId == 1, "bad attempt");
        require(result.developer == CONTRIBUTOR, "wrong signer");
        require(result.candidate.repositoryId == 150721, "wrong repository");
        require(result.candidate.pullNumber == 42, "wrong PR");
        require(result.candidate.baseGitSha == BASE, "baseline not pinned");
        require(result.candidate.headGitSha == FIRST, "head changed");
        require(result.candidate.manifestDigest == bytes32(uint256(10)), "policy changed");
        require(result.candidate.imageDigest == bytes32(uint256(20)), "image unbound");
        require(result.candidate.evidenceDigest == bytes32(uint256(21)), "evidence unbound");
        require(result.candidate.manifestVersion == 1, "wrong manifest version");
        require(result.attemptDigest != bytes32(0), "empty attempt digest");
        require(escrow.latestAttemptId(id) == 1, "wrong sequence");
        require(escrow.seenHeadGitSha(id, FIRST), "head never recorded");
        require(!escrow.canSubmit(id, CONTRIBUTOR), "submission state not locked");
        require(address(escrow).balance == escrow.totalReservedAtoms(), "money moved during claim");
    }

    function testUnauthorizedSponsorOrStrangerCannotSubmit() public {
        uint256 id = _fundAndAssign();
        bytes memory data = abi.encodeWithSelector(escrow.submitCandidate.selector, id, _candidate(FIRST));
        _reject(OTHER, data);
        _reject(SPONSOR, data);
        require(escrow.latestAttemptId(id) == 0, "unauthorized attempt persisted");
        _submit(id, FIRST);
        _reject(OTHER, abi.encodeWithSelector(escrow.resubmitCandidate.selector, id, _candidate(SECOND)));
    }

    function testMalformedAndUnboundInputsAreRejected() public {
        uint256 id = _fundAndAssign();
        BountySubmissionModuleV1.Candidate memory c = _candidate(FIRST);
        c.repositoryId++;
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.baseGitSha = SECOND;
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.manifestDigest = bytes32(uint256(404));
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.manifestVersion = 2;
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.pullNumber = 0;
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.headGitSha = BASE;
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.headGitSha = bytes20(0);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.imageDigest = bytes32(0);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        c = _candidate(FIRST);
        c.evidenceDigest = bytes32(0);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, c));
        require(escrow.latestAttemptId(id) == 0, "malformed attempt persisted");
    }

    function testReplayCannotCreateSecondAttemptWithoutReview() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, _candidate(SECOND)));
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.resubmitCandidate.selector, id, _candidate(SECOND)));
        require(escrow.latestAttemptId(id) == 1, "replay increased sequence");
    }

    function testAuthorizedReviewRetryCreatesNewImmutableAttempt() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        BountySubmissionModuleV1.FixAttempt memory old = escrow.getPinnedAttempt(id, 1);
        escrow.simulateReviewedRejection(id, 1, bytes32(uint256(777)));
        require(escrow.retryReviewDigest(id) == bytes32(uint256(777)), "review auth absent");

        vm.prank(CONTRIBUTOR);
        escrow.resubmitCandidate(id, _candidate(SECOND));
        require(escrow.latestAttemptId(id) == 2, "new attempt missing");
        require(escrow.retryReviewDigest(id) == bytes32(0), "review auth reused");
        BountySubmissionModuleV1.FixAttempt memory first = escrow.getPinnedAttempt(id, 1);
        BountySubmissionModuleV1.FixAttempt memory second = escrow.getPinnedAttempt(id, 2);
        require(first.attemptDigest == old.attemptDigest, "historical proof rewritten");
        require(first.candidate.headGitSha == FIRST, "force push mutated original head");
        require(second.candidate.headGitSha == SECOND, "new head not pinned");
        require(second.attemptDigest != first.attemptDigest, "attempt hash replay");
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.resubmitCandidate.selector, id, _candidate(FIRST)));
    }

    function testReviewerCannotAuthorizeWrongSequenceOrBlankVerdict() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        _reject(address(this), abi.encodeWithSelector(escrow.simulateReviewedRejection.selector, id, 2, bytes32(uint256(2))));
        _reject(address(this), abi.encodeWithSelector(escrow.simulateReviewedRejection.selector, id, 1, bytes32(0)));
        _reject(OTHER, abi.encodeWithSelector(escrow.simulateReviewedRejection.selector, id, 1, bytes32(uint256(10))));
        escrow.simulateReviewedRejection(id, 1, bytes32(uint256(10)));
        _reject(address(this), abi.encodeWithSelector(escrow.simulateReviewedRejection.selector, id, 1, bytes32(uint256(11))));
    }

    function testResubmissionKeepsSamePullRequestNumber() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        escrow.simulateReviewedRejection(id, 1, bytes32(uint256(10)));
        BountySubmissionModuleV1.Candidate memory c = _candidate(SECOND);
        c.pullNumber = 43;
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.resubmitCandidate.selector, id, c));
        require(escrow.latestAttemptId(id) == 1, "wrong PR replayed");
    }

    function testPreviouslySubmittedRevisionCannotReappearAfterReview() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        escrow.simulateReviewedRejection(id, 1, bytes32(uint256(11)));
        vm.prank(CONTRIBUTOR);
        escrow.resubmitCandidate(id, _candidate(SECOND));
        escrow.simulateReviewedRejection(id, 2, bytes32(uint256(12)));
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.resubmitCandidate.selector, id, _candidate(FIRST)));
        require(escrow.seenHeadGitSha(id, FIRST), "original SHA forgotten");
        require(escrow.latestAttemptId(id) == 2, "old commit replay advanced sequence");
    }

    function testSubmissionAfterDeadlineOrOnWrongChainFails() public {
        uint256 id = _fundAndAssign();
        uint64 deadline = escrow.getFundingTerms(id).submissionDeadline;
        vm.warp(uint256(deadline) + 1);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id, _candidate(FIRST)));

        uint256 id2 = _fundAndAssign();
        vm.chainId(CHAIN + 1);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.submitCandidate.selector, id2, _candidate(FIRST)));
        require(escrow.latestAttemptId(id2) == 0, "wrong-chain commit accepted");
    }

    function testResubmissionAfterDeadlineIsRejectedEvenWithReviewApproval() public {
        uint256 id = _fundAndAssign();
        _submit(id, FIRST);
        escrow.simulateReviewedRejection(id, 1, bytes32(uint256(17)));
        vm.warp(uint256(escrow.getFundingTerms(id).submissionDeadline) + 1);
        _reject(CONTRIBUTOR, abi.encodeWithSelector(escrow.resubmitCandidate.selector, id, _candidate(SECOND)));
    }

    function testCrossBountyReplayHasDifferentDigestAndIndependentHistory() public {
        uint256 id1 = _fundAndAssign();
        uint256 id2 = _fundAndAssign();
        _submit(id1, FIRST);
        _submit(id2, FIRST);
        BountySubmissionModuleV1.FixAttempt memory a = escrow.getPinnedAttempt(id1, 1);
        BountySubmissionModuleV1.FixAttempt memory b = escrow.getPinnedAttempt(id2, 1);
        require(a.attemptDigest != b.attemptDigest, "bounty domain missing");
        require(escrow.latestAttemptId(id1) == 1 && escrow.latestAttemptId(id2) == 1, "crossed history");
        require(escrow.seenHeadGitSha(id1, FIRST) && escrow.seenHeadGitSha(id2, FIRST), "independent bounty keys missing");
    }

    function testDeniedSubmissionCannotChangeFundingSpecOrTransferFunds() public {
        uint256 id = _fundAndAssign();
        BountyFundingModuleV1.BountyTerms memory beforeTerms = escrow.getFundingTerms(id);
        _submit(id, FIRST);
        BountyFundingModuleV1.BountyTerms memory afterTerms = escrow.getFundingTerms(id);
        require(beforeTerms.manifestDigest == afterTerms.manifestDigest, "manifest changed");
        require(beforeTerms.baselineGitSha == afterTerms.baselineGitSha, "baseline changed");
        require(beforeTerms.rewardAtoms == afterTerms.rewardAtoms, "reward changed");
        require(address(escrow).balance == 1 ether, "submission moved value");
        require(escrow.totalReservedAtoms() == 1 ether, "submission released funds");
    }

    function testUnknownAttemptAndUnknownBountyRevert() public {
        uint256 id = _fundAndAssign();
        _reject(OTHER, abi.encodeWithSelector(escrow.getPinnedAttempt.selector, id, 0));
        _reject(OTHER, abi.encodeWithSelector(escrow.getPinnedAttempt.selector, id, 1));
        _reject(OTHER, abi.encodeWithSelector(escrow.getPinnedAttempt.selector, id + 1, 1));
    }
}
